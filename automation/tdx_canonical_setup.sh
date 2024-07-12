#!/bin/bash

CUR_DIR=$(pwd)
TDX_DIR="$CUR_DIR"/tdx_setup
BRANCH_NAME=${BRANCH_NAME:-2.0}

clone_tdx_repo() {
        echo -e "\n\nCloning TDX git repository with '$BRANCH_NAME' branch.."
        [ -d $TDX_DIR ] && rm -rf $TDX_DIR
        git clone -b $BRANCH_NAME https://github.com/canonical/tdx.git $TDX_DIR
}

setup_tdx_host() {
        cd $TDX_DIR
        echo -e "\nSetting up the host for TDX..."
        sed -i 's/^TDX_SETUP_ATTESTATION=0/TDX_SETUP_ATTESTATION=1/' "$TDX_DIR"/setup-tdx-config
        ./setup-tdx-host.sh
        usermod -aG kvm $USER
}
cleanup(){
        rm -rf $TDX_DIR
}

clone_tdx_repo
setup_tdx_host
cleanup
