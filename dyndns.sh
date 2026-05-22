#!/bin/bash

################################################################################
# Hetzner DNS DynDNS Update Script
# Moderne Version für die aktuelle Hetzner DNS API (v1)
# 
# Unterstützt sowohl Zone-Name als auch Zone-ID und aktualisiert DNS-Records
# automatisch nur wenn sich die IP-Adresse ändert.
#
# Kompatibel mit allen Legacy Environment-Variablen:
# - HETZNER_AUTH_API_TOKEN
# - HETZNER_ZONE_NAME oder HETZNER_ZONE_ID
# - HETZNER_RECORD_NAME
# - HETZNER_RECORD_TTL (default: 60)
# - HETZNER_RECORD_TYPE (default: A)
#
# API Dokumentation: https://docs.hetzner.cloud/reference/cloud#tag/zones
################################################################################

set -o pipefail

# Konstanten
readonly API_ENDPOINT="https://api.hetzner.cloud/v1"
readonly SCRIPT_NAME="$(basename "$0")"

# Globale Variablen
auth_api_token="${HETZNER_AUTH_API_TOKEN:-}"
zone_id="${HETZNER_ZONE_ID:-}"
zone_name="${HETZNER_ZONE_NAME:-}"
record_id="${HETZNER_RECORD_ID:-}"
record_name="${HETZNER_RECORD_NAME:-}"
record_ttl="${HETZNER_RECORD_TTL:-60}"
record_type="${HETZNER_RECORD_TYPE:-A}"
verbose="${HETZNER_VERBOSE:-false}"
force_colors="false"

# Farben werden später initialisiert nach Argument Parsing

################################################################################
# Hilfsfunktionen
################################################################################

# Logging mit Zeitstempel
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
                echo -e "${BLUE}[${timestamp}] DEBUG: ${message}${NC}"
            fi
            ;;
    esac
}

# Hilfsfunktion für API-Aufrufe
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
        log DEBUG "API-Anfrage: $method $endpoint"
        # Überprüfe ob JSON valide ist
        if ! echo "$data" | jq . &>/dev/null; then
            log ERROR "Ungültige JSON-Payload: $data"
            return 1
        fi
        log DEBUG "Payload (formatted): $(echo "$data" | jq -c .)"
    fi
    
    local response
    response=$(curl "${curl_args[@]}" "${API_ENDPOINT}${endpoint}")
    
    if [[ $? -ne 0 ]]; then
        log ERROR "API-Aufruf fehlgeschlagen: $method $endpoint"
        return 1
    fi
    
    log DEBUG "API-Antwort: $response"
    
    # Überprüfe auf Fehler in der API-Antwort
    if [[ -n "$response" ]] && echo "$response" | jq -e '.error' &>/dev/null; then
        local error_msg=$(echo "$response" | jq -r '.error.message // .error' 2>/dev/null)
        log ERROR "API-Fehler: $error_msg"
        return 1
    fi
    
    echo "$response"
    return 0
}

# Hole die öffentliche IPv4-Adresse
get_public_ipv4() {
    # Versuche mehrere DNS-Query-Services
    local ipv4
    
    # Methode 1: DNS über Hetzner
    ipv4=$(curl -s "https://dns.hetzner.com/api/v1/dns/check?domain=example.com" 2>/dev/null | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | head -1)
    
    if [[ -z "$ipv4" ]]; then
        # Methode 2: Verwende einen öffentlichen Service
        ipv4=$(curl -s "https://api.ipify.org?format=text" 2>/dev/null)
    fi
    
    if [[ -z "$ipv4" ]]; then
        # Methode 3: Alternative
        ipv4=$(curl -s "https://icanhazip.com" 2>/dev/null | tr -d '[:space:]')
    fi
    
    if [[ -z "$ipv4" ]] || ! [[ "$ipv4" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log ERROR "Konnte öffentliche IPv4 nicht ermitteln"
        return 1
    fi
    
    echo "$ipv4"
}

# Hole die öffentliche IPv6-Adresse
get_public_ipv6() {
    local ipv6
    
    # Methode 1: IPv6-spezifischer Service
    ipv6=$(curl -s -6 "https://api6.ipify.org?format=text" 2>/dev/null)
    
    if [[ -z "$ipv6" ]]; then
        # Methode 2: Alternative
        ipv6=$(curl -s -6 "https://icanhazip.com" 2>/dev/null | tr -d '[:space:]')
    fi
    
    if [[ -z "$ipv6" ]] || ! [[ "$ipv6" =~ ^[0-9a-fA-F:]+$ ]]; then
        log ERROR "Konnte öffentliche IPv6 nicht ermitteln"
        return 1
    fi
    
    echo "$ipv6"
}

# Ermittle die aktuelle öffentliche IP basierend auf Record-Type
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
            log ERROR "Unbekannter Record-Type: $type"
            return 1
            ;;
    esac
}

# Finde Zone-ID anhand Zone-Name
get_zone_id_by_name() {
    local name="$1"
    
    log DEBUG "Suche Zone-ID für Zone: $name"
    
    local response
    response=$(api_call GET "/zones?name=$name") || return 1
    
    local found_id
    found_id=$(echo "$response" | jq -r '.zones[0].id' 2>/dev/null)
    
    if [[ -z "$found_id" ]] || [[ "$found_id" == "null" ]]; then
        log ERROR "Zone nicht gefunden: $name"
        return 1
    fi
    
    echo "$found_id"
}

# Validiere Zone-ID
validate_zone_id() {
    local zone_id="$1"
    
    log DEBUG "Validiere Zone-ID: $zone_id"
    
    local response
    response=$(api_call GET "/zones/$zone_id") || return 1
    
    # Überprüfe ob die Zone-Struktur vorhanden ist
    if echo "$response" | jq -e '.zone' &>/dev/null 2>&1; then
        log DEBUG "Zone validiert: $zone_id"
        echo "$zone_id"
        return 0
    fi
    
    log DEBUG "Validierung fehlgeschlagen. API-Antwort: $response"
    return 1
}

# Hole alle Records für eine Zone
get_zone_records() {
    local zone_id="$1"
    
    log DEBUG "Hole Records für Zone: $zone_id"
    
    api_call GET "/zones/$zone_id/rrsets" || return 1
}

# Suche einen spezifischen Record
find_record() {
    local zone_id="$1"
    local record_name="$2"
    local record_type="$3"
    
    log DEBUG "Suche Record: name=$record_name, type=$record_type"
    
    local response
    response=$(get_zone_records "$zone_id") || return 1
    
    # Suche nach dem passenden Record (nur mit dem Namen ohne FQDN)
    local rrset
    rrset=$(echo "$response" | jq --arg name "$record_name" --arg type "$record_type" \
        '.rrsets[] | select(.name == $name and .type == $type)' 2>/dev/null)
    
    if [[ -z "$rrset" ]]; then
        log DEBUG "Record nicht gefunden: $record_name ($record_type)"
        return 1
    fi
    
    echo "$rrset"
}

# Extrahiere aktuelle IP aus einem Record
extract_record_value() {
    local rrset="$1"
    
    # Der Wert eines Records ist ein Array von Records
    echo "$rrset" | jq -r '.records[0].value' 2>/dev/null
}

# Erstelle einen neuen Record
create_record() {
    local zone_id="$1"
    local record_name="$2"
    local record_type="$3"
    local record_value="$4"
    local ttl="$5"
    
    log INFO "Erstelle neuen Record: $record_name ($record_type) = $record_value"
    
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
    
    api_call POST "/zones/$zone_id/rrsets" "$payload" > /dev/null || return 1
}

# Aktualisiere einen bestehenden Record
update_record() {
    local zone_id="$1"
    local record_name="$2"
    local record_type="$3"
    local record_value="$4"
    local ttl="$5"
    
    log INFO "Aktualisiere Record: $record_name ($record_type) = $record_value"
    
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
    
    api_call PUT "/zones/$zone_id/rrsets/$record_name/$record_type" "$payload" > /dev/null || return 1
}

# Lösche einen bestehenden RRSET (Name + Typ)
delete_record() {
    local zone_id="$1"
    local record_name="$2"
    local record_type="$3"

    log INFO "Lösche bestehenden Record: $record_name ($record_type)"

    api_call DELETE "/zones/$zone_id/rrsets/$record_name/$record_type" > /dev/null || return 1
}

# Zeige Hilfe
show_help() {
    cat <<EOF
${BLUE}Hetzner DNS DynDNS Update Script${NC}

${YELLOW}VERWENDUNG:${NC}
  $SCRIPT_NAME [-z <Zone ID> | -Z <Zone Name>] -n <Record Name> [OPTIONS]

${YELLOW}ERFORDERLICHE PARAMETER:${NC}
  -z <Zone ID>         Zone-ID (alternativ zu -Z)
  -Z <Zone Name>       Zone-Name (alternativ zu -z), z.B. example.com
  -n <Record Name>     Name des Records, z.B. dyn oder @ für Zone-Apex

${YELLOW}OPTIONALE PARAMETER:${NC}
  -t <TTL>            Time To Live in Sekunden (default: 60)
  -T <Record Type>    Record-Type: A (IPv4) oder AAAA (IPv6) (default: A)
  -r <Record ID>      Record-ID (deprecated, wird automatisch ermittelt)
  -v                  Verbose-Modus (Debug-Ausgaben)
  -C                  Farben erzwingen (auch wenn nicht zu Terminal)
  -h                  Diese Hilfe anzeigen

${YELLOW}UMGEBUNGSVARIABLEN:${NC}
  HETZNER_AUTH_API_TOKEN    API-Token (erforderlich)
  HETZNER_ZONE_ID           Zone-ID
  HETZNER_ZONE_NAME         Zone-Name
  HETZNER_RECORD_NAME       Record-Name
  HETZNER_RECORD_TTL        TTL (default: 60)
  HETZNER_RECORD_TYPE       Record-Type (default: A)
  HETZNER_VERBOSE           Verbose-Modus (true/false)
  NO_COLOR                  Deaktiviert Farben (auch wenn Terminal)

${YELLOW}BEISPIELE:${NC}
  # Mit Zone-Name und Command-Line-Parametern
  HETZNER_AUTH_API_TOKEN='your-token' \\
    $SCRIPT_NAME -Z example.com -n dyn

  # Mit Zone-Name und IPv6
  HETZNER_AUTH_API_TOKEN='your-token' \\
    $SCRIPT_NAME -Z example.com -n dyn -T AAAA

  # Mit Zone-ID
  HETZNER_AUTH_API_TOKEN='your-token' \\
    $SCRIPT_NAME -z 98jFjsd8dh1GHasdf7a8hJG7 -n dyn

  # Nur mit Umgebungsvariablen
  export HETZNER_AUTH_API_TOKEN='your-token'
  export HETZNER_ZONE_NAME='example.com'
  export HETZNER_RECORD_NAME='dyn'
  $SCRIPT_NAME

${YELLOW}CRON-BEISPIEL:${NC}
  # Aktualisiere alle 5 Minuten
  */5 * * * * HETZNER_AUTH_API_TOKEN='your-token' /usr/local/bin/dyndns.sh -Z example.com -n dyn

${YELLOW}DOKUMENTATION:${NC}
  https://docs.hetzner.cloud/reference/cloud#tag/zones

EOF
}

################################################################################
# Hauptfunktion
################################################################################

main() {
    # Validiere erforderliche Argumente
    if [[ -z "$auth_api_token" ]]; then
        log ERROR "HETZNER_AUTH_API_TOKEN nicht gesetzt"
        exit 1
    fi
    
    if [[ -z "$record_name" ]]; then
        log ERROR "Record-Name nicht angegeben (-n)"
        show_help
        exit 1
    fi
    
    if [[ -z "$zone_id" && -z "$zone_name" ]]; then
        log ERROR "Entweder Zone-ID (-z) oder Zone-Name (-Z) erforderlich"
        show_help
        exit 1
    fi
    
    if [[ -n "$zone_id" && -n "$zone_name" ]]; then
        log WARN "Sowohl Zone-ID als auch Zone-Name angegeben, verwende Zone-ID"
    fi
    
    # Bestimme Zone-ID
    if [[ -z "$zone_id" ]]; then
        log INFO "Ermittle Zone-ID für Zone: $zone_name"
        zone_id=$(get_zone_id_by_name "$zone_name") || {
            log ERROR "Konnte Zone-ID nicht ermitteln"
            exit 1
        }
        log INFO "Zone-ID gefunden: $zone_id"
    else
        log INFO "Überprüfe Zone-ID: $zone_id"
        local validation_result
        validation_result=$(validate_zone_id "$zone_id")
        if [[ $? -ne 0 ]]; then
            log ERROR "Zone-ID ungültig oder nicht erreichbar: $zone_id"
            exit 1
        fi
        log INFO "Zone-ID ist gültig"
    fi
    
    # Ermittle aktuelle öffentliche IP
    log INFO "Ermittle aktuelle öffentliche IP ($record_type)..."
    local current_ip
    current_ip=$(get_current_ip "$record_type") || {
        log ERROR "Konnte öffentliche IP nicht ermitteln"
        exit 1
    }
    log INFO "Aktuelle IP: $current_ip"
    
    # Suche bestehenden Record
    local existing_record
    existing_record=$(find_record "$zone_id" "$record_name" "$record_type")
    
    if [[ -n "$existing_record" ]]; then
        # Record existiert, überprüfe ob Update nötig ist
        local existing_ip
        existing_ip=$(extract_record_value "$existing_record")
        
        log INFO "Bestehender Record gefunden: $record_name ($record_type) = $existing_ip"
        
        if [[ "$existing_ip" == "$current_ip" ]]; then
            log INFO "IP-Adresse hat sich nicht geändert, keine Aktualisierung nötig"
            exit 0
        fi
        
        log INFO "IP-Adresse hat sich geändert: $existing_ip -> $current_ip"

        delete_record "$zone_id" "$record_name" "$record_type" || {
            log ERROR "Konnte bestehenden Record nicht löschen"
            exit 1
        }

        # kurzer Schutz gegen API-Race-Conditions
        sleep 1

        create_record "$zone_id" "$record_name" "$record_type" "$current_ip" "$record_ttl" || {
            log ERROR "Konnte Record nicht neu erstellen"
            exit 1
        }

        log INFO "Record erfolgreich neu erstellt"

    else
        # Record existiert nicht, erstelle ihn
        log INFO "Record existiert nicht, erstelle neuen Record"
        create_record "$zone_id" "$record_name" "$record_type" "$current_ip" "$record_ttl" || {
            log ERROR "Konnte Record nicht erstellen"
            exit 1
        }
        log INFO "Record erfolgreich erstellt"
    fi
    
    log INFO "DynDNS-Update abgeschlossen: $record_name ($record_type) = $current_ip"
    exit 0
}

################################################################################
# Argument Parsing
################################################################################

# Erste schnelle Runde nur für Farb-Optionen
while getopts "z:Z:n:r:t:T:vCh" opt 2>/dev/null; do
    [[ $opt == "C" ]] && force_colors="true"
done

# Farben initialisieren basierend auf force_colors Flag BEVOR andere Funktionen aufgerufen werden
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

# Setze OPTIND zurück für vollständige Verarbeitung
OPTIND=1

# Hauptschleife für alle Argumente
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
            # Erzwinge Farben - setze die Variable vor den Farben
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

# Starte Hauptfunktion
main
