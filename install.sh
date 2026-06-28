#!/usr/bin/env bash
# Install Secure Automatic JMX Monitoring with Zabbix (Z_J_gw_A_lo).
# zabbix-secure-automatic-jmx — Alexander Rydzewski <rydzewski.al@gmail.com>
# https://github.com/AlexRydzewski/zabbix-secure-automatic-jmx
# Documentation: docs/SECURE AUTOMATIC JMX  WITH ZABBIX.md  |  Repo index: README.md

set -e

ROOT="${PACKAGE_ROOT:-${JAVA_GENERIC_ROOT:-$(cd "$(dirname "$0")" && pwd)}}"
PREFIX="${PREFIX:-/usr/local}"
DOC_DIR="${PREFIX}/share/doc/zabbix-jmx-discovery"
WELL_KNOWN="${PREFIX}/lib/zabbix-jmx-discovery/well-known-java.sh"
MAIN_DOC="SECURE AUTOMATIC JMX  WITH ZABBIX.md"

install -d "$PREFIX/bin" "$PREFIX/lib/zabbix-jmx-discovery" "$DOC_DIR/docs" /etc/zabbix/zabbix_agentd.d

install -m 755 "$ROOT/bin/zabbix_java_gw_adapter" "$PREFIX/bin/"
if [ -f "$ROOT/bin/zabbix_jmx_discovery" ]; then
    install -m 755 "$ROOT/bin/zabbix_jmx_discovery" "$PREFIX/bin/"
    ln -sf zabbix_jmx_discovery "$PREFIX/bin/zabbix_jvm_discovery"
fi
install -m 644 "$ROOT/zabbix_agentd.d/zabbix_java_gw_adapter_lo.conf" /etc/zabbix/zabbix_agentd.d/

install -m 755 "$ROOT/examples/well-known-java.example.sh" "$WELL_KNOWN"

install -m 644 "$ROOT/docs/${MAIN_DOC}" "$DOC_DIR/docs/"
install -m 644 "$ROOT/docs/zabbix_java_gw_adapter-examples.md" "$DOC_DIR/docs/"
install -m 644 "$ROOT/README.md" "$DOC_DIR/"

echo "Installed zabbix_java_gw_adapter to $PREFIX/bin/"
if [ -f "$PREFIX/bin/zabbix_jmx_discovery" ]; then
    echo "  optional aggregator: $PREFIX/bin/zabbix_jmx_discovery (see docs/${MAIN_DOC} §0, §4.0)"
else
    echo "  optional aggregator: not in this package (sketch only — see docs/${MAIN_DOC} §0, §4.0)"
fi
echo "  well-known example:  $WELL_KNOWN  (--dry-run)"
echo "  docs:                $DOC_DIR/docs/${MAIN_DOC}"
echo "  schedule examples:   cron/ and timers/ in repository"
echo "Import template: $ROOT/template/template_generic_java_z_j_gw_a_lo.yaml"
