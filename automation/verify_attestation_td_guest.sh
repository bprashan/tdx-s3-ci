#!/bin/bash
CUR_DIR=$(pwd)
TD_QUOTE_TEXT="Successfully get the TD Quote"
TD_REPORT_TEXT="Wrote TD Report to report.dat"
TRUST_SERVICE_PATH=/usr/share/doc/libtdx-attest-dev/examples/
TDX_DIR="$CUR_DIR"/tdx_verifier
ATTESTATION_DIR="$TDX_DIR"/attestation

setup_trust_service(){
        echo "Installing attestation packages on TD guest and verifying it ..."
        cd $ATTESTATION_DIR
        sudo ./setup-attestation-guest.sh
        trustauthority-cli version
        if ! [[ $? == 0 ]]; then
                echo "ERROR: trustauthority service is not installed"
                exit 1
        fi
}

verify_trust_service(){
        echo "Checking whether Intel Tiber Trust Services is running ..."
        cd $TRUST_SERVICE_PATH
        var=$(./test_tdx_attest)
        echo "$var"
        if [[ ("$var" =~ "$TD_QUOTE_TEXT") && ("$var" =~ "$TD_REPORT_TEXT") ]]; then
                echo "Intel Tiber Trust Services running"
        else
                echo "ERROR: Intel Tiber Trust Services not running"
                exit 1
        fi
}

attest_trust_service(){
        echo "Verify attest with Intel Tiber Trust Service ..."
        cd $CUR_DIR
        trustauthority-cli token -c config.json
        if ! [[ $? == 0 ]]; then
                echo "ERROR: Attestation with Intel Tiber Trust Service got failed!"
                exit 1
        else
                echo "Attestation with Intel Tiber Trust Service is successful!"
        fi
}

setup_trust_service
verify_trust_service
attest_trust_service
