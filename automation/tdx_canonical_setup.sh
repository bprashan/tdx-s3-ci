#!/bin/bash

CUR_DIR=$(pwd)
TDX_DIR="$CUR_DIR"/tdx_setup
GUEST_TOOLS_DIR="$TDX_DIR"/guest-tools
GUEST_IMG_DIR="$GUEST_TOOLS_DIR"/image
ATTESTATION_DIR="$TDX_DIR"/attestation
BRANCH_NAME=noble-24.04

clone_tdx_repo(){
        echo -e "\n\nCloning TDX git repository with '$BRANCH_NAME' branch.."
        [ -d $TDX_DIR ] && rm -rf $TDX_DIR
        git clone -b $BRANCH_NAME https://github.com/canonical/tdx.git $TDX_DIR
}

check_production_system() {
        cd $ATTESTATION_DIR
        echo -e "\n\nVerifying if the system supports attestation.."
        output=$(sudo ./check-production.sh)
        echo $output
        if [[ $output =~ "Production" ]]; then
                echo -e "Attestation is supported.\nThe attestation components will be installed "
                sed -i 's/^TDX_SETUP_ATTESTATION=0/TDX_SETUP_ATTESTATION=1/' "$TDX_DIR"/setup-tdx-config
        else
                echo -e "Failure: Pre-production system. Attestation is not supported on Pre-production systems.\n"
        fi
}

setup_tdx_host(){
        cd $TDX_DIR
        echo -e "\n\nSetting up the host for TDX.."
        sudo ./setup-tdx-host.sh
}

create_td_guest(){
        echo -e "\n\nCreating TD guest image.."
        echo $GUEST_IMG_DIR
        cd "$GUEST_IMG_DIR"
        sudo ./create-td-image.sh
}

configure_pccs_service(){
        cd $CUR_DIR
        sudo cp -f default.json /opt/intel/sgx-dcap-pccs/config/default.json
        sudo systemctl restart pccs
}

clone_tdx_repo
check_production_system
setup_tdx_host
create_td_guest
configure_pccs_service

echo "=========================================================================================================="
echo "The host OS setup has been done successfully. Now, please reboot the system, run and verify TD Guest image"
echo "=========================================================================================================="
