# Shared JVM TRAP discovery via local zabbix-java-gateway.
# Sourced by zabbix_jvm_discovery; not executed directly.
#
# Instance collector contract (bash file pointed to by INSTANCE_COLLECTOR):
#   jvm_discovery_collect_instances() {
#       jvm_discovery_add_instance SERVER_ID APP_NAME APP_DIR PID JMXPORT [HOST]
#   }

ZABBIX_SENDER="${ZABBIX_SENDER:-/usr/bin/zabbix_sender}"
ZABBIX_AGENT_CONFIG="${ZABBIX_AGENT_CONFIG:-/etc/zabbix/zabbix_agentd.conf}"
ZABBIX_MONITORED_HOST_JMX="${ZABBIX_MONITORED_HOST_JMX:-}"

ZABBIX_DISCOVERY_KEY_JVM="${ZABBIX_DISCOVERY_KEY_JVM:-zabbix.jvm.discovery}"
ZABBIX_DISCOVERY_KEY_GC="${ZABBIX_DISCOVERY_KEY_GC:-zabbix.jmx_jvm_gc.discovery}"
ZABBIX_DISCOVERY_KEY_MP="${ZABBIX_DISCOVERY_KEY_MP:-zabbix.jmx_jvm_mp.discovery}"

_zabbix_jvm_json=()
_zabbix_jmx_jvm_gc_json=()
_zabbix_jmx_jvm_mp_json=()
_json_for_pid=()
_zabbix_jmx_jvm_gc_collected_pid=()
_zabbix_jmx_jvm_mp_collected_pid=()

zabbix_java_gw_adapter=""
jmx_user=""
jmx_pass=""
_jvm_json_only=0

jvm_discovery_load_config() {
    [ -f /etc/default/zabbix_jvm_discovery ] && . /etc/default/zabbix_jvm_discovery

    ZABBIX_MONITORED_HOST_JMX="${ZABBIX_MONITORED_HOST_JMX:-${ZABBIX_MONITORED_HOST:-$(sed -nr 's/^\s+?Hostname=([0-9a-zA-Z.-]+)\s?$/\1/p' "$ZABBIX_AGENT_CONFIG")}}"
    ZABBIX_MONITORED_HOST_JMX="${ZABBIX_MONITORED_HOST_JMX:-$(hostname)}"
}

jvm_discovery_check_adapter() {
    ! find $(test -d /usr/share/zabbix-java-gateway/bin && echo /usr/share/zabbix-java-gateway/bin) /usr/sbin \
        -regex '/.*/zabbix-java-gateway[-0-9\.]+jar' &>/dev/null && return 1
    ! ps --no-header -C java --format cmd | grep -qE 'zabbix-java-gateway[0-9.-]+jar' && return 1

    for conf in /etc/zabbix/zabbix_agentd.d/*java_gw_adapter*.conf; do
        [ -f "$conf" ] || continue
        read -r jmx_user jmx_pass < <(sed -rn 's/^UserParameter=.*\$3\s+([a-zA-Z0-9+-]+)\s+"?([^"]+)"?\s+?\|.*/\1 \2/p' "$conf" 2>/dev/null)
        [ -n "$jmx_user" ] && break
    done

    zabbix_java_gw_adapter="$(command -v zabbix_java_gw_adapter 2>/dev/null)"
    [ -x "$zabbix_java_gw_adapter" ] || zabbix_java_gw_adapter="/usr/local/bin/zabbix_java_gw_adapter"
    [ -x "$zabbix_java_gw_adapter" ]
}

__jvm_jmx_adapter() {
    local jmx_port="$1"
    local key="$2"
    if [ -n "$jmx_user" ]; then
        "$zabbix_java_gw_adapter" localhost "$jmx_port" "$key" "$jmx_user" "$jmx_pass"
    else
        "$zabbix_java_gw_adapter" localhost "$jmx_port" "$key"
    fi
}

__jvm_parse_jmx_discovery() {
    local macro_obj="$1"
    local -n _out_array=$2
    local jmx_port="$3"
    local jmx_pattern="$4"
    local prefix="$5"
    local line line_buffer=""

    [ -z "$jmx_port" ] || [ "$jmx_port" = "0" ] && return 1

    while read -r line; do
        [ -z "$line_buffer" ] && { line_buffer="$line"; continue; }
        _out_array+=("{${prefix},${line},${line_buffer/JMXOBJ/${macro_obj}}}")
        line_buffer=""
    done < <(grep -Eo '("{#JMXOBJ}":"[^"]+"|"{#JMXNAME}":"[^"]+")' \
        < <(__jvm_jmx_adapter "$jmx_port" "jmx.discovery[beans,\\\"${jmx_pattern}\\\"]" | sed -re 's/\\//g'))
}

__jvm_get_gc_mp_discovery() {
    local pid="$1"
    local jmx_port="$2"
    local prefix="$3"

    ! (IFS=$'\n'; echo "${_zabbix_jmx_jvm_gc_collected_pid[*]}") | grep -qFx "${pid}" &&
        __jvm_parse_jmx_discovery JMXGCOBJ _zabbix_jmx_jvm_gc_json "$jmx_port" 'java.lang:type=GarbageCollector,name=*' "$prefix" &&
        _zabbix_jmx_jvm_gc_collected_pid+=("$pid")

    ! (IFS=$'\n'; echo "${_zabbix_jmx_jvm_mp_collected_pid[*]}") | grep -qFx "${pid}" &&
        __jvm_parse_jmx_discovery JMXMPOBJ _zabbix_jmx_jvm_mp_json "$jmx_port" 'java.lang:type=MemoryPool,name=*' "$prefix" &&
        _zabbix_jmx_jvm_mp_collected_pid+=("$pid")
}

jvm_discovery_add_instance() {
    local server_id="$1"
    local app_name="$2"
    local app_dir="$3"
    local pid="$4"
    local jmx_port="$5"
    local host="${6:-$(hostname)}"
    local prefix

    [ -z "$server_id" ] || [ -z "$jmx_port" ] || [ "$jmx_port" = "0" ] && return 0
    (IFS=$'\n'; echo "${_json_for_pid[*]}") | grep -qFx "$pid" && return 0

    prefix="\"{#APPDIR}\":\"${app_dir}\",\"{#SERVERID}\":\"${server_id}\",\"{#APPNAME}\":\"${app_name}\",\"{#HOST}\":\"${host}\",\"{#PID}\":\"${pid}\",\"{#JMXPORT}\":\"${jmx_port}\""
    _zabbix_jvm_json+=("{${prefix}}")
    _json_for_pid+=("$pid")

    [ -n "$zabbix_java_gw_adapter" ] && __jvm_get_gc_mp_discovery "$pid" "$jmx_port" "$prefix"
}

__jvm_show_json() {
    local -n rows=$1
    printf '{"data":[\n'
    local delim=""
    for row in "${rows[@]}"; do
        printf '%s   %s' "$delim" "$row"
        delim=$',\n'
    done
    echo -e "\n]}"
}

__jvm_send_discovery() {
    local key="$1"
    local -n payload=$2

    [ ${#payload[@]} -eq 0 ] && return 0
    [ "$_jvm_json_only" -eq 1 ] && { echo "$key"; __jvm_show_json payload; return 0; }

    "$ZABBIX_SENDER" --config "$ZABBIX_AGENT_CONFIG" --host "$ZABBIX_MONITORED_HOST_JMX" \
        -k "$key" -o "$(__jvm_show_json payload)" &>/dev/null
}

jvm_discovery_send_all() {
    __jvm_send_discovery "$ZABBIX_DISCOVERY_KEY_JVM" _zabbix_jvm_json
    __jvm_send_discovery "$ZABBIX_DISCOVERY_KEY_GC" _zabbix_jmx_jvm_gc_json
    __jvm_send_discovery "$ZABBIX_DISCOVERY_KEY_MP" _zabbix_jmx_jvm_mp_json
}
