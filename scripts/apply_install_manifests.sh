#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
DEPLOY_DIR=${DEPLOY_DIR:=$my_dir/../deploy}

if [[ $# != "1" ]]; then
  echo "Pass path to openshift install directory as the param"
  exit 1
fi

install_dir=$1

cp $DEPLOY_DIR/manifests/* $install_dir/manifests

curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/openshift/99_master-iptables-machine-config.yaml -o openshift/99_master-iptables-machine-config.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/openshift/99_master-kernel-modules-overlay.yaml -o openshift/99_master-kernel-modules-overlay.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/openshift/99_master_network_functions.yaml -o openshift/99_master_network_functions.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/openshift/99_master_network_manager_stop_service.yaml -o openshift/99_master_network_manager_stop_service.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/openshift/99_master-pv-mounts.yaml -o openshift/99_master-pv-mounts.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/openshift/99_worker-iptables-machine-config.yaml -o openshift/99_worker-iptables-machine-config.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/openshift/99_worker-kernel-modules-overlay.yaml -o openshift/99_worker-kernel-modules-overlay.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/openshift/99_worker_network_functions.yaml -o openshift/99_worker_network_functions.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/openshift/99_worker_network_manager_stop_service.yaml -o openshift/99_worker_network_manager_stop_service.yaml
