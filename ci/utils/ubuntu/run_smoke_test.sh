setuptdx(){
        [ -d $TDX_DIR ] && rm -rf $TDX_DIR
        git clone -b $BRANCH_NAME https://github.com/canonical/tdx.git $TDX_DIR
        cd $TDX_DIR
        sed -i 's/^TDX_SETUP_ATTESTATION=0/TDX_SETUP_ATTESTATION=1/' "$TDX_DIR"/setup-tdx-config
        ./setup-tdx-host.sh | tee setup_tdx.log
        if [ $? -ne 0 ]; then
                echo -e "\n\n ERROR: Setup TDX Host failed"
                exit 1
        fi
        if grep -viq "${RESTART_CHECK_STRING}" setup_tdx.log; then
                echo "system restart skipped"
        else
                echo "system restart required"
                exit 3
        fi
}

verifytdx(){
        var="$(dmesg | grep -i tdx)"
        echo "$var"
        if [[ "$var" =~ "${TDT_HOST_VERIFY_TEXT}" ]]; then
                echo "tdx is configured on the Host"
        else
                echo "tdx is not configured on the Host"
                exit 1
        fi
}

createtd(){
        echo $GUEST_IMG_DIR
        cd "$GUEST_IMG_DIR"
        if [ -e td_image_created ]; then
                echo "TD image already present"
        else
                ./create-td-image.sh
                virt-get-kernel -a $QCOW2_IMG
                touch td_image_created
        fi
        VMLINUZ="$GUEST_IMG_DIR"/"$(ls | grep vmlinuz)"
        echo "$VMLINUZ"
        cd "$TDX_DIR"
}

verifytd(){
        echo "with portnumber : $1"
        home_dir=$(cat /etc/passwd | grep $USER | cut -d ":" -f 6)
        if [ -f "$home_dir/.ssh/known_hosts" ]; then
                ssh-keygen -f "$home_dir/.ssh/known_hosts" -R "[localhost]:$TD_GUEST_PORT"
        fi
        out=$(sshpass -p $TD_GUEST_PASSWORD ssh -o StrictHostKeyChecking=no -p $1 root@localhost 'dmesg | grep -i tdx' 2>&1 )
        echo "$out"
        if [[ "$out" =~ "${TD_GUEST_VERIFY_TEXT}" ]]; then
                echo "td guest is configured"
        else
                echo "td guest is not configured"
                exit 1
        fi
}

cleanup(){
        ./$TD_VIRSH_DELETE_CMD
        fuser -k $QCOW2_IMG
        sleep 20
}

runtdqemu(){
        echo "creating TD guest with QEMU"
        usermod -aG kvm $USER
        cd "$GUEST_TOOLS_DIR"
        cleanup
        var=$( ./run_td.sh)
        ret=$?
        echo $var
        if [ $ret -ne 0 ]; then
                exit 1
        fi
        echo "verifying TD guest on QEMU"
        port_num=$(echo $var | awk -F '-p' '{print $2}' | cut -d ' ' -f 2)
        verifytd $port_num
        QEMU_PID=$(echo $var | awk -F ', PID:' '{print $2}' | cut -d ' ' -f 2 | sed 's/,/ /g')
}

cleantdqemu(){
        echo "Killing Qemu with PID $QEMU_PID"
        kill -9 $QEMU_PID
}

runtdlibvirt(){
        echo "creating TD guest with libvirt"
        grep -q 'user =' "$LIBVIRT_CONF" && sed 's/^user =.*/user = \"root\"/' -i "$LIBVIRT_CONF" || sh -c "echo 'user = "root"' >> $LIBVIRT_CONF"
        grep -q 'group =' "$LIBVIRT_CONF" && sed 's/^group =.*/group = \"root\"/' -i "$LIBVIRT_CONF" || sh -c "echo 'group = "root"' >> $LIBVIRT_CONF"
        grep -q 'dynamic_ownership =' "$LIBVIRT_CONF" && sed 's/^dynamic_ownership =.*/dynamic_ownership = 0/' -i "$LIBVIRT_CONF" || sh -c "echo 'dynamic_ownership = 0' >> $LIBVIRT_CONF"
        systemctl restart libvirtd
        cd "$GUEST_TOOLS_DIR"
        cleanup
        var=$(./${TD_VIRSH_BOOT_CMD})
        ret=$?
        echo $var
        if [ $ret -ne 0 ]; then
                exit 1
        fi
        sleep 20
        echo "verifying TD guest on libvirt"
        if [[ $DISTRO_VER == "23.10" ]]; then
                port_num=$(echo $var | awk -F '-p' '{print $2}' | cut -d ' ' -f 2)
        else
                port_num=$(echo $(./tdvirsh list --all) | awk -F 'ssh:' '{print $2}' | cut -d ',' -f 1)
                vm_name=$(echo $var | awk -F 'Name:' '{print $2}' | cut -d ' ' -f 2)
        fi
        verifytd $port_num
        del_vm=$(./tdvirsh delete ${vm_name})
        echo $del_vm
}