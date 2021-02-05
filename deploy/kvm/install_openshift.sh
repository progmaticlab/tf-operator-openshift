#!/bin/bash

set -ex

my_file=$(realpath "$0")
my_dir="$(dirname $my_file)"
start_ts=$(date +%s)

function err() {
    echo "${1}"
    exit 1
}

[[ -n "${OPENSHIFT_PULL_SECRET}" ]] || err "set OPENSHIFT_PULL_SECRET env variable"
[[ -n "${OPENSHIFT_PUB_KEY}" ]] || err "set OPENSHIFT_PUB_KEY env variable"

OPENSHIFT_PUB_KEY_FILE="sshkey.pub"
OCP_VERSION=${OCP_VERSION:-"4.5.21"}
RHCOS_VERSION=${RHCOS_VERSION:="4.6/4.6.8"}
RHCOS_IMAGE="rhcos-metal.x86_64.raw.gz"
RHCOS_KERNEL="rhcos-live-kernel-x86_64"
RHCOS_INITRAMFS="rhcos-live-initramfs.x86_64.img"
N_MASTER=${N_MASTER:-"3"}
N_WORKER=${N_WORKER:-"2"}
MASTER_CPU=${MASTER_CPU:-"4"}
MASTER_MEM=${MASTER_MEM:-"16000"}
WORKER_CPU=${WORKER_CPU:-"2"}
WORKER_MEM=${WORKER_MEM:-"8000"}
BOOTSTRAP_CPU=${BOOTSTRAP_CPU:-"4"}
BOOTSTRAP_MEM=${BOOTSTRAP_MEM:-"16000"}
LOADBALANCER_CPU=${LOADBALANCER_CPU:-"1"}
LOADBALANCER_MEM=${LOADBALANCER_MEM:-"1024"}
VIRTUAL_NET=${VIRTUAL_NET:-"openshift"}
BASE_DOMAIN=${BASE_DOMAIN:-"hobgoblin.org"}
CLUSTER_NAME=${CLUSTER_NAME:-"cluster1"}
INSTALL_DIR=${INSTALL_DIR:-"${HOME}/install-${CLUSTER_NAME}"}
DOWNLOADS_DIR=${DOWNLOADS_DIR:-"${HOME}/downloads-${CLUSTER_NAME}"}

DNS_DIR="/etc/dnsmasq.d"
VM_DIR="/var/lib/libvirt/images"
OCP_MIRROR="https://mirror.openshift.com/pub/openshift-v4/clients/ocp"
RHCOS_MIRROR="https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos"
LB_IMG_URL="https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2"
LB_IMAGE="CentOS-7-x86_64-GenericCloud.qcow2"

[[ -d "$INSTALL_DIR"  ]] && rm -rf ${INSTALL_DIR}
mkdir -p ${INSTALL_DIR}
mkdir -p ${DOWNLOADS_DIR}

CLIENT="openshift-client-linux-${OCP_VERSION}.tar.gz"
CLIENT_URL="${OCP_MIRROR}/${OCP_VERSION}/${CLIENT}"

INSTALLER="openshift-install-linux-${OCP_VERSION}.tar.gz"
INSTALLER_URL="${OCP_MIRROR}/${OCP_VERSION}/${INSTALLER}"

RHCOS_URL="${RHCOS_MIRROR}/${RHCOS_VERSION}/${RHCOS_IMAGE}"

if [[ ! -f ${DOWNLOADS_DIR}/${CLIENT} ]]; then
    wget "$CLIENT_URL" -O "${DOWNLOADS_DIR}/$CLIENT"
    tar -xf "${DOWNLOADS_DIR}/${CLIENT}"
    rm -f README.md
fi
if [[ ! -f ${DOWNLOADS_DIR}/${INSTALLER} ]]; then
    wget "$INSTALLER_URL" -O "${DOWNLOADS_DIR}/$INSTALLER"
    tar -xf "${DOWNLOADS_DIR}/${INSTALLER}"
    rm -f rm -f README.md
fi
if [[ ! -f ${DOWNLOADS_DIR}/${RHCOS_IMAGE} ]]; then
    wget "$RHCOS_URL" -O "${DOWNLOADS_DIR}/${RHCOS_IMAGE}"
fi
if [[ ! -f ${DOWNLOADS_DIR}/${RHCOS_KERNEL} ]]; then
    wget "${RHCOS_MIRROR}/${RHCOS_VERSION}/$RHCOS_KERNEL" -O "${DOWNLOADS_DIR}/$RHCOS_KERNEL"
fi
if [[ ! -f ${DOWNLOADS_DIR}/${RHCOS_INITRAMFS} ]]; then
    wget "${RHCOS_MIRROR}/${RHCOS_VERSION}/$RHCOS_INITRAMFS" -O "${DOWNLOADS_DIR}/$RHCOS_INITRAMFS"
fi
if [[ ! -f ${DOWNLOADS_DIR}/${LB_IMAGE} ]]; then
    wget "$LB_IMG_URL" -O "${DOWNLOADS_DIR}/$LB_IMAGE"
fi


mkdir -p rhcos-install
cp "${DOWNLOADS_DIR}/${RHCOS_KERNEL}" "rhcos-install/vmlinuz"
cp "${DOWNLOADS_DIR}/${RHCOS_INITRAMFS}" "rhcos-install/initramfs.img"
cat <<EOF > rhcos-install/.treeinfo
[general]
arch = x86_64
family = Red Hat CoreOS
platforms = x86_64
version = ${OCP_VER}
[images-x86_64]
initrd = initramfs.img
kernel = vmlinuz
EOF

cat <<EOF > ${INSTALL_DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
compute:
- hyperthreading: Disabled
  name: worker
  replicas: 0
controlPlane:
  hyperthreading: Disabled
  name: master
  replicas: ${N_MASTER}
metadata:
  name: ${CLUSTER_NAME}
networking:
  clusterNetworks:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
pullSecret: '${OPENSHIFT_PULL_SECRET}'
sshKey: '${OPENSHIFT_PUB_KEY}'
EOF


./openshift-install create ignition-configs --dir=${INSTALL_DIR}

WS_PORT="1234"
cat <<EOF > tmpws.service
[Unit]
After=network.target
[Service]
Type=simple
WorkingDirectory=/opt
ExecStart=/usr/bin/python -m SimpleHTTPServer ${WS_PORT}
[Install]
WantedBy=default.target
EOF

cat <<EOF >haproxy.cfg
global
  log 127.0.0.1 local2
  chroot /var/lib/haproxy
  pidfile /var/run/haproxy.pid
  maxconn 4000
  user haproxy
  group haproxy
  daemon
  stats socket /var/lib/haproxy/stats
defaults
  mode tcp
  log global
  option tcplog
  option dontlognull
  option redispatch
  retries 3
  timeout queue 1m
  timeout connect 10s
  timeout client 1m
  timeout server 1m
  timeout check 10s
  maxconn 3000
# 6443 points to control plan
frontend ${CLUSTER_NAME}-api *:6443
  default_backend master-api
backend master-api
  balance source
  server bootstrap bootstrap.${CLUSTER_NAME}.${BASE_DOMAIN}:6443 check
EOF

for i in $(seq 1 ${N_MASTER})
do
    echo "  server master-${i} master-${i}.${CLUSTER_NAME}.${BASE_DOMAIN}:6443 check" >> haproxy.cfg
done

cat <<EOF >>haproxy.cfg

# 22623 points to control plane
frontend ${CLUSTER_NAME}-mapi *:22623
  default_backend master-mapi
backend master-mapi
  balance source
  server bootstrap bootstrap.${CLUSTER_NAME}.${BASE_DOMAIN}:22623 check
EOF

for i in $(seq 1 ${N_MASTER})
do
    echo "  server master-${i} master-${i}.${CLUSTER_NAME}.${BASE_DOMAIN}:22623 check" >> haproxy.cfg
done

cat <<EOF >>haproxy.cfg
# 80 points to master nodes
frontend ${CLUSTER_NAME}-http *:80
  default_backend ingress-http
backend ingress-http
  balance source
EOF

for i in $(seq 1 ${N_MASTER})
do
    echo "  server master-${i} master-${i}.${CLUSTER_NAME}.${BASE_DOMAIN}:80 check" >> haproxy.cfg
done

cat <<EOF >>haproxy.cfg
# 443 points to master nodes
frontend ${CLUSTER_NAME}-https *:443
  default_backend infra-https
backend infra-https
  balance source
EOF

for i in $(seq 1 ${N_MASTER})
do
    echo "  server master-${i} master-${i}.${CLUSTER_NAME}.${BASE_DOMAIN}:443 check" >> haproxy.cfg
done

sudo cp "${DOWNLOADS_DIR}/CentOS-7-x86_64-GenericCloud.qcow2" "${VM_DIR}/${CLUSTER_NAME}-lb.qcow2"

sudo virt-customize -a "${VM_DIR}/${CLUSTER_NAME}-lb.qcow2" \
    --uninstall cloud-init --ssh-inject root:file:${OPENSHIFT_PUB_KEY_FILE} --selinux-relabel --install haproxy --install bind-utils \
    --copy-in ${INSTALL_DIR}/bootstrap.ign:/opt/ --copy-in ${INSTALL_DIR}/master.ign:/opt/ --copy-in ${INSTALL_DIR}/worker.ign:/opt/ \
    --copy-in "${DOWNLOADS_DIR}/${RHCOS_IMAGE}":/opt/ --copy-in tmpws.service:/etc/systemd/system/ \
    --copy-in haproxy.cfg:/etc/haproxy/ \
    --run-command "systemctl daemon-reload" --run-command "systemctl enable tmpws.service"

sudo virt-install --import --name ${CLUSTER_NAME}-lb --disk "${VM_DIR}/${CLUSTER_NAME}-lb.qcow2" \
    --memory ${LOADBALANCER_MEM} --cpu host --vcpus ${LOADBALANCER_CPU} --os-type linux --os-variant rhel7-unknown --network network=${VIRTUAL_NET},model=virtio \
    --noreboot --noautoconsole

sudo virsh start ${CLUSTER_NAME}-lb

while true; do
    sleep 5
    LBIP=$(sudo virsh domifaddr "${CLUSTER_NAME}-lb" | grep ipv4 | head -n1 | awk '{print $4}' | cut -d'/' -f1 2> /dev/null)
    if [[ "$?" == "0" && -n "$LBIP" ]]; then
      echo "LBIP = ${LBIP}"
      break
    fi
done
MAC=$(sudo virsh domifaddr "${CLUSTER_NAME}-lb" | grep ipv4 | head -n1 | awk '{print $2}')
# DHCP Reservation
sudo virsh net-update ${VIRTUAL_NET} add-last ip-dhcp-host --xml "<host mac='$MAC' ip='$LBIP'/>" --live --config

# Adding /etc/hosts entry for LB IP
echo  "$LBIP lb.${CLUSTER_NAME}.${BASE_DOMAIN}" \
    "api.${CLUSTER_NAME}.${BASE_DOMAIN}" \
    "api-int.${CLUSTER_NAME}.${BASE_DOMAIN}" | sudo tee -a /etc/hosts

# DNS Check
echo "1.2.3.4 xxxtestxxx.${BASE_DOMAIN}" | sudo tee -a /etc/hosts
sudo systemctl restart libvirtd
sleep 5
fwd_dig=$(ssh -i ${HOME}/key -o StrictHostKeyChecking=no "root@lb.${CLUSTER_NAME}.${BASE_DOMAIN}" "dig +short 'xxxtestxxx.${BASE_DOMAIN}' 2> /dev/null")
[[ "$?" == "0" && "$fwd_dig" = "1.2.3.4" ]] || err "Testing DNS forward record failed ($fwd_dig)"
rev_dig=$(ssh -i ${HOME}/key -o StrictHostKeyChecking=no "root@lb.${CLUSTER_NAME}.${BASE_DOMAIN}" "dig +short -x '1.2.3.4' 2> /dev/null")
[[ "$?" -eq "0" &&  "$rev_dig" = "xxxtestxxx.${BASE_DOMAIN}." ]] || err "Testing DNS reverse record failed ($rev_dig)"

echo "srv-host=xxxtestxxx.${BASE_DOMAIN},yyyayyy.${BASE_DOMAIN},2380,0,10" | sudo tee ${DNS_DIR}/xxxtestxxx.conf
sudo systemctl restart dnsmasq || err "systemctl restart dnsmasq failed"
srv_dig=$(ssh -i ${HOME}/key -o StrictHostKeyChecking=no "root@lb.${CLUSTER_NAME}.${BASE_DOMAIN}" "dig srv +short 'xxxtestxxx.${BASE_DOMAIN}' 2> /dev/null" | grep -q -s "yyyayyy.${BASE_DOMAIN}") || \
    err "ERROR: Testing SRV record failed"
sudo sed -i_bak -e "/xxxtestxxx/d" /etc/hosts
sudo rm -f ${DNS_DIR}/xxxtestxxx.conf 

# Create machines
sudo virt-install --name ${CLUSTER_NAME}-bootstrap \
  --disk "${VM_DIR}/${CLUSTER_NAME}-bootstrap.qcow2,size=50" --ram ${BOOTSTRAP_MEM} --cpu host --vcpus ${BOOTSTRAP_CPU} \
  --os-type linux --os-variant rhel7-unknown \
  --network network=${VIRTUAL_NET},model=virtio --noreboot --noautoconsole \
  --location rhcos-install/ \
  --extra-args "nomodeset rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=vda coreos.inst.image_url=http://${LBIP}:${WS_PORT}/${RHCOS_IMAGE} coreos.inst.ignition_url=http://${LBIP}:${WS_PORT}/bootstrap.ign" > /dev/null || err "Creating boostrap vm failed"

for i in $(seq 1 ${N_MASTER}); do
  sudo virt-install --name ${CLUSTER_NAME}-master-${i} \
    --disk "${VM_DIR}/${CLUSTER_NAME}-master-${i}.qcow2,size=50" --ram ${MASTER_MEM} --cpu host --vcpus ${MASTER_CPU} \
    --os-type linux --os-variant rhel7-unknown \
    --network network=${VIRTUAL_NET},model=virtio --noreboot --noautoconsole \
    --location rhcos-install/ \
    --extra-args "nomodeset rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=vda coreos.inst.image_url=http://${LBIP}:${WS_PORT}/${RHCOS_IMAGE} coreos.inst.ignition_url=http://${LBIP}:${WS_PORT}/master.ign" > /dev/null || err "Creating master-${i} vm failed "
done

for i in $(seq 1 ${N_WORKER}); do

  sudo virt-install --name ${CLUSTER_NAME}-worker-${i} \
    --disk "${VM_DIR}/${CLUSTER_NAME}-worker-${i}.qcow2,size=50" --ram ${WORKER_MEM} --cpu host --vcpus ${WORKER_CPU} \
    --os-type linux --os-variant rhel7-unknown \
    --network network=${VIRTUAL_NET},model=virtio --noreboot --noautoconsole \
    --location rhcos-install/ \
    --extra-args "nomodeset rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=vda coreos.inst.image_url=http://${LBIP}:${WS_PORT}/${RHCOS_IMAGE} coreos.inst.ignition_url=http://${LBIP}:${WS_PORT}/worker.ign" > /dev/null || err "Creating worker-${i} vm failed "
done

while rvms=$(virsh list --name | grep "${CLUSTER_NAME}-master-\|${CLUSTER_NAME}-worker-\|${CLUSTER_NAME}-bootstrap" 2> /dev/null); do
    sleep 15
    echo "  --> VMs with pending installation: $(echo "$rvms" | tr '\n' ' ')"
done

echo "local=/${CLUSTER_NAME}.${BASE_DOMAIN}/" | sudo tee ${DNS_DIR}/${CLUSTER_NAME}.conf || err "failed"

sudo virsh start ${CLUSTER_NAME}-bootstrap || err "virsh start ${CLUSTER_NAME}-bootstrap failed"

for i in $(seq 1 ${N_MASTER}); do
    sudo virsh start ${CLUSTER_NAME}-master-${i} || err "virsh start ${CLUSTER_NAME}-master-${i} failed"
done

for i in $(seq 1 ${N_WORKER}); do
do
    sudo virsh start ${CLUSTER_NAME}-worker-${i} || err "virsh start ${CLUSTER_NAME}-worker-${i} failed"
done
