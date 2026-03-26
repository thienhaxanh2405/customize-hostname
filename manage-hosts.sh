#!/bin/bash

###############################################################################
# Hostname Manager Script for macOS
# Manages /etc/hosts entries through an interactive menu interface
# Author: thienhaxanh2405
###############################################################################

set -euo pipefail

# Block markers for customize section
BLOCK_START="#### Customize Hostname by thienhaxanh2405 ####"
BLOCK_END="#### End Customize Hostname by thienhaxanh2405 ####"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

###############################################################################
# Utility Functions
###############################################################################

# Print colored messages
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

# Display banner
show_banner() {
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║        Hostname Manager for macOS /etc/hosts              ║"
    echo "║                  by thienhaxanh2405                        ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
}

###############################################################################
# Validation Functions
###############################################################################

# Validate IPv4 address format
validate_ip() {
    local ip=$1
    local valid_ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

    if [[ ! $ip =~ $valid_ip_regex ]]; then
        return 1
    fi

    # Check each octet is 0-255
    IFS='.' read -ra OCTETS <<< "$ip"
    for octet in "${OCTETS[@]}"; do
        if ((octet < 0 || octet > 255)); then
            return 1
        fi
    done

    return 0
}

# Validate hostname according to RFC 1123
validate_hostname() {
    local hostname=$1

    # Length check (1-253 characters)
    if [[ ${#hostname} -lt 1 || ${#hostname} -gt 253 ]]; then
        return 1
    fi

    # RFC 1123 compliant: alphanumeric, dots, hyphens
    # No leading/trailing hyphens or dots
    local valid_hostname_regex='^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$'

    if [[ ! $hostname =~ $valid_hostname_regex ]]; then
        return 1
    fi

    # Each label (segment between dots) should be max 63 chars
    # and not start/end with hyphen
    IFS='.' read -ra LABELS <<< "$hostname"
    for label in "${LABELS[@]}"; do
        if [[ ${#label} -gt 63 ]]; then
            return 1
        fi
        if [[ $label =~ ^- || $label =~ -$ ]]; then
            return 1
        fi
    done

    return 0
}

# Check if hostname is reserved
is_reserved_name() {
    local hostname=$1
    local reserved=("localhost" "broadcasthost" "localhost.localdomain")

    for reserved_name in "${reserved[@]}"; do
        if [[ "${hostname,,}" == "${reserved_name,,}" ]]; then
            return 0
        fi
    done

    return 1
}

###############################################################################
# File Operations
###############################################################################

# Create timestamped backup of /etc/hosts
backup_hosts() {
    local timestamp=$(date +"%Y%m%d-%H%M%S")
    local backup_file="/etc/hosts.backup.$timestamp"

    if cp /etc/hosts "$backup_file" 2>/dev/null; then
        print_success "Backup created: $backup_file"
        return 0
    else
        print_error "Failed to create backup"
        return 1
    fi
}

# Flush DNS cache on macOS
flush_dns() {
    print_info "Flushing DNS cache..."
    if sudo dscacheutil -flushcache 2>/dev/null && \
       sudo killall -HUP mDNSResponder 2>/dev/null; then
        print_success "DNS cache flushed"
    else
        print_warning "DNS cache flush may have failed (this is usually okay)"
    fi
}

# Read /etc/hosts into array
read_hosts() {
    mapfile -t hosts_content < /etc/hosts
}

# Write hosts content atomically
write_hosts() {
    local temp_file="/tmp/hosts.tmp.$$"

    # Write to temp file
    printf "%s\n" "${hosts_content[@]}" > "$temp_file"

    # Atomic move
    if sudo mv "$temp_file" /etc/hosts 2>/dev/null; then
        print_success "Updated /etc/hosts"
        flush_dns
        return 0
    else
        print_error "Failed to update /etc/hosts"
        rm -f "$temp_file"
        return 1
    fi
}

###############################################################################
# Block Management Functions
###############################################################################

# Find customize block in hosts_content array
# Returns start and end line indices via global variables
find_block() {
    block_start_idx=-1
    block_end_idx=-1

    local idx=0
    for line in "${hosts_content[@]}"; do
        if [[ "$line" == "$BLOCK_START" ]]; then
            block_start_idx=$idx
        elif [[ "$line" == "$BLOCK_END" ]]; then
            block_end_idx=$idx
            return 0
        fi
        ((idx++))
    done

    return 1
}

# Create customize block if it doesn't exist
create_block() {
    local new_content=()

    # Copy existing content
    new_content=("${hosts_content[@]}")

    # Add empty line if file doesn't end with one
    if [[ ${#new_content[@]} -gt 0 && -n "${new_content[-1]}" ]]; then
        new_content+=("")
    fi

    # Add block markers
    new_content+=("$BLOCK_START")
    new_content+=("$BLOCK_END")

    hosts_content=("${new_content[@]}")
    block_start_idx=$((${#hosts_content[@]} - 2))
    block_end_idx=$((${#hosts_content[@]} - 1))
}

# Get entries from customize block
get_block_entries() {
    local -n entries_ref=$1
    entries_ref=()

    if ! find_block; then
        return 1
    fi

    local idx=$((block_start_idx + 1))
    while ((idx < block_end_idx)); do
        local line="${hosts_content[$idx]}"
        # Skip empty lines and comments
        if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
            entries_ref+=("$line")
        fi
        ((idx++))
    done

    return 0
}

# Update block with new entries
update_block() {
    local -n new_entries_ref=$1

    if ! find_block; then
        create_block
        find_block
    fi

    # Build new hosts content
    local new_content=()

    # Copy lines before block
    local idx=0
    while ((idx < block_start_idx)); do
        new_content+=("${hosts_content[$idx]}")
        ((idx++))
    done

    # Add block start marker
    new_content+=("$BLOCK_START")

    # Add entries
    for entry in "${new_entries_ref[@]}"; do
        new_content+=("$entry")
    done

    # Add block end marker
    new_content+=("$BLOCK_END")

    # Copy lines after block
    idx=$((block_end_idx + 1))
    while ((idx < ${#hosts_content[@]})); do
        new_content+=("${hosts_content[$idx]}")
        ((idx++))
    done

    hosts_content=("${new_content[@]}")
}

###############################################################################
# Menu Operation Functions
###############################################################################

# Menu Option 1: Add hostname
menu_add() {
    echo ""
    print_info "=== Add New Hostname ==="
    echo ""

    # Prompt for hostname
    read -p "Enter hostname: " hostname
    hostname=$(echo "$hostname" | xargs)  # Trim whitespace

    if [[ -z "$hostname" ]]; then
        print_error "Hostname cannot be empty"
        return 1
    fi

    # Validate hostname
    if ! validate_hostname "$hostname"; then
        print_error "Invalid hostname format (must be RFC 1123 compliant)"
        return 1
    fi

    # Check if reserved
    if is_reserved_name "$hostname"; then
        print_error "Cannot use reserved hostname: $hostname"
        return 1
    fi

    # Prompt for IP
    read -p "Enter IP address: " ip
    ip=$(echo "$ip" | xargs)  # Trim whitespace

    if [[ -z "$ip" ]]; then
        print_error "IP address cannot be empty"
        return 1
    fi

    # Validate IP
    if ! validate_ip "$ip"; then
        print_error "Invalid IP address format (must be valid IPv4)"
        return 1
    fi

    # Ask for backup confirmation
    echo ""
    read -p "Create backup before adding? (y/n): " backup_choice
    if [[ "${backup_choice,,}" == "y" ]]; then
        if ! backup_hosts; then
            print_error "Backup failed. Aborting."
            return 1
        fi
    fi

    # Read current hosts file
    read_hosts

    # Get current entries
    local entries=()
    get_block_entries entries || true

    # Check for duplicate hostname
    local found=false
    for entry in "${entries[@]}"; do
        local entry_hostname=$(echo "$entry" | awk '{print $2}')
        if [[ "${entry_hostname,,}" == "${hostname,,}" ]]; then
            print_warning "Hostname '$hostname' already exists"
            found=true
            break
        fi
    done

    if [[ "$found" == true ]]; then
        read -p "Overwrite existing entry? (y/n): " overwrite_choice
        if [[ "${overwrite_choice,,}" != "y" ]]; then
            print_info "Add cancelled"
            return 0
        fi

        # Remove old entry
        local new_entries=()
        for entry in "${entries[@]}"; do
            local entry_hostname=$(echo "$entry" | awk '{print $2}')
            if [[ "${entry_hostname,,}" != "${hostname,,}" ]]; then
                new_entries+=("$entry")
            fi
        done
        entries=("${new_entries[@]}")
    fi

    # Add new entry
    entries+=("$ip    $hostname")

    # Update block
    update_block entries

    # Write to file
    if write_hosts; then
        print_success "Added: $hostname -> $ip"
    else
        print_error "Failed to update hosts file"
        return 1
    fi
}

# Menu Option 2: Search hostname
menu_search() {
    echo ""
    print_info "=== Search Hostname ==="
    echo ""

    read -p "Enter hostname to search: " hostname
    hostname=$(echo "$hostname" | xargs)

    if [[ -z "$hostname" ]]; then
        print_error "Hostname cannot be empty"
        return 1
    fi

    # Read current hosts file
    read_hosts

    # Get entries
    local entries=()
    if ! get_block_entries entries; then
        print_warning "No customize block found"
        return 1
    fi

    if [[ ${#entries[@]} -eq 0 ]]; then
        print_warning "No entries found in customize block"
        return 1
    fi

    # Search for hostname
    local found=false
    for entry in "${entries[@]}"; do
        local entry_ip=$(echo "$entry" | awk '{print $1}')
        local entry_hostname=$(echo "$entry" | awk '{print $2}')

        if [[ "${entry_hostname,,}" == "${hostname,,}" ]]; then
            echo ""
            print_success "Found: $entry_hostname -> $entry_ip"
            found=true
            break
        fi
    done

    if [[ "$found" == false ]]; then
        print_warning "Hostname '$hostname' not found"
        return 1
    fi
}

# Menu Option 3: Edit hostname
menu_edit() {
    echo ""
    print_info "=== Edit Hostname ==="
    echo ""

    read -p "Enter hostname to edit: " hostname
    hostname=$(echo "$hostname" | xargs)

    if [[ -z "$hostname" ]]; then
        print_error "Hostname cannot be empty"
        return 1
    fi

    # Read current hosts file
    read_hosts

    # Get entries
    local entries=()
    if ! get_block_entries entries; then
        print_warning "No customize block found"
        return 1
    fi

    # Find hostname
    local found=false
    local old_ip=""
    for entry in "${entries[@]}"; do
        local entry_ip=$(echo "$entry" | awk '{print $1}')
        local entry_hostname=$(echo "$entry" | awk '{print $2}')

        if [[ "${entry_hostname,,}" == "${hostname,,}" ]]; then
            old_ip="$entry_ip"
            found=true
            break
        fi
    done

    if [[ "$found" == false ]]; then
        print_warning "Hostname '$hostname' not found"
        return 1
    fi

    echo ""
    print_info "Current IP: $old_ip"
    read -p "Enter new IP address: " new_ip
    new_ip=$(echo "$new_ip" | xargs)

    if [[ -z "$new_ip" ]]; then
        print_error "IP address cannot be empty"
        return 1
    fi

    # Validate new IP
    if ! validate_ip "$new_ip"; then
        print_error "Invalid IP address format (must be valid IPv4)"
        return 1
    fi

    # Ask for backup confirmation
    echo ""
    read -p "Create backup before editing? (y/n): " backup_choice
    if [[ "${backup_choice,,}" == "y" ]]; then
        if ! backup_hosts; then
            print_error "Backup failed. Aborting."
            return 1
        fi
    fi

    # Update entry
    local new_entries=()
    for entry in "${entries[@]}"; do
        local entry_ip=$(echo "$entry" | awk '{print $1}')
        local entry_hostname=$(echo "$entry" | awk '{print $2}')

        if [[ "${entry_hostname,,}" == "${hostname,,}" ]]; then
            new_entries+=("$new_ip    $entry_hostname")
        else
            new_entries+=("$entry")
        fi
    done

    # Update block
    update_block new_entries

    # Write to file
    if write_hosts; then
        print_success "Updated: $hostname -> $new_ip (was $old_ip)"
    else
        print_error "Failed to update hosts file"
        return 1
    fi
}

# Menu Option 4: Delete hostname
menu_delete() {
    echo ""
    print_info "=== Delete Hostname ==="
    echo ""

    read -p "Enter hostname to delete: " hostname
    hostname=$(echo "$hostname" | xargs)

    if [[ -z "$hostname" ]]; then
        print_error "Hostname cannot be empty"
        return 1
    fi

    # Read current hosts file
    read_hosts

    # Get entries
    local entries=()
    if ! get_block_entries entries; then
        print_warning "No customize block found"
        return 1
    fi

    # Find hostname
    local found=false
    local delete_ip=""
    for entry in "${entries[@]}"; do
        local entry_ip=$(echo "$entry" | awk '{print $1}')
        local entry_hostname=$(echo "$entry" | awk '{print $2}')

        if [[ "${entry_hostname,,}" == "${hostname,,}" ]]; then
            delete_ip="$entry_ip"
            found=true
            break
        fi
    done

    if [[ "$found" == false ]]; then
        print_warning "Hostname '$hostname' not found"
        return 1
    fi

    # Confirm deletion
    echo ""
    print_warning "Will delete: $hostname -> $delete_ip"
    read -p "Are you sure? (y/n): " confirm_choice
    if [[ "${confirm_choice,,}" != "y" ]]; then
        print_info "Deletion cancelled"
        return 0
    fi

    # Ask for backup confirmation
    read -p "Create backup before deleting? (y/n): " backup_choice
    if [[ "${backup_choice,,}" == "y" ]]; then
        if ! backup_hosts; then
            print_error "Backup failed. Aborting."
            return 1
        fi
    fi

    # Remove entry
    local new_entries=()
    for entry in "${entries[@]}"; do
        local entry_hostname=$(echo "$entry" | awk '{print $2}')
        if [[ "${entry_hostname,,}" != "${hostname,,}" ]]; then
            new_entries+=("$entry")
        fi
    done

    # Update block
    update_block new_entries

    # Write to file
    if write_hosts; then
        print_success "Deleted: $hostname (was pointing to $delete_ip)"
    else
        print_error "Failed to update hosts file"
        return 1
    fi
}

# Menu Option 5: Import from CSV
menu_import() {
    echo ""
    print_info "=== Import from CSV ==="
    echo ""

    read -p "Enter CSV file path: " csv_file
    csv_file=$(echo "$csv_file" | xargs)

    if [[ -z "$csv_file" ]]; then
        print_error "File path cannot be empty"
        return 1
    fi

    if [[ ! -f "$csv_file" ]]; then
        print_error "File not found: $csv_file"
        return 1
    fi

    # Read current hosts file
    read_hosts

    # Get current entries
    local entries=()
    get_block_entries entries || true

    # Build hostname lookup for duplicates
    declare -A existing_hostnames
    for entry in "${entries[@]}"; do
        local entry_hostname=$(echo "$entry" | awk '{print $2}')
        existing_hostnames["${entry_hostname,,}"]="$entry"
    done

    # Statistics
    local added=0
    local skipped=0
    local overwritten=0
    local skip_all=false

    # Ask for backup confirmation
    echo ""
    read -p "Create backup before importing? (y/n): " backup_choice
    if [[ "${backup_choice,,}" == "y" ]]; then
        if ! backup_hosts; then
            print_error "Backup failed. Aborting."
            return 1
        fi
    fi

    # Read CSV file (skip header)
    local line_num=0
    while IFS=',' read -r hostname ip; do
        ((line_num++))

        # Skip header row
        if [[ $line_num -eq 1 && "${hostname,,}" == "hostname" ]]; then
            continue
        fi

        # Trim whitespace
        hostname=$(echo "$hostname" | xargs)
        ip=$(echo "$ip" | xargs)

        # Skip empty lines
        if [[ -z "$hostname" || -z "$ip" ]]; then
            continue
        fi

        # Validate hostname
        if ! validate_hostname "$hostname"; then
            print_warning "Line $line_num: Invalid hostname '$hostname' - skipping"
            ((skipped++))
            continue
        fi

        # Check if reserved
        if is_reserved_name "$hostname"; then
            print_warning "Line $line_num: Reserved hostname '$hostname' - skipping"
            ((skipped++))
            continue
        fi

        # Validate IP
        if ! validate_ip "$ip"; then
            print_warning "Line $line_num: Invalid IP '$ip' for hostname '$hostname' - skipping"
            ((skipped++))
            continue
        fi

        # Check for duplicate
        if [[ -n "${existing_hostnames[${hostname,,}]}" ]]; then
            if [[ "$skip_all" == true ]]; then
                print_info "Skipping duplicate: $hostname"
                ((skipped++))
                continue
            fi

            echo ""
            print_warning "Duplicate found: $hostname already exists"
            echo "Current: ${existing_hostnames[${hostname,,}]}"
            echo "New:     $ip    $hostname"
            read -p "Choose action: [O]verwrite / [S]kip / Skip [A]ll remaining? (o/s/a): " dup_choice

            case "${dup_choice,,}" in
                o)
                    # Remove old entry
                    local new_entries=()
                    for entry in "${entries[@]}"; do
                        local entry_hostname=$(echo "$entry" | awk '{print $2}')
                        if [[ "${entry_hostname,,}" != "${hostname,,}" ]]; then
                            new_entries+=("$entry")
                        fi
                    done
                    entries=("${new_entries[@]}")
                    entries+=("$ip    $hostname")
                    existing_hostnames["${hostname,,}"]="$ip    $hostname"
                    ((overwritten++))
                    print_success "Overwritten: $hostname -> $ip"
                    ;;
                s)
                    ((skipped++))
                    print_info "Skipped: $hostname"
                    ;;
                a)
                    skip_all=true
                    ((skipped++))
                    print_info "Skipped: $hostname (and will skip all remaining duplicates)"
                    ;;
                *)
                    ((skipped++))
                    print_info "Invalid choice, skipping: $hostname"
                    ;;
            esac
        else
            # Add new entry
            entries+=("$ip    $hostname")
            existing_hostnames["${hostname,,}"]="$ip    $hostname"
            ((added++))
            print_success "Added: $hostname -> $ip"
        fi
    done < "$csv_file"

    # Update block
    update_block entries

    # Write to file
    if write_hosts; then
        echo ""
        print_success "Import complete!"
        echo "  Added: $added"
        echo "  Overwritten: $overwritten"
        echo "  Skipped: $skipped"
    else
        print_error "Failed to update hosts file"
        return 1
    fi
}

# Menu Option 6: Clear all customize entries
menu_clear() {
    echo ""
    print_warning "=== Clear All Customize Entries ==="
    echo ""

    # Read current hosts file
    read_hosts

    # Get entries to show count
    local entries=()
    if ! get_block_entries entries; then
        print_warning "No customize block found"
        return 1
    fi

    if [[ ${#entries[@]} -eq 0 ]]; then
        print_warning "No entries to clear"
        return 0
    fi

    echo "Current entries (${#entries[@]} total):"
    for entry in "${entries[@]}"; do
        echo "  $entry"
    done

    echo ""
    print_warning "This will remove ALL ${#entries[@]} entries from the customize block!"
    read -p "Are you sure? (y/n): " confirm_choice
    if [[ "${confirm_choice,,}" != "y" ]]; then
        print_info "Clear cancelled"
        return 0
    fi

    # Ask for backup confirmation
    echo ""
    read -p "Create backup before clearing? (y/n): " backup_choice
    if [[ "${backup_choice,,}" == "y" ]]; then
        if ! backup_hosts; then
            print_error "Backup failed. Aborting."
            return 1
        fi
    fi

    # Clear entries (empty array)
    local empty_entries=()
    update_block empty_entries

    # Write to file
    if write_hosts; then
        print_success "Cleared all ${#entries[@]} entries from customize block"
    else
        print_error "Failed to update hosts file"
        return 1
    fi
}

###############################################################################
# Main Menu
###############################################################################

# Display main menu
show_menu() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                      Main Menu                             ║"
    echo "╠════════════════════════════════════════════════════════════╣"
    echo "║  1. Add hostname                                           ║"
    echo "║  2. Search hostname                                        ║"
    echo "║  3. Edit hostname                                          ║"
    echo "║  4. Delete hostname                                        ║"
    echo "║  5. Import from CSV                                        ║"
    echo "║  6. Clear all customize entries                            ║"
    echo "║  7. Exit                                                   ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
}

# Check for root/sudo privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run with sudo or as root"
        echo "Usage: sudo $0"
        exit 1
    fi
}

# Main function
main() {
    check_root
    show_banner

    while true; do
        show_menu
        read -p "Select option (1-7): " choice

        case $choice in
            1)
                menu_add || true
                ;;
            2)
                menu_search || true
                ;;
            3)
                menu_edit || true
                ;;
            4)
                menu_delete || true
                ;;
            5)
                menu_import || true
                ;;
            6)
                menu_clear || true
                ;;
            7)
                echo ""
                print_success "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid option. Please select 1-7."
                ;;
        esac

        # Pause before showing menu again
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Run main function
main
