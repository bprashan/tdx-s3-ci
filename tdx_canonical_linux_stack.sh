#!/bin/bash
script_name=$(basename "$0")
long=setuptdx,verifytdx,createtd,runtdqemu,runtdlibvirt
TEMP=$(getopt -l $long -n $script_name -- "$@")
CUR_DIR=$(pwd)
TDX_DIR="$CUR_DIR"/tdx
GUEST_TOOLS_DIR="$TDX_DIR"/guest-tools
GUEST_IMG_DIR="$GUEST_TOOLS_DIR"/image
QCOW2_IMG="$GUEST_IMG_DIR"/tdx-guest-ubuntu-23.10.qcow2
TDT_HOST_VERIFY_TEXT="tdx: module initialized"
TD_GUEST_VERIFY_TEXT="tdx: Guest detected"
LIBVIRT_CONF=/etc/libvirt/qemu.conf
RESTART_CHECK_STRING='0 upgraded, 0 newly installed, 0 to remove'

setuptdx(){
        [ -d $TDX_DIR ] && rm -rf $TDX_DIR
        git clone -b mantic-23.10 https://github.com/canonical/tdx.git $TDX_DIR
        cd $TDX_DIR
        sudo ./setup-tdx-host.sh | tee setup_tdx.log
        if grep -viq "${RESTART_CHECK_STRING}" setup_tdx.log; then
                echo "system restart skipped"
        else
                echo "system restart required"
                exit 3
        fi
}

verifytdx(){
        var="$(sudo dmesg | grep -i tdx)"
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
        sudo ./create-td-image.sh
        cd "$TDX_DIR"
        sudo ./setup-tdx-guest.sh
}

verifytd(){
        port_num=$(echo $1 | awk -F '-p' '{print $2}' | cut -d ' ' -f 2)
        echo "with portnumber : $port_num"
        rm -rf $HOME/.ssh/known_hosts
        out=$(sshpass -p "123456" ssh -o StrictHostKeyChecking=no -p $port_num root@localhost 'dmesg | grep -i tdx' 2>&1 )
        echo "$out"
        if [[ "$out" =~ "${TD_GUEST_VERIFY_TEXT}" ]]; then
                echo "td guest is configured"
        else
                echo "td guest is not configured"
                exit 1
        fi
}

cleanup(){
        sudo ./td_virsh_tool.sh -c all
        fuser -k $QCOW2_IMG
        sleep 20
}

runtdqemu(){
        echo "creating TD guest with QEMU"
        sudo usermod -aG kvm $USER
        cd "$GUEST_TOOLS_DIR"
        cleanup
        var=$(TD_IMG="$QCOW2_IMG" ./run_td.sh)
        ret=$?
        echo $var
        if [ $ret -ne 0 ]; then
                exit 1
        fi
        echo "verifying TD guest on QEMU"
        verifytd "$var"
}

runtdlibvirt(){
        echo "creating TD guest with libvirt"
        sudo grep -q '^user =' "$LIBVIRT_CONF" && sudo sed 's/^user =.*/user = \"root\"/' -i "$LIBVIRT_CONF" || sudo echo 'user = "root"' >> "$LIBVIRT_CONF"
        sudo grep -q '^group =' "$LIBVIRT_CONF" && sudo sed 's/^group =.*/group = \"root\"/' -i "$LIBVIRT_CONF" || sudo echo 'group = "root"' >> "$LIBVIRT_CONF"
        sudo grep -q '^dynamic_ownership =' "$LIBVIRT_CONF" && sudo sed 's/^dynamic_ownership =.*/dynamic_ownership = 0/' -i "$LIBVIRT_CONF" || sudo echo 'dynamic_ownership = 0' >> "$LIBVIRT_CONF"
        sudo systemctl restart libvirtd
        cd "$GUEST_TOOLS_DIR"
        cleanup
        var=$(TD_IMG="$QCOW2_IMG" sudo ./td_virsh_tool.sh)
        ret=$?
        echo $var
        if [ $ret -ne 0 ]; then
                exit 1
        fi
        echo "verifying TD guest on libvirt"
        verifytd "$var"
}

while true; do
        case "$1" in
                --setuptdx ) echo "setuptdx got selected"; setuptdx ;shift ;;
                --verifytdx ) echo "verifytdx got selected"; verifytdx ;shift ;;
                --createtd ) echo "createtd got selected"; createtd ;shift ;;
                --runtdqemu ) echo "runtdqemu got selected"; runtdqemu ;shift ;;
                --runtdlibvirt ) echo "runtdlibvirt got selected"; runtdlibvirt ;shift ;;
                --smoke ) echo "Verify entire TDX and TD guest configuraiton"; setuptdx; verifytdx; createtd; runtdqemu; runtdlibvirt ;shift ;;
                -- ) shift; break;;
                * ) break;;
        esac
done