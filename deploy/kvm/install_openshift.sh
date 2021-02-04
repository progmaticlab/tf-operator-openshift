#!/bin/bash

set -ex

my_file=$(realpath "$0")
my_dir="$(dirname $my_file)"
start_ts=$(date +%s)

err() {
    echo "ERROR ${1}"
    exit 1
}

[[ -z ${OPENSHIFT_PULL_SECRET} ]] || err "set OPENSHIFT_PULL_SECRET env variable"
[[ -z ${OPENSHIFT_PUB_KEY} ]] || err "set OPENSHIFT_PUB_KEY env variable"

OCP_VERSION=${OCP_VERSION:-"4.5.21"}
RHCOS_VERSION=${RHCOS_VERSION:="4.6/4.6.8"}
RHCOS_IMAGE="rhcos-metal.x86_64.raw.gz"
RHCOS_KERNEL="rhcos-live-kernel-x86_64"
RHCOS_INITRAMFS="rhcos-live-initramfs.x86_64.img"
N_MASTER=${N_MAST:-"3"}
N_WORKER=${N_WORK:-"2"}
MASTER_CPU=${MASTER_CPU:-"4"}
MASTER_MEM=${MASTER_MEM:-"16000"}
WORKER_CPU=${WORKER_CPU:-"2"}
WORKER_MEMORY=${WORKER_MEMORY:-"8000"}
BOOTSTRAP_CPU=${BOOTSTRAP_CPU:-"4"}
BOOTSTRAP_MEM=${BOOTSTRAP_MEM:-"16000"}
LOADBALANCER_CPU=${LOADBALANCER_CPU:-"1"}
LOADBALANCER_MEM=${LOADBALANCER_MEM:-"1024"}
VIRTUAL_NET=${VIRTUAL_NET:-"default"}
BASE_DOMAIN=${BASE_DOMAIN:-"hobgoblin.org"}
CLUSTER_NAME=${CLUSTER_NAME:-"cluster1"}
INSTALL_DIR=${INSTALL_DIR:-"${HOME}/install-${CLUSTER_NAME}"}
DOWNLOADS_DIR=${DOWNLOADS_DIR:-"${HOME}/downloads-${CLUSTER_NAME}"}


[[ -z ${PULL_SECRET} ]] || err "ERROR: set PULL_SECRET env variable"
[[ -z ${OPENSHIFT_PUB_KEY} ]] || err "ERROR: set OPENSHIFT_PUB_KEY env variable"

DNS_DIR="/etc/NetworkManager/dnsmasq.d"
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


