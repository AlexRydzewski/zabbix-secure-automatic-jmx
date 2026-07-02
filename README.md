# Secure Automatic JMX Monitoring with Zabbix

Reference kit for pattern **`Z_J_gw_A_lo`** — Zabbix + Java gateway + **A**ctive agent + **lo**calhost JMX.

| | |
|---|---|
| **Author** | Alexander Rydzewski — [rydzewski.al@gmail.com](mailto:rydzewski.al@gmail.com) |
| **Repository** | [github.com/AlexRydzewski/zabbix-secure-automatic-jmx](https://github.com/AlexRydzewski/zabbix-secure-automatic-jmx) |
| **Tags** | zabbix, jmx, java, monitoring, observability |

Each tracked component has its **own version** (currently **1.0.0** where noted below). Bump only the artifact you change.

## Component versions

| Component | Version |
|-----------|---------|
| `bin/zabbix_java_gw_adapter` | 1.0.0 (`--version`) |
| `bin/well-known-Z_J_gw_A_lo-discovery` | 1.0.12 (`--version`) |
| `zabbix_agentd.d/zabbix_java_gw_adapter_lo.conf` | 1.0.0 |
| `template/template_generic_java_z_j_gw_a_lo.yaml` | 1.0.4 (Zabbix export format 7.4) |
| `install.sh` | 1.0.0 (`--version`) |
| `examples/discovery.game-servers.example.sh` | 1.0.1 (`--version`) |
| `docs/SECURE AUTOMATIC JMX  WITH ZABBIX.md` | 1.0.0 |
| `docs/zabbix_java_gw_adapter-examples.md` | 1.0.0 |
| `cron/zabbix-jmx-discovery.cron` | 1.0.0 |
| `timers/zabbix-jmx-discovery.*.example` | 1.0.0 |
| `docs/TODO.md` | 1.0.0 |

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
2. Run `well-known-Z_J_gw_A_lo-discovery` (installed) or copy/adapt a discovery example from `examples/`; wire `zabbix_sender` for TRAP key `jvm.discovery[Z_J_gw_A_lo]`.
3. Schedule discovery (cron or systemd timer — see `cron/` and `timers/`).
4. Verify:

```bash
well-known-Z_J_gw_A_lo-discovery --dry-run --report
# or from repo before install:
bin/well-known-Z_J_gw_A_lo-discovery --dry-run --report
zabbix_get -s localhost -k 'z_java_gw_adapter_lo[9010,"jmx[java.lang:type=Runtime,Uptime]"]'
```

Full checklist: [base doc §8](<docs/SECURE AUTOMATIC JMX  WITH ZABBIX.md>).

## Documentation

| Document | Purpose |
|----------|---------|
| **[docs/SECURE AUTOMATIC JMX  WITH ZABBIX.md](<docs/SECURE AUTOMATIC JMX  WITH ZABBIX.md>)** | **Base reference** — architecture, discovery, templates, escaping, deployment, auth |
| [docs/zabbix_java_gw_adapter-examples.md](docs/zabbix_java_gw_adapter-examples.md) | Escaping layers and `zabbix_get` cookbook (§6 detail) |
| [docs/TODO.md](docs/TODO.md) | Maintainer backlog and recommendations |

## Repository layout

| Path | Role |
|------|------|
| **Core** | |
| `bin/zabbix_java_gw_adapter` | Gateway client v1.0.0 (**required**) |
| `bin/well-known-Z_J_gw_A_lo-discovery` | Zabbix discovery for well-known Java v1.0.12 (installed to `/usr/local/bin/`) |
| `zabbix_agentd.d/zabbix_java_gw_adapter_lo.conf` | Agent UserParameter v1.0.0 |
| `template/template_generic_java_z_j_gw_a_lo.yaml` | Generic JVM template v1.0.4 (Zabbix 7.4 export) |
| `install.sh` | Install script v1.0.0 |
| **Discovery examples** (copy and adapt) | |
| `examples/discovery.game-servers.example.sh` | Multi-instance game-server pattern v1.0.1 (base doc §4.4) |
| **Schedule examples** | |
| `cron/zabbix-jmx-discovery.cron` | Cron example v1.0.0 |
| `timers/zabbix-jmx-discovery.service.example` | systemd oneshot v1.0.0 |
| `timers/zabbix-jmx-discovery.timer.example` | systemd timer v1.0.0 |
| **Maintainer** | |
| `docs/TODO.md` | Backlog and recommendations v1.0.0 |

`examples/` holds **abstract patterns** you copy and customize (e.g. game servers). Ready-made discovery scripts live in `bin/` and are installed by `install.sh`. See [base doc §4](<docs/SECURE AUTOMATIC JMX  WITH ZABBIX.md>).

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
