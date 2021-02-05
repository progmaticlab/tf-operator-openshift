#!/bin/bash

CLUSTER_NAME=${CLUSTER_NAME:-"cluster1"}
sudo virsh destroy ${CLUSTER_NAME}-lb || /bin/true
sudo virsh undefine ${CLUSTER_NAME}-lb --remove-all-storage || /bin/true
