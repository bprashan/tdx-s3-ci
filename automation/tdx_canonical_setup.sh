#!/bin/bash

CUR_DIR=$(pwd)
TDX_DIR="$CUR_DIR"/tdx_setup
BRANCH_NAME=${BRANCH_NAME:-2.0}
GUEST_TOOLS_DIR=$TDX_DIR/guest-tools/
GUEST_IMG_DIR="$GUEST_TOOLS_DIR"/image
GUEST_IMG="tdx-guest-ubuntu-24.04-generic.qcow2"
if [[ -z "$SUDO_USER" ]]; then
	LOGIN_USER=`whoami`
else
	LOGIN_USER=$SUDO_USER
fi
TD_IMAGE_DIR=/home/$LOGIN_USER/td_image

finally() {
        setup_summary
        exit 1
}

trap 'finally' ERR

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
        if [ $? -ne 0 ]; then
                echo -e "\n\n ERROR: Setup TDX Host failed"
                return -1
        fi
        usermod -aG kvm $USER
        SETUP_TDX_HOST="PASSED"
}

create_td_image() {
        echo -e "\nCreating TD image ..."
        cd "$GUEST_IMG_DIR"
        var=$(./create-td-image.sh)
        if [ $? -ne 0 ]; then
                echo "$var"
                echo -e "\n\n ERROR: TD image creation failed"
                return -1
        fi

}

copy_td_image(){
	mkdir -p $TD_IMAGE_DIR
	if [ -e $TD_IMAGE_DIR/$GUEST_IMG ]; then
		rm -rf $TD_IMAGE_DIR/$GUEST_IMG
	fi
	cp -f $GUEST_IMG  $TD_IMAGE_DIR
	chown -R $LOGIN_USER:$LOGIN_USER $TD_IMAGE_DIR
	cp $CUR_DIR/config.json $TD_IMAGE_DIR
        CREATE_TD_IMAGE="PASSED"
}

setup_summary() {
        echo -e "\n---------------------------------SETUP STATUS----------------------------------"
        echo "|----------------------------------------------------------------------------- |"
        echo "|                 Steps                     |                Status            |"
        echo "|-------------------------------------------|----------------------------------|"
        echo "| setup TDX host                            |                "${SETUP_TDX_HOST:-FAILED}"            |"
        echo "| TD Image Creation                         |                "${CREATE_TD_IMAGE:-FAILED}"            |"
        echo "|------------------------------------------------------------------------------|"

        if [ ! -z "${CREATE_TD_IMAGE}" ] ; then
                echo "==============================================================================="
                echo "The setup has been done successfully. Please enable now TDX in the BIOS."
                echo "==============================================================================="
                echo "TD Guest Image path : $TD_IMAGE_DIR/tdx-guest-ubuntu-24.04-generic.qcow2"
        fi
}

cleanup(){
        rm -rf $TDX_DIR
}

clone_tdx_repo
setup_tdx_host
create_td_image
copy_td_image
cleanup
finally
