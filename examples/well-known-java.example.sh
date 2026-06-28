#!/usr/bin/env bash
# well_known_java bundle — Java apps with well-known default JMX ports.
# Version: 1.0.0
# zabbix-secure-automatic-jmx — Alexander Rydzewski <rydzewski.al@gmail.com>
#
# Standalone discovery script — run directly on the host.
# Dry-run:      well-known-java.sh --dry-run
#               well-known-java.sh --show   (alias)
#
# Each match registers:
#   zabbix.jmx.jvm.discovery      → Template App Generic Java Z_J_gw_A_lo
#   zabbix.jmx.<app>.discovery    → application template (assumed on host)
#
# Catalog field order (internal):
#   TRAP_KEY | APP_ID | DEFAULT_JMX_PORT | DISPLAY_NAME | CMDLINE_PATTERN

set -euo pipefail

readonly SCRIPT_VERSION='1.0.0'

SERVER_ID="${SERVER_ID:-$(hostname -s 2>/dev/null || hostname)}"
HOST_NAME="${HOST_NAME:-$(hostname)}"

# TRAP key | app id | JMX port | display name | extended-regex for cmdline (optional match)
DEFAULT_JMX_PORT_CATALOG=(
    'zabbix.jmx.cassandra.discovery|cassandra|7199|Apache Cassandra|cassandra|org\.apache\.cassandra'
    'zabbix.jmx.kafka.discovery|kafka|9999|Apache Kafka|kafka\.Kafka|kafka-server'
    'zabbix.jmx.tomcat.discovery|tomcat|8004|Apache Tomcat|catalina|tomcat|org\.apache\.catalina'
    'zabbix.jmx.activemq.discovery|activemq|1099|Apache ActiveMQ|activemq|org\.apache\.activemq'
    'zabbix.jmx.elasticsearch.discovery|elasticsearch|9010|Elasticsearch|elasticsearch'
    'zabbix.jmx.hbase.discovery|hbase|10101|Apache HBase|hbase|org\.apache\.hadoop\.hbase'
    'zabbix.jmx.solr.discovery|solr|18983|Apache Solr|solr|org\.apache\.solr'
    'zabbix.jmx.jetty.discovery|jetty|1099|Eclipse Jetty|jetty|org\.eclipse\.jetty'
)

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

__java_pid_listening_on_port() {
    local port="$1"
    local pid=""

    if command -v lsof >/dev/null 2>&1; then
        pid="$(lsof -n -P -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | head -1)"
    fi
    if [ -z "$pid" ] && command -v ss >/dev/null 2>&1; then
        pid="$(ss -ltnp "sport = :$port" 2>/dev/null | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | head -1)"
    fi
    [ -n "$pid" ] || return 1

    case "$(tr '\0' ' ' <"/proc/$pid/comm" 2>/dev/null)" in
        java|javaw) printf '%s' "$pid" ;;
        *) return 1 ;;
    esac
}

__process_working_directory() {
    local pid="$1"
    readlink -f "/proc/$pid/cwd" 2>/dev/null || echo "/"
}

__process_cmdline_lowercase() {
    local pid="$1"
    tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | tr '[:upper:]' '[:lower:]'
}

__cmdline_matches_pattern() {
    local cmdline="$1"
    local pattern="$2"
    grep -qE "$pattern" <<< "$cmdline"
}

__parse_catalog_entry() {
    local entry="$1" rest
    IFS='|' read -r CATALOG_TRAP_KEY CATALOG_APP_ID CATALOG_JMX_PORT CATALOG_DISPLAY_NAME rest <<< "$entry"
    CATALOG_CMDLINE_PATTERN="$rest"
}

__build_instance_trap_json() {
    local app_dir="$1" server_id="$2" app_id="$3" host="$4" pid="$5" jmx_port="$6" display_name="$7"
    printf '{"{#APPDIR}":"%s","{#SERVERID}":"%s","{#APPNAME}":"%s","{#HOST}":"%s","{#PID}":"%s","{#JMXPORT}":"%s","{#APPID}":"%s","{#DISPLAYNAME}":"%s"}' \
        "$(__json_escape_string "$app_dir")" \
        "$(__json_escape_string "$server_id")" \
        "$(__json_escape_string "$app_id")" \
        "$(__json_escape_string "$host")" \
        "$pid" \
        "$jmx_port" \
        "$(__json_escape_string "$app_id")" \
        "$(__json_escape_string "$display_name")"
}

__emit_instance_line() {
    local server_id="$1" app_name="$2" app_dir="$3" pid="$4" jmx_port="$5" host="$6"
    printf 'INSTANCE\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$server_id" "$app_name" "$app_dir" "$pid" "$jmx_port" "$host"
}

__emit_trap_line() {
    local trap_key="$1" row_json="$2"
    printf 'TRAP\t%s\t%s\n' "$trap_key" "$row_json"
}

__discover_java_on_default_ports() {
    local entry pid cmdline app_dir server_id row_json

    for entry in "${DEFAULT_JMX_PORT_CATALOG[@]}"; do
        __parse_catalog_entry "$entry"

        pid="$(__java_pid_listening_on_port "$CATALOG_JMX_PORT")" || continue
        cmdline="$(__process_cmdline_lowercase "$pid")"
        __cmdline_matches_pattern "$cmdline" "$CATALOG_CMDLINE_PATTERN" || continue

        app_dir="$(__process_working_directory "$pid")"
        server_id="${SERVER_ID}:${CATALOG_APP_ID}"
        row_json="$(__build_instance_trap_json "$app_dir" "$server_id" "$CATALOG_APP_ID" "$HOST_NAME" "$pid" "$CATALOG_JMX_PORT" "$CATALOG_DISPLAY_NAME")"

        __emit_instance_line "$server_id" "$CATALOG_APP_ID" "$app_dir" "$pid" "$CATALOG_JMX_PORT" "$HOST_NAME"
        __emit_trap_line "$CATALOG_TRAP_KEY" "$row_json"
    done
}

__print_discovery_dry_run() {
    local entry pid cmdline app_dir server_id row_json found=0

    printf '=== default JMX port discovery (dry-run) ===\n'
    printf 'SERVER_ID=%s HOST=%s\n\n' "$SERVER_ID" "$HOST_NAME"

    for entry in "${DEFAULT_JMX_PORT_CATALOG[@]}"; do
        __parse_catalog_entry "$entry"

        pid="$(__java_pid_listening_on_port "$CATALOG_JMX_PORT")" || {
            printf '[ ] %s — port %s — no Java listener\n' "$CATALOG_DISPLAY_NAME" "$CATALOG_JMX_PORT"
            continue
        }

        cmdline="$(__process_cmdline_lowercase "$pid")"
        if ! __cmdline_matches_pattern "$cmdline" "$CATALOG_CMDLINE_PATTERN"; then
            printf '[?] %s — port %s — pid %s — cmdline mismatch\n' "$CATALOG_DISPLAY_NAME" "$CATALOG_JMX_PORT" "$pid"
            printf '    %s\n' "$cmdline"
            continue
        fi

        found=1
        app_dir="$(__process_working_directory "$pid")"
        server_id="${SERVER_ID}:${CATALOG_APP_ID}"
        row_json="$(__build_instance_trap_json "$app_dir" "$server_id" "$CATALOG_APP_ID" "$HOST_NAME" "$pid" "$CATALOG_JMX_PORT" "$CATALOG_DISPLAY_NAME")"

        printf '[+] %s — port %s — pid %s\n' "$CATALOG_DISPLAY_NAME" "$CATALOG_JMX_PORT" "$pid"
        printf '    zabbix.jmx.jvm.discovery instance: %s\t%s\t%s\t%s\t%s\t%s\n' \
            "$server_id" "$CATALOG_APP_ID" "$app_dir" "$pid" "$CATALOG_JMX_PORT" "$HOST_NAME"
        printf '    %s: %s\n' "$CATALOG_TRAP_KEY" "$row_json"
        printf '\n'
    done

    [ "$found" -eq 0 ] && printf 'No matching well-known Java applications on this host.\n'
}

__usage() {
    cat <<EOF
$(basename "$0") [--dry-run | --show | --emit]

Java applications with default JMX ports (Cassandra, Kafka, Tomcat, …).
TRAP keys: zabbix.jmx.jvm.discovery + zabbix.jmx.<app>.discovery

  --dry-run, --show   Human-readable preview (run this to debug discovery)
  --emit              Machine output: INSTANCE/TRAP lines (tab-separated)

Examples:
  $(basename "$0") --dry-run
  $(basename "$0") --emit

Installed path:
  /usr/local/lib/zabbix-jmx-discovery/well-known-java.sh
EOF
}

__main() {
    case "${1:-}" in
        -V|--version) printf 'well-known-java.sh %s\n' "$SCRIPT_VERSION"; exit 0 ;;
        -h|--help) __usage; exit 0 ;;
        --dry-run|--show) __print_discovery_dry_run ;;
        --emit) __discover_java_on_default_ports ;;
        *)
            echo "Usage: $(basename "$0") [--dry-run | --show | --emit]" >&2
            exit 1
            ;;
    esac
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && __main "$@"
