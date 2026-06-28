#!/usr/bin/env bash
# Install Secure Automatic JMX Monitoring with Zabbix (Z_J_gw_A_lo).
# Version: 1.0.0
# zabbix-secure-automatic-jmx — Alexander Rydzewski <rydzewski.al@gmail.com>
# https://github.com/AlexRydzewski/zabbix-secure-automatic-jmx
# Documentation: docs/SECURE AUTOMATIC JMX  WITH ZABBIX.md  |  Repo index: README.md

set -e

readonly INSTALL_VERSION='1.0.0'

case "${1:-}" in
    -V|--version) printf 'install.sh %s\n' "$INSTALL_VERSION"; exit 0 ;;
esac

ROOT="${PACKAGE_ROOT:-${JAVA_GENERIC_ROOT:-$(cd "$(dirname "$0")" && pwd)}}"
PREFIX="${PREFIX:-/usr/local}"
DOC_DIR="${PREFIX}/share/doc/zabbix-jmx-discovery"
WELL_KNOWN="${PREFIX}/lib/zabbix-jmx-discovery/well-known-java.sh"
MAIN_DOC="SECURE AUTOMATIC JMX  WITH ZABBIX.md"

install -d "$PREFIX/bin" "$PREFIX/lib/zabbix-jmx-discovery" "$DOC_DIR/docs" /etc/zabbix/zabbix_agentd.d

install -m 755 "$ROOT/bin/zabbix_java_gw_adapter" "$PREFIX/bin/"
install -m 644 "$ROOT/zabbix_agentd.d/zabbix_java_gw_adapter_lo.conf" /etc/zabbix/zabbix_agentd.d/

install -m 755 "$ROOT/examples/well-known-java.example.sh" "$WELL_KNOWN"

install -m 644 "$ROOT/docs/${MAIN_DOC}" "$DOC_DIR/docs/"
install -m 644 "$ROOT/docs/zabbix_java_gw_adapter-examples.md" "$DOC_DIR/docs/"
install -m 644 "$ROOT/README.md" "$DOC_DIR/"

echo "Installed zabbix-secure-automatic-jmx components (install.sh $INSTALL_VERSION):"
echo "  zabbix_java_gw_adapter        $("$PREFIX/bin/zabbix_java_gw_adapter" --version 2>/dev/null | awk '{print $2}')"
echo "  zabbix_java_gw_adapter_lo.conf 1.0.0"
echo "  well-known-java.sh            $("$WELL_KNOWN" --version 2>/dev/null | awk '{print $2}')"
echo "  docs/${MAIN_DOC}              1.0.0"
echo "  docs/zabbix_java_gw_adapter-examples.md  1.0.0"
echo "  template (import manually)    Template App Generic Java Z_J_gw_A_lo 1.0.0"
echo "  well-known example:  $WELL_KNOWN  (--dry-run)"
echo "  docs:                $DOC_DIR/docs/${MAIN_DOC}"
echo "  schedule examples:   cron/ and timers/ in repository (each 1.0.0)"
echo "Import template: $ROOT/template/template_generic_java_z_j_gw_a_lo.yaml"
