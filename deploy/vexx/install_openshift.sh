#!/bin/bash

set -ex

OPENSHIFT_CLUSTER_NAME=${CLUSTER_NAME:-"openstack"}
OPENSHIFT_BASE_DOMAIN=${OPENSHIFT_BASE_DOMAIN:-"hobgoblin.org"}
OPENSHIFT_API_FIP=${OPENSHIFT_API_FIP:-"38.108.68.93"}
OPENSHIFT_INGRESS_FIP=${OPENSHIFT_INGRESS_FIP:-"38.108.68.166"}
OPENSHIFT_INSTALL_PATH=${OPENSHIFT_INSTALL_PATH:-"openshift-install"}
OPENSHIFT_INSTALL_DIR=${OPENSHIFT_INSTALL_DIR:-"os-install-config"}
OS_CLOUD=${OS_CLOUD:-"vexx"}

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
    cloud: ${OS_CLOUD}
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

cat <<EOF > ${OPENSHIFT_INSTALL_DIR}/setup_bootsrap_ign.py
import base64
import json
import os

with open('bootstrap.ign', 'r') as f:
    ignition = json.load(f)

files = ignition['storage'].get('files', [])

infra_id = os.environ.get('INFRA_ID', 'openshift').encode()
hostname_b64 = base64.standard_b64encode(infra_id + b'-bootstrap\n').decode().strip()
files.append(
{
    'path': '/etc/hostname',
    'mode': 420,
    'contents': {
        'source': 'data:text/plain;charset=utf-8;base64,' + hostname_b64,
        'verification': {}
    },
    'filesystem': 'root',
})

ca_cert_path = os.environ.get('OS_CACERT', '')
if ca_cert_path:
    with open(ca_cert_path, 'r') as f:
        ca_cert = f.read().encode()
        ca_cert_b64 = base64.standard_b64encode(ca_cert).decode().strip()

    files.append(
    {
        'path': '/opt/openshift/tls/cloud-ca-cert.pem',
        'mode': 420,
        'contents': {
            'source': 'data:text/plain;charset=utf-8;base64,' + ca_cert_b64,
            'verification': {}
        },
        'filesystem': 'root',
    })

ignition['storage']['files'] = files;

with open('bootstrap.ign', 'w') as f:
    json.dump(ignition, f)
EOF

python3 ${OPENSHIFT_INSTALL_DIR}/setup_bootsrap_ign.py
openstack image create --disk-format=raw --container-format=bare --file bootstrap.ign bootstrap-ignition-image
openstack image show bootstrap-ignition-image

