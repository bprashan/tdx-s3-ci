#!/bin/bash

# Get the script name
script_name=$(basename "$0")

# Define long options for the script
long=setuptdx,verifytdx,createtd,runtdqemu,runtdlibvirt,smoke,pycloudstack_automatedtests,canonical_automatedtests

# Parse the command-line options
TEMP=$(getopt -l $long -n $script_name -- "$@")

# Define directories and file paths
CUR_DIR=$(pwd)
TDX_DIR="$CUR_DIR/tdx"
GUEST_TOOLS_DIR="$TDX_DIR/guest-tools"
GUEST_IMG_DIR="$GUEST_TOOLS_DIR/image"
QCOW2_IMG="$GUEST_IMG_DIR/tdx-guest-ubuntu-24.04-generic.qcow2"
LIBVIRT_CONF=/etc/libvirt/qemu.conf
TDX_TOOLS_DIR="$CUR_DIR/tdx-tools"

# Define constants
RESTART_CHECK_STRING='0 upgraded, 0 newly installed, 0 to remove'
TDT_HOST_VERIFY_TEXT="tdx: module initialized"
TD_GUEST_VERIFY_TEXT="tdx: Guest detected"
BRANCH_NAME=${BRANCH_NAME:-'main'}
TD_VIRSH_BOOT_CMD="tdvirsh new"
TD_VIRSH_DELETE_CMD="tdvirsh delete all"
TD_GUEST_USER=root
TD_GUEST_PASSWORD=123456
TD_GUEST_PORT=10022
PCCS_DEFAULT_JSON="default.json"
MPA_REGISTRATION_CHECK="INFO: Registration Flow - Registration status indicates registration is completed successfully"
MPA_SERVICE_CHECK="mpa_registration_tool.service; enabled; preset: enabled"
TRUSTAUTHORITY_API_FILE="config.json"
VERIFY_ATTESTATION_SCRIPT="verify_attestation_td_guest.sh"

# Function to log messages with timestamps
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to source necessary configuration and script files
source_configs() {
    source "$CUR_DIR/utils/ubuntu/run_smoke_test.sh"
    source "$CUR_DIR/utils/ubuntu/verify_attestation_tdx_host.sh"
    source "$CUR_DIR/utils/ubuntu/run_automated_tests.sh"
}

# Function to execute tasks based on the provided command-line options
execute_task() {
    while true; do
        case "$1" in
            --setuptdx ) log "setuptdx got selected"; setuptdx; shift ;;
            --verifytdx ) log "verifytdx got selected"; verifytdx; shift ;;
            --createtd ) log "createtd got selected"; createtd default; shift ;;
            --runtdqemu ) log "runtdqemu got selected"; runtdqemu; cleantdqemu; shift ;;
            --runtdlibvirt ) log "runtdlibvirt got selected"; runtdlibvirt default; shift ;;
            --smoke ) log "Verify entire TDX and TD guest configuration"; createtd default; runtdqemu; verify_attestation; cleantdqemu; runtdlibvirt default; shift ;;
            --smoke_custom ) log "Verify entire TDX and TD guest configuration"; setuptdx; createtd custom; runtdlibvirt custom; shift ;;
            --pycloudstack_automatedtests ) log "Pycloudstack automated tests got selected"; createtd default; setup_pycloudstack; run_pycloudstack $2; shift ;;
            --canonical_automatedtests ) log "Canonical automated tests got selected"; createtd default; setup_canonical_suite; run_canonical_suite; shift ;;
            -- ) shift; break ;;
            * ) break ;;
        esac
    done
}

# Main function to orchestrate the script execution
main() {
    source_configs
    execute_task "$@"
}

# Start the script by calling the main function with all command-line arguments
main "$@"
