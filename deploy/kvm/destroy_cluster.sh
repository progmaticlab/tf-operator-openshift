#!/bin/bash

CLUSTER_NAME=${CLUSTER_NAME:-"cluster1"}
sudo virsh destroy ${CLUSTER_NAME}-lb