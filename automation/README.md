# Automated scripts to setup and verify TDX

Follow these instructions to setup the Intel TDX host, create a TD, boot the TD, and attest the integrity of the TD's execution environment.

## 1. Supported Hardware
This release supports 4th Generation Intel® Xeon® Scalable Processors with activated Intel® TDX and all 5th Generation Intel® Xeon® Scalable Processors.

## 2. Setup Host OS
Download and install [Ubuntu 24.04](https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso) server on the host machine.

## 3. Install Intel TDX and Remote Attestation in Host OS

### 3.1 Check Hardware Status
For attestation to work, you need Production hardware. The script will internally check if the underlying hardware is production or pre-production, in case of production hardware it will automatically install Intel® SGX Data Center Attestation Primitives (Intel® SGX DCAP) packages.

### 3.2 Pre-requisites
1. Update the proxy settings in `tdx-config`, in case the system is behind proxy.
2. If you are running on a production system and wish to setup remote attestation then you would need a subscription key for the Intel PCS. Add the PCS API key to the `tdx-config` file.
   + If you did not request such a subscription key before, [subscribe](https://api.portal.trustedservices.intel.com/products#product=liv-intel-software-guard-extensions-provisioning-certification-service) to Intel PCS, which requires to log in (or create an account). Two subscription keys are generated (for key rotation) and both can be used for the following step.
   + If you did request such a subscription key before, [retrieve](https://api.portal.trustedservices.intel.com/manage-subscriptions) one of your keys, which requires to log in. You have two subscription keys (for key rotation) and both can be used.
3. Along with the API key you would also need to provide the following:
   + Sha512 hash of the user token for the PCCS client user to register a platform. For example, PCK Cert ID retrieval tool will use the user token to send platform information to PCCS.
   + Sha512 hash of the administrator token for the PCCS administrator to perform a manual refresh of cached artifacts.
4. If you want to perform attestation using Intel Tiber Trust Services then you would need to trustauthority_api_key, which can be obtained by following this [tutorial](https://docs.trustauthority.intel.com/main/articles/tutorial-api-key.html?tabs=attestation-api-key-portal%2Cattestation-sgx-client). This should also be updated to the `tdx-config` file.

### 3.3 Installation
1. Download this repository by cloning the repository (at the appropriate main branch). and execute the setup script.

```
git clone https://github.com/bprashan/tdx-s3-ci.git
cd tdx-s3-ci/automation
./tdx_canonical_setup.sh
```

2. In case the system is behind proxy, then provide the proxy settings
2. Reboot

### 3.4 Enable Intel TDX in the Host's BIOS

1. Go into the host's BIOS.

   NOTE: The following is a sample BIOS configuration. The necessary BIOS settings or the menus might differ based on the platform that is used. Please reach out to your OEM/ODM or independent BIOS vendor for instructions dedicated for your BIOS.

3. Go to Socket Configuration > Processor Configuration > TME, TME-MT, TDX.

  ```
  Set Memory Encryption (TME) to Enabled
  Set Total Memory Encryption Bypass to Enabled (Optional setting for best host OS and regular VM performance.)
  Set Total Memory Encryption Multi-Tenant (TME-MT) to Enabled
  Set TME-MT memory integrity to Disabled
  Set Trust Domain Extension (TDX) to Enabled
  Set TDX Secure Arbitration Mode Loader (SEAM Loader) to Enabled. (NOTE: This allows loading Intel TDX Loader and Intel TDX Module from the ESP or BIOS.)
  Set TME-MT/TDX key split to a non-zero value
  Go to Socket Configuration > Processor Configuration > Software Guard Extension (SGX).
  
  Set SW Guard Extensions (SGX) to Enabled
  ```

3. Save the BIOS settings and boot up.

### 4. Verify Intel TDX and Remote Attestation

1. Execute the verifier script from the host.

   ```
   cd tdx-s3-ci/automation
   ./tdx_canonical_verifier.sh
   ```

2. Towards the end you should see a summary like below of the components installated and tests performed for verification.
