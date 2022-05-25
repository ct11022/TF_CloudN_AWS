from vmware.inventory import Inventory
import json
import sys

if __name__ == '__main__':

    input_json = sys.stdin.read()
    try:
        # The string data passed by query has json format
        input_dict = json.loads(input_json)
        controller_hostname = input_dict.get('controller_hostname')

        inv = Inventory()
        inv.initialize_inventory()
        inv.refresh_inventory_state()

        for vm in inv.vms:
            # find the vcn already registed to controller 
            if controller_hostname in str(vm.state.in_ci_use):
                output = json.dumps({str(key): str(value) for key, value in vm.spec.items()})
                sys.stdout.write(output)
                break
        else:
            # find a free cloudn 
            free_vm = inv.get_available_vms()[0]
            output = json.dumps({str(key): str(value) for key, value in free_vm.spec.items()})
            sys.stdout.write(output)

    except ValueError as e:
        sys.exit(e)