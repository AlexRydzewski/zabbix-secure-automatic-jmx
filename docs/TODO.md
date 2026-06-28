# TODO & Recommendations

**Document version:** 1.0.0

Short, prioritized notes and recommendations for improving the Z_J_gw_A_lo reference kit.

## P0 — Critical (apply before wide production use)
- Ensure the Zabbix template is installed by `install.sh` (add `install -m 644 "$ROOT/template/template_generic_java_z_j_gw_a_lo.yaml" "$DOC_DIR/").
- Harden JSON escaping in `bin/zabbix_java_gw_adapter`: escape control characters (`\n`, `\r`, `\t`) and consider Unicode escapes for non-ASCII input.
- Validate all external inputs where appropriate (already added: `__valid_host`, `__valid_port`) and add unit tests for these validators.

## P1 — High priority (stability & observability)
- Add timeouts or safe wrappers around `lsof`/`ss` calls in discovery scripts to avoid hangs on unusual platforms. Alternatively, go away from third utilities and use /proc.
- Add an uninstall script or documented uninstall steps for files created by `install.sh`.
- Document error handling and common failure modes (gateway down, JMX auth enabled, timeouts, ambiguous port resolution).

## P2 — Medium priority (polish & maintainability)
- Add a small test suite (`tests/`) using `bats` or shell harness to cover `__esc_json`, `__build_instance_trap_json`, and discovery `--dry-run` outputs.
- Consider packaging (RPM/DEB) or simple tarball installer for reproducible host installs.
- Add optional syslog integration or a `--log` flag for discovery scripts to ease debugging in production.

## Future / Nice-to-have
- Implement the aggregator sketch as an optional component (one cron entry to consume `--emit` output, dedupe by PID/JMX port, ordered plugins).
- Provide a small monitoring dashboard or template that alerts when discovery TRAPs stop appearing for a host.

## Quick notes for maintainers
- Keep `docs/SECURE AUTOMATIC JMX  WITH ZABBIX.md` as the canonical source describing scope ("not a framework yet").
- When changing escaping rules, update `docs/zabbix_java_gw_adapter-examples.md` with examples showing required escaping layers for templates and item keys.

---
Generated on 2026-06-28
