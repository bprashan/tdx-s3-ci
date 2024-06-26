#!/bin/bash

CUR_DIR=$(pwd)
TDX_DIR="$CUR_DIR"/tdx_setup

clone_tdx_repo() {
        echo -e "\n\nCloning TDX git repository with '$BRANCH_NAME' branch.."
        [ -d $TDX_DIR ] && rm -rf $TDX_DIR
        git clone -b $BRANCH_NAME https://github.com/canonical/tdx.git $TDX_DIR
}

setup_tdx_host() {
        cd $TDX_DIR
        echo -e "\nSetting up the host for TDX..."
        sudo -E TDX_SETUP_ATTESTATION=1  ./setup-tdx-host.sh
}

clone_tdx_repo
setup_tdx_host
