setup_pycloudstack() {
    echo "Installing PyCloudStack required packages in Guest image"
    # Install necessary packages in the guest image and run initial setup commands
    LIBGUESTFS_DEBUG=1 LIBGUESTFS_TRACE=1 virt-customize -a $QCOW2_IMG --install qemu-utils,libguestfs-tools,cpuid,python3-virtualenv,python3-libvirt,libguestfs-dev,libvirt-dev,python3-dev,net-tools,qemu-guest-agent,docker.io,cgroupfs-mount,python3-pip \
        --run-command 'cgroupfs-mount' \
        --run-command 'dockerd -D &' \
        --run-command "sed -i 's/169.254.2.3/127.0.0.53/g' /etc/resolv.conf"

    echo "Installing PyCloudStack required packages on host system"
    # Install necessary packages on the host system
    apt install -y python3-virtualenv python3-libvirt libguestfs-dev libvirt-dev python3-dev net-tools
    usermod -aG libvirt root
    systemctl restart libvirtd

    echo "Setting up PyCloudStack venv"
    # Clone the tdx-tools repository and set up the virtual environment
    [ -d $TDX_TOOLS_DIR ] && rm -rf $TDX_TOOLS_DIR
    git clone https://github.com/anjalirai-intel/tdx-tools.git $TDX_TOOLS_DIR
    cd $TDX_TOOLS_DIR/tests/
    source setupenv.sh
    ssh-keygen -f tests/vm_ssh_test_key -N ""

    # Create artifacts.yaml with paths to the guest image and kernel
    cat >artifacts.yaml <<EOL
latest-guest-image-ubuntu:
  source: file://${QCOW2_IMG}
latest-guest-kernel-ubuntu:
  source: file://${VMLINUZ}
EOL

    cat artifacts.yaml
}

run_pycloudstack() {
    TEST_TYPE=$1
    cd $TDX_TOOLS_DIR/tests/
    # Run tests based on the TEST_TYPE parameter
    if [[ $TEST_TYPE == "sanity" ]]; then
        ./run.sh -g ubuntu -c tests/test_tdvm_lifecycle.py
    else
        ./run.sh -g ubuntu -s all
    fi
    # Exit if tests fail
    if [ $? -ne 0 ]; then
        exit 1
    fi
}

setup_canonical_suite() {
    echo "Installing Canonical suite required packages on host system"
    # Install necessary packages for the Canonical suite
    apt install -y tox python3
}

run_canonical_suite() {
    cd $TDX_DIR/tests/tests
    export TDXTEST_GUEST_IMG=$QCOW2_IMG
    # Run Canonical suite tests excluding tdreport and perf_benchmark
    tox -e test_specify -- "not tdreport and not perf_benchmark"
}
