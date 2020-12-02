#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
DEPLOY_DIR=${DEPLOY_DIR:=$my_dir/../deploy}
manifests_dir="$DEPLOY_DIR/manifests"
openshift_dir="$DEPLOY_DIR/openshift"

if [[ $# != "1" ]]; then
  echo "Pass path to openshift install directory as the param"
  exit 1
fi




curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/manifests/0000000-contrail-01-namespace.yaml -o manifests/00-contrail-01-namespace.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/manifests/0000000-contrail-02-admin-password.yaml -o manifests/00-contrail-02-admin-password.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/manifests/0000000-contrail-02-rbac-auth.yaml -o manifests/00-contrail-02-rbac-auth.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/manifests/0000000-contrail-02-registry-secret.yaml -o manifests/00-contrail-02-registry-secret.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/manifests/0000000-contrail-03-cluster-role.yaml -o manifests/00-contrail-03-cluster-role.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/manifests/0000000-contrail-04-serviceaccount.yaml -o manifests/00-contrail-04-serviceaccount.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/manifests/0000000-contrail-05-rolebinding.yaml -o manifests/00-contrail-05-rolebinding.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/manifests/0000000-contrail-06-clusterrolebinding.yaml -o manifests/00-contrail-06-clusterrolebinding.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/crds/contrail.juniper.net_cassandras_crd.yaml -o manifests/00-contrail-07-contrail.juniper.net_cassandras_crd.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/crds/contrail.juniper.net_commands_crd.yaml -o manifests/00-contrail-07-contrail.juniper.net_commands_crd.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/crds/contrail.juniper.net_configs_crd.yaml -o manifests/00-contrail-07-contrail.juniper.net_configs_crd.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/crds/contrail.juniper.net_contrailmonitors_crd.yaml -o manifests/00-contrail-07-contrail.juniper.net_contrailmonitors_crd.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/crds/contrail.juniper.net_contrailstatusmonitors_crd.yaml -o manifests/00-contrail-07-contrail.juniper.net_contrailstatusmonitors_crd.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/crds/contrail.juniper.net_controls_crd.yaml -o manifests/00-contrail-07-contrail.juniper.net_controls_crd.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/crds/contrail.juniper.net_keystones_crd.yaml -o manifests/00-contrail-07-contrail.juniper.net_keystones_crd.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/crds/contrail.juniper.net_kubemanagers_crd.yaml -o manifests/00-contrail-07-contrail.juniper.net_kubemanagers_crd.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/crds/contrail.juniper.net_managers_crd.yaml -o manifests/00-contrail-07-contrail.juniper.net_managers_crd.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/crds/contrail.juniper.net_memcacheds_crd.yaml -o manifests/00-contrail-07-contrail.juniper.net_memcacheds_crd.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/crds/contrail.juniper.net_postgres_crd.yaml -o manifests/00-contrail-07-contrail.juniper.net_postgres_crd.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/crds/contrail.juniper.net_provisionmanagers_crd.yaml -o manifests/00-contrail-07-contrail.juniper.net_provisionmanagers_crd.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/crds/contrail.juniper.net_rabbitmqs_crd.yaml -o manifests/00-contrail-07-contrail.juniper.net_rabbitmqs_crd.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/crds/contrail.juniper.net_swiftproxies_crd.yaml -o manifests/00-contrail-07-contrail.juniper.net_swiftproxies_crd.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/crds/contrail.juniper.net_swifts_crd.yaml -o manifests/00-contrail-07-contrail.juniper.net_swifts_crd.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/crds/contrail.juniper.net_swiftstorages_crd.yaml -o manifests/00-contrail-07-contrail.juniper.net_swiftstorages_crd.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/crds/contrail.juniper.net_vrouters_crd.yaml -o manifests/00-contrail-07-contrail.juniper.net_vrouters_crd.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/crds/contrail.juniper.net_webuis_crd.yaml -o manifests/00-contrail-07-contrail.juniper.net_webuis_crd.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/crds/contrail.juniper.net_zookeepers_crd.yaml -o manifests/00-contrail-07-contrail.juniper.net_zookeepers_crd.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/master/deploy/openshift/releases/R2011/manifests/00-contrail-08-operator.yaml -o manifests/00-contrail-08-operator.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/master/deploy/openshift/releases/R2011/manifests/00-contrail-09-manager.yaml -o manifests/00-contrail-09-manager.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/manifests/cluster-network-02-config.yml -o manifests/cluster-network-02-config.yml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/openshift/99_master-iptables-machine-config.yaml -o openshift/99_master-iptables-machine-config.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/openshift/99_master-kernel-modules-overlay.yaml -o openshift/99_master-kernel-modules-overlay.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/openshift/99_master_network_functions.yaml -o openshift/99_master_network_functions.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/openshift/99_master_network_manager_stop_service.yaml -o openshift/99_master_network_manager_stop_service.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/openshift/99_master-pv-mounts.yaml -o openshift/99_master-pv-mounts.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/openshift/99_worker-iptables-machine-config.yaml -o openshift/99_worker-iptables-machine-config.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/openshift/99_worker-kernel-modules-overlay.yaml -o openshift/99_worker-kernel-modules-overlay.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/openshift/99_worker_network_functions.yaml -o openshift/99_worker_network_functions.yaml
curl https://raw.githubusercontent.com/Juniper/contrail-operator/R2011/deploy/openshift/openshift/99_worker_network_manager_stop_service.yaml -o openshift/99_worker_network_manager_stop_service.yaml
