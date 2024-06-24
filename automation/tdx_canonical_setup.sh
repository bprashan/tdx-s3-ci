#!/bin/bash

CUR_DIR=$(pwd)
TDX_DIR="$CUR_DIR"/tdx_setup
source ${CUR_DIR}/tdx_canonical_common

clone_tdx_repo(){
        echo -e "\n\nCloning TDX git repository with '$BRANCH_NAME' branch.."
        [ -d $TDX_DIR ] && rm -rf $TDX_DIR
        git clone -b $BRANCH_NAME https://github.com/canonical/tdx.git $TDX_DIR
}

setup_tdx_host(){
        cd $TDX_DIR
        echo -e "\nSetting up the host for TDX..."
        sudo ./setup-tdx-host.sh
}


clone_tdx_repo
check_attestation_support
setup_tdx_host

if ! [ $is_prod_sys -eq 0 ]; then
        echo "=========================================================================================================================="
        echo "NOTE : This is a Pre-production system. Intel® SGX Data Center Attestation Primitives (Intel® SGX DCAP) are not installed"
        echo "=========================================================================================================================="
fi
