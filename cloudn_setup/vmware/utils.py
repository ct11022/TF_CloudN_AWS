from collections import deque

from pyVim.connect import SmartConnectNoSSL
from pyVim.task import WaitForTasks
from pyVmomi import vim


def init_vsphere_client(server):
    si = SmartConnectNoSSL(
        host=server.ip, user=server.username, pwd=server.password)
    return si


def get_all_vms_from_host(host):
    si = init_vsphere_client(host)
    content = si.content
    vimtype = [vim.VirtualMachine]
    container = content.viewManager.CreateContainerView(
        content.rootFolder, vimtype, True)
    vms = container.view
    container.Destroy()
    return vms


def get_vm_from_host(host, predicate=None):
    all_vms = get_all_vms_from_host(host)
    return list(filter(predicate, all_vms))


def get_all_vm_snapshots(vm):
    """ Returns a list of all VM snapshots """
    predicate = lambda x: x.name == vm.name
    vm_mobj = get_vm_from_host(vm.host, predicate=predicate)[0]
    all_snapshots = []

    def collect_snapshots_recursively(snapshotTree):
        nonlocal all_snapshots
        for node in snapshotTree:
            all_snapshots.append(node.snapshot)
            if node.childSnapshotList:
                collect_snapshots_recursively(node.childSnapshotList)

    if hasattr(vm_mobj.snapshot, 'rootSnapshotList'):
        collect_snapshots_recursively(vm_mobj.snapshot.rootSnapshotList)
    return all_snapshots


def get_vm_snapshot_by_name(vm, snapshot_name):
    """ Returns a VM snapshot matching the specified name """
    predicate = lambda x: x.name == vm.name
    vm_mobj = get_vm_from_host(vm.host, predicate=predicate)[0]
    queue = deque()

    if not hasattr(vm_mobj.snapshot, 'rootSnapshotList'):
        return None
    queue.extend(vm_mobj.snapshot.rootSnapshotList)

    while queue:
        root = queue.popleft()
        if root.name == snapshot_name:
            return root.snapshot
        queue.extend(root.childSnapshotList)

    return None


def create_vm_snapshot(vm, snapshot_name):
    """ Takes a snapshot of a VM """
    predicate = lambda x: x.name == vm.name
    vm_mobj = get_vm_from_host(vm.host, predicate=predicate)[0]
    dump_memory = False
    quiesce = False
    task = vm_mobj.CreateSnapshot(
        snapshot_name, snapshot_name, dump_memory, quiesce)
    WaitForTasks([task])


def revert_vm_to_snapshot(vm, snapshot_name=None):
    """
    Restores the VM to the specified snapshot. If snapshot_name is None,
    restores the VM to the current snapshot
    """
    if not snapshot_name:
        predicate = lambda x: x.name == vm.name
        vm_mobj = get_vm_from_host(vm.host, predicate=predicate)[0]
        task = vm_mobj.RevertToCurrentSnapshot_Task()
        WaitForTasks([task])

    snapshot = get_vm_snapshot_by_name(vm, snapshot_name)
    if not snapshot:
        # TODO(pvichare): Raise error instead of returning quietly
        return
    task = snapshot.RevertToSnapshot_Task()
    WaitForTasks([task])
    # If VM is powered off, then power it back on
    vm_mobj = get_vm_from_host(
        vm.host, predicate=lambda x: x.name == vm.name)[0]
    if vm_mobj.runtime.powerState == "poweredOff":
        WaitForTasks([vm_mobj.PowerOnVM_Task()])


def remove_vm_snapshot(vm, snapshot_name):
    """ Removes a snapshot tree from a VM given the snapshot name """
    snapshot = get_vm_snapshot_by_name(vm, snapshot_name)
    if not snapshot:
        return
    task = snapshot.RemoveSnapshot_Task(removeChildren=True)
    WaitForTasks([task])
