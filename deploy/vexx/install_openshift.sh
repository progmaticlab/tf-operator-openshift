#!/bin/bash

set -ex

OPENSHIFT_CLUSTER_NAME=${CLUSTER_NAME:-"openstack"}
OPENSHIFT_BASE_DOMAIN=${OPENSHIFT_BASE_DOMAIN:-"hobgoblin.org"}
OPENSHIFT_API_FIP=${OPENSHIFT_API_FIP:-"38.108.68.93"}
OPENSHIFT_INGRESS_FIP=${OPENSHIFT_INGRESS_FIP:-"38.108.68.166"}
OPENSHIFT_INSTALL_PATH=${OPENSHIFT_INSTALL_PATH:-"openshift-install"}
OPENSHIFT_INSTALL_DIR=${OPENSHIFT_INSTALL_DIR:-"os-install-config"}

mkdir -p ./tmpopenshift
pushd tmpopenshift
curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.5.21/openshift-install-linux-4.5.21.tar.gz
tar xzf openshift-install-linux-4.5.21.tar.gz
curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.5.21/openshift-client-linux-4.5.21.tar.gz
sudo mv ./openshift-install ./oc ./kubectl /usr/local/bin
popd
rm -rf tmpopenshift

if [[ -z ${OPENSHIFT_PULL_SECRET} ]]; then
  echo "ERROR: set OPENSHIFT_PULL_SECRET env variable"
  exit 1
fi

if [[ -z ${OPENSHIFT_PUB_KEY} ]]; then
  echo "ERROR: set OPENSHIFT_PUB_KEY env variable"
  exit 1
fi

rm -rf $OPENSHIFT_INSTALL_DIR
mkdir -p $OPENSHIFT_INSTALL_DIR

cat <<EOF > ${OPENSHIFT_INSTALL_DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${OPENSHIFT_BASE_DOMAIN}
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: {}
  replicas: 0
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform: {}
  replicas: 3
metadata:
  creationTimestamp: null
  name: openshift
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.100.0.0/24
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  openstack:
    apiVIP: 10.100.0.5
    cloud: vexx
    computeFlavor: v2-highcpu-16
    externalDNS: null
    externalNetwork: public
    ingressVIP: 10.100.0.7
    lbFloatingIP: ${OPENSHIFT_API_FIP}
    octaviaSupport: "1"
    region: ""
    trunkSupport: "0"
publish: External
pullSecret: |
  ${OPENSHIFT_PULL_SECRET}
sshKey: |
  ${OPENSHIFT_PUB_KEY}
EOF

$OPENSHIFT_INSTALL_PATH --dir $OPENSHIFT_INSTALL_DIR create manifests

rm -f ${OPENSHIFT_INSTALL_DIR}/openshift/99_openshift-cluster-api_master-machines-*.yaml ${OPENSHIFT_INSTALL_DIR}/openshift/99_openshift-cluster-api_worker-machineset-*.yaml

$OPENSHIFT_INSTALL_PATH --dir $OPENSHIFT_INSTALL_DIR  create ignition-configs

export INFRA_ID=$(jq -r .infraID $OPENSHIFT_INSTALL_DIR/metadata.json)