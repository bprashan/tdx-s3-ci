#!/bin/bash

# Get the current directory
CUR_DIR=$(pwd)

# Text to verify successful TD Quote and Report
TD_QUOTE_TEXT="Successfully get the TD Quote"
TD_REPORT_TEXT="Wrote TD Report to report.dat"

# Path to the Intel Tiber Trust Service examples
TRUST_SERVICE_PATH=/usr/share/doc/libtdx-attest-dev/examples/

# Function to log messages with timestamps
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to verify if Intel Tiber Trust Services are running
verify_intel_tiber_trust_service(){
    log "Checking whether Intel Tiber Trust Services is running ..."
    trustauthority-cli version
    if ! [[ $? == 0 ]]; then
        log "ERROR: trustauthority service is not installed"
        exit 1
    fi
    cd $TRUST_SERVICE_PATH
    var=$(./test_tdx_attest)
    if [[ ("$var" =~ "$TD_QUOTE_TEXT") && ("$var" =~ "$TD_REPORT_TEXT") ]]; then
        log "Intel Tiber Trust Services running"
    else
        log "$var"
        log "ERROR: Intel Tiber Trust Services not running"
        exit 1
    fi
}

# Function to attest with Intel Tiber Trust Service
attest_intel_tiber_trust_service(){
    log "Verify attest with Intel Tiber Trust Service ..."
    cd $CUR_DIR
    var=$(trustauthority-cli token -c config.json)
    if ! [[ $? == 0 ]]; then
        log "$var"
        log "ERROR: Attestation with Intel Tiber Trust Service failed!"
        exit 1
    else
        log "Attestation with Intel Tiber Trust Service is successful!"
    fi
}

# Execute the functions
verify_intel_tiber_trust_service
attest_intel_tiber_trust_service
