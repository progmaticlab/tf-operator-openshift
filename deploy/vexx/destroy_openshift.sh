#!/bin/bash

set -ex
OPENSHIFT_INSTALL_DIR=${OPENSHIFT_INSTALL_DIR:-"os-install-config"}

export INFRA_ID=$(jq -r .infraID $OPENSHIFT_INSTALL_DIR/metadata.json)
if [[ -z "${INFRA_ID}" ]]; then
  echo "ERROR: Something get wrong. You INFRA_ID has not been set up"
  exit 1
fi

if [[ ! -f $OPENSHIFT_INSTALL_DIR/inventory.yaml || ! -f $OPENSHIFT_INSTALL_DIR/common.yaml ]]; then
  echo "INFO: Files inventory.yaml or common.yaml can't be found. I looks like nothing to delete"
  exit 0
fi

if [[ -f $OPENSHIFT_INSTALL_DIR/network.yaml ]]; then

cat <<EOF > $OPENSHIFT_INSTALL_DIR/destroy_network.yaml
- import_playbook: common.yaml

- hosts: all
  gather_facts: no

  tasks:
  - name: 'Delete the Ingress port'
    os_port:
      name: "{{ os_port_ingress }}"
      state: absent
  - name: 'Delete the API port'
    os_port:
      name: "{{ os_port_api }}"
      state: absent
  - name: 'Delete external router'
    os_router:
      name: "{{ os_router }}"
      state: absent
  - name: 'Delete a subnet'
    os_subnet:
      name: "{{ os_subnet }}"
      state: absent
  - name: 'Delete the cluster network'
    os_network:
      name: "{{ os_network }}"
      state: absent
EOF
    ansible-playbook -i $OPENSHIFT_INSTALL_DIR/inventory.yaml $OPENSHIFT_INSTALL_DIR/destroy_network.yaml
fi

if [[ -f $OPENSHIFT_INSTALL_DIR/security-groups.yaml ]]; then
    cat  <<EOF > $OPENSHIFT_INSTALL_DIR/destroy-security-groups.yaml
- import_playbook: common.yaml

- hosts: all
  gather_facts: no

  tasks:
  - name: 'Delete the master security group'
    os_security_group:
      name: "{{ os_sg_master }}"
      state: absent
  - name: 'Delete the worker security group'
    os_security_group:
      name: "{{ os_sg_worker }}"
      state: absent

EOF
    ansible-playbook -i $OPENSHIFT_INSTALL_DIR/inventory.yaml $OPENSHIFT_INSTALL_DIR/destroy-security-groups.yaml
fi