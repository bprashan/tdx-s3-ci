#!/bin/bash
CUR_DIR=$(pwd)
TD_QUOTE_TEXT="Successfully get the TD Quote"
TD_REPORT_TEXT="Wrote TD Report to report.dat"
TRUST_SERVICE_PATH=/usr/share/doc/libtdx-attest-dev/examples/
TDX_DIR="$CUR_DIR"/tdx_verifier
ATTESTATION_DIR="$TDX_DIR"/attestation
source "$CUR_DIR"/tdx-config

setup_intel_tiber_trust_service(){
        echo "Installing attestation packages on TD guest and verifying it ..."
        if ! [[ -z "$http_proxy" || -z "$https_proxy" ]]; then
                echo -e "Acquire::http::proxy \"$http_proxy\";\nAcquire::https::proxy \"$https_proxy\";" > /etc/apt/apt.conf.d/tdx_proxy
                export http_proxy="$http_proxy"
                export https_proxy="$https_proxy"
        fi
        cd $ATTESTATION_DIR
        ./setup-attestation-guest.sh
        trustauthority-cli version
        if ! [[ $? == 0 ]]; then
                echo -e "\nERROR: trustauthority service is not installed"
                exit 1
        fi
}



verify_intel_tiber_trust_service(){
        echo -e "\nChecking whether Intel Tiber Trust Services is running ..."
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

attest_intel_tiber_trust_service(){
        echo -e "\nVerify attest with Intel Tiber Trust Service ..."
        cd $CUR_DIR
        var=$(trustauthority-cli token -c config.json)
        if ! [[ $? == 0 ]]; then
                echo "$var"
                echo -e "\nERROR: Attestation with Intel Tiber Trust Service got failed!"
                exit 1
        else
                echo -e "\nAttestation with Intel Tiber Trust Service is successful!"
        fi
}

setup_intel_tiber_trust_service
verify_intel_tiber_trust_service
attest_intel_tiber_trust_service
