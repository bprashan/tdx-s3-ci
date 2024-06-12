#!/bin/bash

CUR_DIR=$(pwd)
TDX_DIR="$CUR_DIR"/tdx_verifier
BRANCH_NAME=noble-24.04
ATTESTATION_DIR="$TDX_DIR"/attestation
GUEST_TOOLS_DIR="$TDX_DIR"/guest-tools
TD_GUEST_VERIFY_TEXT="tdx: Guest detected"
TDT_HOST_VERIFY_TEXT="tdx: module initialized"
SERVICE_ACTIVE_STATUS_VERIFY_TEXT="Active: active (running)"
MPA_SERVICE_CHECK="mpa_registration_tool.service; enabled; preset: enabled"
VERIFY_ATTESTATION_SCRIPT="verify_attestation_td_guest.sh"
TD_GUEST_PASSWORD=123456
TD_GUEST_PORT=10022
MPA_REGISTRATION_CHECK="INFO: Registration Flow - Registration status indicates registration is completed successfully"
TRUSTAUTHORITY_API_FILE="config.json"

args=$(getopt -a -o i:h -l td_image_path: -- "$@")
if [[ $? -gt 0 ]]; then
  usage
fi


usage(){
>&2 cat << EOF
Usage: $0
   [ -i | --td_image_path input ]
EOF
exit 1
}


clone_tdx_repo(){
        echo -e "\n\nCloning TDX git repository with '$BRANCH_NAME' branch.."
        [ -d $TDX_DIR ] && rm -rf $TDX_DIR
        git clone -b $BRANCH_NAME https://github.com/canonical/tdx.git $TDX_DIR
}


verify_tdx_host(){
        echo -e "\n\nVerifying whether host is configured with TDX or not.."
        var="$(sudo dmesg | grep -i tdx)"
        echo "$var"
        if [[ "$var" =~ "${TDT_HOST_VERIFY_TEXT}" ]]; then
                        echo -e "TDX is configured on the Host.\n"
        else
                        echo -e "Failure: TDX is not configured on the Host!!\n"
                        exit 1
        fi
}

verify_td_guest(){
        echo -e "\n\nVerifying whether the guest is configured with TDX or not.."
        echo "TD guest is running on portnumber : $TD_GUEST_PORT"
        out=$(sshpass -p "$TD_GUEST_PASSWORD" ssh -o StrictHostKeyChecking=no -p $TD_GUEST_PORT root@localhost 'dmesg | grep -i tdx' 2>&1 )
        echo "$out"
        if [[ "$out" =~ "${TD_GUEST_VERIFY_TEXT}" ]]; then
                        echo -e "TDX is configured on guest.\n"
        else
                        echo -e "Failure: TDX is not configured on guest!!\n"
                        exit 1
        fi
}


run_verify_td_guest(){
        echo -e "\nCreating TD guest with QEMU\n"
        sudo usermod -aG kvm $USER
        cd "$GUEST_TOOLS_DIR"
        var=$(TD_IMG=/home/sdp/bprashan/test/tdx-guest-ubuntu-24.04-generic.qcow2 ./run_td.sh)
        ret=$?
        echo -e "$var"
        if [ $ret -ne 0 ]; then
                        exit 1
        fi
        echo -e "\nVerifying TD guest on QEMU\n"
        TD_GUEST_PORT=$(echo $var | awk -F '-p' '{print $2}' | cut -d ' ' -f 2)
        verify_td_guest
}

check_production_system() {
        cd $ATTESTATION_DIR
        echo -e "\n\nVerifying whether the system supports attestation.."
        output=$(sudo ./check-production.sh)
        echo $output
        if [[ $output =~ "Production" ]]; then
                echo -e "Attestation is supported.\nThe attestation components are installed \n"
        sed -i 's/^TDX_SETUP_ATTESTATION=0/TDX_SETUP_ATTESTATION=1/' "$TDX_DIR"/setup-tdx-config
        else
                echo -e " Pre-production system. Attestation is not supported on Pre-production systems.\n Attestation verification is skipped\n"
        exit 0
        fi
}

verify_sgx_devices() {
        echo -e "\n\nVerifying whether SGX is enabled in BIOS.."
        set -x
        output=$(ls -l /dev/sgx_*)
        set +x
        if [[ $output =~ "/dev/sgx_enclave" && $output =~ "/dev/sgx_provision" && $output =~ "/dev/sgx_vepc" ]]; then
                        echo -e "SGX enabled and devices present.\n"
        else
                        echo -e "Failure: SGX not enabled in BIOS, missing SGX devices. Exiting..!\n"
                        exit 1
        fi
}

verify_service_status(){
        echo -e "$1"
        if ! [[ "$1" =~ "$SERVICE_ACTIVE_STATUS_VERIFY_TEXT" ]]; then
                echo -e "\nFailure: attestation Service is not active. Please verify...\n"
                exit 1
        fi
}

verify_attestation_services() {
        echo -e "\n\nVerifying Attestation services on the host...\n"
        status=$(sudo systemctl status qgsd)
        verify_service_status "$status"

        status=$(sudo systemctl status pccs)
        verify_service_status "$status"

        sudo rm -rf /var/log/mpa_registration.log
        sudo systemctl restart mpa_registration_tool
        sleep 5
        log=$(cat /var/log/mpa_registration.log)
        echo "$log"
        if [[ "$log" =~ "$MPA_REGISTRATION_CHECK" ]]; then
                echo "MPA registration is successful"
        else
                echo "ERROR : MPA registration failure"
                exit 1
        fi

        status=$(sudo systemctl status mpa_registration_tool)
        echo -e "$status"
        if ! [[ "$status" =~ "$MPA_SERVICE_CHECK" ]]; then
                echo "\nFailure: MPA Service is not enabled. Please verify...\n"
                exit 1
        fi
}

verify_attestation_host(){
        verify_sgx_devices
        verify_attestation_services
}

verify_attestation_guest(){
        echo -e "\n\nVerifying Attestation services on the guest...\n"
        cd "$CUR_DIR"
        sshpass -p "$TD_GUEST_PASSWORD" scp -vv -P "$TD_GUEST_PORT" -r "$TDX_DIR" "$VERIFY_ATTESTATION_SCRIPT" "$TRUSTAUTHORITY_API_FILE" root@localhost:/tmp/ 2>&1 || (echo "scp command failure" && exit 1)
        sshpass -p "$TD_GUEST_PASSWORD" ssh -T -o StrictHostKeyChecking=no -p "$TD_GUEST_PORT" root@localhost "cd /tmp; ./$VERIFY_ATTESTATION_SCRIPT" 2>&1 /dev/tty || (echo "ERROR: attestation verification error on td guest" && exit 1)
}

args=$(getopt -a -o i:h -l td_image_path: -- "$@")
if [[ $? -gt 0 ]]; then
  usage
fi

eval set -- "$args"
while :
do
        case $1 in
                -i | --td_image_path) TD_IMG=$2 ; break ;;
                -h) usage; shift ;;
                --) shift; break ;;
                *) >&2 echo Unsupported option: $1
                        usage ;;
        esac
done

if [[ -z $TD_IMG ]]; then
        echo -e "ERROR: -i or --td_image_path is mandatory argument.";
        exit 1;
fi

apt install --yes sshpass &> /dev/null
clone_tdx_repo
verify_tdx_host
check_production_system
verify_attestation_host
run_verify_td_guest
verify_attestation_guest
