#!/usr/bin/env bash
# custom bundle — multi-instance game servers from enabled/*.properties
# zabbix-secure-automatic-jmx — Alexander Rydzewski <rydzewski.al@gmail.com>
#
# Scenario walkthrough: docs/SECURE AUTOMATIC JMX  WITH ZABBIX.md §4.4
#
# Standalone discovery script — copy to the host, wire zabbix_sender for TRAP LLD.
# Optional later: __jmx_discovery_load_emit when using zabbix_jmx_discovery aggregator.
#
#   discovery.game-servers.sh --dry-run
#   discovery.game-servers.sh --emit
#
# Each running instance registers:
#   zabbix.jmx.jvm.discovery   → Template App Generic Java Z_J_gw_A_lo
#   zabbix.jmx.game.discovery  → application template (service URL macros)
#
# Expected properties per instance (server.properties style):
#   SERVER_ID=eu1-alpha
#   APP_HOME=/home/game/eu1-alpha
#   PID_FILE=/home/game/eu1-alpha/game.pid   (optional; default ${APP_HOME}/game.pid)
#   jmx.port=9012                            (optional; else cmdline or listen pool)
#   port=8082                                (HTTP / WS port for service checks)
#   wsPath=/game                             (optional URN path)

set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-/etc/game/enabled}"
HOST_NAME="${HOST_NAME:-$(hostname)}"
JMX_PORT_POOL_BEGIN="${JMX_PORT_POOL_BEGIN:-9010}"
JMX_PORT_POOL_LENGTH="${JMX_PORT_POOL_LENGTH:-19}"
JMX_PORT_POOL_END=$((JMX_PORT_POOL_BEGIN + JMX_PORT_POOL_LENGTH))
TRAP_KEY_GAME="${TRAP_KEY_GAME:-zabbix.jmx.game.discovery}"

__json_escape_string() {
    local s=$1 out="" i c
    for ((i = 0; i < ${#s}; i++)); do
        c=${s:i:1}
        case "$c" in
            \\) out+='\\\\' ;;
            \") out+='\\"' ;;
            *)  out+="$c" ;;
        esac
    done
    printf '%s' "$out"
}

__read_properties() {
    local file="$1"
    local line key val
    c_SERVER_ID="" c_APP_HOME="" c_PID_FILE="" c_jmx_port="" c_port="" c_wsPath=""
    while IFS= read -r line; do
        line="${line%%#*}"
        line="${line//\"/}"
        [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]] || continue
        key="${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"
        val="${val%"${val##*[![:space:]]}"}"
        case "$key" in
            SERVER_ID) c_SERVER_ID="$val" ;;
            APP_HOME)  c_APP_HOME="$val" ;;
            PID_FILE)  c_PID_FILE="$val" ;;
            jmx.port)  c_jmx_port="$val" ;;
            port)      c_port="$val" ;;
            wsPath)    c_wsPath="$val" ;;
        esac
    done < "$file"
}

__pid_from_pidfile() {
    local pidfile="$1"
    local pid=""
    [ -r "$pidfile" ] || return 1
    pid="$(tr -d '[:space:]' <"$pidfile")"
    kill -0 "$pid" 2>/dev/null || return 1
    printf '%s' "$pid"
}

__pid_from_pgrep_settings() {
    local config="$1"
    local pid=""
    pid="$(pgrep -f -- "-Dsettings=${config}" 2>/dev/null | head -1)" || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    printf '%s' "$pid"
}

__resolve_pid() {
    local config="$1" pidfile="$2"
    __pid_from_pidfile "$pidfile" || __pid_from_pgrep_settings "$config"
}

__jmx_port_from_cmdline() {
    local cmdline="$1"
    local port
    port=$(printf '%s' "$cmdline" | grep -oE '(com\.sun\.management\.)?jmxremote\.port[=:][0-9]+' | tail -1)
    port="${port##*=}"
    port="${port##*:}"
    [ -n "$port" ] && printf '%s' "$port"
}

__jmx_port_from_listen_pool() {
    local pid="$1"
    local -a pool_ports=()
    local port

    while read -r port; do
        [ -n "$port" ] || continue
        pool_ports+=("$port")
    done < <(
        lsof -a -P -n -p "$pid" -i -s TCP:LISTEN 2>/dev/null |
            grep -Eo ':[0-9]+' | tr -d ':' |
            while read -r port; do
                [ "$port" -ge "$JMX_PORT_POOL_BEGIN" ] &&
                    [ "$port" -le "$JMX_PORT_POOL_END" ] &&
                    printf '%s\n' "$port"
            done | sort -nu
    )
    [ "${#pool_ports[@]}" -eq 1 ] && printf '%s' "${pool_ports[0]}"
}

__resolve_jmx_port() {
    local pid="$1" configured="$2"
    local cmdline port

    [ -n "$configured" ] && { printf '%s' "$configured"; return; }
    cmdline="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null)"
    port="$(__jmx_port_from_cmdline "$cmdline")"
    [ -n "$port" ] && { printf '%s' "$port"; return; }
    __jmx_port_from_listen_pool "$pid"
}

__emit_instance_line() {
    printf 'INSTANCE\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@"
}

__emit_trap_line() {
    printf 'TRAP\t%s\t%s\n' "$@"
}

__build_game_trap_json() {
    local server_id="$1" app_name="$2" app_dir="$3" host="$4" pid="$5" jmx_port="$6" http_port="$7" ws_path="$8"
    printf '{"{#APPDIR}":"%s","{#SERVERID}":"%s","{#APPNAME}":"%s","{#HOST}":"%s","{#PID}":"%s","{#JMXPORT}":"%s","{#HTTPPORT}":"%s","{#WSPATH}":"%s"}' \
        "$(__json_escape_string "$app_dir")" \
        "$(__json_escape_string "$server_id")" \
        "$(__json_escape_string "$app_name")" \
        "$(__json_escape_string "$host")" \
        "$pid" "$jmx_port" "$http_port" \
        "$(__json_escape_string "$ws_path")"
}

__discover_game_servers() {
    local config pid pidfile app_name jmx_port row_json

    [ -d "$CONFIG_DIR" ] || return 0

    while IFS= read -r -d '' config; do
        __read_properties "$config"
        [ -n "$c_SERVER_ID" ] && [ -n "$c_APP_HOME" ] || continue

        pidfile="${c_PID_FILE:-${c_APP_HOME%/}/game.pid}"
        pid="$(__resolve_pid "$config" "$pidfile")" || continue

        jmx_port="$(__resolve_jmx_port "$pid" "$c_jmx_port")" || continue
        app_name="$(basename "${c_APP_HOME%/}")"
        row_json="$(__build_game_trap_json "$c_SERVER_ID" "$app_name" "$c_APP_HOME" "$HOST_NAME" "$pid" "$jmx_port" "${c_port:-0}" "${c_wsPath:-/}")"

        __emit_instance_line "$c_SERVER_ID" "$app_name" "$c_APP_HOME" "$pid" "$jmx_port" "$HOST_NAME"
        __emit_trap_line "$TRAP_KEY_GAME" "$row_json"
    done < <(find "$CONFIG_DIR" -maxdepth 1 \( -type f -o -type l \) -name '*.properties' -print0 2>/dev/null)
}

__print_dry_run() {
    local config pid pidfile app_name jmx_port row_json found=0

    printf '=== game-servers discovery (dry-run) ===\n'
    printf 'CONFIG_DIR=%s HOST=%s JMX pool=%s..%s\n\n' \
        "$CONFIG_DIR" "$HOST_NAME" "$JMX_PORT_POOL_BEGIN" "$JMX_PORT_POOL_END"

    [ -d "$CONFIG_DIR" ] || { printf 'Config dir missing.\n'; return; }

    while IFS= read -r -d '' config; do
        __read_properties "$config"
        pidfile="${c_PID_FILE:-${c_APP_HOME%/}/game.pid}"

        printf '[config] %s\n' "$config"
        [ -n "$c_SERVER_ID" ] && [ -n "$c_APP_HOME" ] || {
            printf '    skip — SERVER_ID or APP_HOME missing\n\n'
            continue
        }

        pid="$(__resolve_pid "$config" "$pidfile")" || {
            printf '    [ ] not running (pidfile %s, no pgrep match)\n\n' "$pidfile"
            continue
        }

        jmx_port="$(__resolve_jmx_port "$pid" "$c_jmx_port")" || {
            printf '    [?] pid %s — JMX port unknown or ambiguous in pool\n\n' "$pid"
            continue
        }

        found=1
        app_name="$(basename "${c_APP_HOME%/}")"
        row_json="$(__build_game_trap_json "$c_SERVER_ID" "$app_name" "$c_APP_HOME" "$HOST_NAME" "$pid" "$jmx_port" "${c_port:-0}" "${c_wsPath:-/}")"

        printf '    [+] %s — pid %s — jmx %s — http %s\n' "$c_SERVER_ID" "$pid" "$jmx_port" "${c_port:-0}"
        printf '    zabbix.jmx.jvm.discovery instance: %s\t%s\t%s\t%s\t%s\t%s\n' \
            "$c_SERVER_ID" "$app_name" "$c_APP_HOME" "$pid" "$jmx_port" "$HOST_NAME"
        printf '    %s: %s\n\n' "$TRAP_KEY_GAME" "$row_json"
    done < <(find "$CONFIG_DIR" -maxdepth 1 \( -type f -o -type l \) -name '*.properties' -print0 2>/dev/null)

    [ "$found" -eq 0 ] && printf 'No running game server instances.\n'
}

__usage() {
    cat <<EOF
$(basename "$0") [--dry-run | --show | --emit]

Multi-instance game servers from ${CONFIG_DIR}/*.properties.
PID: pidfile, then pgrep -f -Dsettings=<config>.
JMX port: jmx.port, then cmdline, then single listener in pool.

  --dry-run, --show   Human-readable preview
  --emit              INSTANCE/TRAP lines for zabbix_jmx_discovery

Environment:
  CONFIG_DIR              default: /etc/game/enabled
  JMX_PORT_POOL_BEGIN     default: 9010
  JMX_PORT_POOL_LENGTH    default: 19
  TRAP_KEY_GAME           default: zabbix.jmx.game.discovery
EOF
}

__main() {
    case "${1:-}" in
        -h|--help) __usage; exit 0 ;;
        --dry-run|--show) __print_dry_run ;;
        --emit) __discover_game_servers ;;
        *)
            echo "Usage: $(basename "$0") [--dry-run | --show | --emit]" >&2
            exit 1
            ;;
    esac
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && __main "$@"
