#!/usr/bin/env bash
# CursiveOS v0.9-network-efficient candidate
#
# Hypothesis: retain the measured WAN-simulation throughput benefit of v0.8
# while avoiding its always-on CPU C-state, governor, and GPU-frequency power
# cost. This candidate changes network controls only.

set -euo pipefail

ACTION="${1:---help}"
STATE_FILE="$HOME/CursiveOS/preset_state_backup_v0.9-network-efficient.txt"

if [[ -z "${TAO_SUDO_PASS:-}" ]]; then
    read -rsp "[CursiveOS] sudo password: " TAO_SUDO_PASS && echo
fi
SP="$TAO_SUDO_PASS"
export TAO_SUDO_PASS
s() { echo "$SP" | sudo -S "$@" 2>/dev/null; }

get_sysctl() {
    sysctl -n "$1" 2>/dev/null || echo "N/A"
}

write_sysctl() {
    local name="$1" value="$2" label="$3"
    s sysctl -w "$name=$value" >/dev/null \
        && echo "OK $label: $value" \
        || echo "  $label unavailable - skipped"
}

echo "CursiveOS Candidate v0.9-network-efficient"
echo "------------------------------------------"

if [[ "$ACTION" == "--help" ]]; then
    echo "Usage: $0 --apply-temp | --undo | --dry-run"
    echo "Scope: network-only candidate; no CPU, GPU, memory, or power-state changes."
    exit 0
fi

if [[ "$ACTION" == "--dry-run" ]]; then
    echo "DRY RUN - no changes will be made"
    echo "  net.core.rmem_max:             $(get_sysctl net.core.rmem_max) -> 16777216"
    echo "  net.core.wmem_max:             $(get_sysctl net.core.wmem_max) -> 16777216"
    echo "  net.ipv4.tcp_rmem:            $(get_sysctl net.ipv4.tcp_rmem) -> 4096 262144 16777216"
    echo "  net.ipv4.tcp_wmem:            $(get_sysctl net.ipv4.tcp_wmem) -> 4096 262144 16777216"
    echo "  net.core.default_qdisc:       $(get_sysctl net.core.default_qdisc) -> fq"
    echo "  tcp_congestion_control:       $(get_sysctl net.ipv4.tcp_congestion_control) -> bbr"
    echo "  tcp_slow_start_after_idle:    $(get_sysctl net.ipv4.tcp_slow_start_after_idle) -> 0"
    echo "  tcp_tw_reuse:                 $(get_sysctl net.ipv4.tcp_tw_reuse) -> 1"
    echo "  net.core.netdev_max_backlog:  $(get_sysctl net.core.netdev_max_backlog) -> 5000"
    echo "  net.core.somaxconn:           $(get_sysctl net.core.somaxconn) -> 4096"
    exit 0
fi

if [[ "$ACTION" == "--apply-temp" ]]; then
    mkdir -p "$(dirname "$STATE_FILE")"
    {
        echo "rmem_max: $(get_sysctl net.core.rmem_max)"
        echo "wmem_max: $(get_sysctl net.core.wmem_max)"
        echo "tcp_rmem: $(get_sysctl net.ipv4.tcp_rmem)"
        echo "tcp_wmem: $(get_sysctl net.ipv4.tcp_wmem)"
        echo "default_qdisc: $(get_sysctl net.core.default_qdisc)"
        echo "tcp_congestion_control: $(get_sysctl net.ipv4.tcp_congestion_control)"
        echo "tcp_slow_start_after_idle: $(get_sysctl net.ipv4.tcp_slow_start_after_idle)"
        echo "tcp_tw_reuse: $(get_sysctl net.ipv4.tcp_tw_reuse)"
        echo "netdev_max_backlog: $(get_sysctl net.core.netdev_max_backlog)"
        echo "somaxconn: $(get_sysctl net.core.somaxconn)"
    } > "$STATE_FILE"

    s modprobe tcp_bbr >/dev/null || true
    write_sysctl net.core.rmem_max 16777216 "Network receive buffer"
    write_sysctl net.core.wmem_max 16777216 "Network send buffer"
    write_sysctl net.ipv4.tcp_rmem "4096 262144 16777216" "TCP receive autotune"
    write_sysctl net.ipv4.tcp_wmem "4096 262144 16777216" "TCP send autotune"
    write_sysctl net.core.default_qdisc fq "Default queue discipline"
    write_sysctl net.ipv4.tcp_congestion_control bbr "TCP congestion control"
    write_sysctl net.ipv4.tcp_slow_start_after_idle 0 "TCP slow start after idle"
    write_sysctl net.ipv4.tcp_tw_reuse 1 "TCP TIME_WAIT reuse"
    write_sysctl net.core.netdev_max_backlog 5000 "Network device backlog"
    write_sysctl net.core.somaxconn 4096 "Socket accept backlog"
    echo "OK Applied v0.9-network-efficient temporarily."
    exit 0
fi

if [[ "$ACTION" == "--undo" ]]; then
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "No backup found - nothing to undo."
        exit 0
    fi
    value() { grep "^$1:" "$STATE_FILE" | cut -d: -f2- | xargs; }
    restore() {
        local name="$1" stored="$2"
        [[ "$stored" == "N/A" || -z "$stored" ]] || s sysctl -w "$name=$stored" >/dev/null || true
    }
    restore net.core.rmem_max "$(value rmem_max)"
    restore net.core.wmem_max "$(value wmem_max)"
    restore net.ipv4.tcp_rmem "$(value tcp_rmem)"
    restore net.ipv4.tcp_wmem "$(value tcp_wmem)"
    restore net.core.default_qdisc "$(value default_qdisc)"
    restore net.ipv4.tcp_congestion_control "$(value tcp_congestion_control)"
    restore net.ipv4.tcp_slow_start_after_idle "$(value tcp_slow_start_after_idle)"
    restore net.ipv4.tcp_tw_reuse "$(value tcp_tw_reuse)"
    restore net.core.netdev_max_backlog "$(value netdev_max_backlog)"
    restore net.core.somaxconn "$(value somaxconn)"
    rm -f "$STATE_FILE"
    echo "OK All v0.9-network-efficient settings reverted."
    exit 0
fi

echo "Unknown option: $ACTION"
exit 1
