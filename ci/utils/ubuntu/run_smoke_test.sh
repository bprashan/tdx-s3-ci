# Function to setup TDX Host
setuptdx() {
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
        echo -e "\n\n ERROR: Setup TDX Host failed"
        exit 1
    fi

    apt install sshpass
    usermod -aG kvm "$USER"
    
    # Check if system restart is required
    if grep -viq "${RESTART_CHECK_STRING}" setup_tdx.log; then
        echo "system restart skipped"
    else
        echo "system restart required"
        exit 3
    fi
}

# Function to verify TDX Host configuration
verifytdx() {
    var="$(dmesg | grep -i tdx)"
    echo "$var"
    if [[ "$var" =~ "${TDT_HOST_VERIFY_TEXT}" ]]; then
        echo "tdx is configured on the Host"
    else
        echo "tdx is not configured on the Host"
        exit 1
    fi
}

# Function to create TD image
createtd() {
    echo "$GUEST_IMG_DIR"
    cd "$GUEST_IMG_DIR"
    
    # Check if TD image already exists
    if [ -e td_image_created ]; then
        echo "TD image already present"
    else
        ./create-td-image.sh -v 24.04
        virt-get-kernel -a "$QCOW2_IMG"
        touch td_image_created
    fi
    
    VMLINUZ="$GUEST_IMG_DIR/$(ls | grep vmlinuz)"
    echo "$VMLINUZ"
    cd "$TDX_DIR"
}

# Function to verify TD Guest configuration
verifytd() {
    echo "with port number: $1"
    home_dir=$(grep "$USER" /etc/passwd | cut -d ":" -f 6)
    
    # Remove existing SSH key for localhost
    if [ -f "$home_dir/.ssh/known_hosts" ]; then
        ssh-keygen -f "$home_dir/.ssh/known_hosts" -R "[localhost]:$TD_GUEST_PORT"
    fi
    
    out=$(sshpass -p "$TD_GUEST_PASSWORD" ssh -o StrictHostKeyChecking=no -p "$1" root@localhost 'dmesg | grep -i tdx' 2>&1)
    echo "$out"
    if [[ "$out" =~ "${TD_GUEST_VERIFY_TEXT}" ]]; then
        echo "td guest is configured"
    else
        echo "td guest is not configured"
        exit 1
    fi
}

# Function to clean up existing TD guest instances
cleanup() {
    # Deletes all VMs created using libvirt
    ./$TD_VIRSH_DELETE_CMD
    fuser -k "$QCOW2_IMG"
    # Find all QEMU processes
    qemu_processes=$(ps -eF | grep qemu | grep -v grep | awk '{print $2}')
    if [ ! -z "$qemu_processes" ]; then
        for pid in $qemu_processes; do
            echo "killing QEMU process with PID : $pid"
            kill -9 $pid
        done
    fi
    sleep 20
}

# Function to run TD guest with QEMU
runtdqemu() {
    echo "creating TD guest with QEMU"
    cd "$GUEST_TOOLS_DIR"
    cleanup
    var=$(./run_td.sh)
    ret=$?
    echo "$var"
    if [ $ret -ne 0 ]; then
        exit 1
    fi
    echo "verifying TD guest on QEMU"
    #port_num=$(echo "$var" | awk -F '-p' '{print $2}' | cut -d ' ' -f 2)
    port_num=10022
    verifytd "$port_num"
    QEMU_PID=$(echo "$var" | awk -F ', PID:' '{print $2}' | cut -d ' ' -f 2 | sed 's/,/ /g')
}

# Function to clean TD guest with QEMU
cleantdqemu() {
    echo "Killing Qemu with PID $QEMU_PID"
    kill -9 "$QEMU_PID"
}

# Function to run TD guest with Libvirt
runtdlibvirt() {
    echo "creating TD guest with libvirt"
    
    # Update libvirt configuration
    grep -q '^user =' "$LIBVIRT_CONF" && sed 's/^user =.*/user = "root"/' -i "$LIBVIRT_CONF" || echo 'user = "root"' | tee -a "$LIBVIRT_CONF"
    grep -q '^group =' "$LIBVIRT_CONF" && sed 's/^group =.*/group = "root"/' -i "$LIBVIRT_CONF" || echo 'group = "root"' | tee -a "$LIBVIRT_CONF"
    grep -q '^dynamic_ownership =' "$LIBVIRT_CONF" && sed 's/^dynamic_ownership =.*/dynamic_ownership = 0/' -i "$LIBVIRT_CONF" || echo 'dynamic_ownership = 0' | tee -a "$LIBVIRT_CONF"
    grep -q '^security_driver =' "$LIBVIRT_CONF" && sed 's/^security_driver =.*/security_driver = "none"/' -i "$LIBVIRT_CONF" || echo 'security_driver = "none"' | tee -a "$LIBVIRT_CONF"
    
    systemctl restart libvirtd
    cd "$GUEST_TOOLS_DIR"
    cleanup
    var=$(./${TD_VIRSH_BOOT_CMD})
    ret=$?
    echo "$var"
    if [ $ret -ne 0 ]; then
        exit 1
    fi
    sleep 20
    echo "verifying TD guest on libvirt"
    
    if [[ $DISTRO_VER == "23.10" ]]; then
        port_num=$(echo "$var" | awk -F '-p' '{print $2}' | cut -d ' ' -f 2)
    else
        port_num=$(echo $(./tdvirsh list --all) | awk -F 'hostfwd:' '{print $2}' | cut -d ',' -f 1)
    fi
    verifytd "$port_num"
    cleanup
}
