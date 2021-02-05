#!/bin/bash

CLUSTER_NAME=${CLUSTER_NAME:-"cluster1"}
sudo virsh destroy ${CLUSTER_NAME}-lb
sudo virsh vol-delete /var/lib/libvirt/images/${CLUSTER_NAME}-lb.qcow2
