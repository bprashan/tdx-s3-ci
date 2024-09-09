#!/bin/bash

# Get the current directory
CUR_DIR=$(pwd)

# Text to verify successful TD Quote and Report
TD_QUOTE_TEXT="Successfully get the TD Quote"
TD_REPORT_TEXT="Wrote TD Report to report.dat"

# Path to the Intel Tiber Trust Service examples
TRUST_SERVICE_PATH=/usr/share/doc/libtdx-attest-dev/examples/

# Source the TDX configuration
source "$CUR_DIR"/tdx-config

# Function to set up proxy inside the guest environment
setup_proxy_inside_guest(){
    if ! [[ -z "$http_proxy" || -z "$https_proxy" ]]; then
        echo "Updating the proxy details on TD guest..."
        echo -e "Acquire::http::proxy \"$http_proxy\";\nAcquire::https::proxy \"$https_proxy\";" > /etc/apt/apt.conf.d/tdx_proxy
        export http_proxy="$http_proxy"
        export https_proxy="$https_proxy"
    fi
}

# Function to verify if Intel Tiber Trust Services are running
verify_intel_tiber_trust_service(){
    echo -e "\nChecking whether Intel Tiber Trust Services is running ..."
    trustauthority-cli version
    if ! [[ $? == 0 ]]; then
        echo -e "\nERROR: trustauthority service is not installed"
        exit 1
    fi
    cd $TRUST_SERVICE_PATH
    var=$(./test_tdx_attest)
    if [[ ("$var" =~ "$TD_QUOTE_TEXT") && ("$var" =~ "$TD_REPORT_TEXT") ]]; then
        echo -e "\nIntel Tiber Trust Services running"
    else
        echo "$var"
        echo -e "\nERROR: Intel Tiber Trust Services not running"
        exit 1
    fi
}

# Function to attest with Intel Tiber Trust Service
attest_intel_tiber_trust_service(){
    echo -e "\nVerify attest with Intel Tiber Trust Service ..."
    cd $CUR_DIR
    var=$(trustauthority-cli token -c config.json)
    if ! [[ $? == 0 ]]; then
        echo "$var"
        echo -e "\nERROR: Attestation with Intel Tiber Trust Service failed!"
        exit 1
    else
        echo -e "\nAttestation with Intel Tiber Trust Service is successful!"
    fi
}

# Execute the functions
setup_proxy_inside_guest
verify_intel_tiber_trust_service
attest_intel_tiber_trust_service
