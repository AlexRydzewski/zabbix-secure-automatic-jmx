# Example INSTANCE_COLLECTOR for zabbix_jvm_discovery.
# Copy to /usr/local/lib/your-app/collect-instances.sh and set INSTANCE_COLLECTOR in
# /etc/default/zabbix_jvm_discovery.
#
# Must define: jvm_discovery_collect_instances()

JMX_PORT_POOL_BEGIN="${JMX_PORT_POOL_BEGIN:-9010}"
JMX_PORT_POOL_LENGTH="${JMX_PORT_POOL_LENGTH:-9}"

__example_jmx_port_from_pid() {
    local pid="$1"
    local port
    for port in $(lsof -a -P -n -p "$pid" -i -s TCP:LISTEN 2>/dev/null | grep -Eo ':[0-9]+'); do
        [ "${port/:}" -ge "$JMX_PORT_POOL_BEGIN" ] &&
            [ "${port/:}" -le $((JMX_PORT_POOL_BEGIN + JMX_PORT_POOL_LENGTH)) ] &&
            { echo "${port/:}"; return 0; }
    done
    echo "0"
}

jvm_discovery_collect_instances() {
    local pid jmx_port

    # Replace with your process discovery (pgrep, PID files, systemd, etc.).
    for pid in $(pgrep -f 'your\.application\.MainClass' 2>/dev/null); do
        jmx_port="$(__example_jmx_port_from_pid "$pid")"
        [ "$jmx_port" = "0" ] && continue

        jvm_discovery_add_instance \
            "server-1" \
            "my-app" \
            "/opt/my-app" \
            "$pid" \
            "$jmx_port"
    done
}
