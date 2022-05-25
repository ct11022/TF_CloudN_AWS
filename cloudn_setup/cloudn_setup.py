import argparse
import json
import logging
import requests
import sys
import time

from vmware.inventory import Inventory
import vmware.utils as utils

logging.basicConfig(
    filename='cloudn_setup.log',
    filemode='w',
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)

logger = logging.getLogger(__name__)

def get_cid_url(hostame, username, passwd):
    api_url = 'https://{}/v1/api'.format(hostame)
    backend_url = 'https://{}/v1/backend1'.format(hostame)

    payload = {
        "action": "login",
        "username": username,
        "password": passwd
    }

    response = requests.get(api_url, params=payload, verify=False)
    logger.info("response: %s" % response.json())

    if response.status_code not in range(200, 207) or not response.json().get('return'):
        raise RuntimeError("Cannot acquire CID.")
    else:
        cid = response.json().get('CID')

    logger.info("CloudN CID = {}".format(cid))
    return (cid, api_url, backend_url)


def register(CID, URL, controller_hostname, controller_username, controller_passwd, cloudn_name):
    payload = {'action': 'register_caag_with_controller',
               'CID': CID,
               'controller_ip_or_fqdn': controller_hostname,
               'username': controller_username,
               'password': controller_passwd,
               'gateway_name': cloudn_name
               }

    response = requests.post(URL, data=payload, verify=False)
    if response.status_code not in range(200, 207) or not response.json().get('return'):
        raise RuntimeError(
            "CloudN Register to Controller Failure. {}".format(response.json()))

    logger.info('RESULT: {}'.format(response.json().get('results')))


def upgrade(hostame, username, passwd, version):
    cid ,api_url, backend_url = get_cid_url(hostame, username, passwd)

    payload_upgrade = {'action': 'upgrade',
               'CID': cid,
               'version': version,
               }

    try:
        requests.post(api_url, data=payload_upgrade, verify=False, timeout=5)

    except requests.exceptions.ReadTimeout: 
        pass
    time.sleep(420)

    # logout
    requests.post(api_url, data={'action': 'logout', 'CID': cid}, verify=False)
    time.sleep(10)
    cid ,api_url, backend_url = get_cid_url(hostame, username, passwd)
    payload_get_ver = {'action': 'list_version_info', 'CID':cid}
    response = requests.post(api_url, data=payload_get_ver, verify=False)
    if response.status_code not in range(200, 207) or not response.json().get('return'):
        raise RuntimeError("Get Version FAIL, {}".format(response.json()))
    upgrade_version = response.json().get("results").get("current_version").split('.')[-1]

    logger.info(upgrade_version)

    logger.info('Upgrade successfully.')


def reset_caag(CID, URL):
    payload = {'action': 'reset_caag_to_cloudn_factory_state_by_cloudn',
               'CID': CID}
    response = requests.post(URL, data=payload, verify=False)
    if response.status_code not in range(200, 207) or not response.json().get('return'):
        raise RuntimeError("CaaG Reset Failure. {}".format(response.json()))
    logger.info('RESULT: {}'.format(response.json().get('results')))


def reset_caag_from_controller(controller_hostname, controller_username, controller_passwd, cloudn_name):

    cid ,api_url, backend_url = get_cid_url(controller_hostname, controller_username, controller_passwd)

    payload = {'action': 'reset_managed_cloudn_to_factory_state',
               'CID': cid,
               'device_name': cloudn_name}
    response = requests.post(api_url, data=payload, verify=False)
    if response.status_code not in range(200, 207) or not response.json().get('return'):
        raise RuntimeError(
            "CaaG Reset From Controller Failure. {}".format(response.json()))
    logger.info('RESULT: {}'.format(response.json().get('results')))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Smoke Test Script')
    parser.add_argument(
        '--op_code', help='op code, 0 reset, 1 register', required=True)
    parser.add_argument('--cn_name', help='CloudN name', required=True)
    parser.add_argument(
        '--cn_hostame', help='login CloudN hostame', required=True)
    parser.add_argument('--cn_username', help='CloudN username', required=True)
    parser.add_argument('--cn_passwd', help='CloudN passwd', required=True)
    parser.add_argument(
        '--vcn_snapname', help='vcn snapshot name', required=False)
    parser.add_argument(
        '--version', help='CloudN upgrade Version', required=False)
    parser.add_argument('--cntrl_hostname',
                        help='controller hostname', required=True)
    parser.add_argument('--cntrl_username',
                        help='controller_username', required=True)
    parser.add_argument(
        '--cntrl_passwd', help='controller_passwd', required=True)

    args = parser.parse_args()

    logger.info('Input arguments: {}'.format(args))
    op_code = args.op_code
    hostame = args.cn_hostame
    username = args.cn_username
    passwd = args.cn_passwd
    controller_hostname = args.cntrl_hostname
    controller_username = args.cntrl_username
    controller_passwd = args.cntrl_passwd
    cloudn_name = args.cn_name
    vcn_snapshot_name = args.vcn_snapname
    upgrade_version = args.version


    # relase VCN's marking
    if op_code == '0':
        logger.info("step 1: First time login cloudn")
        cid ,api_url, backend_url = get_cid_url(hostame, username, passwd)
        logger.info("step 2: Reset CaaG")
        reset_caag(CID=cid, URL=api_url)

        logger.info("step 3: Reset CaaG from Controller")
        reset_caag_from_controller(controller_hostname=controller_hostname, controller_username=controller_username,
                                   controller_passwd=controller_passwd, cloudn_name=cloudn_name)

        logger.info('step 4: Release vCloudN from Exsi')
        inv = Inventory()
        inv.initialize_inventory()
        inv.refresh_inventory_state()
        vcn = inv.get_inventory_object('vm', cloudn_name)

        # set cloudn state to False
        vcn.state.in_ci_use = False
        vcn.update_tags()
        logger.info(vcn.state.__dict__)

        # revert vcn to golden Img
        try:
            if vcn_snapshot_name == "":
                vcn_snapshot_name = None
            utils.revert_vm_to_snapshot(vcn, vcn_snapshot_name)

        except Exception as e:
            raise Exception(e)

    # registration VCN and mark it in using.
    elif op_code == '1':
        logger.info("step 1: First time login cloudn")
        cid ,api_url, backend_url = get_cid_url(hostame, username, passwd)

        logger.info("step 2: set vcloudn state to occupied")
        try:
            inv = Inventory()
            inv.initialize_inventory()
            inv.refresh_inventory_state()
            vcn = inv.get_inventory_object('vm', cloudn_name)
            # set cloudn state to controller hostname
            vcn.state.in_ci_use = controller_hostname
            vcn.update_tags()
            logger.info(vcn.state.__dict__)
        except Exception as e:
            raise Exception(e)

        logger.info("step 3: Reset CaaG")
        reset_caag(CID=cid, URL=api_url)
        time.sleep(90)

        logger.info("step 3: Upgrade CloudN")
        upgrade(hostame, username, passwd, version=upgrade_version)

        cid ,api_url, backend_url = get_cid_url(hostame, username, passwd)
        logger.info("step 4: Register CloudN to Controller")
        register(
            CID=cid, URL=api_url,
            controller_hostname=controller_hostname,
            controller_username=controller_username,
            controller_passwd=controller_passwd,
            cloudn_name=cloudn_name)

        logger.info("Congratulation! CloudN register to Controller is set!!")

