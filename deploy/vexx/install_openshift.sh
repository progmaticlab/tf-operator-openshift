#!/bin/bash

set -ex

OPENSHIFT_CLUSTER_NAME=${CLUSTER_NAME:-"vexx-openshift"}
OPENSHIFT_BASE_DOMAIN=${OPENSHIFT_BASE_DOMAIN:-"hobgoblin.org"}
OPENSHIFT_API_FIP=${OPENSHIFT_API_FIP:-"38.108.68.93"}
OPENSHIFT_INGRESS_FIP=${OPENSHIFT_INGRESS_FIP:-"38.108.68.166"}
OPENSHIFT_INSTALL_PATH=${OPENSHIFT_INSTALL_PATH:-"openshift-install"}
OPENSHIFT_INSTALL_DIR=${OPENSHIFT_INSTALL_DIR:-"os-install-config"}
OS_IMAGE_PUBLIC_SERVICE=${OS_IMAGE_PUBLIC_SERVICE:="https://image.public.sjc1.vexxhost.net/"}
OS_CLOUD=${OS_CLOUD:-"vexx"}

sudo yum install -y python3 epel-release
sudo yum install -y jq
sudo pip3 install python-openstackclient ansible yq

mkdir -p ./tmpopenshift
pushd tmpopenshift
if ! command -v openshift-install; then
  curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.5.21/openshift-install-linux-4.5.21.tar.gz
  tar xzf openshift-install-linux-4.5.21.tar.gz
  sudo mv ./openshift-install /usr/local/bin
fi
if ! command -v oc || ! command -v kubectl; then
  curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.5.21/openshift-client-linux-4.5.21.tar.gz
  tar xzf openshift-client-linux-4.5.21.tar.gz
  sudo mv ./oc ./kubectl /usr/local/bin
fi
popd
rm -rf tmpopenshift

if [[ -z ${OPENSHIFT_PULL_SECRET} ]]; then
  echo "ERROR: set OPENSHIFT_PULL_SECRET env variable"
  exit 1
fi

if [[ -z ${OPENSHIFT_PUB_KEY} ]]; then
  echo "ERROR: set OPENSHIFT_PUB_KEY env variable"
  exit 1
fi

rm -rf $OPENSHIFT_INSTALL_DIR
mkdir -p $OPENSHIFT_INSTALL_DIR

cat <<EOF > ${OPENSHIFT_INSTALL_DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${OPENSHIFT_BASE_DOMAIN}
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: {}
  replicas: 0
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform: {}
  replicas: 3
metadata:
  creationTimestamp: null
  name: ${OPENSHIFT_CLUSTER_NAME}
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.100.0.0/24
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  openstack:
    apiVIP: 10.100.0.5
    cloud: ${OS_CLOUD}
    computeFlavor: v2-highcpu-16
    externalDNS: null
    externalNetwork: public
    ingressVIP: 10.100.0.7
    lbFloatingIP: ${OPENSHIFT_API_FIP}
    octaviaSupport: "1"
    region: ""
    trunkSupport: "0"
publish: External
pullSecret: |
  ${OPENSHIFT_PULL_SECRET}
sshKey: |
  ${OPENSHIFT_PUB_KEY}
EOF

$OPENSHIFT_INSTALL_PATH --dir $OPENSHIFT_INSTALL_DIR create manifests

rm -f ${OPENSHIFT_INSTALL_DIR}/openshift/99_openshift-cluster-api_master-machines-*.yaml ${OPENSHIFT_INSTALL_DIR}/openshift/99_openshift-cluster-api_worker-machineset-*.yaml

$OPENSHIFT_INSTALL_PATH --dir $OPENSHIFT_INSTALL_DIR  create ignition-configs

export INFRA_ID=$(jq -r .infraID $OPENSHIFT_INSTALL_DIR/metadata.json)

cat <<EOF > ${OPENSHIFT_INSTALL_DIR}/setup_bootsrap_ign.py
import base64
import json
import os

with open('${OPENSHIFT_INSTALL_DIR}/bootstrap.ign', 'r') as f:
    ignition = json.load(f)

files = ignition['storage'].get('files', [])

infra_id = os.environ.get('INFRA_ID', 'openshift').encode()
hostname_b64 = base64.standard_b64encode(infra_id + b'-bootstrap\n').decode().strip()
files.append(
{
    'path': '/etc/hostname',
    'mode': 420,
    'contents': {
        'source': 'data:text/plain;charset=utf-8;base64,' + hostname_b64,
        'verification': {}
    },
    'filesystem': 'root',
})

ca_cert_path = os.environ.get('OS_CACERT', '')
if ca_cert_path:
    with open(ca_cert_path, 'r') as f:
        ca_cert = f.read().encode()
        ca_cert_b64 = base64.standard_b64encode(ca_cert).decode().strip()

    files.append(
    {
        'path': '/opt/openshift/tls/cloud-ca-cert.pem',
        'mode': 420,
        'contents': {
            'source': 'data:text/plain;charset=utf-8;base64,' + ca_cert_b64,
            'verification': {}
        },
        'filesystem': 'root',
    })

ignition['storage']['files'] = files;

with open('${OPENSHIFT_INSTALL_DIR}/bootstrap.ign', 'w') as f:
    json.dump(ignition, f)
EOF

python3 ${OPENSHIFT_INSTALL_DIR}/setup_bootsrap_ign.py
if [[ $(openstack image list | grep bootstrap-ignition-image | wc -l) -gt 0 ]]; then
  openstack image delete bootstrap-ignition-image
fi
openstack image create --disk-format=raw --container-format=bare --file ${OPENSHIFT_INSTALL_DIR}/bootstrap.ign bootstrap-ignition-image
uri=$(openstack image show bootstrap-ignition-image | grep -oh "/v2/images/.*/file")
storage_url=${OS_IMAGE_PUBLIC_SERVICE}${uri}
token=$(openstack token issue -c id -f value)
ca_sert=$(cat ${OPENSHIFT_INSTALL_DIR}/auth/kubeconfig | yq -r '.clusters[0].cluster["certificate-authority-data"]')
cat <<EOF > $OPENSHIFT_INSTALL_DIR/$INFRA_ID-bootstrap-ignition.json
{
  "ignition": {
    "config": {
      "append": [{
        "source": "${storage_url}",
        "verification": {},
        "httpHeaders": [{
          "name": "X-Auth-Token",
          "value": "${token}"
        }]
      }]
    },
    "security": {
      "tls": {
        "certificateAuthorities": [{
          "source": "data:text/plain;charset=utf-8;base64,${ca_sert}",
          "verification": {}
        }]
      }
    },
    "timeouts": {},
    "version": "2.4.0"
  },
  "networkd": {},
  "passwd": {},
  "storage": {},
  "systemd": {}
}
EOF

for index in $(seq 0 2); do
    MASTER_HOSTNAME="$INFRA_ID-master-$index\n"
    python3 -c "import base64, json, sys;
ignition = json.load(sys.stdin);
files = ignition['storage'].get('files', []);
files.append({'path': '/etc/hostname', 'mode': 420, 'contents': {'source': 'data:text/plain;charset=utf-8;base64,' + base64.standard_b64encode(b'$MASTER_HOSTNAME').decode().strip(), 'verification': {}}, 'filesystem': 'root'});
ignition['storage']['files'] = files;
json.dump(ignition, sys.stdout)" <$OPENSHIFT_INSTALL_DIR/master.ign > "$OPENSHIFT_INSTALL_DIR/$INFRA_ID-master-$index-ignition.json"
done

cat <<EOF > $OPENSHIFT_INSTALL_DIR/common.yaml
- hosts: localhost
  gather_facts: no

  vars_files:
  - metadata.json

  tasks:
  - name: 'Compute resource names'
    set_fact:
      cluster_id_tag: "openshiftClusterID={{ infraID }}"
      os_network: "{{ infraID }}-network"
      os_subnet: "{{ infraID }}-nodes"
      os_router: "{{ infraID }}-external-router"
      # Port names
      os_port_api: "{{ infraID }}-api-port"
      os_port_ingress: "{{ infraID }}-ingress-port"
      os_port_bootstrap: "{{ infraID }}-bootstrap-port"
      os_port_master: "{{ infraID }}-master-port"
      os_port_worker: "{{ infraID }}-worker-port"
      # Security groups names
      os_sg_master: "{{ infraID }}-master"
      os_sg_worker: "{{ infraID }}-worker"
      # Server names
      os_bootstrap_server_name: "{{ infraID }}-bootstrap"
      os_cp_server_name: "{{ infraID }}-master"
      os_cp_server_group_name: "{{ infraID }}-master"
      os_compute_server_name: "{{ infraID }}-worker"
      # Trunk names
      os_cp_trunk_name: "{{ infraID }}-master-trunk"
      os_compute_trunk_name: "{{ infraID }}-worker-trunk"
      # Subnet pool name
      subnet_pool: "{{ infraID }}-kuryr-pod-subnetpool"
      # Service network name
      os_svc_network: "{{ infraID }}-kuryr-service-network"
      # Service subnet name
      os_svc_subnet: "{{ infraID }}-kuryr-service-subnet"
      # Ignition files
      os_bootstrap_ignition: "{{ infraID }}-bootstrap-ignition.json"
EOF

cat <<EOF > $OPENSHIFT_INSTALL_DIR/inventory.yaml
all:
  hosts:
    localhost:
      ansible_connection: local
      ansible_python_interpreter: "{{ansible_playbook_python}}"

      # User-provided values
      os_subnet_range: '10.100.0.0/24'
      os_flavor_master: 'v2-highcpu-32'
      os_flavor_worker: 'v2-highcpu-16'
      os_image_rhcos: 'rhcos'
      os_external_network: 'public'
      # OpenShift API floating IP address
      os_api_fip: '${OPENSHIFT_API_FIP}'
      # OpenShift Ingress floating IP address
      os_ingress_fip: '${OPENSHIFT_INGRESS_FIP}'
      # Service subnet cidr
      svc_subnet_range: '172.30.0.0/16'
      os_svc_network_range: '172.30.0.0/15'
      # Subnet pool prefixes
      cluster_network_cidrs: '10.128.0.0/14'
      # Subnet pool prefix length
      host_prefix: '23'
      # Name of the SDN.
      # Possible values are OpenshiftSDN or Kuryr.
      os_networking_type: 'OpenshiftSDN'

      # Number of provisioned Control Plane nodes
      # 3 is the minimum number for a fully-functional cluster.
      os_cp_nodes_number: 3

      # Number of provisioned Compute nodes.
      # 3 is the minimum number for a fully-functional cluster.
      os_compute_nodes_number: 3
EOF

cat <<EOF > $OPENSHIFT_INSTALL_DIR/security-groups.yaml
# Required Python packages:
#
# ansible
# openstackclient
# openstacksdk

- import_playbook: common.yaml

- hosts: all
  gather_facts: no

  tasks:
  - name: 'Create the master security group'
    os_security_group:
      name: "{{ os_sg_master }}"

  - name: 'Set master security group tag'
    command:
      cmd: "openstack security group set --tag {{ cluster_id_tag }} {{ os_sg_master }} "

  - name: 'Create the worker security group'
    os_security_group:
      name: "{{ os_sg_worker }}"

  - name: 'Set worker security group tag'
    command:
      cmd: "openstack security group set --tag {{ cluster_id_tag }} {{ os_sg_worker }} "

  - name: 'Create master-sg rule "ICMP"'
    os_security_group_rule:
      security_group: "{{ os_sg_master }}"
      protocol: icmp

  - name: 'Create master-sg rule "machine config server"'
    os_security_group_rule:
      security_group: "{{ os_sg_master }}"
      protocol: tcp
      remote_ip_prefix: "{{ os_subnet_range }}"
      port_range_min: 22623
      port_range_max: 22623

  - name: 'Create master-sg rule "SSH"'
    os_security_group_rule:
      security_group: "{{ os_sg_master }}"
      protocol: tcp
      port_range_min: 22
      port_range_max: 22

  - name: 'Create master-sg rule "DNS (TCP)"'
    os_security_group_rule:
      security_group: "{{ os_sg_master }}"
      remote_ip_prefix: "{{ os_subnet_range }}"
      protocol: tcp
      port_range_min: 53
      port_range_max: 53

  - name: 'Create master-sg rule "DNS (UDP)"'
    os_security_group_rule:
      security_group: "{{ os_sg_master }}"
      remote_ip_prefix: "{{ os_subnet_range }}"
      protocol: udp
      port_range_min: 53
      port_range_max: 53

  - name: 'Create master-sg rule "mDNS"'
    os_security_group_rule:
      security_group: "{{ os_sg_master }}"
      remote_ip_prefix: "{{ os_subnet_range }}"
      protocol: udp
      port_range_min: 5353
      port_range_max: 5353

  - name: 'Create master-sg rule "OpenShift API"'
    os_security_group_rule:
      security_group: "{{ os_sg_master }}"
      protocol: tcp
      port_range_min: 6443
      port_range_max: 6443

  - name: 'Create master-sg rule "VXLAN"'
    os_security_group_rule:
      security_group: "{{ os_sg_master }}"
      protocol: udp
      remote_ip_prefix: "{{ os_subnet_range }}"
      port_range_min: 4789
      port_range_max: 4789

  - name: 'Create master-sg rule "Geneve"'
    os_security_group_rule:
      security_group: "{{ os_sg_master }}"
      protocol: udp
      remote_ip_prefix: "{{ os_subnet_range }}"
      port_range_min: 6081
      port_range_max: 6081

  - name: 'Create master-sg rule "ovndb"'
    os_security_group_rule:
      security_group: "{{ os_sg_master }}"
      protocol: tcp
      remote_ip_prefix: "{{ os_subnet_range }}"
      port_range_min: 6641
      port_range_max: 6642

  - name: 'Create master-sg rule "master ingress internal (TCP)"'
    os_security_group_rule:
      security_group: "{{ os_sg_master }}"
      protocol: tcp
      remote_ip_prefix: "{{ os_subnet_range }}"
      port_range_min: 9000
      port_range_max: 9999

  - name: 'Create master-sg rule "master ingress internal (UDP)"'
    os_security_group_rule:
      security_group: "{{ os_sg_master }}"
      protocol: udp
      remote_ip_prefix: "{{ os_subnet_range }}"
      port_range_min: 9000
      port_range_max: 9999

  - name: 'Create master-sg rule "kube scheduler"'
    os_security_group_rule:
      security_group: "{{ os_sg_master }}"
      protocol: tcp
      remote_ip_prefix: "{{ os_subnet_range }}"
      port_range_min: 10259
      port_range_max: 10259

  - name: 'Create master-sg rule "kube controller manager"'
    os_security_group_rule:
      security_group: "{{ os_sg_master }}"
      protocol: tcp
      remote_ip_prefix: "{{ os_subnet_range }}"
      port_range_min: 10257
      port_range_max: 10257

  - name: 'Create master-sg rule "master ingress kubelet secure"'
    os_security_group_rule:
      security_group: "{{ os_sg_master }}"
      protocol: tcp
      remote_ip_prefix: "{{ os_subnet_range }}"
      port_range_min: 10250
      port_range_max: 10250

  - name: 'Create master-sg rule "etcd"'
    os_security_group_rule:
      security_group: "{{ os_sg_master }}"
      protocol: tcp
      remote_ip_prefix: "{{ os_subnet_range }}"
      port_range_min: 2379
      port_range_max: 2380

  - name: 'Create master-sg rule "master ingress services (TCP)"'
    os_security_group_rule:
      security_group: "{{ os_sg_master }}"
      protocol: tcp
      remote_ip_prefix: "{{ os_subnet_range }}"
      port_range_min: 30000
      port_range_max: 32767

  - name: 'Create master-sg rule "master ingress services (UDP)"'
    os_security_group_rule:
      security_group: "{{ os_sg_master }}"
      protocol: udp
      remote_ip_prefix: "{{ os_subnet_range }}"
      port_range_min: 30000
      port_range_max: 32767

  - name: 'Create master-sg rule "VRRP"'
    os_security_group_rule:
      security_group: "{{ os_sg_master }}"
      protocol: '112'
      remote_ip_prefix: "{{ os_subnet_range }}"


  - name: 'Create worker-sg rule "ICMP"'
    os_security_group_rule:
      security_group: "{{ os_sg_worker }}"
      protocol: icmp

  - name: 'Create worker-sg rule "SSH"'
    os_security_group_rule:
      security_group: "{{ os_sg_worker }}"
      protocol: tcp
      port_range_min: 22
      port_range_max: 22

  - name: 'Create worker-sg rule "mDNS"'
    os_security_group_rule:
      security_group: "{{ os_sg_worker }}"
      protocol: udp
      remote_ip_prefix: "{{ os_subnet_range }}"
      port_range_min: 5353
      port_range_max: 5353

  - name: 'Create worker-sg rule "Ingress HTTP"'
    os_security_group_rule:
      security_group: "{{ os_sg_worker }}"
      protocol: tcp
      port_range_min: 80
      port_range_max: 80

  - name: 'Create worker-sg rule "Ingress HTTPS"'
    os_security_group_rule:
      security_group: "{{ os_sg_worker }}"
      protocol: tcp
      port_range_min: 443
      port_range_max: 443

  - name: 'Create worker-sg rule "router"'
    os_security_group_rule:
      security_group: "{{ os_sg_worker }}"
      protocol: tcp
      remote_ip_prefix: "{{ os_subnet_range }}"
      port_range_min: 1936
      port_range_max: 1936

  - name: 'Create worker-sg rule "VXLAN"'
    os_security_group_rule:
      security_group: "{{ os_sg_worker }}"
      protocol: udp
      remote_ip_prefix: "{{ os_subnet_range }}"
      port_range_min: 4789
      port_range_max: 4789

  - name: 'Create worker-sg rule "Geneve"'
    os_security_group_rule:
      security_group: "{{ os_sg_worker }}"
      protocol: udp
      remote_ip_prefix: "{{ os_subnet_range }}"
      port_range_min: 6081
      port_range_max: 6081

  - name: 'Create worker-sg rule "worker ingress internal (TCP)"'
    os_security_group_rule:
      security_group: "{{ os_sg_worker }}"
      protocol: tcp
      remote_ip_prefix: "{{ os_subnet_range }}"
      port_range_min: 9000
      port_range_max: 9999

  - name: 'Create worker-sg rule "worker ingress internal (UDP)"'
    os_security_group_rule:
      security_group: "{{ os_sg_worker }}"
      protocol: udp
      remote_ip_prefix: "{{ os_subnet_range }}"
      port_range_min: 9000
      port_range_max: 9999

  - name: 'Create worker-sg rule "worker ingress kubelet insecure"'
    os_security_group_rule:
      security_group: "{{ os_sg_worker }}"
      protocol: tcp
      remote_ip_prefix: "{{ os_subnet_range }}"
      port_range_min: 10250
      port_range_max: 10250

  - name: 'Create worker-sg rule "worker ingress services (TCP)"'
    os_security_group_rule:
      security_group: "{{ os_sg_worker }}"
      protocol: tcp
      remote_ip_prefix: "{{ os_subnet_range }}"
      port_range_min: 30000
      port_range_max: 32767

  - name: 'Create worker-sg rule "worker ingress services (UDP)"'
    os_security_group_rule:
      security_group: "{{ os_sg_worker }}"
      protocol: udp
      remote_ip_prefix: "{{ os_subnet_range }}"
      port_range_min: 30000
      port_range_max: 32767

  - name: 'Create worker-sg rule "VRRP"'
    os_security_group_rule:
      security_group: "{{ os_sg_worker }}"
      protocol: '112'
      remote_ip_prefix: "{{ os_subnet_range }}"
EOF

cat <<EOF >$OPENSHIFT_INSTALL_DIR/network.yaml
# Required Python packages:
#
# ansible
# openstackclient
# openstacksdk
# netaddr

- import_playbook: common.yaml

- hosts: all
  gather_facts: no

  tasks:
  - name: 'Create the cluster network'
    os_network:
      name: "{{ os_network }}"

  - name: 'Set the cluster network tag'
    command:
      cmd: "openstack network set --tag {{ cluster_id_tag }} {{ os_network }}"

  - name: 'Create a subnet'
    os_subnet:
      name: "{{ os_subnet }}"
      network_name: "{{ os_network }}"
      cidr: "{{ os_subnet_range }}"
      allocation_pool_start: "{{ os_subnet_range | next_nth_usable(10) }}"
      allocation_pool_end: "{{ os_subnet_range | ipaddr('last_usable') }}"

  - name: 'Set the cluster subnet tag'
    command:
      cmd: "openstack subnet set --tag {{ cluster_id_tag }} {{ os_subnet }}"

  - name: 'Create the service network'
    os_network:
      name: "{{ os_svc_network }}"
    when: os_networking_type == "Kuryr"

  - name: 'Set the service network tag'
    command:
      cmd: "openstack network set --tag {{ cluster_id_tag }} {{ os_svc_network }}"
    when: os_networking_type == "Kuryr"

  - name: 'Computing facts for service subnet'
    set_fact:
      first_ip_svc_subnet_range: "{{ svc_subnet_range | ipv4('network') }}"
      last_ip_svc_subnet_range: "{{ svc_subnet_range | ipaddr('last_usable') |ipmath(1) }}"
      first_ip_os_svc_network_range: "{{ os_svc_network_range | ipv4('network') }}"
      last_ip_os_svc_network_range: "{{ os_svc_network_range | ipaddr('last_usable') |ipmath(1) }}"
      allocation_pool: ""
    when: os_networking_type == "Kuryr"

  - name: 'Get first part of OpenStack network'
    set_fact:
      allocation_pool: "{{ allocation_pool + '--allocation-pool start={{ first_ip_os_svc_network_range | ipmath(1) }},end={{ first_ip_svc_subnet_range |ipmath(-1) }}' }}"
    when:
    - os_networking_type == "Kuryr"
    - first_ip_svc_subnet_range != first_ip_os_svc_network_range

  - name: 'Get last part of OpenStack network'
    set_fact:
      allocation_pool: "{{ allocation_pool + ' --allocation-pool start={{ last_ip_svc_subnet_range | ipmath(1) }},end={{ last_ip_os_svc_network_range |ipmath(-1) }}' }}"
    when:
    - os_networking_type == "Kuryr"
    - last_ip_svc_subnet_range != last_ip_os_svc_network_range

  - name: 'Get end of allocation'
    set_fact:
      gateway_ip: "{{ allocation_pool.split('=')[-1] }}"
    when: os_networking_type == "Kuryr"

  - name: 'replace last IP'
    set_fact:
      allocation_pool: "{{ allocation_pool | replace(gateway_ip, gateway_ip | ipmath(-1))}}"
    when: os_networking_type == "Kuryr"

  - name: 'list service subnet'
    command:
      cmd: "openstack subnet list --name {{ os_svc_subnet }} --tag {{ cluster_id_tag }}"
    when: os_networking_type == "Kuryr"
    register: svc_subnet

  - name: 'Create the service subnet'
    command:
      cmd: "openstack subnet create --ip-version 4 --gateway {{ gateway_ip }} --subnet-range {{ os_svc_network_range }} {{ allocation_pool }} --no-dhcp --network {{ os_svc_network }} --tag {{ cluster_id_tag }} {{ os_svc_subnet }}"
    when:
    - os_networking_type == "Kuryr"
    - svc_subnet.stdout == ""

  - name: 'list subnet pool'
    command:
      cmd: "openstack subnet pool list --name {{ subnet_pool }} --tags {{ cluster_id_tag }}"
    when: os_networking_type == "Kuryr"
    register: pods_subnet_pool

  - name: 'Create pods subnet pool'
    command:
      cmd: "openstack subnet pool create --default-prefix-length {{ host_prefix }} --pool-prefix {{ cluster_network_cidrs }} --tag {{ cluster_id_tag }} {{ subnet_pool }}"
    when:
    - os_networking_type == "Kuryr"
    - pods_subnet_pool.stdout == ""

  - name: 'Create external router'
    os_router:
      name: "{{ os_router }}"
      network: "{{ os_external_network }}"
      interfaces:
      - "{{ os_subnet }}"

  - name: 'Set external router tag'
    command:
      cmd: "openstack router set --tag {{ cluster_id_tag }} {{ os_router }}"
    when: os_networking_type == "Kuryr"

  - name: 'Create the API port'
    os_port:
      name: "{{ os_port_api }}"
      network: "{{ os_network }}"
      security_groups:
      - "{{ os_sg_master }}"
      fixed_ips:
      - subnet: "{{ os_subnet }}"
        ip_address: "{{ os_subnet_range | next_nth_usable(5) }}"

  - name: 'Set API port tag'
    command:
      cmd: "openstack port set --tag {{ cluster_id_tag }} {{ os_port_api }}"

  - name: 'Create the Ingress port'
    os_port:
      name: "{{ os_port_ingress }}"
      network: "{{ os_network }}"
      security_groups:
      - "{{ os_sg_worker }}"
      fixed_ips:
      - subnet: "{{ os_subnet }}"
        ip_address: "{{ os_subnet_range | next_nth_usable(7) }}"

  - name: 'Set the Ingress port tag'
    command:
      cmd: "openstack port set --tag {{ cluster_id_tag }} {{ os_port_ingress }}"

  # NOTE: openstack ansible module doesn't allow attaching Floating IPs to
  # ports, let's use the CLI instead
  - name: 'Attach the API floating IP to API port'
    command:
      cmd: "openstack floating ip set --port {{ os_port_api }} {{ os_api_fip }}"

  # NOTE: openstack ansible module doesn't allow attaching Floating IPs to
  # ports, let's use the CLI instead
  - name: 'Attach the Ingress floating IP to Ingress port'
    command:
      cmd: "openstack floating ip set --port {{ os_port_ingress }} {{ os_ingress_fip }}"
EOF

ansible-playbook -i $OPENSHIFT_INSTALL_DIR/inventory.yaml $OPENSHIFT_INSTALL_DIR/security-groups.yaml
ansible-playbook -i $OPENSHIFT_INSTALL_DIR/inventory.yaml $OPENSHIFT_INSTALL_DIR/network.yaml

cat <<EOF > $OPENSHIFT_INSTALL_DIR/bootstrap.yaml
# Required Python packages:
#
# ansible
# openstackclient
# openstacksdk
# netaddr

- import_playbook: common.yaml

- hosts: all
  gather_facts: no

  tasks:
  - name: 'Create the bootstrap server port'
    os_port:
      name: "{{ os_port_bootstrap }}"
      network: "{{ os_network }}"
      security_groups:
      - "{{ os_sg_master }}"
      allowed_address_pairs:
      - ip_address: "{{ os_subnet_range | next_nth_usable(5) }}"
      - ip_address: "{{ os_subnet_range | next_nth_usable(6) }}"

  - name: 'Set bootstrap port tag'
    command:
      cmd: "openstack port set --tag {{ cluster_id_tag }} {{ os_port_bootstrap }}"

  - name: 'Create the bootstrap server'
    os_server:
      name: "{{ os_bootstrap_server_name }}"
      image: "{{ os_image_rhcos }}"
      flavor: "{{ os_flavor_master }}"
      volume_size: 25
      boot_from_volume: True
      userdata: "{{ lookup('file', os_bootstrap_ignition) | string }}"
      auto_ip: no
      nics:
      - port-name: "{{ os_port_bootstrap }}"

  - name: 'Create the bootstrap floating IP'
    os_floating_ip:
      state: present
      network: "{{ os_external_network }}"
      server: "{{ os_bootstrap_server_name }}"
EOF

ansible-playbook -i ${OPENSHIFT_INSTALL_DIR}/inventory.yaml ${OPENSHIFT_INSTALL_DIR}/bootstrap.yaml

cat <<EOF > ${OPENSHIFT_INSTALL_DIR}/control-plane.yaml
- import_playbook: common.yaml

- hosts: all
  gather_facts: no

  tasks:
  - name: 'Create the Control Plane ports'
    os_port:
      name: "{{ item.1 }}-{{ item.0 }}"
      network: "{{ os_network }}"
      security_groups:
      - "{{ os_sg_master }}"
      allowed_address_pairs:
      - ip_address: "{{ os_subnet_range | next_nth_usable(5) }}"
      - ip_address: "{{ os_subnet_range | next_nth_usable(6) }}"
      - ip_address: "{{ os_subnet_range | next_nth_usable(7) }}"
    with_indexed_items: "{{ [os_port_master] * os_cp_nodes_number }}"
    register: ports

  - name: 'Set Control Plane ports tag'
    command:
      cmd: "openstack port set --tag {{ cluster_id_tag }} {{ item.1 }}-{{ item.0 }}"
    with_indexed_items: "{{ [os_port_master] * os_cp_nodes_number }}"

  - name: 'List the Control Plane Trunks'
    command:
      cmd: "openstack network trunk list"
    when: os_networking_type == "Kuryr"
    register: control_plane_trunks

  - name: 'Create the Control Plane trunks'
    command:
      cmd: "openstack network trunk create --parent-port {{ item.1.id }} {{ os_cp_trunk_name }}-{{ item.0 }}"
    with_indexed_items: "{{ ports.results }}"
    when:
    - os_networking_type == "Kuryr"
    - "os_cp_trunk_name|string not in control_plane_trunks.stdout"

  - name: 'List the Server groups'
    command:
      cmd: "openstack server group list -f json -c ID -c Name"
    register: server_group_list

  - name: 'Parse the Server group ID from existing'
    set_fact:
      server_group_id: "{{ (server_group_list.stdout | from_json | json_query(list_query) | first).ID }}"
    vars:
      list_query: "[?Name=='{{ os_cp_server_group_name }}']"
    when:
    - "os_cp_server_group_name|string in server_group_list.stdout"

  - name: 'Create the Control Plane server group'
    command:
      cmd: "openstack --os-compute-api-version=2.15 server group create -f json -c id --policy=soft-anti-affinity {{ os_cp_server_group_name }}"
    register: server_group_created
    when:
    - server_group_id is not defined

  - name: 'Parse the Server group ID from creation'
    set_fact:
      server_group_id: "{{ (server_group_created.stdout | from_json).id }}"
    when:
    - server_group_id is not defined

  - name: 'Create the Control Plane servers'
    os_server:
      name: "{{ item.1 }}-{{ item.0 }}"
      image: "{{ os_image_rhcos }}"
      flavor: "{{ os_flavor_master }}"
      volume_size: 25
      boot_from_volume: True
      auto_ip: no
      # The ignition filename will be concatenated with the Control Plane node
      # name and its 0-indexed serial number.
      # In this case, the first node will look for this filename:
      #    "{{ infraID }}-master-0-ignition.json"
      userdata: "{{ lookup('file', [item.1, item.0, 'ignition.json'] | join('-')) | string }}"
      nics:
      - port-name: "{{ os_port_master }}-{{ item.0 }}"
      scheduler_hints:
        group: "{{ server_group_id }}"
    with_indexed_items: "{{ [os_cp_server_name] * os_cp_nodes_number }}"
EOF

ansible-playbook -i ${OPENSHIFT_INSTALL_DIR}/inventory.yaml ${OPENSHIFT_INSTALL_DIR}/control-plane.yaml

${OPENSHIFT_INSTALL_PATH} --dir ${OPENSHIFT_INSTALL_DIR} wait-for bootstrap-complete

cat <<EOF > ${OPENSHIFT_INSTALL_DIR}/down-bootstrap.yaml
- import_playbook: common.yaml

- hosts: all
  gather_facts: no

  tasks:
  - name: 'Remove the bootstrap server'
    os_server:
      name: "{{ os_bootstrap_server_name }}"
      state: absent
      delete_fip: yes

  - name: 'Remove the bootstrap server port'
    os_port:
      name: "{{ os_port_bootstrap }}"
      state: absent
EOF

ansible-playbook -i ${OPENSHIFT_INSTALL_DIR}/inventory.yaml ${OPENSHIFT_INSTALL_DIR}/down-bootstrap.yaml

cat <<EOF > ${OPENSHIFT_INSTALL_DIR}/compute-nodes.yaml
- import_playbook: common.yaml

- hosts: all
  gather_facts: no

  tasks:
  - name: 'Create the Compute ports'
    os_port:
      name: "{{ item.1 }}-{{ item.0 }}"
      network: "{{ os_network }}"
      security_groups:
      - "{{ os_sg_worker }}"
      allowed_address_pairs:
      - ip_address: "{{ os_subnet_range | next_nth_usable(7) }}"
    with_indexed_items: "{{ [os_port_worker] * os_compute_nodes_number }}"
    register: ports

  - name: 'Set Compute ports tag'
    command:
      cmd: "openstack port set --tag {{ cluster_id_tag }} {{ item.1 }}-{{ item.0 }}"
    with_indexed_items: "{{ [os_port_worker] * os_compute_nodes_number }}"

  - name: 'List the Compute Trunks'
    command:
      cmd: "openstack network trunk list"
    when: os_networking_type == "Kuryr"
    register: compute_trunks

  - name: 'Create the Compute trunks'
    command:
      cmd: "openstack network trunk create --parent-port {{ item.1.id }} {{ os_compute_trunk_name }}-{{ item.0 }}"
    with_indexed_items: "{{ ports.results }}"
    when:
    - os_networking_type == "Kuryr"
    - "os_compute_trunk_name|string not in compute_trunks.stdout"

  - name: 'Create the Compute servers'
    os_server:
      name: "{{ item.1 }}-{{ item.0 }}"
      image: "{{ os_image_rhcos }}"
      flavor: "{{ os_flavor_worker }}"
      volume_size: 25
      boot_from_volume: True
      auto_ip: no
      userdata: "{{ lookup('file', 'worker.ign') | string }}"
      nics:
      - port-name: "{{ os_port_worker }}-{{ item.0 }}"
    with_indexed_items: "{{ [os_compute_server_name] * os_compute_nodes_number }}"
EOF

ansible-playbook -i ${OPENSHIFT_INSTALL_DIR}/inventory.yaml ${OPENSHIFT_INSTALL_DIR}/compute-nodes.yaml

mkdir -p ~/.kube
cp ${OPENSHIFT_INSTALL_DIR}/auth/kubeconfig ~/.kube/config
chmod go-rwx ~/.kube/config

# We have to approve 6 certs totally
count=6
while [[ $count -gt 0 ]]; do
  for cert in $(oc get csr | grep Pending | sed 's/|/ /' | awk '{print $1}'); do
    oc adm certificate approve $cert
    count=$((count-1))
  done
  sleep 3s
done

openshift-install  --dir ${OPENSHIFT_INSTALL_DIR}  --log-level debug wait-for install-complete

echo "INFO: Openshift Setup Complete"