#!/bin/bash

manifests=(contrail.juniper.net_cassandras_crd.yaml
contrail.juniper.net_commands_crd.yaml
contrail.juniper.net_configs_crd.yaml
contrail.juniper.net_contrailmonitors_crd.yaml
contrail.juniper.net_contrailstatusmonitors_crd.yaml
contrail.juniper.net_controls_crd.yaml
contrail.juniper.net_keystones_crd.yaml
contrail.juniper.net_kubemanagers_crd.yaml
contrail.juniper.net_managers_crd.yaml
contrail.juniper.net_memcacheds_crd.yaml
contrail.juniper.net_postgres_crd.yaml
contrail.juniper.net_provisionmanagers_crd.yaml
contrail.juniper.net_rabbitmqs_crd.yaml
contrail.juniper.net_swiftproxies_crd.yaml
contrail.juniper.net_swifts_crd.yaml
contrail.juniper.net_swiftstorages_crd.yaml
contrail.juniper.net_vrouters_crd.yaml
contrail.juniper.net_webuis_crd.yaml
contrail.juniper.net_zookeepers_crd.yaml)

for m in ${manifests[@]}; do
  cp -f crds/$m manifests/00-contrail-07-$m
  echo $m
done
