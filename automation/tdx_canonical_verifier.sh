#!/bin/bash
CUR_DIR=$(pwd)
TDX_CONFIG=tdx-config
TDX_DIR="$CUR_DIR"/tdx_verifier
source "$CUR_DIR"/tdx_canonical_common
source "$CUR_DIR"/$TDX_CONFIG
GUEST_TOOLS_DIR="$TDX_DIR"/guest-tools
GUEST_IMG_DIR="$GUEST_TOOLS_DIR"/image
TD_GUEST_VERIFY_TEXT="tdx: Guest detected"
TDT_HOST_VERIFY_TEXT="tdx: module initialized"
SERVICE_ACTIVE_STATUS_VERIFY_TEXT="Active: active (running)"
MPA_SERVICE_CHECK="mpa_registration_tool.service; enabled; preset: enabled"
VERIFY_ATTESTATION_SCRIPT="verify_attestation_td_guest.sh"
TD_GUEST_PASSWORD=123456
TD_GUEST_PORT=10022
MPA_REGISTRATION_CHECK="INFO: Registration Flow - Registration status indicates registration is completed successfully"
TRUSTAUTHORITY_API_FILE="config.json"
PASSED=PASSED
FAILED=FAILED
VERIFY_TDX_HOST=$FAILED
CREATE_TD_IMAGE=$FAILED
RUN_TD_GUEST=$FAILED
VERIFY_TD_GUEST=$FAILED
IS_ATTESTATION_SUPPORT=False
CONFIGURING_ATTESTATION_HOST=$FAILED
VERIFY_ATTESTATION_HOST=$FAILED
VERIFY_ATTESTATION_GUEST=$FAILED
PCCS_DEFAULT_JSON="default.json"

clone_tdx_repo(){
        echo -e "\nCloning TDX git repository with '$BRANCH_NAME' branch ..."
        [ -d $TDX_DIR ] && rm -rf $TDX_DIR
        git clone -b $BRANCH_NAME https://github.com/canonical/tdx.git $TDX_DIR
}


verify_tdx_host(){
        echo -e "\nVerifying whether host is enabled with TDX ..."
        var="$(sudo dmesg | grep -i tdx)"
        if [[ "$var" =~ "${TDT_HOST_VERIFY_TEXT}" ]]; then
                        echo "TDX is configured on the Host"
                        VERIFY_TDX_HOST=$PASSED
        else
                        echo "$var"
                        echo -e "\n\nERROR: TDX is not enabled on the Host"
                        verification_summary
                        exit 1
        fi
}

create_td_image(){
        echo -e "\nCreating TD image ..."
        echo $GUEST_IMG_DIR
        cd "$GUEST_IMG_DIR"
        var=$(sudo ./create-td-image.sh)
        if [ $? -ne 0 ]; then
                echo "$var"
                echo -e "\n\n ERROR: TD image creation failed"
                verification_summary
                exit 1
        fi
        CREATE_TD_IMAGE=$PASSED
}

run_td_guest(){
        echo -e "\nCreating TD guest ..."
        sudo usermod -aG kvm $USER
        cd "$GUEST_TOOLS_DIR"
        var=$(./run_td.sh)
        if [ $? -ne 0 ]; then
                echo "$var"
                echo -e "\n\nERROR: Booting TD guest failed"
                verification_summary
                exit 1
        else
                echo "TD guest booted successfully"
                RUN_TD_GUEST=$PASSED
        fi

        echo -e "\nVerifying TDX enablement on guest ..."
        TD_GUEST_PORT=$(echo $var | awk -F '-p' '{print $2}' | cut -d ' ' -f 2)
        echo "TD guest is running on port : $TD_GUEST_PORT"
        ssh-keygen -f "$HOME/.ssh/known_hosts" -R "[localhost]:$TD_GUEST_PORT"
        out=$(sshpass -p "$TD_GUEST_PASSWORD" ssh -o StrictHostKeyChecking=no -p $TD_GUEST_PORT root@localhost 'dmesg | grep -i tdx' 2>&1 )
        if [[ "$out" =~ "${TD_GUEST_VERIFY_TEXT}" ]]; then
                        echo "TDX is configured on guest"
                        VERIFY_TD_GUEST=$PASSED
        elif [[ "$out" =~ "REMOTE HOST IDENTIFICATION HAS CHANGED!" ]]; then
                echo "$out"
                echo -e "\nERROR : Remove the host key '[localhost]:$TD_GUEST_PORT' $HOME/.ssh/known_hosts "
                echo -e "ERROR: TDX is not properly configured on guest"
                verification_summary
                exit 1
        else
                echo "$out"
                echo -e "\nERROR: TDX is not properly configured on guest"
                verification_summary
                exit 1
        fi
}

configure_attestation_host() {
        #Configure the PCCS service
        echo -e "\nConfiguring PCCS service ..."
        cd $CUR_DIR
        sudo cp -f $PCCS_DEFAULT_JSON /opt/intel/sgx-dcap-pccs/config/$PCCS_DEFAULT_JSON
        sudo sed -i 's/"ApiKey" :.*/"ApiKey" : '\"$ApiKey\"',/' /opt/intel/sgx-dcap-pccs/config/$PCCS_DEFAULT_JSON
        sudo sed -i 's/"UserTokenHash" :.*/"UserTokenHash" : '\"$UserTokenHash\"',/' /opt/intel/sgx-dcap-pccs/config/$PCCS_DEFAULT_JSON
        sudo sed -i 's/"AdminTokenHash" :.*/"AdminTokenHash" : '\"$AdminTokenHash\"',/' /opt/intel/sgx-dcap-pccs/config/$PCCS_DEFAULT_JSON
        sudo systemctl restart pccs

        #Verify MPA registration log
        echo -e "\nVerifying MPA registration ..."
        sudo rm -rf /var/log/mpa_registration.log
        sudo systemctl restart mpa_registration_tool
        sleep 5
        log=$(cat /var/log/mpa_registration.log)
        if [[ "$log" =~ "$MPA_REGISTRATION_CHECK" ]]; then
                echo -e "\nMPA registration is successful ..."
                CONFIGURING_ATTESTATION_HOST=$PASSED
        else
                echo "$log"
                echo -e "\nERROR : MPA registration failed"
                echo "Boot into the BIOS, go to Socket Configuration > Processor Configuration > Software Guard Extension (SGX), and set"
                echo "SGX Factory Reset to Enabled"
                echo "SGX Auto MP Registration to Enabled"
                verification_summary
                exit 1
        fi
}

verify_service_status(){
        if ! [[ "$1" =~ "$SERVICE_ACTIVE_STATUS_VERIFY_TEXT" ]]; then
                echo "$1"
                echo -e "\nERROR: $2 Service is not active. Please verify ..."
                verification_summary
                exit 1
        fi
}

verify_attestation_host(){
        echo -e "\nVerifying whether SGX is enabled in BIOS ..."
        set -x
        output=$(ls -l /dev/sgx_*)
        set +x
        if [[ $output =~ "/dev/sgx_enclave" && $output =~ "/dev/sgx_provision" && $output =~ "/dev/sgx_vepc" ]]; then
                echo "SGX enabled and devices are available"
        else
                echo -e "\nERROR: SGX not enabled in BIOS, missing SGX devices."
                verification_summary
                exit 1
        fi

        echo -e "\nVerifying Attestation services on the host ..."
        status=$(sudo systemctl status qgsd)
        verify_service_status "$status" "qgsd"

        status=$(sudo systemctl status pccs)
        verify_service_status "$status" "pccs"

        status=$(sudo systemctl status mpa_registration_tool)
        echo "$status"
        if ! [[ "$status" =~ "$MPA_SERVICE_CHECK" ]]; then
                echo "$status"
                echo "\nERROR: MPA registration service is not enabled. Please verify ..."
                verification_summary
                exit 1
        fi
        VERIFY_ATTESTATION_HOST=$PASSED
}

verify_attestation_guest(){
        echo -e "\nVerifying Attestation services on the guest ..."
        cd "$CUR_DIR"
        output=0
        sshpass -p "$TD_GUEST_PASSWORD" rsync -avz --exclude={'*.img','*.qcow2'} -e "ssh -p $TD_GUEST_PORT" "$TDX_DIR" "$VERIFY_ATTESTATION_SCRIPT" "$TRUSTAUTHORITY_API_FILE" "$TDX_CONFIG" root@localhost:/tmp/ 2>&1 || ( echo "ERROR: tdx canonical files are not copied to the TD guest"; verification_summary ; output=1 )
        [ $output -ne 0 ] && exit 1

        sshpass -p "$TD_GUEST_PASSWORD" ssh -T -o StrictHostKeyChecking=no -p "$TD_GUEST_PORT" root@localhost "cd /tmp; ./$VERIFY_ATTESTATION_SCRIPT" 2>&1 /dev/tty || ( echo "ERROR: attestation verification error on td guest"; verification_summary ; output=1 )
        if [ $output -eq 0 ]; then
                VERIFY_ATTESTATION_GUEST=$PASSED
                exit 1
        fi

}

verification_summary(){
        echo -e "\n---------------------------------VERIFICATION STATUS----------------------------------"
        echo "|------------------------------------------------------------------------------------|"
        echo "|                 Steps                        |                Status               |"
        echo "|----------------------------------------------|-------------------------------------|"
        echo "| TDX HOST Enabled check                       |                "$VERIFY_TDX_HOST"               |"
        echo "| TD Image Creation                            |                "$CREATE_TD_IMAGE"               |"
        echo "| Boot TD Guest                                |                "$RUN_TD_GUEST"               |"
        echo "| Verify TD Guest                              |                "$VERIFY_TD_GUEST"               |"
        echo "| Is Attestation Support                       |                "$IS_ATTESTATION_SUPPORT"                 |"
        echo "| Configure Attestation on Host                |                "$CONFIGURING_ATTESTATION_HOST"               |"
        echo "| Attestation Verification on Host             |                "$VERIFY_ATTESTATION_HOST"               |"
        echo "| Attestation using Intel Tiber Trust Services |                "$VERIFY_ATTESTATION_GUEST"               |"
        echo "|------------------------------------------------------------------------------------|"
}

sudo apt install --yes sshpass &> /dev/null

if [[ -z "$ApiKey" || -z "$UserTokenHash" || -z "$AdminTokenHash" ]]; then
        echo "ERROR : PCCS config values are missing in tdx-config file"
        exit 1
fi

clone_tdx_repo
verify_tdx_host
create_td_image
run_td_guest
check_attestation_support

if [ $is_prod_sys -eq 0 ]; then
        IS_ATTESTATION_SUPPORT=True
        configure_attestation_host
        verify_attestation_host
        verify_attestation_guest
        verification_summary
else
        echo "========================================================================================================================="
        echo "The host OS setup (TDX) has been done successfully. Now, please enable Intel TDX in the BIOS."
        echo "NOTE : This is a Pre-production system. Intel® SGX Data Center Attestation Primitives (Intel® SGX DCAP) are not installed"
        echo "========================================================================================================================="
        verification_summary
fi