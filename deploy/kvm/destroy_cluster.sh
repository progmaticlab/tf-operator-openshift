#!/bin/bash

CLUSTER_NAME=${CLUSTER_NAME:-"cluster1"}
BASE_DOMAIN=${BASE_DOMAIN:-"hobgoblin.org"}
sudo virsh destroy ${CLUSTER_NAME}-bootstrap || /bin/true
sudo virsh undefine ${CLUSTER_NAME}-bootstrap --remove-all-storage || /bin/true
sudo virsh destroy ${CLUSTER_NAME}-lb || /bin/true
sudo virsh undefine ${CLUSTER_NAME}-lb --remove-all-storage || /bin/true
sed_cmd=$(echo "/${CLUSTER_NAME}\.${BASE_DOMAIN}/d")
sudo sed -i_bak -e ${sed_cmd} /etc/hosts
sudo sed -i_bak -e "/xxxtestxxx/d" /etc/hosts