#!/bin/bash

function realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

my_file=$(realpath "$0")
my_dir="$(dirname $my_file)"
DEPLOY_DIR=${DEPLOY_DIR:=$my_dir/../deploy}

if [[ $# != "1" ]]; then
  echo "Pass path to openshift install directory as the param"
  exit 1
fi

install_dir=$1

cp $DEPLOY_DIR/manifests/* $install_dir/manifests
cp $DEPLOY_DIR/openshift/* $install_dir/openshift


