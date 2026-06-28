# Secure Automatic JMX Monitoring with Zabbix

Reference kit for pattern **`Z_J_gw_A_lo`** — Zabbix + Java gateway + **A**ctive agent + **lo**calhost JMX.

| | |
|---|---|
| **Author** | Alexander Rydzewski — [rydzewski.al@gmail.com](mailto:rydzewski.al@gmail.com) |
| **Repository** | [github.com/AlexRydzewski/zabbix-secure-automatic-jmx](https://github.com/AlexRydzewski/zabbix-secure-automatic-jmx) |
| **Tags** | zabbix, jmx, java, monitoring, observability |

> **Not a framework yet** — a documented **pattern**, reference adapter, Zabbix template, and example discovery scripts you copy and adapt per product. Read **§0** in the [base doc](<docs/SECURE AUTOMATIC JMX  WITH ZABBIX.md>) before deploying.

## Why this exists

Standard Zabbix JMX monitoring expects a **network-exposed JMX port** and **manual per-JVM host interfaces** — awkward for dynamic instances and a security concern when you only need to read MXBeans.

This pattern keeps JMX on **localhost** (`jmxremote.local.only=true`), runs **zabbix-java-gateway** on the app host, discovers instances with **your** scripts + TRAP LLD, and collects metrics through **active** items via `zabbix_java_gw_adapter`. Details and motivation: [base doc](<docs/SECURE AUTOMATIC JMX  WITH ZABBIX.md>) (preamble).

## Architecture (minimal)

```text
Java app ── localhost JMX ──► zabbix-java-gateway :10052
                                    ▲
discovery script ──TRAP LLD──► zabbix-agent ──► zabbix_java_gw_adapter
                                    │
                                    ▼
                            Zabbix server (templates)
```

## Quick start

**Prerequisites on the app host:** `zabbix-agent`, `zabbix-java-gateway` (listening on `localhost:10052`), JVM with `jmxremote.local.only=true`.

```bash
git clone https://github.com/AlexRydzewski/zabbix-secure-automatic-jmx.git
cd zabbix-secure-automatic-jmx
sudo ./install.sh
sudo systemctl restart zabbix-agent zabbix-java-gateway
```

1. Import `template/template_generic_java_z_j_gw_a_lo.yaml` in Zabbix and link to the host.
2. Copy/adapt a discovery example; wire `zabbix_sender` for TRAP key `zabbix.jmx.jvm.discovery`.
3. Schedule discovery (cron or systemd timer — see `cron/` and `timers/`).
4. Verify:

```bash
examples/well-known-java.example.sh --dry-run
zabbix_get -s localhost -k 'z_java_gw_adapter_lo[9010,"jmx[java.lang:type=Runtime,Uptime]"]'
```

Full checklist: [base doc §8](<docs/SECURE AUTOMATIC JMX  WITH ZABBIX.md>).

## Documentation

| Document | Purpose |
|----------|---------|
| **[docs/SECURE AUTOMATIC JMX  WITH ZABBIX.md](<docs/SECURE AUTOMATIC JMX  WITH ZABBIX.md>)** | **Base reference** — architecture, discovery, templates, escaping, deployment, auth |
| [docs/zabbix_java_gw_adapter-examples.md](docs/zabbix_java_gw_adapter-examples.md) | Escaping layers and `zabbix_get` cookbook (§6 detail) |

## Repository layout

| Path | Role |
|------|------|
| **Core** | |
| `bin/zabbix_java_gw_adapter` | Gateway binary-protocol client (**required**) |
| `zabbix_agentd.d/zabbix_java_gw_adapter_lo.conf` | Agent UserParameter `z_java_gw_adapter_lo` |
| `template/template_generic_java_z_j_gw_a_lo.yaml` | Generic JVM template (Zabbix 7.4 export) |
| `install.sh` | Install adapter, agent drop-in, well-known example, docs under `/usr/local` |
| **Discovery examples** | |
| `examples/well-known-java.example.sh` | Cassandra, Kafka, Tomcat, ActiveMQ, … — default JMX ports |
| `examples/discovery.game-servers.example.sh` | Multi-instance `enabled/*.properties` pattern (base doc §4.4) |
| **Schedule examples** | |
| `cron/zabbix_jmx_discovery.cron` | `/etc/cron.d/` example — one entry per product script |
| `timers/zabbix-jmx-discovery.service.example` | systemd oneshot |
| `timers/zabbix-jmx-discovery.timer.example` | systemd timer (e.g. every 5 min) |

Example scripts implement `--dry-run` and `--emit`; production copies add **`zabbix_sender`** for instance TRAP LLD. See [base doc §4](<docs/SECURE AUTOMATIC JMX  WITH ZABBIX.md>).

## Production defaults

| Topic | Default |
|-------|---------|
| JMX network | `jmxremote.local.only=true` — no remote JMX |
| JMX auth | `jmxremote.authenticate=false` on dedicated app hosts |
| Credentials | Never in Zabbix item keys; optional host-local file only (base doc §8) |
| Item escaping | `\\"` before inner `"` in keys; adapter `__esc_json` handles gateway JSON (base doc §6) |

## References

- [Zabbix blog: JMX via Java gateway from the agent (2017)](https://blog.zabbix.com/new-monitoring-possibilities-for-java-applications-in-zabbix-3-4/5972/)
- [Zabbix Java gateway documentation](https://www.zabbix.com/documentation/current/en/manual/concepts/java)
- [Official generic Java JMX template](https://git.zabbix.com/projects/ZBX/repos/zabbix/browse/templates/app/generic_java_jmx) (contrast in base doc preamble)

## License

[MIT](LICENSE) — Copyright (c) 2026 Alexander Rydzewski.
