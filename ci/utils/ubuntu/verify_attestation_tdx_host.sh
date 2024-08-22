check_attestation_support() {
        cd "$TDX_DIR"/attestation
        echo -e "\nVerifying if the system supports attestation ..."
        output=$(./check-production.sh)
        if [[ $output =~ "Production" ]]; then
                echo "Intel® SGX Data Center Attestation Primitives (Intel® SGX DCAP) will be installed on the Host ..."
                IS_ATTESTATION_SUPPORTED=1
        else
                echo "This is a Pre-production system and hence Intel® SGX Data Center Attestation Primitives (Intel® SGX DCAP) will not be installed on the Host ..."
        fi
}

configure_attestation_host() {

        # Configure the PCCS service
        echo -e "\nConfiguring PCCS service ..."
        if [[ -z "$ApiKey" || -z "$UserPassword" || -z "$AdminPassword" || -z "$trustauthority_api_key" ]]; then
                echo "ERROR : config values are not initiatized"
                echo "Attestation services cannot be configured on Host"
                exit 1
        fi

        cd $CUR_DIR
        UserTokenHash=$(echo -n "$UserPassword" | sha512sum | cut -d ' ' -f 1)
        AdminTokenHash=$(echo -n "$AdminPassword" | sha512sum | cut -d ' ' -f 1)
        sed -i 's/"ApiKey".*/"ApiKey" : '\"$ApiKey\"',/' /opt/intel/sgx-dcap-pccs/config/$PCCS_DEFAULT_JSON
        sed -i 's/"UserTokenHash".*/"UserTokenHash" : '\"$UserTokenHash\"',/' /opt/intel/sgx-dcap-pccs/config/$PCCS_DEFAULT_JSON
        sed -i 's/"AdminTokenHash".*/"AdminTokenHash" : '\"$AdminTokenHash\"',/' /opt/intel/sgx-dcap-pccs/config/$PCCS_DEFAULT_JSON
        systemctl restart pccs

        # Verify MPA registration log
        echo -e "\nVerifying MPA registration ..."
        rm -rf /var/log/mpa_registration.log
        systemctl restart mpa_registration_tool
        sleep 5
        log=$(cat /var/log/mpa_registration.log)
        if [[ "$log" =~ "$MPA_REGISTRATION_CHECK" ]]; then
                echo -e "\nMPA registration is successful ..."
        else
                echo "$log"
                echo -e "\nERROR : MPA registration failed"
                echo "Boot into the BIOS, go to Socket Configuration > Processor Configuration > Software Guard Extension (SGX), and set"
                echo "SGX Factory Reset to Enabled"
                echo "SGX Auto MP Registration to Enabled"
                exit 1
        fi
}

verify_service_status() {
        if ! [[ "$1" =~ "Active: active (running)" ]]; then
                echo "$1"
                echo -e "\nERROR: $2 Service is not active. Please verify ..."
                finally
        fi
}

verify_attestation_host() {
        echo -e "\nVerifying whether SGX is enabled in BIOS ..."
        output=$(ls -l /dev/sgx_*)
        if [[ $output =~ "/dev/sgx_enclave" && $output =~ "/dev/sgx_provision" && $output =~ "/dev/sgx_vepc" ]]; then
                echo "SGX enabled and devices are available"
        else
                echo -e "\nERROR: SGX not enabled in BIOS, missing SGX devices."

                return -1
        fi

        echo -e "\nVerifying Attestation services on the host ..."
        status=$(systemctl status qgsd)
        verify_service_status "$status" "qgsd"

        status=$(systemctl status pccs)
        verify_service_status "$status" "pccs"

        status=$(systemctl status mpa_registration_tool)
        echo "$status"
        if ! [[ "$status" =~ "$MPA_SERVICE_CHECK" ]]; then
                echo "$status"
                echo "\nERROR: MPA registration service is not enabled. Please verify ..."
                exit 1
        fi

}

verify_attestation_guest() {
        echo -e "\nVerifying Attestation services on the guest ..."
        cd "$CUR_DIR/utils/canonical"
        output=0

        sed -i 's/"trustauthority_api_key".*/"trustauthority_api_key":'\"$trustauthority_api_key\"'/' $TRUSTAUTHORITY_API_FILE
        sshpass -p "$TD_GUEST_PASSWORD" rsync -avz --exclude={'*.img','*.qcow2'} -e "ssh -p $TD_GUEST_PORT" "$VERIFY_ATTESTATION_SCRIPT" "$TRUSTAUTHORITY_API_FILE" root@localhost:/tmp/ 2>&1 || output=1
        if [ $output -ne 0 ]; then
                echo "ERROR: tdx canonical files are not copied to the TD guest"
                exit 1
        fi

        sshpass -p "$TD_GUEST_PASSWORD" ssh -T -o StrictHostKeyChecking=no -p "$TD_GUEST_PORT" root@localhost "cd /tmp; ./$VERIFY_ATTESTATION_SCRIPT" 2>&1 /dev/tty || output=1
        if [ $output -ne 0 ]; then
                echo "ERROR: attestation verification error on td guest"
                exit 1
        fi
        cd "$CUR_DIR"

}

verify_attestation(){
        check_attestation_support
        if [ $IS_ATTESTATION_SUPPORTED -eq 1 ]; then
                configure_attestation_host
                verify_attestation_host
                verify_attestation_guest
        else
                echo "========================================================================================================================="
                echo "NOTE : This is a Pre-production system. Intel® SGX Data Center Attestation Primitives (Intel® SGX DCAP) are not installed"
                echo "========================================================================================================================="
        fi
}