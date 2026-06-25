# Strict Secure JMX monitoring with Zabbix

**Technical pattern:** `Z_J_gw_A_lo` (Zabbix + Java gateway + Active agent + localhost).

This document is the canonical method description for the **generic JVM monitoring package** in this repository. Application integrations (instance collectors, app-specific Zabbix templates) live in separate project repos and should link here.

---

## Purpose

**Strict Secure JMX monitoring with Zabbix** is the standard approach for Java applications when:

* JMX is bound to **localhost only** (recommended for security);
* one physical host may run **several JVM instances**;
* metrics must be collected **without exposing JMX** on a network-reachable address.

Use this page as the **general reference**. Product-specific details (init scripts, business JMX beans, trap key prefixes) belong in application wiki pages that link back here.

---

## Problem

### Why stock Zabbix JMX does not fit

| Fact | Consequence |
|------|-------------|
| `zabbix-java-gateway` is **passive** | The Zabbix server connects to the gateway; the gateway connects to the application JMX port. |
| Production JVMs use `jmxremote.local.only=true` | JMX accepts connections only on the application host (loopback). |
| Remote pollers cannot safely use localhost JMX | Server-side JMX items cannot reach `127.0.0.1` on a remote application host. |

Opening JMX on `0.0.0.0` or on the host's public IP is a **security risk** and is **not** the chosen approach.

### Additional complications

* **Multiple JVMs** on one host — each needs its own JMX port and discovery metadata.
* **GC and memory pool names vary** (CMS, G1, ZGC, …) — templates must not hardcode collector or pool names.
* **Application-specific JMX beans** (business metrics) are separate from generic JVM metrics.

---

## Solution overview

All JMX access stays **on the application host**. Metrics leave the host through the **Zabbix agent** (active checks and TRAP discovery).

```
┌─────────────────────────────────────────────────────────────────┐
│ Application host                                                │
│                                                                 │
│  ┌─────────────┐   localhost    ┌──────────────────────┐       │
│  │ Java app(s) │◄── JMX :901x ───│ zabbix-java-gateway  │       │
│  │ local.only  │                  │ :10052               │       │
│  └─────────────┘                  └──────────┬───────────┘       │
│                                              │ gateway protocol  │
│                                   ┌──────────▼───────────┐       │
│                                   │ zabbix_java_gw_adapter│       │
│                                   └──────────┬───────────┘       │
│                                              │ UserParameter     │
│                                   ┌──────────▼───────────┐       │
│                                   │ zabbix-agent (active) │       │
│                                   └──────────┬───────────┘       │
│                                              │                   │
│  ┌──────────────────────┐                   │                   │
│  │ zabbix_jvm_discovery │── zabbix_sender ──┘ (TRAP LLD)        │
│  │ + INSTANCE_COLLECTOR │                                       │
│  └──────────────────────┘                                       │
└─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                           Zabbix server
```

**Result:** full JMX visibility for monitoring, **no** JMX port open to the network.

---

## Architecture

### Metric collection path (active checks)

1. Zabbix server schedules an **active** item, e.g. `z_java_gw_adapter_lo[{#JMXPORT},"jmx[…]"]`.
2. `zabbix-agent` runs the UserParameter → `zabbix_java_gw_adapter`.
3. The adapter speaks the **Zabbix Java gateway binary protocol** to `localhost:10052`.
4. `zabbix-java-gateway` reads JMX from `localhost:{#JMXPORT}`.
5. JSON result returns to Zabbix; template preprocessing extracts the value.

The same path supports `jmx.discovery[…]` for runtime bean enumeration (GC, memory pools).

**Reference:** [New monitoring possibilities for Java applications in Zabbix 3.4](https://blog.zabbix.com/new-monitoring-possibilities-for-java-applications-in-zabbix-3-4/5972/)

### Discovery path (TRAP / low-level discovery)

```
zabbix_jvm_discovery (cron/timer)
  → INSTANCE_COLLECTOR   (application-specific: find running JVMs, ports, IDs)
  → jvm-discovery-core   (generic: GC/MP via jmx.discovery)
  → zabbix_sender        (TRAP keys → Zabbix LLD rules)
```

Discovery must run **independently** of application start/stop scripts so LLD reflects what is running **now**.

### Layering: generic vs application-specific

| Layer | Scope | Provided by |
|-------|--------|-------------|
| **Generic JVM** | Heap, threads, GC, memory pools | **This repository** |
| **Application** | Business MBeans, custom trap keys | Application integration repo |

Only **INSTANCE_COLLECTOR** and **application Zabbix templates** are product-specific.

---

## This repository

| Path | Role |
|------|------|
| `bin/zabbix_java_gw_adapter` | Gateway protocol client (installed to `/usr/local/bin/`) |
| `bin/zabbix_jvm_discovery` | TRAP discovery entry point |
| `lib/jvm-discovery-core.sh` | Shared discovery logic (GC/MP runtime probe) |
| `zabbix_agentd.d/zabbix_java_gw_adapter_lo.conf` | UserParameter for active JMX checks |
| `template/template_generic_java_z_j_gw_a_lo.yaml` | Zabbix template **Template App Generic Java Z_J_gw_A_lo** |
| `etc/default/zabbix_jvm_discovery.example` | Config sample (`INSTANCE_COLLECTOR`, trap keys) |
| `cron/zabbix_jvm_discovery.cron` | Optional cron snippet |
| `examples/instance-collector.example.sh` | Instance collector contract example |
| `install.sh` | Host installation script |

### Default TRAP discovery keys (this package)

| Key | Content |
|-----|---------|
| `zabbix.jvm.discovery` | `{#SERVERID}`, `{#APPNAME}`, `{#JMXPORT}`, `{#PID}`, … |
| `zabbix.jmx_jvm_gc.discovery` | `{#JMXNAME}`, `{#JMXGCOBJ}` |
| `zabbix.jmx_jvm_mp.discovery` | `{#JMXNAME}`, `{#JMXMPOBJ}` |

Override via `/etc/default/zabbix_jvm_discovery`. Application integrations may use prefixed keys; template TRAP rules and `zabbix_sender` keys **must match**.

### Instance collector contract

```bash
jvm_discovery_collect_instances() {
    jvm_discovery_add_instance SERVER_ID APP_NAME APP_DIR PID JMXPORT [HOST]
}
```

See `examples/instance-collector.example.sh`.

---

## JVM / JMX configuration (production)

| Property | Typical value | Notes |
|----------|---------------|--------|
| `com.sun.management.jmxremote` | enabled | Required |
| `com.sun.management.jmxremote.local.only` | `true` | **Local connections only** |
| `com.sun.management.jmxremote.port` | per-instance port | e.g. pool `9010–9019` |
| `com.sun.management.jmxremote.authenticate` | `false` | Acceptable on loopback-only |
| `com.sun.management.jmxremote.ssl` | `false` | TLS optional on localhost |

Monitoring connects to `localhost:{port}` from the **same host**. No `java.rmi.server.hostname` override is required for Zabbix.

---

## Zabbix item patterns

### Generic JVM

```text
z_java_gw_adapter_lo[{#JMXPORT},"jmx[java.lang:type=Memory,HeapMemoryUsage.used]"]
```

Preprocessing: `JSONPath` → `$.data[0].value`

### Application MBean (separate template)

```text
z_java_gw_adapter_lo[{#JMXPORT},"jmx[net.example.app:name=usersOnline,Value]"]
```

### Codahale / Dropwizard metrics

| JMX wrapper type | Common attributes |
|------------------|-------------------|
| **Gauge** | `Value` |
| **Histogram** | `99thPercentile`, `Max`, `Count`, … |
| **Timer** | `99thPercentile`, `Max`, `OneMinuteRate`, … |

GC/MP discovery (do not hardcode collector names):

```text
jmx.discovery[beans,"java.lang:type=GarbageCollector,name=*"]
jmx.discovery[beans,"java.lang:type=MemoryPool,name=*"]
```

---

## Deployment checklist

1. Install `zabbix-java-gateway`; confirm `localhost:10052`.
2. Run `sudo ./install.sh` from this repository.
3. Set `INSTANCE_COLLECTOR` in `/etc/default/zabbix_jvm_discovery`.
4. Install application instance collector (separate integration package).
5. Copy `cron/zabbix_jvm_discovery.cron` to `/etc/cron.d/` (or use systemd timer).
6. `systemctl restart zabbix-agent zabbix-java-gateway`
7. Import `template/template_generic_java_z_j_gw_a_lo.yaml` in Zabbix.
8. Link **Template App Generic Java Z_J_gw_A_lo** to hosts; add app templates as needed.
9. Verify: `zabbix_jvm_discovery --json` lists instances; heap metrics and LLD look correct.

Quick install summary is also in [README.md](../README.md).

---

## Debug access (not for production monitoring)

Production monitoring **does not** use SSH tunnels.

* **On-server:** `jconsole 127.0.0.1:{jmx_port}` works with `local.only=true`.
* **SSH tunnel:** temporary debug JVM profile only (`local.only=false`, fixed `rmi.port`, `java.rmi.server.hostname=127.0.0.1`).

---

## Out of scope (this package)

| Topic | Notes |
|-------|--------|
| Application business metrics | Separate Zabbix template + collector in app repo |
| Non-JMX agent metrics | Separate templates |
| JMX Exporter / Prometheus | Different architecture (HTTP sidecar) |
| Per-method timer MBeans | Use aggregate metrics unless explicit method LLD is designed |

---

## Redmine wiki

Textile version for copy/paste: [docs/redmine/strict-secure-jmx-monitoring-zabbix.textile](redmine/strict-secure-jmx-monitoring-zabbix.textile)

Suggested wiki page: `Strict_Secure_JMX_monitoring_with_Zabbix`

---

## External references

* [Zabbix Java gateway](https://www.zabbix.com/documentation/current/en/manual/concepts/java)
* [JMX LLD examples](https://www.zabbix.com/documentation/current/en/manual/discovery/low_level_discovery/examples/jmx)
* [Zabbix blog: JMX via Java gateway from the agent](https://blog.zabbix.com/new-monitoring-possibilities-for-java-applications-in-zabbix-3-4/5972/)

---

## Glossary

| Term | Meaning |
|------|---------|
| **Strict Secure JMX monitoring with Zabbix** | Localhost-only JMX; metrics via Zabbix agent + local Java gateway |
| **Z_J_gw_A_lo** | Technical pattern: Zabbix + Java gateway + Active agent + localhost |
| **TRAP discovery** | LLD fed by `zabbix_sender`, not server polling |
| **INSTANCE_COLLECTOR** | App script listing running JVMs for discovery |
| **Adapter** | `zabbix_java_gw_adapter` — local gateway protocol client |
| **local.only** | JVM flag restricting JMX to local connections |
