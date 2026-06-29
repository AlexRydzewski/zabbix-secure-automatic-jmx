---

## author: Alexander Rydzewski
email: [rydzewski.al@gmail.com](mailto:rydzewski.al@gmail.com)
repo: [https://github.com/AlexRydzewski/zabbix-secure-automatic-jmx](https://github.com/AlexRydzewski/zabbix-secure-automatic-jmx)
document_version: 1.0.0
tags: [zabbix, jmx, java, monitoring, observability]

# Secure Automatic JMX Monitoring with Zabbix — base reference

**Technical pattern:** `Z_J_gw_A_lo` (Zabbix + Java gateway + Active agent + localhost JMX) — [zabbix-secure-automatic-jmx](https://github.com/AlexRydzewski/zabbix-secure-automatic-jmx)

> **Scope.** This is the **only base documentation file** for the repository. For the repo index and quick paths, see [README.md](../README.md). Read **§0** first — this is a **pattern and reference kit**, not a framework yet.

---



## Preamble — state of affairs and purpose

Observe today's JMX monitoring with Zabbix.

The [official Zabbix template](https://git.zabbix.com/projects/ZBX/repos/zabbix/browse/templates/app/generic_java_jmx) has improved significantly, but it still has several gaps.

### Issue 1 — Garbage Collector discovery

It creates only two monitoring items, which is not enough to provide a complete view of GC state. This could be improved by redesigning the discovery rule to identify each known garbage collector individually and create the full set of required monitoring items and triggers for each of them.

The Memory Pool discovery follows the same approach. It's not yet clear whether it needs a more sophisticated implementation or whether extending the existing discovery would be sufficient — the best approach seems to be keeping the generic discovery model but significantly increasing the number of item prototypes, without needing GC-specific discovery logic.

At the moment, the template contains only two JMX discovery rules. It would also be useful to discover the Java version and automatically create version-specific monitoring items where appropriate.

### Issue 2 — Exposed JMX port

The Java application must expose a JMX port so external connections are possible. This creates an unnecessary security concern when the requirement is only to **read** MXBeans, not to manage the JVM.

This can be avoided by installing a dedicated Zabbix Proxy and Zabbix Java Gateway on the monitored host, keeping the JMX connection local-only — though this is rather heavy for simple metric collection. The issue can also be partially addressed with Jolokia or the Prometheus JMX Exporter, but both require changes to the application deployment or JVM startup configuration.

### Issue 3 — Static configuration workflow

Every JVM that should be monitored must be configured explicitly in Zabbix. This means you need to know in advance which Java applications are running on a host and add each one as a separate JMX interface.

When Java applications start dynamically, run as multiple instances, or migrate between hosts, this approach becomes hard to manage and doesn't scale. Automatic discovery of newly started JVMs isn't provided, making configuration harder to maintain.

---



## Naming and terminology

The name reflects the three main goals of the architecture:

- **Secure** — JMX remains accessible only from the local host.
- **Automatic** — running JMX-enabled application instances are discovered automatically.
- **JMX Monitoring** — the suite isn't limited to generic JVM metrics; it can be extended to application-specific JMX beans.



### The pattern name

**Secure Automatic JMX Monitoring with Zabbix** describes the overall suite. Use it when referring to the complete architecture: local JMX transport, discovery engine, discovery plugins, Zabbix templates, and active-agent–based metric delivery.

---



## 0. Not a framework yet — pattern and reference kit

> **Honest status.** This repository is **not a framework** in the sense of a unified, plug-in discovery platform you deploy once and extend cleanly. It is a **documented monitoring pattern**, a **reference adapter**, **Zabbix templates**, and **example discovery scripts** you copy and adapt per product (well-known Java, custom game servers, …).


| Today (what you get)                                | Not yet (what "framework" would imply)                   |
| --------------------------------------------------- | -------------------------------------------------------- |
| Pattern name `Z_J_gw_A_lo` and architecture         | One discovery layer required on every host               |
| `zabbix_java_gw_adapter` + agent UserParameter      | Shared discovery library all scripts use                 |
| Generic JVM Zabbix template + escaping rules        | —                                                        |
| `bin/well-known-Z_J_gw_A_lo-discovery` (installed by `install.sh`) | —                                                        |
| Example scripts in `examples/` (e.g. game-servers) | Registry of bundles, enforced order, dedup in production |
| Future aggregator sketch (not in repo)              | Aggregator as the normal cron entry                      |


**What you do in production today:** install the adapter, template, and `well-known-Z_J_gw_A_lo-discovery` when needed; copy/adapt patterns from `examples/` for custom products; run discovery with `zabbix_sender`; keep product-specific logic in product repos or host-specific copies under `/usr/local/lib/zabbix-jmx-discovery/`.

**What might become a framework later** — once discoveries accumulate on hosts and duplication starts to hurt:

- One cron job / one aggregator (not shipped — see §4.0)
- A common `--emit` protocol (`INSTANCE`/`TRAP` lines), TRAP key naming, dedup by PID/port
- Optional shared helpers instead of copy-paste between scripts
- A documented bundle order (well-known → custom → fallback)

Until that consolidation is implemented and adopted, treat this repo as **reference material**, not a framework you drop in.

---



## 1. Goals


| Goal               | Meaning                                                                            |
| ------------------ | ---------------------------------------------------------------------------------- |
| **Secure**         | JMX stays on localhost (`jmxremote.local.only=true`); no network-exposed JMX port. |
| **Automatic**      | Running instances are discovered on a schedule; Zabbix LLD tracks what exists now. |
| **JMX monitoring** | Generic JVM metrics and application MBeans through the same transport.             |


---



## 2. Core conclusion: discovery is application-specific

Reliable JMX monitoring requires knowing **which process** and **which port** is JMX. That knowledge is almost always **application-specific**.


| Approach                         | Limitation                                                                                           |
| -------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `pgrep` only                     | Finds Java; does not identify JMX among several listen ports.                                        |
| Cmdline `-Djmxremote.port=`      | Not all JVMs expose the port on the command line.                                                    |
| Single global port pool + `lsof` | Helps only when JMX ports fall in a known range and there is **one** listener in that range per PID. |
| Complex production apps          | Need pidfile, config files, `ss`, per-app port ranges, stable `serverId` / `{#IID}`.                 |


**Therefore:**

- This repository provides `zabbix_java_gw_adapter`, **Zabbix templates**, and **standalone discovery script examples** — not a universal collector or a finished framework.
- Operators copy example patterns and implement a **custom discovery script** per application (or product family), each sending instance TRAP LLD via `zabbix_sender`.
- **Zabbix templates** own metric and bean discovery once an instance exists.

---



## 3. Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│ Application host                                                │
│                                                                 │
│   Java app(s) ◄── localhost JMX ──► zabbix-java-gateway :10052  │
│       ▲                                      ▲                  │
│       │                                      │                  │
│   discovery script(s) ──TRAP LLD──►  zabbix-agent (active)      │
│   (standalone; zabbix_sender)                │                  │
│                                               ▼                 │
│                                   zabbix_java_gw_adapter        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                      Zabbix server (templates)
```

Optional later: a **single cron aggregator** over several `--emit` scripts (§4.0).

### Responsibility split


| Layer                                  | Responsibility                                                                         |
| -------------------------------------- | -------------------------------------------------------------------------------------- |
| **Discovery scripts** (required today) | Find instances; send TRAP LLD (`zabbix.jmx.<name>.discovery`); product-specific logic. |
| **Zabbix templates**                   | Instance LLD rules; `jmx.discovery` for GC/MBeans; items; triggers; graphs.            |
| `zabbix_java_gw_adapter`               | Binary protocol to local Java gateway; JSON-escape via `__esc_json`.                   |
| **Zabbix agent**                       | Active checks; UserParameter `z_java_gw_adapter_lo`.                                   |


Discovery scripts do **not** probe JMX beans for metrics. GC, memory pools, and app MBeans are discovered by **template** active `jmx.discovery` rules (child LLD under instance TRAP).

---



## 4. Discovery model



### 4.0 Standalone scripts today; aggregation later

**At this stage**, the required pieces per host are:


| Piece                                          | Role                                                     |
| ---------------------------------------------- | -------------------------------------------------------- |
| `zabbix_java_gw_adapter` + agent UserParameter | Active JMX checks via local gateway                      |
| Zabbix template(s)                             | Instance LLD consumption, GC/MP `jmx.discovery`, metrics |
| Standalone discovery script(s)                 | Find JVMs; `zabbix_sender` TRAP LLD                      |


`examples/` scripts are **abstract patterns** (`--dry-run`, `--emit`) you copy and wire for your product. `bin/well-known-Z_J_gw_A_lo-discovery` is a **ready-made** discovery script installed to `/usr/local/bin/` and sends TRAP LLD by default.

**When discoveries accumulate** (well-known Java plus several custom products on one host, multiple TRAP keys, dedup across bundles), it becomes reasonable to **unify** — a possible future framework direction (§4.0):

- One cron entry instead of many
- Ordered bundle execution and skip-if-already-seen (PID / JMX port)
- Shared TRAP key naming (`zabbix.jmx.<name>.discovery`) and JSON escaping
- Optional wiring: a shared loader consumes `--emit` output from standalone scripts



### 4.1 Minimum instance attributes


| Macro                      | Role                                                              |
| -------------------------- | ----------------------------------------------------------------- |
| **APPID** / `{#SERVERID}`  | Logical instance identity (stable across restarts when possible). |
| **JMXPORT** / `{#JMXPORT}` | Current JMX endpoint on localhost.                                |


Identity and endpoint are separate: the port may change; the app ID should not.

### 4.2 Discovery bundles (execution order) — framework future

Plugins run in order. Each plugin skips PIDs / APPIDs already discovered.


| Order | Plugin type         | Purpose                                                                                              |
| ----- | ------------------- | ---------------------------------------------------------------------------------------------------- |
| 1     | **well_known_java** | Fixed apps with known default JMX ports (Cassandra 7199, Kafka 9999, Tomcat 8004, ActiveMQ 1099, …). |
| 2     | **custom**          | Product-specific scripts — pidfile, properties, port ranges, `ss`.                                   |
| 3     | **any_java**        | Last-resort fallback for unmatched Java PIDs on the host.                                            |




### 4.3 Discovery scripts — ready-made vs examples

**Naming (ready-made and production copies):** `<catalog>-Z_J_gw_A_lo-discovery` — catalog first (what you discover), pattern in the middle, `discovery` last (what the script does). Example: `well-known-Z_J_gw_A_lo-discovery`; custom copies: `game-servers-Z_J_gw_A_lo-discovery`.

| Script | Location | Type | Notes |
| ------ | -------- | ---- | ----- |
| `well-known-Z_J_gw_A_lo-discovery` | `bin/` (installed to `/usr/local/bin/`) | **well_known_java** | `--report` catalog scan; `--show` TRAP JSON; `--dry-run` skips send; default sends. |
| `discovery.game-servers.example.sh` | `examples/` | **custom** (multi-instance) | Copy and adapt — full walkthrough in §4.4. |

Copy `examples/` scripts for custom products; use `bin/well-known-Z_J_gw_A_lo-discovery` as-is when the catalog matches your stack (§4.5).

### 4.4 Game-servers example scenario (`discovery.game-servers.example.sh`)

**When to use:** several JVM game servers on one host, each with its own config and pidfile, JMX ports from a known pool — a multi-instance layout without per-product port-range scans or in-script JMX bean probing.

**Relation to common production patterns:**


| Pattern                 | What this example keeps                                                | What it omits (templates handle it now)                                   |
| ----------------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| Config dir + properties | `enabled/*.properties`, pidfile, `pgrep -f -Dsettings=`, JMX port pool | init-script-only discovery                                                |
| Port-range scan         | pidfile → pgrep fallback, `server.properties` fields                   | full-host `ss` scan, multiple legacy TRAP keys, `jmx.discovery` in script |




#### Host layout

```text
/etc/game/enabled/
  eu1-alpha.properties   → symlink or copy of instance config
  eu1-beta.properties

/home/game/eu1-alpha/
  server.properties       (or same file as enabled/eu1-alpha.properties)
  game.pid
```

Set `CONFIG_DIR` (default `/etc/game/enabled`) to the directory scanned by the script.

#### Properties per instance

Required: `SERVER_ID`, `APP_HOME`. Optional:


| Property   | Role                                                   |
| ---------- | ------------------------------------------------------ |
| `PID_FILE` | Default: `${APP_HOME}/game.pid`                        |
| `jmx.port` | Fixed JMX port if known                                |
| `port`     | HTTP/WebSocket port → `{#HTTPPORT}` for service checks |
| `wsPath`   | Context path → `{#WSPATH}` (default `/`)               |


Example `eu1-alpha.properties`:

```properties
SERVER_ID=eu1-alpha
APP_HOME=/home/game/eu1-alpha
PID_FILE=/home/game/eu1-alpha/game.pid
jmx.port=9012
port=8082
wsPath=/game
```



#### Discovery algorithm (per config file)

1. Parse properties from each `*.properties` in `CONFIG_DIR` (files and symlinks, one level).
2. Skip if `SERVER_ID` or `APP_HOME` is missing.
3. **PID:** read `PID_FILE` and `kill -0`; on failure, `pgrep -f -- "-Dsettings=<absolute-config-path>"`.
4. **JMX port** (first match wins):
  - `jmx.port` from properties
  - `-Dcom.sun.management.jmxremote.port=` / `-Djmxremote.port=` from `/proc/PID/cmdline`
  - exactly **one** TCP `LISTEN` on that PID inside `JMX_PORT_POOL_BEGIN`…`JMX_PORT_POOL_BEGIN+LENGTH` (default `9010`…`9029`)
5. Skip the instance if PID or JMX port cannot be resolved unambiguously.
6. Build TRAP rows and output (see below).

Environment overrides: `CONFIG_DIR`, `JMX_PORT_POOL_BEGIN`, `JMX_PORT_POOL_LENGTH`, `TRAP_KEY_GAME` (default `zabbix.jmx.game.discovery`).

#### TRAP keys and macros

Each running instance produces two logical registrations:


| TRAP key                    | Zabbix template                         | Macros                                                                      |
| --------------------------- | --------------------------------------- | --------------------------------------------------------------------------- |
| `zabbix.jmx.jvm.discovery`  | *Template App Generic Java Z_J_gw_A_lo* | `{#APPDIR}`, `{#SERVERID}`, `{#APPNAME}`, `{#HOST}`, `{#PID}`, `{#JMXPORT}` |
| `zabbix.jmx.game.discovery` | Application template (you provide)      | above + `{#HTTPPORT}`, `{#WSPATH}`                                          |


Generic JVM metrics and GC/memory-pool LLD come from the **template** after `zabbix.jmx.jvm.discovery` — not from the discovery script.

#### Script interface

```bash
discovery.game-servers.example.sh --dry-run   # human-readable; lists each config and match/skip reason
discovery.game-servers.example.sh --emit      # machine output: INSTANCE and TRAP lines (tab-separated)
```

`--emit` line format (for a possible future aggregator):

```text
INSTANCE	SERVER_ID	APP_NAME	APPDIR	PID	JMXPORT	HOST
TRAP	zabbix.jmx.game.discovery	{"{#APPDIR}":"…",…}
```



#### Deploy today (standalone)

1. Copy `examples/discovery.game-servers.example.sh` to the host (e.g. `/usr/local/lib/zabbix-jmx-discovery/discovery.game-servers.sh`).
2. Adjust defaults or set `CONFIG_DIR` / port pool via environment.
3. **Dry-run:** `discovery.game-servers.sh --dry-run` until every expected instance shows `[+]`.
4. **Send TRAP:** add `zabbix_sender` calls in your copy, or parse `--emit` and send each key — the example intentionally stops at `--emit` so you can inspect rows before wiring send.
5. **Cron:** schedule your script (one cron entry per product script; see §4.0).
6. Import and link *Template App Generic Java Z_J_gw_A_lo* plus an application template with LLD rule `zabbix.jmx.game.discovery`.



#### Optional later (aggregation)

When several discovery scripts run on the same host, a future aggregator could consume their `--emit` output for one cron job and PID/port dedup (§4.0).

### 4.5 Common production patterns

**Multi-product discovery script:**

- Arrays of app names, WS port ranges, JMX port ranges.
- Collect via pidfile → `ps` → `ss`; read `server.properties`.
- Multiple TRAP keys (app, service URL, JVM).
- **Remove** in-script `jmx.discovery` / GC probing — templates handle that now.

**Multi-instance init + cron:**

- Init may send discovery on start/stop.
- **Cron** on a standalone discovery script remains authoritative (crash/restart without init).

Use `discovery.game-servers.example.sh` as a starting point when migrating multi-instance hosts to the Z_J_gw_A_lo template model.

---



## 5. Metric collection (templates)

After instance TRAP provides `{#JMXPORT}` (and identity macros):

1. Zabbix schedules **active** items.
2. The agent runs the UserParameter → adapter → Java gateway → `localhost:{#JMXPORT}`.
3. Template preprocessing (`JSONPath`, etc.) extracts values.



### Generic JVM template


| Rule            | Detail                                                                       |
| --------------- | ---------------------------------------------------------------------------- |
| TRAP rule       | `zabbix.jmx.jvm.discovery` — instances only                                  |
| Child LLD       | `jmx.discovery` for GC and memory pools (active, via `z_java_gw_adapter_lo`) |
| Item prototypes | All metrics via `z_java_gw_adapter_lo[{#JMXPORT},"jmx[…]"]`                  |


Import: `template/template_generic_java_z_j_gw_a_lo.yaml`

### Application templates

Separate templates per product: business MBeans, service URLs, custom TRAP keys. Link together with the generic JVM template on the same host.

---



## 6. JMX item keys and escaping

Escaping affects **every** `jmx[bean,attribute]` item and **every** `jmx.discovery[…]` rule — not only GC/MP discovery. Any bean name that contains a comma (GC collectors, memory pools, app MBeans) hits the same problem in item prototypes, triggers, and graphs.

### 6.1 The problem

JMX object names contain **commas** between key properties (`java.lang:name=G1 Young Generation,type=GarbageCollector`, `java.lang:type=MemoryPool,name=Code Cache`, `name=CodeHeap 'non-nmethods'`). Zabbix item keys split UserParameter arguments on commas. The legacy workaround is one quoted `jmx[…]` string as the second parameter (`"$2"`).

**You cannot abandon quote escaping** in `z_java_gw_adapter_lo[…,"jmx[…]"]` items: the Zabbix agent strips one escaping layer when it parses the item key and passes `$2` to the UserParameter. Without `\"` (or `\\"` in the stored key) around the bean, commas inside `jmx[…]` split parameters and the key is corrupted before the adapter runs.

`zabbix_java_gw_adapter` now JSON-escapes the logical key in the gateway message (`__esc_json`). That moves gateway quoting to the **tail** and lets templates use `\\"` (two backslashes before each inner `"`) instead of the older `\\\\\"` (four) — but the **agent key layer remains mandatory** for legacy one-string keys.

### 6.2 Escaping layers (front → tail)

All JMX items use `z_java_gw_adapter_lo` → `zabbix_java_gw_adapter`. One UserParameter, one quoting rule.


| Stage | Where                                   | What you write                                      | Escaping                                                                             |
| ----- | --------------------------------------- | --------------------------------------------------- | ------------------------------------------------------------------------------------ |
| **1** | Zabbix item key / `zabbix_get -k`       | Whole `jmx[…]` or `jmx.discovery[…]` as quoted `$2` | `\\"` before each inner `"` around bean/pattern (mandatory — agent strips one layer) |
| **2** | Bean/pattern content                    | GC names, pool names, `*`, spaces, `'`              | Literal — no extra escapes                                                           |
| **3** | `zabbix_java_gw_adapter` (`__esc_json`) | Gateway JSON `"keys":["…"]`                         | JSON-escape `"` and `\` once (not duplicated in template)                            |


Gateway must see (inside JSON):

```json
"keys":["jmx.discovery[beans,\"*:type=GarbageCollector,name=*\"]"]
```

**Does not work** — single quotes around the pattern (invalid gateway JSON):

```json
"keys":["jmx.discovery[beans,'*:type=GarbageCollector,name=*']"]
```



### 6.3 Item keys and `zabbix_get` examples

UserParameter: `z_java_gw_adapter_lo[*]` → `zabbix_java_gw_adapter localhost $1 "$2" …`

The whole `jmx[…]` / `jmx.discovery[…]` string is `$2`.


| Layer       | Who                                     | What you store in the item key                      | What the adapter receives as `$3` |
| ----------- | --------------------------------------- | --------------------------------------------------- | --------------------------------- |
| **Agent**   | Zabbix item key parser                  | `\\"` before each inner `"` around the bean/pattern | Logical key with real `"`         |
| **Gateway** | `zabbix_java_gw_adapter` (`__esc_json`) | *(nothing in template)*                             | `\"` in JSON `"keys":["…"]`       |


**Logical key** (must arrive at the adapter after agent parsing):

```text
jmx["java.lang:type=MemoryPool,name=CodeHeap 'non-nmethods'",Usage.committed]
```

**Gateway JSON** (built by the adapter):

```json
"keys":["jmx[\"java.lang:type=MemoryPool,name=CodeHeap 'non-nmethods'\",Usage.committed]"]
```

Single quotes inside the pool name (`'non-nmethods'`) are **literal JMX characters** — not JSON string delimiters. Spaces are fine. Only **double quotes** around the bean and **commas** between key properties force the agent-layer escaping. Never use `\'` around pool-name quotes (it breaks `__esc_json`); the `'"'"'` shell idiom is for **single-quoted** `zabbix_get -k` only, not for double-quoted direct `zabbix_java_gw_adapter` args.

> **Info.** Direct CLI failure/success matrix: `docs/zabbix_java_gw_adapter-examples.md` §1.2.1.



#### `zabbix_get` — discovery (bash, outer single quotes)

```bash
zabbix_get -s app-host.example -k \
  'z_java_gw_adapter_lo[1090,"jmx.discovery[beans,\\"*:type=GarbageCollector,name=*\\"]"]'
```



#### `zabbix_get` — hard case: comma, spaces, single quotes in pool name

Pool `CodeHeap 'non-nmethods'` — shell idiom `'"'"'` embeds `'` inside a single-quoted `-k` string:

```bash
zabbix_get -s app-host.example -k \
  'z_java_gw_adapter_lo[1090,"jmx[\\"java.lang:type=MemoryPool,name=CodeHeap '"'non-nmethods'"'\\",Usage.committed]"]'
```



#### Template YAML (same escaping as `zabbix_get` above)

```yaml
# LLD item prototype ({#JMXOBJ} contains commas)
key: 'z_java_gw_adapter_lo[{#JMXPORT},"jmx[\\"{#JMXOBJ}\\",Usage.committed]"]'

# GC discovery rule
key: 'z_java_gw_adapter_lo[{#JMXPORT},"jmx.discovery[beans,\\"*:type=GarbageCollector,name=*\\"]"]'

# Fixed pool with spaces in name
key: 'z_java_gw_adapter_lo[{#JMXPORT},"jmx[\\"java.lang:type=MemoryPool,name=Code Cache\\",Usage.used]"]'
```

Use `\\"` (two backslashes + quote) in exported template keys — not the older `\\\\\"` four-backslash form. The adapter now performs gateway JSON escaping.

**Does not work** — no escapes (agent splits on commas):

```bash
zabbix_get -s HOST -k 'z_java_gw_adapter_lo[1090,"jmx.discovery[beans,"*:type=GarbageCollector,name=*"]"]'
```

**Does not work** — single quotes as JSON/pattern delimiters (gateway expects `\"`):

```bash
zabbix_get -s HOST -k "z_java_gw_adapter_lo[1090,\"jmx.discovery[beans,'*:type=GarbageCollector,name=*']\"]"
```


| Approach                                 | Agent-key escapes?        | Notes                              |
| ---------------------------------------- | ------------------------- | ---------------------------------- |
| `z_java_gw_adapter_lo[…,"jmx[\\"…\\"]"]` | **Yes**, `\\"`            | Only style — all items             |
| Old templates with `\\\\\"`              | **Yes** (4 → 2 reducible) | Migrate to `\\"` when re-exporting |




### 6.4 LLD preprocessing (GC / MemoryPool discovery rules)

Gateway response unwrap only — no `{#JMXOBJ_PIPE}` macro:

```javascript
var o = JSON.parse(value);
var inner = o.data && o.data[0] && o.data[0].value;
if (!inner) return value;
if (typeof inner === 'string') {
  inner = inner.replace(/\\\//g, '/');
  inner = JSON.parse(inner);
}
return JSON.stringify(inner);
```



### 6.5 Template keys

All items in `template_generic_java_z_j_gw_a_lo.yaml` use `z_java_gw_adapter_lo[{#JMXPORT},"jmx[…]"]`. Use `\\"` before inner bean quotes (§6.3). See `docs/zabbix_java_gw_adapter-examples.md` for layer-by-layer examples.

### 6.6 Other options (not implemented here)

- **Custom Zabbix plugin** — maximum control; higher maintenance.

---



## 7. Repository layout


| Path                                              | Track | Version | Role                                               |
| ------------------------------------------------- | ----- | ------- | -------------------------------------------------- |
| `bin/zabbix_java_gw_adapter`                      | yes   | 1.0.0   | Gateway protocol client (**required**)             |
| `bin/well-known-Z_J_gw_A_lo-discovery`              | yes   | 1.0.7   | Zabbix discovery for well-known Java apps          |
| `zabbix_agentd.d/zabbix_java_gw_adapter_lo.conf`  | yes   | 1.0.0   | UserParameter `z_java_gw_adapter_lo`               |
| `template/template_generic_java_z_j_gw_a_lo.yaml` | yes   | 1.0.0   | Generic JVM Zabbix template                        |
| `install.sh`                                      | yes   | 1.0.0   | Install adapter, agent drop-in, well-known script  |
| `examples/discovery.game-servers.example.sh`      | yes   | 1.0.0   | Multi-instance game-server pattern (§4.4)          |
| `cron/zabbix-jmx-discovery.cron`                  | yes   | 1.0.0   | Cron example (`/etc/cron.d/`)                      |
| `timers/zabbix-jmx-discovery.*.example`           | yes   | 1.0.0   | systemd timer + oneshot service example            |
| `docs/SECURE AUTOMATIC JMX WITH ZABBIX.md`        | yes   | 1.0.0   | **This file** — base documentation                 |
| `docs/zabbix_java_gw_adapter-examples.md`         | yes   | 1.0.0   | Escaping cookbook (§6 detail)                      |
| `docs/TODO.md`                                    | yes   | 1.0.0   | Maintainer backlog and recommendations             |
| `README.md`                                       | yes   | —       | Repo index (lists component versions)              |


**Versioning:** each component above carries its **own** version in the file (header, `version` field, or `--version` on scripts). `zabbix_export.version: '7.4'` in the template YAML is the **Zabbix server export format**, not a component version. Bump only the artifacts you change.

---



## 8. Deployment checklist

1. Install `zabbix-java-gateway` on the app host (`localhost:10052`).
2. `sudo ./install.sh` (adapter, `well-known-Z_J_gw_A_lo-discovery`, template import path).
3. Wire **custom discovery** — copy/adapt `examples/discovery.game-servers.example.sh` to `/usr/local/lib/zabbix-jmx-discovery/`; cron per script.
4. `well-known-Z_J_gw_A_lo-discovery --dry-run --report` or `--dry-run --show` — verify instance rows and TRAP JSON before enabling send.
5. Enable schedule: `cron/zabbix-jmx-discovery.cron` or `timers/*.example` (one entry per product script).
6. Restart `zabbix-agent` and `zabbix-java-gateway`.
7. Import the JVM template; link it to the host.
8. Add application template(s) and matching discovery TRAP keys.



### JVM flags (production)


| Property                                    | Value        | Notes                              |
| ------------------------------------------- | ------------ | ---------------------------------- |
| `com.sun.management.jmxremote`              | enabled      |                                    |
| `com.sun.management.jmxremote.local.only`   | `true`       |                                    |
| `com.sun.management.jmxremote.port`         | per instance |                                    |
| `com.sun.management.jmxremote.authenticate` | `false`      | **Production default** — see below |
| `com.sun.management.jmxremote.ssl`          | `false`      | Acceptable with `local.only=true`  |




### JMX authentication and credentials

**Production expectation: no JMX authentication.** This pattern targets **dedicated application hosts** where the only relevant local actors are the app, `zabbix-agent`, and `zabbix-java-gateway` — not extra OS users who must be kept away from JMX. With `jmxremote.local.only=true`, JMX is not exposed on the network; that's the main security control.

> **Do not.** Put JMX usernames or passwords in Zabbix item keys, template macros, or discovery TRAP payloads. The server must not be the credential store for JMX. Native Zabbix JMX (host interface passwords) is a different model — `Z_J_gw_A_lo` deliberately avoids shipping secrets from the server on each poll.


| Threat                               | Mitigation in this pattern                                     |
| ------------------------------------ | -------------------------------------------------------------- |
| Remote JMX access                    | `jmxremote.local.only=true`                                    |
| Credentials in Zabbix DB/UI          | Not used in production default; items use port + `jmx[…]` only |
| Compromised monitoring path off-host | No remote JMX; agent + local gateway only                      |


**If you still need JMX isolated on the host** (other local OS users must not connect to JMX, but monitoring must):

1. Enable JVM JMX auth (`jmxremote.authenticate=true`) with a **read-only monitoring user** (`jmxremote.password.file` + `jmxremote.access.file`).
2. Keep credentials **on the host only** — not in Zabbix templates:
  - a separate file under `/etc/zabbix/zabbix_agentd.d/` or `/etc/zabbix/` with mode `600` (or `640` and group `zabbix` if only the agent must read it)
  - `Include=` that file from agent config
  - optional adapter args 4–5 wired there, never in item keys
3. Accept the limits: **root**, and anyone who can alter agent or JVM config, can still obtain access. This is **local separation**, not protection from the platform administrator.

The sample UserParameter in `zabbix_agentd.d/zabbix_java_gw_adapter_lo.conf` passes **no** credentials. The commented line shows optional auth via a **host-local password file** (mode `600`) — never credentials in Zabbix item keys.

---



## 9. Work focus (recommended)


| Priority | Work                                                                                                              |
| -------- | ----------------------------------------------------------------------------------------------------------------- |
| **1**    | **Zabbix templates** — metrics, `jmx.discovery` LLD, triggers (`z_java_gw_adapter_lo` keys).                      |
| **2**    | **Standalone discovery scripts** — well-known + custom patterns; each sends TRAP via `zabbix_sender`.             |
| **3**    | **Custom scripts per product** — slim legacy scripts (drop in-script bean discovery); templates collect metrics.  |
| **4**    | **Toward a framework** — aggregator, bundle order, dedup; only when script count on a host justifies unification. |


---



## 10. Glossary


| Term                 | Meaning                                                                                 |
| -------------------- | --------------------------------------------------------------------------------------- |
| **Z_J_gw_A_lo**      | Zabbix + Java gateway + Active agent + localhost                                        |
| **Discovery script** | Standalone script that finds instances and sends TRAP LLD                               |
| **Discovery engine** | Optional future aggregator — not part of today's minimum deploy                         |
| **TRAP LLD**         | LLD fed by `zabbix_sender`, not server-side polling; keys `zabbix.jmx.<name>.discovery` |


---



## 11. References

- [Zabbix blog: JMX via Java gateway from the agent](https://blog.zabbix.com/new-monitoring-possibilities-for-java-applications-in-zabbix-3-4/5972/)
- [Zabbix Java gateway](https://www.zabbix.com/documentation/current/en/manual/concepts/java)
- [JMX LLD examples](https://www.zabbix.com/documentation/current/en/manual/discovery/low_level_discovery/examples/jmx)
- Local adapter notes: `docs/zabbix_java_gw_adapter-examples.md`

---

