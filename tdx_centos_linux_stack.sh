#!/bin/bash
script_name=$(basename "$0")
long=setuptdx,verifytdx,createtd,runtdqemu,runtdlibvirt
TEMP=$(getopt -l $long -n $script_name -- "$@")
CUR_DIR=$(pwd)
NOTHING_TO_DO="Nothing to do."
TDT_HOST_VERIFY_TEXT="tdx: module initialized"
TDT_BIOS_ENABLED="tdx: BIOS enabled"
RHEL_IMAGE_PATH=/home/sdp/tdx/rhel-9.3-x86_64-kvm.qcow2
TD_GUEST_XML_PATH=${CUR_DIR}/utils/centos/td_guest.xml
SSH_PUBLIC_KEY=/home/sdp/.ssh/id_rsa.pub
ROOT_PASSWORD=123456
TD_GUEST_VERIFY_TEXT="tdx: Guest detected"
RHEL_IMAGE_LIBVIRT_PATH=/var/lib/libvirt/images/rhel-9.3-x86_64-kvm.qcow2
DEFAULT_NET_PATH=${CUR_DIR}/utils/centos/default.xml
IP="localhost"

writetdxrepo(){
        echo "[tdx]
name=CentOS TDX
metalink=https://mirrors.centos.org/metalink?repo=centos-virt-sig-tdx-devel-\$releasever-stream&arch=\$basearch&protocol=https
gpgcheck=0
enabled=1" | sudo tee /etc/yum.repos.d/tdx.repo
}



setuptdx(){
        writetdxrepo
        var=$(sudo dnf install kernel-tdx qemu-kvm-tdx libvirt-tdx )
        sleep 5
        echo $var
        if [[ $var =~ "${NOTHING_TO_DO}" ]]; then
                echo "system restart skipped"
        else
                echo "system restart required"
                exit 3
        fi
}

verifytdxinitialize(){
        var="$(sudo dmesg | grep -i tdx)"
        echo "$var"
        if [[ "$var" =~ "${TDT_HOST_VERIFY_TEXT}" ]]; then
                echo "tdx is configured on the Host"
        elif [[ "$var" =~ "${TDT_BIOS_ENABLED}" ]]; then
                sudo rmmod kvm_intel
                sudo modprobe kvm_intel tdx=1
                echo "options kvm_intel tdx=1" | sudo tee /etc/modprobe.d/tdx.conf
        else
                echo "tdx is not configured on the Host"
                exit 1
        fi
}



verifytdx(){
        kernel_ver=$(uname -r)
        kernel_ver="${kernel_ver//.x86_64/}"
        echo "system kernel version : ${kernel_ver}"
        tdx_repo_kernel_ver=$(dnf repository-packages tdx list kernel)
        echo -e "tdx repo kernel version details : \n $tdx_repo_kernel_ver"
        if [[ $tdx_repo_kernel_ver =~ $kernel_ver ]]; then
                echo "System kernel version matches with TDX repo kernel version"
                verifytdxinitialize
        else
                echo "System kernel version is not matching with TDX repo kernel version"
                exit 1
        fi
}

createtd(){
        sudo dnf install guestfs-tools
        sudo fuser -k $RHEL_IMAGE_PATH
        sleep 5
        virt-customize -a $RHEL_IMAGE_PATH --root-password password:$ROOT_PASSWORD --uninstall cloud-init --ssh-inject "root:file:${SSH_PUBLIC_KEY}"
}

verifytd(){
        if [ "$#" -eq 0 ]; then
                out=$(ssh -o StrictHostKeyChecking=no root@"$IP" 'dmesg | grep -i tdx' 2>&1 )
        else
                out=$(ssh -o StrictHostKeyChecking=no -p $1 root@"$IP" 'dmesg | grep -i tdx' 2>&1 )
        fi
        echo "$out"
        if [[ "$out" =~ "${TD_GUEST_VERIFY_TEXT}" ]]; then
                echo "td guest is configured"
        else
                echo "td guest is not configured"
                exit 1
        fi
}

runtdqemu(){
        /usr/libexec/qemu-kvm \
                -accel kvm \
                -m 4G -smp 1 \
                -name process=tdxvm,debug-threads=on \
                -cpu host \
                -object tdx-guest,id=tdx \
                -machine q35,hpet=off,kernel_irqchip=split,memory-encryption=tdx,memory-backend=ram1 \
                -object memory-backend-ram,id=ram1,size=4G,private=on \
                -nographic -vga none \
                -bios /usr/share/edk2/ovmf/OVMF.inteltdx.fd \
                -daemonize \
                -nodefaults \
                -device virtio-net-pci,netdev=nic0 -netdev user,id=nic0,hostfwd=tcp::10022-:22 \
                -drive file=${RHEL_IMAGE_PATH},if=none,id=virtio-disk0 \
                -device virtio-blk-pci,drive=virtio-disk0 \
                -pidfile /tmp/tdx-demo-td-pid.pid

        PID_TD=$(cat /tmp/tdx-demo-td-pid.pid)
        echo "TD VM, PID: ${PID_TD}, SSH : ssh -p 10022 root@localhost"
        IP="localhost"
        verifytd 10022
}

cleanlibvirt(){
        sudo virsh destroy my-td-guest
        sudo virsh net-destroy default
        sudo virsh undefine my-td-guest
        sudo virsh net-undefine default
        sleep 5
}

runtdlibvirt(){
        sudo cp -rf $RHEL_IMAGE_PATH $RHEL_IMAGE_LIBVIRT_PATH
        cleanlibvirt
        # configure default network
        sudo virsh net-define $DEFAULT_NET_PATH
        sudo virsh net-start default
        sudo virsh define $TD_GUEST_XML_PATH
        sudo virsh start my-td-guest
        sleep 20
        var=$(sudo virsh domifaddr my-td-guest)
        echo $var
        IP="$(grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' <<< "$var")"
        verifytd
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