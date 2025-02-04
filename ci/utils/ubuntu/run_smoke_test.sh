# Function to setup TDX Host
setuptdx() {
    log "Setting up TDX Host"
    # Remove existing TDX directory if it exists
    [ -d "$TDX_DIR" ] && rm -rf "$TDX_DIR"
    
    # Clone the TDX repository
    git clone -b "$BRANCH_NAME" https://github.com/canonical/tdx.git "$TDX_DIR"
    cd "$TDX_DIR"
    
    # Enable TDX attestation
    sed -i 's/^TDX_SETUP_ATTESTATION=0/TDX_SETUP_ATTESTATION=1/' "$TDX_DIR/setup-tdx-config"
    
    # Run the setup script and log the output
    ./setup-tdx-host.sh | tee setup_tdx.log
    if [ $? -ne 0 ]; then
        log "ERROR: Setup TDX Host failed"
        exit 1
    fi

    apt install sshpass
    usermod -aG kvm "$USER"
    
    # Check if system restart is required
    if grep -viq "${RESTART_CHECK_STRING}" setup_tdx.log; then
        log "System restart skipped"
    else
        log "System restart required"
        exit 3
    fi
}

# Function to verify TDX Host configuration
verifytdx() {
    log "Verifying TDX Host configuration"
    var="$(dmesg | grep -i tdx)"
    echo "$var"
    if [[ "$var" =~ "${TDT_HOST_VERIFY_TEXT}" ]]; then
        log "tdx is configured on the Host"
    else
        log "tdx is not configured on the Host"
        exit 1
    fi
}

# Function to get values from tdx-config file
get_value() {
    local key=$1
    local file="$CUR_DIR/utils/ubuntu/tdx-config"
    grep "^$key=" "$file" | cut -d'=' -f2
}

# Function to create TD image
createtd() {
    IMAGE_TYPE=$1
    image_version=24.04
    log "Image type is $IMAGE_TYPE"

    # Check if TD image already exists
    cd "$GUEST_IMG_DIR"
    if [ -e td_image_created ]; then
        log "TD image already present"
    else
        if [ "$IMAGE_TYPE" == "custom" ]; then
            log "Inside Custom test"
            ./create-td-image.sh -v "$image_version" -o tdx-guest.qcow2 -u tdx_test -p intel123 -n test-guest | tee create_td_image.log
            QCOW2_IMG="$GUEST_IMG_DIR/tdx-guest.qcow2"
            # Check if custom TDX image was created
            if grep -viq "tdx-guest.qcow2" create_td_image.log; then
                log "Verified the image name"
            else
                log "Image name does not match custom name, exiting now."
                exit 1
            fi
        else
            ./create-td-image.sh -v "$image_version"
        fi
        virt-get-kernel -a "$QCOW2_IMG"
        touch td_image_created
    fi
    
    VMLINUZ="$GUEST_IMG_DIR/$(ls | grep vmlinuz)"
    log "$VMLINUZ"
    cd "$TDX_DIR"
    # fetch the http_proxy and https_proxy from the tdx-config file
    http_proxy=$(get_value 'http_proxy')
    https_proxy=$(get_value 'https_proxy')
    LIBGUESTFS_DEBUG=1 LIBGUESTFS_TRACE=1 virt-customize -a $QCOW2_IMG --run-command 'echo "Acquire::http::proxy \"$http_proxy\";\nAcquire::https::proxy \"$https_proxy\";" > /etc/apt/apt.conf.d/tdx_proxy' \
        --run-command 'echo "http_proxy=$http_proxy" >> /etc/environment' \
        --run-command 'echo "https_proxy=$https_proxy" >> /etc/environment'
}

# Function to verify TD Guest configuration
verifytd() {
    log "Verifying TD Guest configuration with port number: $2"
    home_dir=$(grep -w "$USER" /etc/passwd | cut -d ":" -f 6)
    
    # Remove existing SSH key for localhost
    if [ -f "$home_dir/.ssh/known_hosts" ]; then
        ssh-keygen -f "$home_dir/.ssh/known_hosts" -R "[localhost]:$TD_GUEST_PORT"
        [ -n "$3"] && ssh-keygen -f '$home_dir/.ssh/known_hosts' -R "$3"
    fi
    
    IMAGE_TYPE=$4
    if [ "$IMAGE_TYPE" == "custom" ]; then
        log "This is custom image hence setting the guest user and password"
        TD_GUEST_PASSWORD=intel123
        TD_GUEST_USER=tdx_test
    fi
    out=$(sshpass -p "$TD_GUEST_PASSWORD" ssh -o StrictHostKeyChecking=no -p "$2" $TD_GUEST_USER@localhost 'sudo dmesg | grep -i tdx' 2>&1)
    echo "$out"
    if [[ "$out" =~ "${TD_GUEST_VERIFY_TEXT}" ]]; then
        log "td guest is configured (checked using port number)"
    else
        log "td guest is not configured (checked using port number)"
        exit 1
    fi

    RUN_TYPE=$1
    if [ "$RUN_TYPE" == "virsh" ]; then
        ip_addr=$(sshpass -p "$TD_GUEST_PASSWORD" ssh -o StrictHostKeyChecking=no $TD_GUEST_USER@"$3" 'sudo dmesg | grep -i tdx' 2>&1)
        echo "$ip_addr"
        if [[ "$ip_addr" =~ "${TD_GUEST_VERIFY_TEXT}" ]]; then
            log "td guest is configured (checked using ip address)"
        else
            log "td guest is not configured (checked using ip address)"
            exit 1
        fi
    fi

    username=$(sshpass -p "$TD_GUEST_PASSWORD" ssh -o StrictHostKeyChecking=no -p "$2" $TD_GUEST_USER@localhost 'whoami' 2>&1)
    echo "$username"
    if [[ "$username" == "${TD_GUEST_USER}" ]]; then
        log "Username matches the custom user set when creating TD image"
    else
        log "Username doesn't match the custom user set when creating TD image"
        exit 1
    fi

    verify_tdxguest=$(sshpass -p "$TD_GUEST_PASSWORD" ssh -o StrictHostKeyChecking=no -p "$2" $TD_GUEST_USER@localhost 'sudo mkdir -p /sys/kernel/config/tsm/report/testreport0 && cat /sys/kernel/config/tsm/report/testreport0/provider' 2>&1)
    log "$verify_tdxguest"
    if [[ "$verify_tdxguest" == "tdx_guest" ]]; then
        log "Verified quote generation provider"
    else
        log "Could not verify quote generation provider"
        exit 1
    fi
}

# Function to clean up existing TD guest instances
cleanup() {
    log "Cleaning up existing TD guest instances"
    # Deletes all VMs created using libvirt
    ./$TD_VIRSH_DELETE_CMD
    fuser -k "$QCOW2_IMG"
    # Find all QEMU processes
    qemu_processes=$(ps -eF | grep qemu | grep -v grep | awk '{print $2}')
    if [ ! -z "$qemu_processes" ]; then
        for pid in $qemu_processes; do
            log "killing QEMU process with PID : $pid"
            kill -9 $pid
        done
    fi
    sleep 20
}

# Function to run TD guest with QEMU
runtdqemu() {
    log "creating TD guest with QEMU"
    cd "$GUEST_TOOLS_DIR"
    cleanup
    var=$(./run_td.sh)
    ret=$?
    echo "$var"
    if [ $ret -ne 0 ]; then
        exit 1
    fi
    log "verifying TD guest on QEMU"
    port_num=10022
    verifytd "qemu" "$port_num"
    QEMU_PID=$(echo "$var" | awk -F ', PID:' '{print $2}' | cut -d ' ' -f 2 | sed 's/,/ /g')
}

# Function to clean TD guest with QEMU
cleantdqemu() {
    log "Killing Qemu with PID $QEMU_PID"
    kill -9 "$QEMU_PID"
}

# Function to run TD guest with Libvirt
runtdlibvirt() {
    IMAGE_TYPE=$1
    log "creating TD guest with libvirt"
    
    # Update libvirt configuration
    grep -q '^user =' "$LIBVIRT_CONF" && sed 's/^user =.*/user = "root"/' -i "$LIBVIRT_CONF" || echo 'user = "root"' | tee -a "$LIBVIRT_CONF"
    grep -q '^group =' "$LIBVIRT_CONF" && sed 's/^group =.*/group = "root"/' -i "$LIBVIRT_CONF" || echo 'group = "root"' | tee -a "$LIBVIRT_CONF"
    grep -q '^dynamic_ownership =' "$LIBVIRT_CONF" && sed 's/^dynamic_ownership =.*/dynamic_ownership = 0/' -i "$LIBVIRT_CONF" || echo 'dynamic_ownership = 0' | tee -a "$LIBVIRT_CONF"
    grep -q '^security_driver =' "$LIBVIRT_CONF" && sed 's/^security_driver =.*/security_driver = "none"/' -i "$LIBVIRT_CONF" || echo 'security_driver = "none"' | tee -a "$LIBVIRT_CONF"
    
    systemctl restart libvirtd
    cd "$GUEST_TOOLS_DIR"
    cleanup
    if [ "$IMAGE_TYPE" == "custom" ]; then
        log "Starting custom TD image"
        var=$(./${TD_VIRSH_BOOT_CMD} -i ${QCOW2_IMG})
    else
        var=$(./${TD_VIRSH_BOOT_CMD})
    fi
    ret=$?
    echo "$var"
    if [ $ret -ne 0 ]; then
        exit 1
    fi
    sleep 20
    log "verifying TD guest on libvirt"
    
    port_num=$(echo $(./tdvirsh list --all) | awk -F 'hostfwd:' '{print $2}' | cut -d ',' -f 1)
    ip_addr=$(echo $(./tdvirsh list --all) | awk -F 'ip:' '{print $2}' | cut -d ',' -f 1)

    verifytd "virsh" "$port_num" "$ip_addr" "$IMAGE_TYPE"
    cleanup
}
