#!/bin/bash

################################################################################
# Test script for Hetzner DynDNS
#
# Runs various tests to verify that dyndns.sh is correctly configured
# and working.
################################################################################

set -o pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test counters
tests_total=0
tests_passed=0
tests_failed=0

################################################################################
# Helper functions
################################################################################

test_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

test_pass() {
    ((tests_passed++))
    ((tests_total++))
    echo -e "${GREEN}✓ PASS${NC}: $1"
}

test_fail() {
    ((tests_failed++))
    ((tests_total++))
    echo -e "${RED}✗ FAIL${NC}: $1"
}

test_skip() {
    echo -e "${YELLOW}⊘ SKIP${NC}: $1"
}

test_info() {
    echo -e "${BLUE}ℹ INFO${NC}: $1"
}

summary() {
    echo -e "\n${BLUE}=== Test Summary ===${NC}"
    echo -e "Total:  ${YELLOW}$tests_total${NC}"
    echo -e "Passed: ${GREEN}$tests_passed${NC}"
    echo -e "Failed: ${RED}$tests_failed${NC}"
    
    if [[ $tests_failed -eq 0 ]] && [[ $tests_total -gt 0 ]]; then
        echo -e "\n${GREEN}✓ All tests passed!${NC}"
        return 0
    else
        echo -e "\n${RED}✗ Some tests failed${NC}"
        return 1
    fi
}

################################################################################
# Prerequisite Tests
################################################################################

test_prerequisites() {
    test_header "Check prerequisites"
    
    # curl
    if command -v curl &> /dev/null; then
        test_pass "curl is installed"
    else
        test_fail "curl is NOT installed"
        return 1
    fi
    
    # jq
    if command -v jq &> /dev/null; then
        test_pass "jq is installed"
    else
        test_fail "jq is NOT installed"
        return 1
    fi
    
    # bash
    if [[ ${BASH_VERSINFO[0]} -ge 4 ]]; then
        test_pass "Bash 4.0+ is installed (version ${BASH_VERSION})"
    else
        test_fail "Bash 4.0+ required (current version ${BASH_VERSION})"
        return 1
    fi
}

################################################################################
# Script Tests
################################################################################

test_script_exists() {
    test_header "Check script exists"
    
    if [[ -f "./dyndns.sh" ]]; then
        test_pass "dyndns.sh exists"
    else
        test_fail "dyndns.sh not found"
        return 1
    fi
}

test_script_executable() {
    test_header "Check script permissions"
    
    if [[ -x "./dyndns.sh" ]]; then
        test_pass "dyndns.sh is executable"
    else
        test_fail "dyndns.sh is NOT executable"
        test_info "Run: chmod +x dyndns.sh"
    fi
}

test_script_syntax() {
    test_header "Check Bash syntax"
    
    if bash -n ./dyndns.sh 2>/dev/null; then
        test_pass "dyndns.sh has valid Bash syntax"
    else
        test_fail "dyndns.sh has syntax errors"
        bash -n ./dyndns.sh
    fi
}

test_help_output() {
    test_header "Check help output"
    
    local help_output
    help_output=$("./dyndns.sh" -h 2>&1)
    
    if echo "$help_output" | grep -q "USAGE"; then
        test_pass "Help text contains 'USAGE'"
    else
        test_fail "Help text malformed"
    fi
    
    if echo "$help_output" | grep -q "REQUIRED PARAMETERS"; then
        test_pass "Help text contains 'REQUIRED PARAMETERS'"
    else
        test_fail "Help text malformed"
    fi
    
    if echo "$help_output" | grep -q "EXAMPLES"; then
        test_pass "Help text contains 'EXAMPLES'"
    else
        test_fail "Help text malformed"
    fi
}

################################################################################
# Configuration tests
################################################################################

test_environment_variables() {
    test_header "Environment variable support"
    
    if grep -q "HETZNER_AUTH_API_TOKEN" dyndns.sh; then
        test_pass "HETZNER_AUTH_API_TOKEN is supported"
    else
        test_fail "HETZNER_AUTH_API_TOKEN is NOT supported"
    fi
    
    if grep -q "HETZNER_ZONE_NAME" dyndns.sh; then
        test_pass "HETZNER_ZONE_NAME is supported"
    else
        test_fail "HETZNER_ZONE_NAME is NOT supported"
    fi
    
    if grep -q "HETZNER_ZONE_ID" dyndns.sh; then
        test_pass "HETZNER_ZONE_ID is supported"
    else
        test_fail "HETZNER_ZONE_ID is NOT supported"
    fi
    
    if grep -q "HETZNER_RECORD_NAME" dyndns.sh; then
        test_pass "HETZNER_RECORD_NAME is supported"
    else
        test_fail "HETZNER_RECORD_NAME is NOT supported"
    fi
}

################################################################################
# API tests
################################################################################

test_api_connectivity() {
    test_header "Check API connectivity"
    
    if curl -s "https://api.hetzner.cloud/v1/zones" \
        -H "Authorization: Bearer invalid-token" | jq . > /dev/null 2>&1; then
        test_pass "Hetzner API is reachable"
    else
        test_fail "Hetzner API is NOT reachable"
    fi
}

test_ipv4_detection() {
    test_header "Test IPv4 detection"
    
    local ipv4
    ipv4=$(curl -s "https://api.ipify.org?format=text" 2>/dev/null)
    
    if [[ $ipv4 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        test_pass "Public IPv4 detected: $ipv4"
    else
        test_fail "Could not determine public IPv4"
    fi
}

test_ipv6_detection() {
    test_header "Test IPv6 detection"
    
    local ipv6
    ipv6=$(curl -s -6 "https://api6.ipify.org?format=text" 2>/dev/null)
    
    if [[ -n "$ipv6" ]] && [[ "$ipv6" =~ ^[0-9a-fA-F:]+$ ]]; then
        test_pass "Public IPv6 detected: $ipv6"
    else
        test_skip "IPv6 is not available on this system"
    fi
}

################################################################################
# Config file tests
################################################################################

test_config_example() {
    test_header "Check config examples"
    
    if [[ -f "config-examples.sh" ]]; then
        test_pass "config-examples.sh exists"
        
        if bash -n config-examples.sh 2>/dev/null; then
            test_pass "config-examples.sh has valid syntax"
        else
            test_fail "config-examples.sh has syntax errors"
        fi
    else
        test_fail "config-examples.sh not found"
    fi
}

test_readme() {
    test_header "Check documentation"
    
    if [[ -f "README.md" ]]; then
        test_pass "README.md exists"
        
        if grep -q "Installation" README.md; then
            test_pass "README contains 'Installation'"
        else
            test_fail "README missing 'Installation' section"
        fi
        
        if grep -iq "example" README.md; then
            test_pass "README contains examples"
        else
            test_fail "README missing examples section"
        fi
        
        if grep -q "Cron" README.md; then
            test_pass "README contains cron information"
        else
            test_fail "README missing cron information"
        fi
    else
        test_fail "README.md not found"
    fi
}

################################################################################
# Integration tests
################################################################################

test_no_token_error() {
    test_header "Error handling: missing API token"
    
    local output
    output=$("./dyndns.sh" -Z "example.com" -n "dyn" 2>&1)
    
    if echo "$output" | grep -q "HETZNER_AUTH_API_TOKEN"; then
        test_pass "Script outputs a meaningful error message"
    else
        test_fail "Error message not meaningful"
    fi
}

test_help_flag() {
    test_header "Test help flag"
    
    local exit_code
    "./dyndns.sh" -h > /dev/null 2>&1
    exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        test_pass "Help flag (-h) works correctly"
    else
        test_fail "Help flag (-h) returned an error"
    fi
}

################################################################################
# Performance tests
################################################################################

test_execution_time() {
    test_header "Check performance"
    
    local start_time
    local end_time
    local execution_time
    
    start_time=$(date +%s%N)
    bash -c 'source ./dyndns.sh' 2>/dev/null
    end_time=$(date +%s%N)
    
    execution_time=$(( (end_time - start_time) / 1000000 ))  # milliseconds
    
    if [[ $execution_time -lt 1000 ]]; then
        test_pass "Script load time under 1 second ($execution_time ms)"
    else
        test_info "Script load time: $execution_time ms"
    fi
}

################################################################################
# Main Test Runner
################################################################################

main() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════════╗
║   Hetzner DynDNS - Test Suite               ║
╚═══════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    # Check we are in the right directory
    if [[ ! -f "dyndns.sh" ]]; then
        echo -e "${RED}Error: dyndns.sh not found${NC}"
        echo "Please run this script from the directory containing dyndns.sh"
        exit 1
    fi
    
    # Run all tests
    test_prerequisites || exit 1
    test_script_exists
    test_script_executable
    test_script_syntax
    test_help_output
    test_environment_variables
    test_api_connectivity
    test_ipv4_detection
    test_ipv6_detection
    test_config_example
    test_readme
    test_no_token_error
    test_help_flag
    test_execution_time
    
    # Show summary
    summary
}

# Run tests
main "$@"
