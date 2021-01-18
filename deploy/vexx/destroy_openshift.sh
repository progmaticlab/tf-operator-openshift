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

if [[ -f ${OPENSHIFT_INSTALL_DIR}/compute-nodes.yaml ]]; then
    cat <<EOF > ${OPENSHIFT_INSTALL_DIR}/destroy-compute-nodes.yaml
- import_playbook: common.yaml

- hosts: all
  gather_facts: no

  tasks:

  - name: 'Delete Compute servers'
    os_server:
      name: "{{ item.1 }}-{{ item.0 }}"
      state: absent
      delete_fip: yes
    with_indexed_items: "{{ [os_compute_server_name] * os_compute_nodes_number }}"

  - name: 'Delete Compute ports'
    os_port:
      name: "{{ item.1 }}-{{ item.0 }}"
      state: absent
    with_indexed_items: "{{ [os_port_worker] * os_compute_nodes_number }}"
EOF
    ansible-playbook -i $OPENSHIFT_INSTALL_DIR/inventory.yaml $OPENSHIFT_INSTALL_DIR/destroy-compute-nodes.yaml
fi

if [[ -f ${OPENSHIFT_INSTALL_DIR}/control-plane.yaml ]]; then
    cat <<EOF > ${OPENSHIFT_INSTALL_DIR}/destroy-control-plane.yaml
- import_playbook: common.yaml

- hosts: all
  gather_facts: no

  tasks:
  - name: 'Delete the Control Plane servers'
    os_server:
      name: "{{ item.1 }}-{{ item.0 }}"
      state: absent
      delete_fip: yes
    with_indexed_items: "{{ [os_cp_server_name] * os_cp_nodes_number }}"

  - name: 'Delete the Control Plane ports'
    os_port:
      name: "{{ item.1 }}-{{ item.0 }}"
      state: absent
    with_indexed_items: "{{ [os_port_master] * os_cp_nodes_number }}"
EOF
    ansible-playbook -i $OPENSHIFT_INSTALL_DIR/inventory.yaml $OPENSHIFT_INSTALL_DIR/destroy-control-plane.yaml
fi

if [[ -f $OPENSHIFT_INSTALL_DIR/bootstrap.yaml ]]; then
    cat <<EOF > ${OPENSHIFT_INSTALL_DIR}/destroy_bootstrap.yaml
- import_playbook: common.yaml
- hosts: all
  gather_facts: no

  tasks:
  - name: 'Remove the bootstrap server'
    os_server:
      name: "{{ os_bootstrap_server_name }}"
      state: absent
      delete_fip: yes

  - name: 'Remove the bootstrap server port'
    os_port:
      name: "{{ os_port_bootstrap }}"
      state: absent
EOF
    ansible-playbook -i $OPENSHIFT_INSTALL_DIR/inventory.yaml $OPENSHIFT_INSTALL_DIR/destroy_bootstrap.yaml
fi

if [[ -f $OPENSHIFT_INSTALL_DIR/network.yaml ]]; then
    cat <<EOF > ${OPENSHIFT_INSTALL_DIR}/destroy_network.yaml
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
EOF
    ansible-playbook -i $OPENSHIFT_INSTALL_DIR/inventory.yaml $OPENSHIFT_INSTALL_DIR/destroy_network.yaml
fi

image_name="bootstrap-ignition-image-$INFRA_ID"
openstack image delete $image_name >/dev/null 2>&1 || true
