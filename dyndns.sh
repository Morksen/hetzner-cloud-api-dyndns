#!/bin/bash

################################################################################
# Hetzner DNS DynDNS Update Script
# Modern implementation for the current Hetzner DNS API (v1)
#
# Supports both zone name and zone ID and updates DNS records
# automatically only when the IP address changes.
#
# Compatible with all legacy environment variables:
# - HETZNER_AUTH_API_TOKEN
# - HETZNER_ZONE_NAME or HETZNER_ZONE_ID
# - HETZNER_RECORD_NAME
# - HETZNER_RECORD_TTL (default: 60)
# - HETZNER_RECORD_TYPE (default: A)
#
# API documentation: https://docs.hetzner.cloud/reference/cloud#tag/zones
################################################################################

set -o pipefail

# Constants
readonly API_ENDPOINT="https://api.hetzner.cloud/v1"
readonly SCRIPT_NAME="$(basename "$0")"

# Global variables
auth_api_token="${HETZNER_AUTH_API_TOKEN:-}"
zone_id="${HETZNER_ZONE_ID:-}"
zone_name="${HETZNER_ZONE_NAME:-}"
record_id="${HETZNER_RECORD_ID:-}"
record_name="${HETZNER_RECORD_NAME:-}"
record_ttl="${HETZNER_RECORD_TTL:-60}"
record_type="${HETZNER_RECORD_TYPE:-A}"
verbose="${HETZNER_VERBOSE:-false}"
force_colors="false"
__retval=""  # Global return variable for functions that return values

# Colors are initialized later after argument parsing

################################################################################
# Helper functions
################################################################################

# Logging with timestamp
log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        ERROR)
            echo -e "${RED}[${timestamp}] ERROR: ${message}${NC}" >&2
            ;;
        WARN)
            echo -e "${YELLOW}[${timestamp}] WARN: ${message}${NC}" >&2
            ;;
        INFO)
            echo -e "${GREEN}[${timestamp}] INFO: ${message}${NC}"
            ;;
        DEBUG)
            if [[ "$verbose" == "true" ]]; then
                echo -e "${BLUE}[${timestamp}] DEBUG: ${message}${NC}" >&2
            fi
            ;;
    esac
}

# Helper function for API calls
api_call() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    
    local curl_args=(
        -s
        -X "$method"
        -H "Authorization: Bearer ${auth_api_token}"
        -H "Content-Type: application/json"
    )
    
    if [[ -n "$data" ]]; then
        curl_args+=(-d "$data")
        log DEBUG "API request: $method $endpoint"
        # Validate JSON payload
        if ! echo "$data" | jq . &>/dev/null; then
            log ERROR "Invalid JSON payload: $data"
            return 1
        fi
        log DEBUG "Payload (formatted): $(echo "$data" | jq -c .)"
    fi
    
    local response
    response=$(curl "${curl_args[@]}" "${API_ENDPOINT}${endpoint}")
    
    if [[ $? -ne 0 ]]; then
        log ERROR "API call failed: $method $endpoint"
        return 1
    fi
    
    log DEBUG "API response: $response"
    
    # Check for errors in the API response
    if [[ -n "$response" ]] && echo "$response" | jq -e '.error' &>/dev/null; then
        local error_msg=$(echo "$response" | jq -r '.error.message // .error' 2>/dev/null)
        log ERROR "API error: $error_msg"
        return 1
    fi
    
    __retval="$response"
    return 0
}

# Get the public IPv4 address
get_public_ipv4() {
    # Try multiple IP discovery services
    local ipv4
    
    # Method 1: DNS via Hetzner
    ipv4=$(curl -s "https://dns.hetzner.com/api/v1/dns/check?domain=example.com" 2>/dev/null | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | head -1)
    
    if [[ -z "$ipv4" ]]; then
        # Method 2: Public IP service
        ipv4=$(curl -s "https://api.ipify.org?format=text" 2>/dev/null)
    fi
    
    if [[ -z "$ipv4" ]]; then
        # Method 3: Alternative
        ipv4=$(curl -s "https://icanhazip.com" 2>/dev/null | tr -d '[:space:]')
    fi
    
    if [[ -z "$ipv4" ]] || ! [[ "$ipv4" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log ERROR "Could not determine public IPv4 address"
        return 1
    fi
    
    __retval="$ipv4"
}

# Get the public IPv6 address
get_public_ipv6() {
    local ipv6
    
    # Method 1: IPv6-specific service
    ipv6=$(curl -s -6 "https://api6.ipify.org?format=text" 2>/dev/null)
    
    if [[ -z "$ipv6" ]]; then
        # Method 2: Alternative
        ipv6=$(curl -s -6 "https://icanhazip.com" 2>/dev/null | tr -d '[:space:]')
    fi
    
    if [[ -z "$ipv6" ]] || ! [[ "$ipv6" =~ ^[0-9a-fA-F:]+$ ]]; then
        log ERROR "Could not determine public IPv6 address"
        return 1
    fi
    
    __retval="$ipv6"
}

# Determine the current public IP based on record type
get_current_ip() {
    local type="$1"
    
    case "$type" in
        A)
            get_public_ipv4
            ;;
        AAAA)
            get_public_ipv6
            ;;
        *)
            log ERROR "Unknown record type: $type"
            return 1
            ;;
    esac
}

# Look up zone ID by zone name
get_zone_id_by_name() {
    local name="$1"
    
    log DEBUG "Looking up zone ID for zone: $name"
    
    api_call GET "/zones?name=$name" || return 1
    local response="$__retval"
    
    local found_id
    found_id=$(echo "$response" | jq -r '.zones[0].id' 2>/dev/null)
    
    if [[ -z "$found_id" ]] || [[ "$found_id" == "null" ]]; then
        log ERROR "Zone not found: $name"
        return 1
    fi
    
    __retval="$found_id"
}

# Validate zone ID
validate_zone_id() {
    local zone_id="$1"
    
    log DEBUG "Validating zone ID: $zone_id"
    
    api_call GET "/zones/$zone_id" || return 1
    local response="$__retval"
    
    # Check whether the zone structure is present
    if echo "$response" | jq -e '.zone' &>/dev/null 2>&1; then
        log DEBUG "Zone validated: $zone_id"
        __retval="$zone_id"
        return 0
    fi
    
    log DEBUG "Validation failed. API response: $response"
    return 1
}

# Fetch all records for a zone
get_zone_records() {
    local zone_id="$1"
    
    log DEBUG "Fetching records for zone: $zone_id"
    
    api_call GET "/zones/$zone_id/rrsets" || return 1
}

# Find a specific record
find_record() {
    local zone_id="$1"
    local record_name="$2"
    local record_type="$3"
    
    log DEBUG "Looking up record: name=$record_name, type=$record_type"
    
    get_zone_records "$zone_id" || return 1
    local response="$__retval"
    
    # Find the matching record (name only, without FQDN)
    local rrset
    rrset=$(echo "$response" | jq --arg name "$record_name" --arg type "$record_type" \
        '.rrsets[] | select(.name == $name and .type == $type)' 2>/dev/null)
    
    if [[ -z "$rrset" ]]; then
        log DEBUG "Record not found: $record_name ($record_type)"
        __retval=""
        return 1
    fi
    
    __retval="$rrset"
}

# Extract the current IP value from a record
extract_record_value() {
    local rrset="$1"
    
    # The record value is stored in an array of record entries
    __retval=$(echo "$rrset" | jq -r '.records[0].value' 2>/dev/null)
}

# Create a new record
create_record() {
    local zone_id="$1"
    local record_name="$2"
    local record_type="$3"
    local record_value="$4"
    local ttl="$5"
    
    log INFO "Creating new record: $record_name ($record_type) = $record_value"
    
    local payload=$(cat <<EOF
{
  "name": "$record_name",
  "type": "$record_type",
  "ttl": $ttl,
  "records": [
    {
      "value": "$record_value"
    }
  ]
}
EOF
)
    
    log DEBUG "Payload (formatted): $(echo "$payload" | jq -c .)"
    
    api_call POST "/zones/$zone_id/rrsets" "$payload" || return 1
}

# Update an existing record
update_record() {
    local zone_id="$1"
    local record_name="$2"
    local record_type="$3"
    local record_value="$4"
    local ttl="$5"
    
    log INFO "Updating record: $record_name ($record_type) = $record_value"
    
    local payload=$(cat <<EOF
{
  "records": [
    {
      "value": "$record_value"
    }
  ],
  "ttl": $ttl
}
EOF
)
    
    log DEBUG "Payload (formatted): $(echo "$payload" | jq -c .)"
    
    api_call PUT "/zones/$zone_id/rrsets/$record_name/$record_type" "$payload" || return 1
}

# Delete an existing RRset (name + type)
delete_record() {
    local zone_id="$1"
    local record_name="$2"
    local record_type="$3"

    log INFO "Deleting existing record: $record_name ($record_type)"

    api_call DELETE "/zones/$zone_id/rrsets/$record_name/$record_type" || return 1
}

# Show help
show_help() {
    cat <<EOF
${BLUE}Hetzner DNS DynDNS Update Script${NC}

${YELLOW}USAGE:${NC}
  $SCRIPT_NAME [-z <Zone ID> | -Z <Zone Name>] -n <Record Name> [OPTIONS]

${YELLOW}REQUIRED PARAMETERS:${NC}
  -z <Zone ID>         Zone ID (alternative to -Z)
  -Z <Zone Name>       Zone name (alternative to -z), e.g. example.com
  -n <Record Name>     Name of the record, e.g. dyn or @ for zone apex

${YELLOW}OPTIONAL PARAMETERS:${NC}
  -t <TTL>            Time To Live in seconds (default: 60)
  -T <Record Type>    Record type: A (IPv4) or AAAA (IPv6) (default: A)
  -r <Record ID>      Record ID (deprecated, determined automatically)
  -v                  Verbose mode (debug output)
  -C                  Force colors (even when not writing to a terminal)
  -h                  Show this help

${YELLOW}ENVIRONMENT VARIABLES:${NC}
  HETZNER_AUTH_API_TOKEN    API token (required)
  HETZNER_ZONE_ID           Zone ID
  HETZNER_ZONE_NAME         Zone name
  HETZNER_RECORD_NAME       Record name
  HETZNER_RECORD_TTL        TTL (default: 60)
  HETZNER_RECORD_TYPE       Record type (default: A)
  HETZNER_VERBOSE           Verbose mode (true/false)
  NO_COLOR                  Disable colors (even when writing to a terminal)

${YELLOW}EXAMPLES:${NC}
  # With zone name and command-line parameters
  HETZNER_AUTH_API_TOKEN='your-token' \\
    $SCRIPT_NAME -Z example.com -n dyn

  # With zone name and IPv6
  HETZNER_AUTH_API_TOKEN='your-token' \\
    $SCRIPT_NAME -Z example.com -n dyn -T AAAA

  # With zone ID
  HETZNER_AUTH_API_TOKEN='your-token' \\
    $SCRIPT_NAME -z 98jFjsd8dh1GHasdf7a8hJG7 -n dyn

  # Using environment variables only
  export HETZNER_AUTH_API_TOKEN='your-token'
  export HETZNER_ZONE_NAME='example.com'
  export HETZNER_RECORD_NAME='dyn'
  $SCRIPT_NAME

${YELLOW}CRON EXAMPLE:${NC}
  # Update every 5 minutes
  */5 * * * * HETZNER_AUTH_API_TOKEN='your-token' /usr/local/bin/dyndns.sh -Z example.com -n dyn

${YELLOW}DOCUMENTATION:${NC}
  https://docs.hetzner.cloud/reference/cloud#tag/zones

EOF
}

################################################################################
# Main function
################################################################################

main() {
    # Validate required arguments
    if [[ -z "$auth_api_token" ]]; then
        log ERROR "HETZNER_AUTH_API_TOKEN is not set"
        exit 1
    fi
    
    if [[ -z "$record_name" ]]; then
        log ERROR "Record name not specified (-n)"
        show_help
        exit 1
    fi
    
    if [[ -z "$zone_id" && -z "$zone_name" ]]; then
        log ERROR "Either zone ID (-z) or zone name (-Z) is required"
        show_help
        exit 1
    fi
    
    if [[ -n "$zone_id" && -n "$zone_name" ]]; then
        log WARN "Both zone ID and zone name specified, using zone ID"
    fi
    
    # Determine zone ID
    if [[ -z "$zone_id" ]]; then
        log INFO "Looking up zone ID for zone: $zone_name"
        get_zone_id_by_name "$zone_name" || {
            log ERROR "Could not determine zone ID"
            exit 1
        }
        zone_id="$__retval"
        log INFO "Zone ID found: $zone_id"
    else
        log INFO "Verifying zone ID: $zone_id"
        if ! validate_zone_id "$zone_id"; then
            log ERROR "Zone ID invalid or unreachable: $zone_id"
            exit 1
        fi
        log INFO "Zone ID is valid"
    fi
    
    # Determine current public IP
    log INFO "Determining current public IP ($record_type)..."
    get_current_ip "$record_type" || {
        log ERROR "Could not determine public IP"
        exit 1
    }
    local current_ip="$__retval"
    log INFO "Current IP: $current_ip"
    
    # Look up existing record
    find_record "$zone_id" "$record_name" "$record_type"
    local existing_record="$__retval"
    
    if [[ -n "$existing_record" ]]; then
        # Record exists, check whether an update is needed
        extract_record_value "$existing_record"
        local existing_ip="$__retval"
        
        log INFO "Existing record found: $record_name ($record_type) = $existing_ip"
        
        if [[ "$existing_ip" == "$current_ip" ]]; then
            log INFO "IP address has not changed, no update needed"
            exit 0
        fi
        
        log INFO "IP address has changed: $existing_ip -> $current_ip"

        delete_record "$zone_id" "$record_name" "$record_type" || {
            log ERROR "Could not delete existing record"
            exit 1
        }

        # Brief guard against API race conditions
        sleep 1

        create_record "$zone_id" "$record_name" "$record_type" "$current_ip" "$record_ttl" || {
            log ERROR "Could not recreate record"
            exit 1
        }

        log INFO "Record successfully recreated"

    else
        # Record does not exist, create it
        log INFO "Record does not exist, creating new record"
        create_record "$zone_id" "$record_name" "$record_type" "$current_ip" "$record_ttl" || {
            log ERROR "Could not create record"
            exit 1
        }
        log INFO "Record successfully created"
    fi
    
    log INFO "DynDNS update complete: $record_name ($record_type) = $current_ip"
    exit 0
}

################################################################################
# Argument parsing
################################################################################

# First quick pass to detect color options only
while getopts "z:Z:n:r:t:T:vCh" opt 2>/dev/null; do
    [[ $opt == "C" ]] && force_colors="true"
done

# Initialize colors based on force_colors flag BEFORE any functions are called
if [[ "$force_colors" == "true" ]] || ([[ -t 1 ]] && [[ "${NO_COLOR:-}" != "1" ]]); then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Reset OPTIND for full processing
OPTIND=1

# Main loop for all arguments
while getopts "z:Z:n:r:t:T:vCh" opt; do
    case $opt in
        z)
            zone_id="$OPTARG"
            ;;
        Z)
            zone_name="$OPTARG"
            ;;
        n)
            record_name="$OPTARG"
            ;;
        r)
            record_id="$OPTARG"
            ;;
        t)
            record_ttl="$OPTARG"
            ;;
        T)
            record_type="$OPTARG"
            ;;
        v)
            verbose="true"
            ;;
        C)
            # Force colors
            force_colors="true"
            ;;
        h)
            show_help
            exit 0
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
done

# Run main function
main
