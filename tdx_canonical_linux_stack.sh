#!/bin/bash
script_name=$(basename "$0")
long=setuptdx,verifytdx,createtd,runtdqemu,runtdlibvirt
TEMP=$(getopt -l $long -n $script_name -- "$@")
CUR_DIR=$(pwd)
TDX_DIR="$CUR_DIR"/tdx
TDX_TOOLS_DIR="$CUR_DIR"/tdx-tools
GUEST_TOOLS_DIR="$TDX_DIR"/guest-tools
GUEST_IMG_DIR="$GUEST_TOOLS_DIR"/image
QCOW2_IMG="$GUEST_IMG_DIR"/tdx-guest-ubuntu-24.04-generic.qcow2
TDT_HOST_VERIFY_TEXT="tdx: module initialized"
TD_GUEST_VERIFY_TEXT="tdx: Guest detected"
LIBVIRT_CONF=/etc/libvirt/qemu.conf
RESTART_CHECK_STRING='0 upgraded, 0 newly installed, 0 to remove'
BRANCH_NAME=noble-24.04
TD_VIRSH_BOOT_CMD="tdvirsh new"
TD_VIRSH_DELETE_CMD="tdvirsh delete all"
DISTRO_VER=$(. /etc/os-release; echo $VERSION_ID)
echo "Verifying TDX on Ubuntu $DISTRO_VER"

if [[ $DISTRO_VER == "23.10" ]]; then
        QCOW2_IMG="$GUEST_IMG_DIR"/tdx-guest-ubuntu-23.10.qcow2
        BRANCH_NAME=mantic-23.10
        TD_VIRSH_BOOT_CMD=td_virsh_tool.sh
        TD_VIRSH_DELETE_CMD="$TD_VIRSH_BOOT_CMD -c all"        
fi

setuptdx(){
        [ -d $TDX_DIR ] && rm -rf $TDX_DIR
        git clone -b $BRANCH_NAME https://github.com/canonical/tdx.git $TDX_DIR
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
	sudo virt-get-kernel -a $QCOW2_IMG
	VMLINUZ="$GUEST_IMG_DIR"/"$(ls | grep vmlinuz)"
	echo "$VMLINUZ"
        cd "$TDX_DIR"
        sudo ./setup-tdx-guest.sh
}

verifytd(){
        echo "with portnumber : $1"
        rm -rf $HOME/.ssh/known_hosts
        out=$(sshpass -p "123456" ssh -o StrictHostKeyChecking=no -p $1 root@localhost 'dmesg | grep -i tdx' 2>&1 )
        echo "$out"
        if [[ "$out" =~ "${TD_GUEST_VERIFY_TEXT}" ]]; then
                echo "td guest is configured"
        else
                echo "td guest is not configured"
                exit 1
        fi
}

cleanup(){
        sudo ./$TD_VIRSH_DELETE_CMD
        fuser -k $QCOW2_IMG
        sleep 20
}

runtdqemu(){
        echo "creating TD guest with QEMU"
        sudo usermod -aG kvm $USER
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
}

runtdlibvirt(){
        echo "creating TD guest with libvirt"
        sudo grep -q 'user =' "$LIBVIRT_CONF" && sudo sed 's/^user =.*/user = \"root\"/' -i "$LIBVIRT_CONF" || sudo sh -c "echo 'user = "root"' >> $LIBVIRT_CONF"
        sudo grep -q 'group =' "$LIBVIRT_CONF" && sudo sed 's/^group =.*/group = \"root\"/' -i "$LIBVIRT_CONF" || sudo sh -c "echo 'group = "root"' >> $LIBVIRT_CONF"
        sudo grep -q 'dynamic_ownership =' "$LIBVIRT_CONF" && sudo sed 's/^dynamic_ownership =.*/dynamic_ownership = 0/' -i "$LIBVIRT_CONF" || sudo sh -c "echo 'dynamic_ownership = 0' >> $LIBVIRT_CONF"
        sudo systemctl restart libvirtd
        cd "$GUEST_TOOLS_DIR"
        cleanup
        var=$(sudo ./${TD_VIRSH_BOOT_CMD})
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
                port_num=$(echo $(sudo ./tdvirsh list --all) | awk -F 'ssh:' '{print $2}' | cut -d ',' -f 1)    
        fi
        verifytd $port_num
}

setup_pycloudstack(){
	echo "Installing PyCloudStack required packages in Guest image"
	sudo LIBGUESTFS_DEBUG=1 LIBGUESTFS_TRACE=1 virt-customize -a $QCOW2_IMG --install qemu-utils,libguestfs-tools,cpuid,python3-virtualenv,python3-libvirt,libguestfs-dev,libvirt-dev,python3-dev,net-tools,qemu-guest-agent,docker.io,cgroupfs-mount --run-command 'cgroupfs-mount' --run-command 'dockerd -D &' --run-command "docker pull redis" --run-command "docker pull nginx"
	echo "Installing PyCloudStack required packages on host system"
	sudo apt install -y python3-virtualenv python3-libvirt libguestfs-dev libvirt-dev python3-dev net-tools
	sudo usermod -aG libvirt root
	sudo systemctl restart libvirtd
	echo "Setting up PyCloudStack venv"
	[ -d $TDX_TOOLS_DIR ] && sudo rm -rf $TDX_TOOLS_DIR
	git clone https://github.com/anjalirai-intel/tdx-tools.git $TDX_TOOLS_DIR
	cd $TDX_TOOLS_DIR/tests/
	source setupenv.sh
	ssh-keygen -f tests/vm_ssh_test_key -N ""
	cat >artifacts.yaml <<EOL
  latest-guest-image-ubuntu:
   source: file://${QCOW2_IMG}
  latest-guest-kernel-ubuntu:
   source: file://${VMLINUZ}
EOL

	cat artifacts.yaml
}

run_pycloudstack(){
	TEST_TYPE=$1
	cd $TDX_TOOLS_DIR/tests/
	if [[ $TEST_TYPE == "sanity" ]]; then
		sudo ./run.sh -g ubuntu -c tests/test_tdvm_lifecycle.py
	else
		sudo ./run.sh -g ubuntu -s all
	fi
}

while true; do
        case "$1" in
                --setuptdx ) echo "setuptdx got selected"; setuptdx ;shift ;;
                --verifytdx ) echo "verifytdx got selected"; verifytdx ;shift ;;
                --createtd ) echo "createtd got selected"; createtd ;shift ;;
                --runtdqemu ) echo "runtdqemu got selected"; runtdqemu ;shift ;;
                --runtdlibvirt ) echo "runtdlibvirt got selected"; runtdlibvirt ;shift ;;
                --smoke ) echo "Verify entire TDX and TD guest configuraiton"; setuptdx; verifytdx; createtd; runtdqemu; runtdlibvirt ;shift ;;
		--automatedtests  ) echo "Pycloudstack automated tests got selected"; setuptdx; verifytdx; createtd; setup_pycloudstack; run_pycloudstack $2 ;shift ;;
                -- ) shift; break;;
                * ) break;;
        esac
done
