#!/bin/bash

################################################################################
# Hetzner DynDNS - Configuration examples
#
# This script shows various configuration options for the dyndns.sh script.
#
# Use it as a template for your own configuration.
################################################################################

# ============================================================================
# EXAMPLE 1: Minimal configuration (required parameters only)
# ============================================================================

example_minimal() {
    local api_token="your-hetzner-api-token-here"
    local zone_name="example.com"
    local record_name="dyn"
    
    # Simple call using environment variables
    HETZNER_AUTH_API_TOKEN="$api_token" \
        /usr/local/bin/dyndns.sh -Z "$zone_name" -n "$record_name"
}

# ============================================================================
# EXAMPLE 2: IPv6 support (AAAA record)
# ============================================================================

example_ipv6() {
    local api_token="your-hetzner-api-token-here"
    local zone_name="example.com"
    local record_name="dyn6"
    
    HETZNER_AUTH_API_TOKEN="$api_token" \
        /usr/local/bin/dyndns.sh -Z "$zone_name" -n "$record_name" -T AAAA
}

# ============================================================================
# EXAMPLE 3: Custom TTL (Time To Live)
# ============================================================================

example_custom_ttl() {
    local api_token="your-hetzner-api-token-here"
    local zone_name="example.com"
    local record_name="dyn"
    local ttl="300"  # 5 minutes
    
    HETZNER_AUTH_API_TOKEN="$api_token" \
        /usr/local/bin/dyndns.sh -Z "$zone_name" -n "$record_name" -t "$ttl"
}

# ============================================================================
# EXAMPLE 4: Zone ID instead of zone name (faster, no lookup required)
# ============================================================================

example_zone_id() {
    local api_token="your-hetzner-api-token-here"
    local zone_id="98jFjsd8dh1GHasdf7a8hJG7"  # Zone ID
    local record_name="dyn"
    
    HETZNER_AUTH_API_TOKEN="$api_token" \
        /usr/local/bin/dyndns.sh -z "$zone_id" -n "$record_name"
}

# ============================================================================
# EXAMPLE 5: Configuration via environment variables
# ============================================================================

example_env_vars() {
    export HETZNER_AUTH_API_TOKEN="your-hetzner-api-token-here"
    export HETZNER_ZONE_NAME="example.com"
    export HETZNER_RECORD_NAME="dyn"
    export HETZNER_RECORD_TYPE="A"
    export HETZNER_RECORD_TTL="120"
    
    # Script runs with all settings from environment variables
    /usr/local/bin/dyndns.sh
}

# ============================================================================
# EXAMPLE 6: Load configuration from file
# ============================================================================

example_config_file() {
    local config_file="$HOME/.hetzner-dyndns.conf"
    
    # Load the configuration
    if [[ -f "$config_file" ]]; then
        # IMPORTANT: Secure file permissions!
        # chmod 600 ~/.hetzner-dyndns.conf
        set -a  # Export all variables
        source "$config_file"
        set +a
        
        /usr/local/bin/dyndns.sh
    else
        echo "Config file not found: $config_file"
        return 1
    fi
}

# ============================================================================
# EXAMPLE 7: Verbose debugging
# ============================================================================

example_verbose() {
    local api_token="your-hetzner-api-token-here"
    local zone_name="example.com"
    local record_name="dyn"
    
    HETZNER_AUTH_API_TOKEN="$api_token" \
        /usr/local/bin/dyndns.sh -Z "$zone_name" -n "$record_name" -v
}

# ============================================================================
# EXAMPLE 8: Multiple records (IPv4 and IPv6)
# ============================================================================

example_multiple_records() {
    local api_token="your-hetzner-api-token-here"
    local zone_name="example.com"
    
    # IPv4 record
    HETZNER_AUTH_API_TOKEN="$api_token" \
        /usr/local/bin/dyndns.sh -Z "$zone_name" -n "dyn" -T A
    
    # IPv6 record (with delay)
    sleep 2
    
    HETZNER_AUTH_API_TOKEN="$api_token" \
        /usr/local/bin/dyndns.sh -Z "$zone_name" -n "dyn" -T AAAA
}

# ============================================================================
# EXAMPLE 9: With error handling and logging
# ============================================================================

example_with_error_handling() {
    local api_token="your-hetzner-api-token-here"
    local zone_name="example.com"
    local record_name="dyn"
    local log_file="/var/log/dyndns.log"
    
    {
        echo "=== DynDNS update starting: $(date) ==="
        
        if HETZNER_AUTH_API_TOKEN="$api_token" \
           /usr/local/bin/dyndns.sh -Z "$zone_name" -n "$record_name"; then
            echo "✓ DynDNS update successful: $(date)"
        else
            echo "✗ DynDNS update failed: $(date)"
            exit 1
        fi
    } | tee -a "$log_file"
}

# ============================================================================
# EXAMPLE 10: Cron integration with logger
# ============================================================================

example_cron_setup() {
    cat << 'EOF'
# Add these lines to your crontab (crontab -e):

# Update IPv4 record every 5 minutes
*/5 * * * * HETZNER_AUTH_API_TOKEN='your-api-token' /usr/local/bin/dyndns.sh -Z example.com -n dyn -T A >> /var/log/dyndns.log 2>&1

# Update IPv6 record every 5 minutes
*/5 * * * * HETZNER_AUTH_API_TOKEN='your-api-token' /usr/local/bin/dyndns.sh -Z example.com -n dyn -T AAAA >> /var/log/dyndns.log 2>&1

# Use a separate cron entry per zone
*/5 * * * * HETZNER_AUTH_API_TOKEN='token1' /usr/local/bin/dyndns.sh -Z zone1.com -n dyn >> /var/log/dyndns-z1.log 2>&1
*/5 * * * * HETZNER_AUTH_API_TOKEN='token2' /usr/local/bin/dyndns.sh -Z zone2.com -n dyn >> /var/log/dyndns-z2.log 2>&1
EOF
}

# ============================================================================
# SETUP HELPER FUNCTIONS
# ============================================================================

# Get zone ID
list_zones() {
    local api_token="$1"
    
    if [[ -z "$api_token" ]]; then
        echo "Error: API token required"
        echo "Usage: list_zones 'your-api-token'"
        return 1
    fi
    
    echo "=== Available Zones ==="
    curl -s "https://api.hetzner.cloud/v1/zones" \
        -H "Authorization: Bearer $api_token" | jq '.zones[] | {id, name}'
}

# Show zone records
list_zone_records() {
    local api_token="$1"
    local zone_id="$2"
    
    if [[ -z "$api_token" ]] || [[ -z "$zone_id" ]]; then
        echo "Error: API token and zone ID required"
        echo "Usage: list_zone_records 'token' 'zone-id'"
        return 1
    fi
    
    echo "=== Records for zone $zone_id ==="
    curl -s "https://api.hetzner.cloud/v1/zones/$zone_id/rrsets" \
        -H "Authorization: Bearer $api_token" | jq '.rrsets[] | {name, type, ttl, records}'
}

# ============================================================================
# CONFIG FILE TEMPLATE
# ============================================================================

create_config_template() {
    cat > "$HOME/.hetzner-dyndns.conf" << 'EOF'
# Hetzner DynDNS - Configuration file
#
# Location: ~/.hetzner-dyndns.conf
# Permissions: chmod 600 ~/.hetzner-dyndns.conf
#
# Note: This file is loaded via "source", so all bash variables are supported.

# API token (required)
# Get it from: https://console.hetzner.com/
HETZNER_AUTH_API_TOKEN="your-api-token-here"

# Zone name or zone ID (required, use ONE of the two)
HETZNER_ZONE_NAME="example.com"
# HETZNER_ZONE_ID="98jFjsd8dh1GHasdf7a8hJG7"

# Record name (required)
# Use "@" for the zone apex (e.g. example.com)
# Use "dyn" for dyn.example.com
HETZNER_RECORD_NAME="dyn"

# Record type (optional, default: A)
# A = IPv4
# AAAA = IPv6
HETZNER_RECORD_TYPE="A"

# TTL in seconds (optional, default: 60)
# Recommended for DynDNS: 60-300 seconds
HETZNER_RECORD_TTL="120"

# Verbose mode (optional, default: false)
# Set to "true" to see debug output
HETZNER_VERBOSE="false"
EOF
    
    chmod 600 "$HOME/.hetzner-dyndns.conf"
    echo "✓ Config file created: $HOME/.hetzner-dyndns.conf"
    echo "  Edit the file with your settings:"
    echo "  nano $HOME/.hetzner-dyndns.conf"
}

# ============================================================================
# SYSTEMD TIMER TEMPLATE
# ============================================================================

create_systemd_timer() {
    local service_name="dyndns"
    local timer_file="/etc/systemd/system/${service_name}.timer"
    local service_file="/etc/systemd/system/${service_name}.service"
    
    echo "=== Systemd Timer Configuration ==="
    echo ""
    echo "Service file: $service_file"
    echo "Timer file: $timer_file"
    echo ""
    echo "Service ($service_file):"
    cat << 'EOF'
[Unit]
Description=Hetzner DNS DynDNS Update
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=%h/.hetzner-dyndns.conf
ExecStart=/usr/local/bin/dyndns.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=dyndns
EOF
    
    echo ""
    echo "Timer ($timer_file):"
    cat << 'EOF'
[Unit]
Description=Hetzner DNS DynDNS Update Timer
Requires=dyndns.service

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
AccuracySec=1sec
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    echo ""
    echo "Activation:"
    echo "  sudo systemctl daemon-reload"
    echo "  sudo systemctl enable --now dyndns.timer"
    echo "  sudo systemctl status dyndns.timer"
    echo ""
}

# ============================================================================
# INTERACTIVE SETUP
# ============================================================================

interactive_setup() {
    clear
    
    echo "╔════════════════════════════════════════╗"
    echo "║   Hetzner DynDNS - Interactive Setup   ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    read -p "Enter API token: " api_token
    
    if [[ -z "$api_token" ]]; then
        echo "✗ API token required"
        return 1
    fi
    
    echo ""
    echo "=== Available Zones ==="
    list_zones "$api_token" || return 1
    
    echo ""
    read -p "Enter zone name (e.g. example.com): " zone_name
    
    # Determine zone ID
    local zone_id
    zone_id=$(curl -s "https://api.hetzner.cloud/v1/zones?name=$zone_name" \
        -H "Authorization: Bearer $api_token" | jq -r '.zones[0].id')
    
    if [[ -z "$zone_id" ]] || [[ "$zone_id" == "null" ]]; then
        echo "✗ Zone not found"
        return 1
    fi
    
    echo "✓ Zone ID: $zone_id"
    echo ""
    
    echo "=== Zone records ==="
    list_zone_records "$api_token" "$zone_id" || return 1
    
    echo ""
    read -p "Enter record name (e.g. dyn): " record_name
    
    read -p "Enter record type (A/AAAA) [default: A]: " record_type
    record_type="${record_type:-A}"
    
    read -p "Enter TTL [default: 60]: " record_ttl
    record_ttl="${record_ttl:-60}"
    
    echo ""
    echo "=== Summary ==="
    echo "Zone: $zone_name ($zone_id)"
    echo "Record: $record_name ($record_type)"
    echo "TTL: $record_ttl"
    echo ""
    
    read -p "Save this configuration? (y/n): " save_config
    
    if [[ "$save_config" == "y" ]]; then
        cat > "$HOME/.hetzner-dyndns.conf" << EOF
HETZNER_AUTH_API_TOKEN="$api_token"
HETZNER_ZONE_NAME="$zone_name"
HETZNER_RECORD_NAME="$record_name"
HETZNER_RECORD_TYPE="$record_type"
HETZNER_RECORD_TTL="$record_ttl"
EOF
        
        chmod 600 "$HOME/.hetzner-dyndns.conf"
        echo "✓ Config file created: ~/.hetzner-dyndns.conf"
    fi
    
    echo ""
    read -p "Run test update? (y/n): " test_update
    
    if [[ "$test_update" == "y" ]]; then
        source "$HOME/.hetzner-dyndns.conf"
        /usr/local/bin/dyndns.sh -v
    fi
}

# ============================================================================
# MAIN MENU
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-menu}" in
        example1)
            example_minimal
            ;;
        example2)
            example_ipv6
            ;;
        example3)
            example_custom_ttl
            ;;
        example4)
            example_zone_id
            ;;
        example5)
            example_env_vars
            ;;
        example6)
            example_config_file
            ;;
        example7)
            example_verbose
            ;;
        example8)
            example_multiple_records
            ;;
        example9)
            example_with_error_handling
            ;;
        example10)
            example_cron_setup
            ;;
        list-zones)
            list_zones "${2:-}"
            ;;
        list-records)
            list_zone_records "${2:-}" "${3:-}"
            ;;
        create-config)
            create_config_template
            ;;
        systemd)
            create_systemd_timer
            ;;
        setup)
            interactive_setup
            ;;
        *)
            cat << 'EOF'
Hetzner DynDNS - Configuration examples

Available examples:
  ./config-examples.sh example1      - Minimal configuration
  ./config-examples.sh example2      - IPv6 support
  ./config-examples.sh example3      - Custom TTL
  ./config-examples.sh example4      - Use zone ID
  ./config-examples.sh example5      - Environment variables
  ./config-examples.sh example6      - Config file
  ./config-examples.sh example7      - Verbose debugging
  ./config-examples.sh example8      - Multiple records
  ./config-examples.sh example9      - With error handling
  ./config-examples.sh example10     - Cron setup

Helper functions:
  ./config-examples.sh list-zones <token>              - List zones
  ./config-examples.sh list-records <token> <zone-id>  - List records
  ./config-examples.sh create-config                   - Create config file
  ./config-examples.sh systemd                         - Show systemd timer
  ./config-examples.sh setup                           - Interactive setup

EOF
            ;;
    esac
fi
