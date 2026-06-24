#!/usr/bin/env bash

set -euo pipefail

BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $*"; FAILURES=$((FAILURES + 1)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
info() { echo -e "       $*"; }

FAILURES=0

adb_check() {
    if ! command -v adb &>/dev/null; then
        echo -e "${RED}adb not found.${NC}" && exit 1
    fi
    local state
    state="$(adb get-state 2>/dev/null || echo none)"
    if [[ "$state" != "device" ]]; then
        echo -e "${RED}No adb device connected (state: $state).${NC}" && exit 1
    fi
}

check_binary_exists() {
    echo -e "${BOLD}--- 1. Binary Presence ---${NC}"
    local result
    result="$(adb shell "ls /system/xbin/su 2>&1")"
    if echo "$result" | grep -q "No such file"; then
        fail "/system/xbin/su not found"
    else
        pass "/system/xbin/su exists"
        info "$result"
    fi
}

check_permissions() {
    echo -e "${BOLD}--- 2. Permissions & Ownership ---${NC}"
    local stat_out
    stat_out="$(adb shell "ls -la /system/xbin/su 2>/dev/null")"
    info "$stat_out"

    if echo "$stat_out" | grep -qE "^-rws"; then
        pass "Setuid bit is set"
    else
        fail "Setuid bit is NOT set (expected -rwsr-xr-x)"
    fi

    if echo "$stat_out" | grep -qE "root\s+root"; then
        pass "Owned by root:root"
    else
        fail "Not owned by root:root"
    fi
}

check_selinux_context() {
    echo -e "${BOLD}--- 3. SELinux Context ---${NC}"
    local ctx_out
    ctx_out="$(adb shell "ls -laZ /system/xbin/su 2>/dev/null")"
    info "$ctx_out"

    if echo "$ctx_out" | grep -q "su_exec"; then
        pass "SELinux context is u:object_r:su_exec:s0"
    else
        fail "SELinux context does not contain su_exec"
    fi
}

check_version() {
    echo -e "${BOLD}--- 4. Binary Version ---${NC}"
    local ver
    ver="$(adb shell "/system/xbin/su --version 2>&1")"
    if echo "$ver" | grep -q "SystematicSU"; then
        pass "Version output OK: $ver"
    else
        fail "Version output unexpected: $ver"
    fi
}

check_uid_escalation() {
    echo -e "${BOLD}--- 5. UID Escalation ---${NC}"
    local id_out
    id_out="$(adb shell "/system/xbin/su -c id 2>&1")"
    info "Output: $id_out"

    if echo "$id_out" | grep -q "uid=0(root)"; then
        pass "UID escalation to root succeeded"
    else
        fail "UID escalation FAILED — not running as root"
        warn "Check SELinux policy or setuid mount options"
    fi
}

check_selinux_denials() {
    echo -e "${BOLD}--- 6. SELinux AVC Denials ---${NC}"
    local denials
    denials="$(adb shell "dmesg 2>/dev/null | grep 'avc: denied' | grep -i su | tail -5")"
    if [[ -z "$denials" ]]; then
        pass "No su-related AVC denials in dmesg"
    else
        warn "AVC denials found:"
        echo "$denials" | while IFS= read -r line; do
            info "$line"
        done
    fi
}

check_nosuid_mount() {
    echo -e "${BOLD}--- 7. Mount Flags ---${NC}"
    local mounts
    mounts="$(adb shell "cat /proc/mounts 2>/dev/null | grep ' /system '")"
    info "$mounts"

    if echo "$mounts" | grep -q "nosuid"; then
        fail "/system is mounted with nosuid — setuid bit will be ignored"
        warn "Recheck fstab or init rc files"
    else
        pass "/system is mounted WITHOUT nosuid"
    fi
}

print_summary() {
    echo ""
    echo -e "${BOLD}=============================${NC}"
    if [[ $FAILURES -eq 0 ]]; then
        echo -e "${GREEN}${BOLD} ALL CHECKS PASSED${NC}"
    else
        echo -e "${RED}${BOLD} $FAILURES CHECK(S) FAILED${NC}"
    fi
    echo -e "${BOLD}=============================${NC}"
    echo ""
}

main() {
    echo -e "${BOLD}"
    echo "  SystematicSU — verify.sh"
    echo -e "${NC}"

    adb_check

    check_binary_exists
    echo ""
    check_permissions
    echo ""
    check_selinux_context
    echo ""
    check_version
    echo ""
    check_uid_escalation
    echo ""
    check_selinux_denials
    echo ""
    check_nosuid_mount

    print_summary
    exit $FAILURES
}

main "$@"
