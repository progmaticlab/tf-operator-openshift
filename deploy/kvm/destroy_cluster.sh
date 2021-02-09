#!/bin/bash

CLUSTER_NAME=${CLUSTER_NAME:-"test1"}
BASE_DOMAIN=${BASE_DOMAIN:-"hobgoblin.org"}
N_MASTER=${N_MASTER:-"3"}
N_WORKER=${N_WORK:-"2"}
for i in $(seq 1 ${N_WORKER}); do
    sudo virsh destroy ${CLUSTER_NAME}-worker-${i} || /bin/true
    sudo virsh undefine ${CLUSTER_NAME}-worker-${i} --remove-all-storage || /bin/true
done
for i in $(seq 1 ${N_MASTER}); do
    sudo virsh destroy ${CLUSTER_NAME}-master-${i} || /bin/true
    sudo virsh undefine ${CLUSTER_NAME}-master-${i} --remove-all-storage || /bin/true
done
sudo virsh destroy ${CLUSTER_NAME}-bootstrap || /bin/true
sudo virsh undefine ${CLUSTER_NAME}-bootstrap --remove-all-storage || /bin/true
sudo virsh destroy ${CLUSTER_NAME}-lb || /bin/true
sudo virsh undefine ${CLUSTER_NAME}-lb --remove-all-storage || /bin/true
sed_cmd=$(echo "/${CLUSTER_NAME}\.${BASE_DOMAIN}/d")
sudo sed -i_bak -e ${sed_cmd} /etc/hosts
sudo sed -i_bak -e "/xxxtestxxx/d" /etc/hosts
