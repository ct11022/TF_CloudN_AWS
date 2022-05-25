import argparse
import ipaddress
import logging
import paramiko
import requests
import sys
import time
import unittest

from requests.exceptions import Timeout, URLRequired

requests.packages.urllib3.disable_warnings()

logging.basicConfig(
    filename='smoke_test.log',
    filemode='w',
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)

logger = logging.getLogger(__name__)


class UseLoopDec(object):
    """
    This Decorator is used to extend the existing function and add loop logic for verification
    EX use:
    @UseLoopDec(3, 30)
    def verify_xxx()
    func verify_xxx() will run max 3 times upon failure and wait 30 second in between
    """

    def __init__(self, count=10, wait=30):
        """
        :param count: Max number of loop to verify the func
        :param wait: Wait time between each func run
        """
        self.count = count
        self.wait = wait

    def __call__(self, func):
        """
        :param func: The func to be called. The func must use API get and has True/False as return
        """
        decorator_self = self

        def wrapper(*args, **kwargs):
            logger.info("%s is running" % func.__name__)
            for i in range(decorator_self.count):
                if func(*args, **kwargs):
                    logger.info("%s Pass" % func.__name__)
                    return True
                else:
                    logger.error("%s Fail, wait to retry" % func.__name__)
                    time.sleep(decorator_self.wait)
            else:
                logger.error("%s still Fail after %s second" % (
                    func.__name__, decorator_self.count*decorator_self.wait))
                return False
        return wrapper


def get_aviatrix_api_endpoint_url(controller_ip=None, api_version="v1", path="api"):
    """
    Get the aviatrix api endpoint URL.
    :param controller_ip <str>: controller ip
    :param api_version <str>: api version
    :param path <str>: api path
    :return: url with api path, url with backend path
    """
    endpoint_url = "https://{HOSTNAME}/{VERSION}/{PATH}"

    try:
        ipaddress.ip_address(controller_ip.split(":")[0])
    except ipaddress.AddressValueError as e:
        logger.error(e)
        raise Exception()
    else:
        api_endpoint_url = endpoint_url.format(
            HOSTNAME=controller_ip,
            VERSION=api_version,
            PATH=path
        )
        backend_endpoint_url = endpoint_url.format(
            HOSTNAME=controller_ip,
            VERSION=api_version,
            PATH='backend1'
        )
        return api_endpoint_url, backend_endpoint_url


def get_cid(api_url=None, user=None, passwd=None):
    """
    get CID.
    :return: CID
    """
    payload = {
        "action": "login",
        "username": user,
        "password": passwd
    }
    response = requests.get(api_url,
                            params=payload,
                            verify=False)
    avx_api_login_dict = response.json()

    if (response.status_code not in range(200, 207)) or (avx_api_login_dict.get("return") is False):
        raise RuntimeError("Cannot acquire CID.")
    else:
        cid = avx_api_login_dict.get("CID")
        # logger.debug("Acquired CID: %s." % cid)
        return cid


@UseLoopDec(20, 15)
def gw_status_checker(api_url, cid, device_name):

    payload = {'action': 'list_gateway_upgrade_status'}
    payload["CID"] = cid
    try:
        response = requests.get(
            url=api_url, params=payload, timeout=5, verify=False)

        if response.status_code not in range(200, 207):
            raise RuntimeError("HTTP status code not 200")

        rsp_dict = response.json()
        if not rsp_dict['return']:
            raise Exception(rsp_dict)

        for gw_info in rsp_dict['results']['gw_info']:
            if gw_info['name'] == device_name:
                logger.debug('{} : VPA_state: {}, update_status: {}'.format(
                    gw_info['name'], gw_info['vpc_state'], gw_info['update_status']))
                if gw_info['vpc_state'] != 'up' or gw_info['update_status'] != 'complete':
                    return False
                return True
        else:
            logger.debug(rsp_dict)
            raise Exception('{} not exists in the data'.format(device_name))

    except requests.exceptions.Timeout as e:
        return False


def get_kernel_version(api_url, CID):
    try:
        payload = {
            'action': 'list_version_info',
            'CID': CID,
        }
        response = requests.get(url=api_url, params=payload, verify=False)
        if response.status_code not in range(200, 207):
            raise Exception("HTTP status code not 200")

        if response.json()['return']:
            return response.json()['results']['kernel_version']
        else:
            return response.json()

    except requests.exceptions.Timeout as e:
        return False


def remove_new_line_characters(string=""):
    if "\n" in string:
        string = string.replace("\n", "")

    return string


@UseLoopDec(8, 60)
def tunnelchecker(sshclient, CloudN_kernel_version, cn_num, expect_tunn):

    if "4.15" in CloudN_kernel_version:
        logger.info('    {} Kernel Version {}, Is Racoon'.format(
            cn_num, CloudN_kernel_version)
        )

        # Ph2CountIs0 = avx_ping_test.execute_command("sudo racoonctl -ll ss isakmp | grep -c \'[^a-zA-Z]0 *$\'")
        command = "sudo racoonctl -ll ss isakmp | grep -c \'[^a-zA-Z][1-9] *$\'"
        stdin, stdout, stderr = sshclient.exec_command(command=command)

        results = list()
        # Print Result
        for line in stdout.readlines():
            line = remove_new_line_characters(line)
            results.append(line)
            # logger.debug(line)

        # established tunnles need reached 90% is pass, ,
        logger.info('    {} Currently S2C Tunnels {}'.format(
            cn_num, results[0]
        ))

        if eval(results[0]) >= eval(expect_tunn)*0.9:
            return True

        logger.error(
            'Failed Established tunnels not enough required {}/{}, Currently {}/{}'.format(
                eval(expect_tunn)*0.9,
                expect_tunn,
                int(results[0]),
                expect_tunn
            ))
        return False

    if "5.4" in CloudN_kernel_version:
        logger.info('    {} Kernel Version {}, Is StrongSwan'.format(
            cn_num, CloudN_kernel_version)
        )
        # result = sshclient.execute_command("sudo swanctl -l | grep -c INSTALL")
        command = "sudo swanctl -l | grep -c INSTALL"
        stdin, stdout, stderr = sshclient.exec_command(command=command)

        results = list()
        # Print Result
        for line in stdout.readlines():
            line = remove_new_line_characters(line)
            results.append(line)
            # logger.debug(line)

        logger.info('    {} Currently S2C Tunnels {}'.format(
            cn_num, results[0]
        ))

        if int(results[0]) >= expect_tunn-2:
            return True

        logger.error(
            'Failed Established tunnels not enough required {}/{}, Currently {}/{}'.format(
                expect_tunn-2,
                expect_tunn,
                int(results[0]),
                expect_tunn
            ))
        return False


class Test(object):
    # def __init__(self):
    #     super().__init__()
    def __init__(self, args):
        self.__write_result("PASS")

        self.controller_ip = args.controller_hostname
        self.controller_username = args.controller_username
        self.controller_password = args.controller_passwd
        self.spoke_vm = args.spoke_vm
        self.pem_path = args.spoke_pem_path
        self.expt_tunnel = args.expt_tunnel
        self.cloudn = args.cn_name
        self.conn_name = args.conn_name
        self.cn_hostname = args.cn_hostname
        self.cn_username = args.cn_username
        self.cn_password = args.cn_passwd
        self.cn_ssh_username = args.cn_ssh_username
        self.cn_ssh_password = args.cn_ssh_passwd
        self.cn_ssh_prot = args.cn_ssh_prot
        self.cn_api_prot = args.cn_api_prot
        self.onprem_ip = args.onprem_ip
        self.vpc_id = args.vpc_id

        try:
            self.api_endpoint_url, self.backend_endpoint_url = get_aviatrix_api_endpoint_url(
                controller_ip=self.controller_ip)
            self.cid = get_cid(api_url=self.api_endpoint_url,
                               user=self.controller_username, passwd=self.controller_password)
            logger.info('api url: {}'.format(self.api_endpoint_url))
            logger.info('CID: {}'.format(self.cid))
        except Exception as e:
            logger.exception(str(e))
            logger.error("Failed to login to controller IP {}}",
                         format(self.controller_ip))
            self.result = "FAIL"

    # def __exit__(self, exc_type, exc_val, exc_tb):
    #     # self.__write_result(self.result)
    #     print ("__exit__")
    # def __del__(self):
    #     print ("__del__")

    def test_01_upgrade_cloudn(self):
        logger.info('Start test_01_upgrade_cloudn')
        payload = {"action": "upgrade_selected_gateway",
                   "software_version": 'latest',
                   "force_upgrade": False,
                   "async": True
                   }
        payload["gateway_list"] = self.cloudn
        payload["CID"] = self.cid

        try:
            response = requests.post(self.api_endpoint_url,
                                     data=payload,
                                     verify=False)

            if response.status_code not in range(200, 207):
                raise RuntimeError("Call upgrade api failed")

            if not (
                gw_status_checker(
                    api_url=self.api_endpoint_url,
                    cid=self.cid,
                    device_name=self.cloudn
                )
            ):
                raise Exception(
                    '{} status check failed after upgrade.'.format(self.cloudn))

        except Exception as e:
            logger.exception(str(e))
            logger.error(e)
            self.__write_result("FAIL")

    def test_02_run_diag(self):
        logger.info('Start test_02_run_diag')
        payload = {"action": "run_site2cloud_diag",
                   "vpc_id": self.vpc_id,
                   "gateway_name": self.cloudn,
                   "action_name": "run_analysis",
                   "connection_name": self.conn_name
                   }
        payload["CID"] = self.cid

        try:
            response = requests.post(self.api_endpoint_url,
                                     data=payload,
                                     verify=False)

            if response.status_code not in range(200, 207):
                raise RuntimeError("Call run_site2cloud_diag api failed")
            logger.debug('response :{}'.format(response.json()))
            if not response.json()['return']:
                raise Exception(response.json())

            if '{} is UP'.format(self.conn_name) not in response.json()['results']:
                raise Exception('Run Diagnosic show connection not up. \'{}\''.format(
                    response.json()))

        except Exception as e:
            logger.exception(str(e))
            logger.error(e)
            self.__write_result("FAIL")

    def test_03_ping(self):
        logger.info('test_03_ping')
        try:

            # Check CloudN s2c tunnel countting.
            cn_api_endpoint_url, cn_backend_endpoint_url = get_aviatrix_api_endpoint_url(
                controller_ip="{}:{}".format(self.cn_hostname, self.cn_api_prot) if bool(self.cn_api_prot) else self.cn_hostname)
            cn_cid = get_cid(api_url=cn_api_endpoint_url,
                             user=self.cn_username, passwd=self.cn_password)
            logger.info('api url: {}'.format(cn_api_endpoint_url))
            logger.info('CID: {}'.format(cn_cid))

            cn_ssh_client = paramiko.SSHClient()
            cn_ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            cn_ssh_client.connect(
                hostname=self.cn_hostname,
                username=self.cn_ssh_username,
                password=self.cn_ssh_password,
                port=self.cn_ssh_prot
            )
            cn_kernel_ver = get_kernel_version(cn_api_endpoint_url, cn_cid)
            if not (tunnelchecker(
                cn_ssh_client,
                cn_kernel_ver,
                self.cloudn,
                self.expt_tunnel
            )
            ):
                raise Exception()

            # ip_str = " ".join([self.onprem_ip])
            cmd = "fping {} -q -i 1 -r 3 -u -x {}".format(self.onprem_ip, 1)

            ssh_client = paramiko.SSHClient()
            pem_key = paramiko.RSAKey.from_private_key_file(self.pem_path)
            ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh_client.connect(
                hostname=self.spoke_vm,
                username='ubuntu',
                pkey=pem_key
            )
            stdin, stdout, stderr = ssh_client.exec_command(cmd, timeout=60)
            r_stdout = stdout.readlines()[0]
            logger.info(r_stdout)
            if 'Target IP Unreachable' in r_stdout:
                raise Exception()

        except Exception as e:
            logger.exception(str(e))
            logger.error(e)
            self.__write_result("FAIL")

    def __write_result(self, result):
        with open('result.txt', 'w') as result_file:
            result_file.write(result+'\n')


if __name__ == "__main__":

    parser = argparse.ArgumentParser(description='Smoke Test Script')
    parser.add_argument('--controller_hostname',
                        help='Controller IP address or FQDN')
    parser.add_argument('--controller_username', help='Controller username')
    parser.add_argument('--controller_passwd', help='Controller password')
    parser.add_argument('--cn_hostname', help='CloudN IP address or FQDN')
    parser.add_argument('--cn_username', help='CloudN username')
    parser.add_argument('--cn_passwd', help='CloudN password')
    parser.add_argument('--cn_ssh_username', help='CloudN SSH username')
    parser.add_argument('--cn_ssh_passwd', help='CloudN SSH password')
    parser.add_argument('--cn_name', help='CloudN device Name')
    parser.add_argument(
        '--conn_name', help='Connection name of Transit attach with ClounN')
    parser.add_argument('--cn_api_prot', help='Access ClounN API port number')
    parser.add_argument('--cn_ssh_prot', help='Access ClounN SSH port number')
    parser.add_argument('--spoke_vm', help='Spoke VM IP address')
    parser.add_argument('--onprem_ip', help='On-Prem IP address')
    parser.add_argument(
        '--expt_tunnel', help='The number of tunnel should expect')
    parser.add_argument('--spoke_pem_path', help='Spoke Pem file')
    # parser.add_argument('--cn_pem_path',help='CloudN Pem file')
    parser.add_argument('--vpc_id', help='Transit VPC ID')

    args = parser.parse_args()

    test = Test(args)
    test.test_01_upgrade_cloudn()
    test.test_02_run_diag()
    test.test_03_ping()
