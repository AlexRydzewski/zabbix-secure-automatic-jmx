#!/usr/bin/env bash
# Install generic Strict Secure JMX / Z_J_gw_A_lo Java monitoring package.
# Run from java-generic/ directory or pass JAVA_GENERIC_ROOT.

set -e

ROOT="${JAVA_GENERIC_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
PREFIX="${PREFIX:-/usr/local}"
ETC_DEFAULT="${ETC_DEFAULT:-/etc/default/zabbix_jvm_discovery}"

install -d "$PREFIX/bin" "$PREFIX/lib/zabbix-jvm-discovery" /etc/zabbix/zabbix_agentd.d

install -m 755 "$ROOT/bin/zabbix_java_gw_adapter" "$PREFIX/bin/"
install -m 755 "$ROOT/bin/zabbix_jvm_discovery" "$PREFIX/bin/"
install -m 644 "$ROOT/lib/jvm-discovery-core.sh" "$PREFIX/lib/zabbix-jvm-discovery/"
install -m 644 "$ROOT/zabbix_agentd.d/zabbix_java_gw_adapter_lo.conf" /etc/zabbix/zabbix_agentd.d/

[ -f "$ETC_DEFAULT" ] || install -m 644 "$ROOT/etc/default/zabbix_jvm_discovery.example" "$ETC_DEFAULT"

echo "Installed zabbix_java_gw_adapter and zabbix_jvm_discovery to $PREFIX"
echo "Set INSTANCE_COLLECTOR in $ETC_DEFAULT before enabling cron"
echo "Import template: $ROOT/template/template_generic_java_z_j_gw_a_lo.yaml"
