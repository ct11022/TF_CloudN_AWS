import copy
from pathlib import Path
import re
import yaml

import vmware.utils as utils

from pyVim.task import WaitForTasks
from pyVmomi import vim


BASE_DIRECTORY = (Path.cwd() / Path(__file__)).parent
DEFAULT_INVENTORY_FILE = "inventory_data.yaml"


class State():
    """ Class to store all CI-related state of VMs """

    def __init__(self):
        self.power_state = None
        self.in_ci_use = False


class Inventory():

    def __init__(self):
        self.vms = list()
        self.hosts = list()
        self.vcs = list()
        self.spec = None

    def initialize_inventory(self, file=None):
        """ Reads inventory data from user yaml and initializes objects """
        file = file or str(BASE_DIRECTORY / DEFAULT_INVENTORY_FILE)
        with open(file, 'r') as f:
            data = yaml.safe_load(f)
        
        self.spec = data["inventory"]
        self._configure_vcs()
        self._configure_hosts()
        self._configure_vms()

    def _configure_vcs(self):
        """ Initializes all VC objects from the inventory yaml """
        pass

    def _configure_hosts(self):
        """ Initializes all host objects from the inventory yaml """
        type = "host"
        self._add_objs_to_inventory(type)

        for host in self.hosts:
            kwargs = copy.deepcopy(host.spec)
            if 'vc' in host.spec:
                obj = self.get_inventory_object('vc', host.spec.get('vc'))
                kwargs['vc'] = obj
            host.init(**kwargs)               

    def _configure_vms(self):
        """ Initializes all VMs from the inventory yaml """
        type = "vm"
        self._add_objs_to_inventory(type)

        for vm in self.vms:
            kwargs = copy.deepcopy(vm.spec)
            if 'host' in vm.spec:
                obj = self.get_inventory_object('host', vm.spec.get('host'))
                kwargs['host'] = obj
            vm.init(**kwargs)

    def _add_objs_to_inventory(self, type):
        """
        Instantiates an object based on its type (e.g. host or vm) and adds it
        to the corresponding collection in the inventory
        """
        klasses = globals()
        for index, spec in self.spec.get(type).items():
            cls = klasses[type.title()]
            id = spec.get("id")
            name = spec.get("name") or (type + re.search(r'\d+', index).group())
            obj = cls(spec=spec, name=name, id=id)
            collection = getattr(self, type + "s")
            collection.append(obj)
    
    def get_inventory_object(self, type, name):
        """ Returns inventory object matching the type and name """
        objs = getattr(self, type + 's')
        obj = [x for x in objs if x.name == name][0]
        return obj

    def refresh_inventory_state(self):
        """ Scans all VMs and gets their current tags """
        for vm in self.vms:
            vm.refresh_tags()

    def get_available_vms(self):
        """ Returns a list of VMs available for CI to use """
        return [vm for vm in self.vms if (
                vm.state.power_state == 'poweredOn' and vm.state.in_ci_use == False)]


class InventoryObj(object):
    def __init__(self, spec=None, id=None):
        self.spec = spec
        self.id = id


class Vc(InventoryObj):
    def __init__(self, spec=None, name=None, **kwargs):
        super(Vc, self).__init__(spec=spec)
        self.name = name

    def init(self, ip=None, username=None, password=None, **kwargs):
        self.ip = ip
        self.username = username or "administrator@vsphere.local"
        self.password = password or "Aviatrix123#"


class Host(InventoryObj):

    def __init__(self, spec=None, name=None, id=None):
        super(Host, self).__init__(spec=spec, id=id)
        self.name = name

    def init(self, vc=None, ip=None, username=None, password=None, **kwargs):
        self.vc = vc
        self.ip = ip
        self.username = username or "root"
        self.password = password or "Aviatrix123#"
        self.state = State()


class Vm(InventoryObj):

    def __init__(self, spec=None, name=None, id=None):
        super(Vm, self).__init__(spec=spec, id=id)
        self.name = name

    def init(self, name=None, host=None, ip=None, **kwargs):
        self.host = host
        self.ip = ip
        # TODO(pvichare): add username and password if cloudn's clish is disabled
        # and ssh is available
        self.state = State()

    def refresh_tags(self):
        """ Gets the runtime annotations of the VM from its host/VC """
        predicate = lambda x: x.name == self.name
        vm_mobj = utils.get_vm_from_host(self.host, predicate=predicate)[0]
        self.id = vm_mobj._moId
        annotations = vm_mobj.config.annotation.split(",")
        for annotation in annotations:
            if not annotation:
                continue
            prop, value = annotation.split(":")
            if hasattr(self.state, prop):
                if value in ('True', 'False'):
                    value = eval(value)
                setattr(self.state, prop, value)
        self.state.power_state = vm_mobj.runtime.powerState

    def update_tags(self):
        """ Read state and update annotations on the VM """
        current_state = ",".join(
            [(prop + ':' + str(value)) for prop, value in vars(self.state).items()])
        predicate = lambda x: x.name == self.name
        vm_mobj = utils.get_vm_from_host(self.host, predicate=predicate)[0]
        spec = vim.vm.ConfigSpec()
        spec.annotation = current_state
        task = vm_mobj.ReconfigVM_Task(spec)
        WaitForTasks([task])


if __name__ == '__main__':
    inventory = Inventory()
    inventory.initialize_inventory()
    inventory.refresh_inventory_state()
