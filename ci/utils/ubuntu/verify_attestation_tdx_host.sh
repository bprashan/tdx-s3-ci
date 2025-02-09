# Function to check if the system supports attestation
check_attestation_support() {
    cd "$TDX_DIR/attestation"
    log "Verifying if the system supports attestation ..."
    output=$(./check-production.sh)
    if [[ $output =~ "Production" ]]; then
        log "Intel® SGX Data Center Attestation Primitives (Intel® SGX DCAP) will be installed on the Host ..."
        IS_ATTESTATION_SUPPORTED=1
    else
        log "This is a Pre-production system and hence Intel® SGX Data Center Attestation Primitives (Intel® SGX DCAP) will not be installed on the Host ..."
    fi
}

# Function to configure the PCCS service
configure_pccs_service() {
    log "Configuring PCCS service ..."
    if [[ -z "$JENKINS_URL" ]]; then
        source "$CUR_DIR/utils/ubuntu/tdx-config"
    fi
    if [[ -z "$ApiKey" || -z "$UserPassword" || -z "$AdminPassword" || -z "$trustauthority_api_key" ]]; then
        log "ERROR: Config values are not initialized"
        log "Attestation services cannot be configured on Host"
        exit 1
    fi

    cd $CUR_DIR
    UserTokenHash=$(echo -n "$UserPassword" | sha512sum | cut -d ' ' -f 1)
    AdminTokenHash=$(echo -n "$AdminPassword" | sha512sum | cut -d ' ' -f 1)
    sed -i 's/"ApiKey".*/"ApiKey" : '\"$ApiKey\"',/' /opt/intel/sgx-dcap-pccs/config/$PCCS_DEFAULT_JSON
    sed -i 's/"UserTokenHash".*/"UserTokenHash" : '\"$UserTokenHash\"',/' /opt/intel/sgx-dcap-pccs/config/$PCCS_DEFAULT_JSON
    sed -i 's/"AdminTokenHash".*/"AdminTokenHash" : '\"$AdminTokenHash\"',/' /opt/intel/sgx-dcap-pccs/config/$PCCS_DEFAULT_JSON
    systemctl restart pccs
}

# Function to verify MPA registration
verify_mpa_registration() {
    log "Verifying MPA registration ..."
    rm -rf /var/log/mpa_registration.log
    systemctl restart mpa_registration_tool
    sleep 5
    log_content=$(cat /var/log/mpa_registration.log)
    if [[ "$log_content" =~ "$MPA_REGISTRATION_CHECK" ]]; then
        log "MPA registration is successful ..."
    else
        log "$log_content"
        log "ERROR: MPA registration failed"
        log "Boot into the BIOS, go to Socket Configuration > Processor Configuration > Software Guard Extension (SGX), and set"
        log "SGX Factory Reset to Enabled"
        log "SGX Auto MP Registration to Enabled"
        exit 1
    fi
}

# Function to verify service status
verify_service_status() {
    if ! [[ "$1" =~ "Active: active (running)" ]]; then
        log "$1"
        log "ERROR: $2 Service is not active. Please verify ..."
        exit 1
    fi
}

# Function to verify attestation host
verify_attestation_host() {
    log "Verifying whether SGX is enabled in BIOS ..."
    output=$(ls -l /dev/sgx_*)
    if [[ $output =~ "/dev/sgx_enclave" && $output =~ "/dev/sgx_provision" && $output =~ "/dev/sgx_vepc" ]]; then
        log "SGX enabled and devices are available"
    else
        log "ERROR: SGX not enabled in BIOS, missing SGX devices."
        exit 1
    fi

    log "Verifying Attestation services on the host ..."
    verify_service_status "$(systemctl status qgsd)" "qgsd"
    verify_service_status "$(systemctl status pccs)" "pccs"
    status=$(systemctl status mpa_registration_tool)
    log "$status"
    if ! [[ "$status" =~ "$MPA_SERVICE_CHECK" ]]; then
        log "$status"
        log "\nERROR: MPA registration service is not enabled. Please verify ..."
        exit 1
    fi
}

# Function to verify attestation guest
verify_attestation_guest() {
    log "Verifying Attestation services on the guest ..."
    cd "$CUR_DIR/utils/ubuntu"
    output=0

    sed -i 's/"trustauthority_api_key".*/"trustauthority_api_key":'\"$trustauthority_api_key\"'/' $TRUSTAUTHORITY_API_FILE
    sshpass -p "$TD_GUEST_PASSWORD" rsync -avz --exclude={'*.img','*.qcow2'} -e "ssh -p $TD_GUEST_PORT" "$VERIFY_ATTESTATION_SCRIPT" "$TRUSTAUTHORITY_API_FILE" root@localhost:/tmp/ 2>&1 || output=1
    if [ $output -ne 0 ]; then
        log "ERROR: tdx canonical files are not copied to the TD guest"
        exit 1
    fi

    sshpass -p "$TD_GUEST_PASSWORD" ssh -T -o StrictHostKeyChecking=no -p "$TD_GUEST_PORT" root@localhost "cd /tmp; ./$VERIFY_ATTESTATION_SCRIPT" 2>&1 /dev/tty || output=1
    if [ $output -ne 0 ]; then
        log "ERROR: attestation verification error on td guest"
        exit 1
    fi
    cd "$CUR_DIR"
}

# Main function to verify attestation
verify_attestation() {
    check_attestation_support
    if [ $IS_ATTESTATION_SUPPORTED -eq 1 ]; then
        configure_pccs_service
        verify_mpa_registration
        verify_attestation_host
        verify_attestation_guest
    else
        log "========================================================================================================================="
        log "NOTE: This is a Pre-production system. Intel® SGX Data Center Attestation Primitives (Intel® SGX DCAP) are not installed"
        log "========================================================================================================================="
    fi
}