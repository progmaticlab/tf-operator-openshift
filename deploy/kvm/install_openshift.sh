#!/bin/bash

set -ex

my_file=$(realpath "$0")
my_dir="$(dirname $my_file)"
start_ts=$(date +%s)

err() {
    echo "ERROR ${1}"
    exit 1
}

OCP_VERSION=${OCP_VERSION:-"4.5.21"}
N_MAST=${N_MAST:-"3"}
N_WORK=${N_WORK:-"2"}
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


# Create install dirs, or fail if it is exists
# [[ -d "$INSTALL_DIR"  ]] && err "Installation directory $INSTALL_DIR already in use"
[[ -d "$INSTALL_DIR"  ]] && rm -rf ${INSTALL_DIR}
mkdir -p ${INSTALL_DIR}
mkdir -p ${DOWNLOADS_DIR}

CLIENT=$(curl -N --fail -qs "${OCP_MIRROR}/${OCP_VERSION}/" | grep  -m1 "client-linux" | sed 's/.*href="\(openshift-.*\)">open.*/\1/')
CLIENT_URL="${OCP_MIRROR}/${OCP_VERSION}/${CLIENT}"

INSTALLER=$(curl -N --fail -qs "${OCP_MIRROR}/${OCP_VERSION}/" | grep  -m1 "install-linux" | sed 's/.*href="\(openshift-.*\)">open.*/\1/')
INSTALLER_URL="${OCP_MIRROR}/${OCP_VERSION}/${INSTALLER}"

[[ -f ${DOWNLOADS_DIR}/${CLIENT} ]] || wget "$CLIENT_URL" -O "${DOWNLOADS_DIR}/$CLIENT"
[[ -f ${DOWNLOADS_DIR}/${INSTALLER} ]] || wget "$INSTALLER_URL" -O "${DOWNLOADS_DIR}/$INSTALLER"
tar -xf "${DOWNLOADS_DIR}/${CLIENT}" && rm -f README.md
tar -xf "${DOWNLOADS_DIR}/${INSTALLER}" && rm -f rm -f README.md
