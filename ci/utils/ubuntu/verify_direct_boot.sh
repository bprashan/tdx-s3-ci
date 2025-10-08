#!/bin/bash
#
# TDX Direct Boot Automation Script
# Based on Canonical TDX direct-boot tools
# Repository: https://github.com/canonical/tdx/tree/3.3/guest-tools/direct-boot
#

# Function to check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."
    
    # Check if required directories exist
    for dir in "$GUEST_IMG_DIR" "$DIRECT_BOOT_DIR"; do
        if [[ ! -d "$dir" ]]; then
            echo "Required directory not found: $dir"
            return 1
        fi
    done
    
    # Check if create-td-uki.sh script exists
    if [[ ! -f "$GUEST_IMG_DIR/create-td-uki.sh" ]]; then
        echo "create-td-uki.sh script not found in $GUEST_IMG_DIR"
        return 1
    fi
    
    # Check if boot scripts exist
    for script in "boot_direct.sh" "boot_uki.sh"; do
        if [[ ! -f "$DIRECT_BOOT_DIR/$script" ]]; then
            echo "$script not found in $DIRECT_BOOT_DIR"
            return 1
        fi
    done
    
    # Check for SSH tools
    local missing_tools=()
    
    if ! command -v sshpass >/dev/null 2>&1; then
        missing_tools+=("sshpass")
    fi
    
    if ! command -v expect >/dev/null 2>&1; then
        missing_tools+=("expect")
    fi
    
    if ! command -v nc >/dev/null 2>&1; then
        missing_tools+=("netcat")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo "Warning: Missing SSH verification tools: ${missing_tools[*]}"
        echo "Please install them for automated SSH verification:"
        echo "  Ubuntu/Debian: sudo apt-get install sshpass expect netcat-openbsd"
        echo "  RHEL/CentOS: sudo yum install sshpass expect nc"
        echo ""
        echo "SSH verification will be skipped if these tools are not available."
    fi
    
    echo "All prerequisites met"
    return 0
}

# Function 1: Kernel, initrd and UKI creation
create_kernel_initrd_uki() {
    echo "=========================================="
    echo "Creating Kernel, initrd and UKI files"
    echo "=========================================="
    
    local ubuntu_version="${1:-$UBUNTU_VERSION}"
    local guest_image="tdx-guest-ubuntu-${ubuntu_version}-generic.qcow2"
    
    echo "Ubuntu version: $ubuntu_version"
    echo "Guest image: $guest_image"
    
    # Check if guest image exists
    if [[ ! -f "$QCOW2_IMG" ]]; then
        echo "Guest image not found: $QCOW2_IMG"
        echo "Please create the TD guest image first using:"
        echo "cd $GUEST_IMG_DIR && ./create-td-image.sh"
        return 1
    fi
    
    # Change to image directory
    cd "$GUEST_IMG_DIR" || {
        echo "Failed to change to image directory: $IMAGE_DIR"
        return 1
    }
    
    echo "Executing create-td-uki.sh script..."
    echo "Command: ./create-td-uki.sh $guest_image"
    
    # Execute the UKI creation script
    if ./create-td-uki.sh "$guest_image"; then
        echo "UKI creation completed successfully"
        
        # Verify generated files
        local files_created=()
        local expected_files=(
            "vmlinuz-${ubuntu_version}"
            "initrd.img-${ubuntu_version}"
            "uki.efi-${ubuntu_version}"
        )
        
        echo "Verifying generated files..."
        for file in "${expected_files[@]}"; do
            if [[ -f "$file" ]]; then
                files_created+=("$file")
                local file_size=$(du -h "$file" | cut -f1)
                echo "✓ $file (Size: $file_size)"
            else
                echo "✗ $file (not found)"
            fi
        done
        
        if [[ ${#files_created[@]} -eq ${#expected_files[@]} ]]; then
            echo "All required files created successfully:"
            echo "  • vmlinuz-${ubuntu_version} : the kernel of the guest image"
            echo "  • initrd.img-${ubuntu_version} : the initrd of the guest image"
            echo "  • uki.efi-${ubuntu_version} : the Unified Kernel Image"
            return 0
        else
            echo "Some files may be missing. Please check the output above."
            return 1
        fi
    else
        echo "Failed to create UKI files"
        return 1
    fi
}

# Function to update QEMU command in boot_direct.sh
update_qemu_command() {
    local boot_script="$DIRECT_BOOT_DIR/boot_direct.sh"
    
    echo "Updating QEMU command in boot_direct.sh..."
    
    # Check if boot_direct.sh exists
    if [[ ! -f "$boot_script" ]]; then
        echo "Error: boot_direct.sh not found at $boot_script"
        return 1
    fi
    
    # Create backup of original script
    cp "$boot_script" "$boot_script.backup"
    
    # Update QEMU command with network and daemonize options
    # Remove any existing serial stdio line that conflicts with daemonize
    sed -i '/serial stdio/d' "$boot_script"
    
    # Add network options before the pidfile line
    sed -i '/pidfile \/tmp\/tdx-demo-td-pid\.pid/i \		   -netdev user,id=net0,hostfwd=tcp::2222-:22 \\' "$boot_script"
    sed -i '/pidfile \/tmp\/tdx-demo-td-pid\.pid/i \		   -device virtio-net-pci,netdev=net0 \\' "$boot_script"
    
    # Add daemonize option after the pidfile line
    sed -i '/pidfile \/tmp\/tdx-demo-td-pid\.pid/i \		   -daemonize \\' "$boot_script"
    
    echo "✓ QEMU command updated with network and daemonize options"
    echo "  Added: -netdev user,id=net0,hostfwd=tcp::2222-:22"
    echo "  Added: -device virtio-net-pci,netdev=net0"
    echo "  Added: -daemonize"
    echo "  Removed: -serial stdio (conflicts with daemonize)"
    return 0
}

# Function 2: Direct boot
direct_boot() {
    echo "=========================================="
    echo "Starting TDX Direct Boot"
    echo "=========================================="
    
    local ubuntu_version="${1:-$UBUNTU_VERSION}"
    
    echo "Ubuntu version: $ubuntu_version"
    
    # Check if required files exist
    local required_files=(
        "$GUEST_IMG_DIR/vmlinuz-${ubuntu_version}"
        "$GUEST_IMG_DIR/initrd.img-${ubuntu_version}"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            echo "Required file not found: $file"
            echo "Please run create_kernel_initrd_uki function first"
            return 1
        fi
    done
    
    # Change to direct-boot directory
    cd "$DIRECT_BOOT_DIR" || {
        echo "Failed to change to direct-boot directory: $DIRECT_BOOT_DIR"
        return 1
    }
    
    # Update QEMU command in boot_direct.sh
    if ! update_qemu_command; then
        echo "Failed to update QEMU command"
        return 1
    fi
    
    echo "Executing direct boot script..."
    echo "Command: ./boot_direct.sh $ubuntu_version"
    echo ""
    echo "Boot process will start with enhanced networking:"
    echo "  • SSH access via localhost:2222"
    echo "  • Running in daemon mode"
    echo "  • Run 'tdeventlog' to see the event log journal"
    echo "  • Verify TDX functionality"
    echo "  • Check RTMR values"
    echo ""
    echo "Press Ctrl+C to interrupt if needed"
    
    # Execute the direct boot script
    if ./boot_direct.sh "$ubuntu_version"; then
        echo "✓ Direct boot completed successfully"
        
        # Wait a moment for the system to fully boot
        echo "Waiting for system to fully initialize..."
        sleep 30
        
        # Verify TDX event log via SSH
        if verify_tdx_eventlog "2222" "Direct Boot"; then
            echo "✓ TDX verification completed successfully for Direct Boot"
            
            # Cleanup QEMU process after successful verification
            cleanup_qemu_process "/tmp/tdx-demo-td-pid.pid" "Direct Boot"
            
            return 0
        else
            echo "✗ TDX verification failed for Direct Boot"
            
            # Cleanup QEMU process even on verification failure
            cleanup_qemu_process "/tmp/tdx-demo-td-pid.pid" "Direct Boot"
            
            return 1
        fi
    else
        echo "✗ Direct boot failed"
        
        # Cleanup any residual QEMU process
        cleanup_qemu_process "/tmp/tdx-demo-td-pid.pid" "Direct Boot"
        
        return 1
    fi
}

# Function to update QEMU command in boot_uki.sh
update_qemu_command_uki() {
    local boot_script="$DIRECT_BOOT_DIR/boot_uki.sh"
    
    echo "Updating QEMU command in boot_uki.sh..."
    
    # Check if boot_uki.sh exists
    if [[ ! -f "$boot_script" ]]; then
        echo "Error: boot_uki.sh not found at $boot_script"
        return 1
    fi
    
    # Create backup of original script
    cp "$boot_script" "$boot_script.backup"
    
    # Update QEMU command with network and daemonize options (UKI version)
    # Note: UKI uses -bios instead of -kernel/-initrd
    # Remove any existing serial stdio line that conflicts with daemonize
    sed -i '/serial stdio/d' "$boot_script"
    
    # Add network options before the pidfile line (using port 2223 for UKI)
    sed -i '/pidfile \/tmp\/tdx-demo-td-pid\.pid/i \		   -netdev user,id=net0,hostfwd=tcp::2223-:22 \\' "$boot_script"
    sed -i '/pidfile \/tmp\/tdx-demo-td-pid\.pid/i \		   -device virtio-net-pci,netdev=net0 \\' "$boot_script"
    
    # Add daemonize option after the pidfile line
    sed -i '/pidfile \/tmp\/tdx-demo-td-pid\.pid/i \		   -daemonize \\' "$boot_script"
    
    echo "✓ QEMU UKI command updated with network and daemonize options"
    echo "  Added: -netdev user,id=net0,hostfwd=tcp::2223-:22"
    echo "  Added: -device virtio-net-pci,netdev=net0"
    echo "  Added: -daemonize"
    echo "  Note: Using port 2223 for UKI to avoid conflict with direct boot"
    return 0
}

# Function 3: Direct boot with UKI
direct_boot_uki() {
    echo "=========================================="
    echo "Starting TDX Direct Boot with UKI"
    echo "=========================================="
    
    local ubuntu_version="${1:-$UBUNTU_VERSION}"
    
    echo "Ubuntu version: $ubuntu_version"
    
    # Check if UKI file exists
    local uki_file="$GUEST_IMG_DIR/uki.efi-${ubuntu_version}"
    if [[ ! -f "$uki_file" ]]; then
        echo "UKI file not found: $uki_file"
        echo "Please run create_kernel_initrd_uki function first"
        return 1
    fi
    
    # Change to direct-boot directory
    cd "$DIRECT_BOOT_DIR" || {
        echo "Failed to change to direct-boot directory: $DIRECT_BOOT_DIR"
        return 1
    }
    
    # Update QEMU command in boot_uki.sh
    if ! update_qemu_command_uki; then
        echo "Failed to update QEMU UKI command"
        return 1
    fi
    
    echo "Executing UKI boot script..."
    echo "Command: ./boot_uki.sh $ubuntu_version"
    echo ""
    echo "UKI boot process will start with enhanced networking:"
    echo "  • SSH access via localhost:2223"
    echo "  • Running in daemon mode"
    echo "  • Better UEFI Secure Boot support"
    echo "  • Better TPM measurements support"
    echo "  • Enhanced confidential computing"
    echo "  • More robust boot process"
    echo ""
    echo "Once in guest console, you can:"
    echo "  • Run 'tdeventlog' to see the event log journal"
    echo "  • Verify TDX functionality with enhanced security"
    echo ""
    echo "Press Ctrl+C to interrupt if needed"
    
    # Execute the UKI boot script
    if ./boot_uki.sh "$ubuntu_version"; then
        echo "✓ UKI direct boot completed successfully"
        
        # Wait a moment for the system to fully boot
        echo "Waiting for system to fully initialize..."
        sleep 15
        
        # Verify TDX event log via SSH
        if verify_tdx_eventlog "2223" "UKI Boot"; then
            echo "✓ TDX verification completed successfully for UKI Boot"
            
            # Cleanup QEMU process after successful verification
            cleanup_qemu_process "/tmp/tdx-demo-td-pid.pid" "UKI Boot"
            
            return 0
        else
            echo "✗ TDX verification failed for UKI Boot"
            
            # Cleanup QEMU process even on verification failure
            cleanup_qemu_process "/tmp/tdx-demo-td-pid.pid" "UKI Boot"
            
            return 1
        fi
    else
        echo "✗ UKI direct boot failed"
        
        # Cleanup any residual QEMU process
        cleanup_qemu_process "/tmp/tdx-demo-td-pid.pid" "UKI Boot"
        
        return 1
    fi
}

# Function to cleanup QEMU processes
cleanup_qemu_process() {
    local pidfile="$1"
    local process_name="$2"
    
    echo "Cleaning up QEMU process for $process_name..."
    
    if [[ -f "$pidfile" ]]; then
        local qemu_pid=$(cat "$pidfile")
        if [[ -n "$qemu_pid" ]] && ps -p "$qemu_pid" > /dev/null 2>&1; then
            echo "  Terminating QEMU process (PID: $qemu_pid)"
            kill "$qemu_pid" 2>/dev/null
            
            # Wait for graceful shutdown
            local timeout=10
            while [[ $timeout -gt 0 ]] && ps -p "$qemu_pid" > /dev/null 2>&1; do
                echo "  Waiting for graceful shutdown... ($timeout seconds)"
                sleep 1
                ((timeout--))
            done
            
            # Force kill if still running
            if ps -p "$qemu_pid" > /dev/null 2>&1; then
                echo "  Force killing QEMU process"
                kill -9 "$qemu_pid" 2>/dev/null
            fi
            
            echo "  ✓ QEMU process cleaned up successfully"
        else
            echo "  QEMU process not running (PID: $qemu_pid)"
        fi
        
        # Remove PID file
        rm -f "$pidfile"
        echo "  ✓ PID file removed: $pidfile"
    else
        echo "  No PID file found: $pidfile"
    fi
}

# Function to wait for SSH service to be ready
wait_for_ssh() {
    local port="$1"
    local max_attempts=30
    local attempt=1
    
    echo "Waiting for SSH service on port $port..."
    
    while [[ $attempt -le $max_attempts ]]; do
        if nc -z localhost "$port" 2>/dev/null; then
            echo "✓ SSH service is ready on port $port"
            return 0
        fi
        echo "  Attempt $attempt/$max_attempts - SSH not ready yet, waiting 10 seconds..."
        sleep 10
        ((attempt++))
    done
    
    echo "✗ SSH service failed to become ready on port $port after $((max_attempts * 10)) seconds"
    return 1
}

# Function to verify TDX event log via SSH
verify_tdx_eventlog() {
    local port="$1"
    local boot_type="$2"
    local ssh_user="root"
    local ssh_password="123456"
    local ssh_host="localhost"
    
    echo "=========================================="
    echo "Verifying TDX Event Log for $boot_type"
    echo "=========================================="
    
    # Wait for SSH to be ready
    if ! wait_for_ssh "$port"; then
        echo "✗ SSH verification failed - service not available"
        return 1
    fi
    
    echo "Connecting to TDX VM via SSH..."
    echo "SSH Command: ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $port $ssh_user@$ssh_host"
    
    # Use sshpass to automate password input and run tdeventlog
    local eventlog_output
    eventlog_output=$(sshpass -p "$ssh_password" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 -p "$port" "$ssh_user@$ssh_host" "tdeventlog" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        echo "✗ Failed to connect via SSH or execute tdeventlog command"
        echo "  Trying alternative SSH connection method..."
        
        # Alternative method using expect if sshpass fails
        eventlog_output=$(expect -c "
            set timeout 30
            spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $port $ssh_user@$ssh_host
            expect \"password:\"
            send \"$ssh_password\r\"
            expect \"# \"
            send \"tdeventlog\r\"
            expect \"# \"
            send \"exit\r\"
            expect eof
        " 2>/dev/null | grep -A 1000 "TDX Event Log Entry")
        
        if [[ $? -ne 0 ]]; then
            echo "✗ Both SSH connection methods failed"
            return 1
        fi
    fi
    
    echo "✓ Successfully connected and executed tdeventlog"
    echo ""
    
    # Verify the event log contains expected TDX patterns
    verify_eventlog_patterns "$eventlog_output" "$boot_type"
}

# Function to verify event log patterns
verify_eventlog_patterns() {
    local eventlog_output="$1"
    local boot_type="$2"
    
    echo "Analyzing TDX Event Log output..."
    echo "========================================"
    
    # Check for essential TDX event log patterns
    local patterns=(
        "==== TDX Event Log Entry"
        "RTMR"
        "Type"
        "Length"
        "Algorithms"
        "RAW DATA:"
        "==== Replayed RTMR values from event log ===="
        "rtmr_0"
        "rtmr_1"
        "rtmr_2"
        "rtmr_3"
    )
    
    local verification_results=()
    local failed_patterns=()
    
    for pattern in "${patterns[@]}"; do
        if echo "$eventlog_output" | grep -q "$pattern"; then
            verification_results+=("✓ Found: $pattern")
        else
            verification_results+=("✗ Missing: $pattern")
            failed_patterns+=("$pattern")
        fi
    done
    
    # Display verification results
    echo "Pattern Verification Results:"
    echo "----------------------------"
    for result in "${verification_results[@]}"; do
        echo "  $result"
    done
    echo ""
    
    # Check for specific TDX entries
    local entry_count=$(echo "$eventlog_output" | grep -c "==== TDX Event Log Entry")
    echo "TDX Event Log Entries Found: $entry_count"
    
    # Check for RTMR values
    local rtmr_count=$(echo "$eventlog_output" | grep -c "rtmr_[0-3]")
    echo "RTMR Values Found: $rtmr_count"
    
    echo ""
    
    # Final verification
    if [[ ${#failed_patterns[@]} -eq 0 && $entry_count -gt 0 && $rtmr_count -ge 4 ]]; then
        echo "🎉 TDX Event Log Verification PASSED for $boot_type!"
        echo "✓ All required patterns found"
        echo "✓ Event log entries present ($entry_count entries)"
        echo "✓ RTMR values complete ($rtmr_count values)"
        echo ""
        
        # Display sample of the event log
        echo "Sample TDX Event Log Output:"
        echo "============================"
        echo "$eventlog_output" | head -50
        echo ""
        echo "... (output truncated for readability) ..."
        echo ""
        echo "$eventlog_output" | tail -10
        echo ""
        
        return 0
    else
        echo "❌ TDX Event Log Verification FAILED for $boot_type!"
        echo "✗ Missing patterns: ${failed_patterns[*]}"
        echo "✗ Entry count: $entry_count (expected > 0)"
        echo "✗ RTMR count: $rtmr_count (expected >= 4)"
        echo ""
        echo "Full Event Log Output for Debugging:"
        echo "===================================="
        echo "$eventlog_output"
        echo ""
        return 1
    fi
}

# Function to display usage
usage() {
    echo "TDX Direct Boot Automation Script"
    echo ""
    echo "Usage: $0 [COMMAND] [UBUNTU_VERSION]"
    echo ""
    echo "Commands:"
    echo "  create-uki    Create kernel, initrd and UKI files"
    echo "  direct-boot   Perform direct boot with kernel + initrd"
    echo "  uki-boot      Perform direct boot with UKI"
    echo "  all           Run all steps in sequence"
    echo "  cleanup       Cleanup any running QEMU processes"
    echo "  help          Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  UBUNTU_VERSION  Ubuntu version to use (default: 24.04)"
    echo ""
    echo "Examples:"
    echo "  $0 create-uki                    # Create UKI files for Ubuntu 24.04"
    echo "  $0 create-uki 25.04             # Create UKI files for Ubuntu 25.04"
    echo "  $0 direct-boot                  # Direct boot with default version"
    echo "  $0 uki-boot 24.04               # UKI boot with Ubuntu 24.04"
    echo "  $0 all                          # Run complete workflow"
    echo ""
    echo "Prerequisites:"
    echo "  • Canonical TDX repository cloned with guest-tools"
    echo "  • TD guest image created using create-td-image.sh"
    echo "  • QEMU with TDX support installed"
}

# Function to run all steps
rundirectboot() {
    local ubuntu_version="${1:-$UBUNTU_VERSION}"
    
    echo "Running complete TDX Direct Boot workflow"
    echo "Ubuntu version: $ubuntu_version"
    
    # Step 1: Create UKI files
    echo ""
    echo "=========================================="
    echo "Step 1: Creating kernel, initrd and UKI files"
    echo "=========================================="
    if ! create_kernel_initrd_uki "$ubuntu_version"; then
        echo "Failed to create UKI files"
        return 1
    fi
    sleep 10
    
    # Step 2: Run direct boot with kernel + initrd
    echo ""
    echo "=========================================="
    echo "Step 2: Running direct boot (kernel + initrd)"
    echo "=========================================="
    if ! direct_boot "$ubuntu_version"; then
        echo "Direct boot failed"
        return 1
    fi
    
    # Step 3: Run direct boot with UKI
    echo ""
    echo "=========================================="
    echo "Step 3: Running direct boot with UKI"
    echo "=========================================="
    if ! direct_boot_uki "$ubuntu_version"; then
        echo "UKI direct boot failed"
        return 1
    fi
    
    echo ""
    echo "=========================================="
    echo "All TDX Direct Boot tests completed successfully!"
    echo "=========================================="
    echo "Summary:"
    echo "  ✓ Kernel, initrd and UKI files created"
    echo "  ✓ Direct boot with kernel + initrd tested"
    echo "  ✓ Direct boot with UKI tested"
    echo ""
}
