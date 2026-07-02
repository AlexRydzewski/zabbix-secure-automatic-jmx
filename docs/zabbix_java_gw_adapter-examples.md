# zabbix_java_gw_adapter — escaping examples

**Document version:** 1.0.0

**Author:** Alexander Rydzewski — [zabbix-secure-automatic-jmx](https://github.com/AlexRydzewski/zabbix-secure-automatic-jmx)

Companion to **[SECURE AUTOMATIC JMX  WITH ZABBIX.md](<SECURE AUTOMATIC JMX  WITH ZABBIX.md>) §6** — layer-by-layer `zabbix_get`, template keys, and failure cases for `z_java_gw_adapter_lo`.

**Related docs**

- [Zabbix 3.4 — JMX low-level discovery](https://www.zabbix.com/documentation/3.4/en/manual/discovery/low_level_discovery/jmx)
- [Zabbix blog: JMX via Java gateway from the agent](https://blog.zabbix.com/new-monitoring-possibilities-for-java-applications-in-zabbix-3-4/5972/)
- UserParameter: `zabbix_agentd.d/zabbix_java_gw_adapter_lo.conf`

**Prerequisites on the application host**

```bash
systemctl status zabbix-java-gateway   # listening on localhost:10052
ss -ltnp | grep 10052
# JVM: com.sun.management.jmxremote.local.only=true, jmxremote.port=<JMX_PORT>
```

Replace placeholders:

| Placeholder | Example |
|-------------|---------|
| `JMX_PORT` | `1090`, `7199`, `9010` |
| `USER` / `PASS` | only if `jmxremote.authenticate=true` on loopback |

---

## Escaping layers — read this first

These examples are **raw material**: same JMX target shown at each layer so you can see what to type where. Do not copy one line into another layer without translating quotes.

| Layer | Where | What you type | What `zabbix_java_gw_adapter` must get as `<jmx_key>` |
|-------|--------|---------------|------------------------------------------------------|
| **0 — logical** | JMX / gateway semantics | `jmx["java.lang:type=MemoryPool,name=Code Cache",Usage.used]` | *(this string, with real `"` around the bean)* |
| **1 — direct CLI** | `zabbix_java_gw_adapter` on app host | single-quoted `'jmx["…",…]'` (logical key), or double-quoted `"jmx[\"…\",…]"` / `"jmx[\\\"…\\\",…]"` — see §1.2 lab | layer 0 (logical `"` around bean; `'` in pool names **literal**, never `\'`) |
| **2 — agent key (current)** | `zabbix_get -k '…'` / re-exported template | **`\\"`** before each inner `"` around bean/pattern | layer 0 (agent strips one `\` layer) |
| **3 — agent key (legacy YAML)** | `template_generic_java_z_j_gw_a_lo.yaml` as shipped | **`\\\\\"`** before inner `"` | layer 0 *if* agent strips two layers; **migrate to layer 2** after adapter `__esc_json` |
| **4 — gateway JSON** | inside TCP message to `:10052` | *(nothing you type in template)* | built by adapter `__esc_json` → `\"` in `"keys":["…"]` |

**Mandatory agent layer (`z_java_gw_adapter_lo`):** you **cannot** omit inner `\"` / `\\"` entirely — the agent splits UserParameter arguments on commas before the adapter runs.

**After `__esc_json`:** gateway JSON escaping moved to the adapter (layer 4). Templates and `zabbix_get` drop from layer 3 to **layer 2** (`\\"`). Shipped YAML still on layer 3 until re-exported.

Target for all working examples below: discovery pattern  
`*:type=GarbageCollector,name=*`  
or attribute on pool **`CodeHeap 'non-nmethods'`** (comma, spaces, single quotes in the bean name).

---

## Quick reference — GC discovery from Zabbix server

### Layer 0 — logical key (reference only)

```text
jmx.discovery[beans,"*:type=GarbageCollector,name=*"]
jmx["java.lang:type=MemoryPool,name=CodeHeap 'non-nmethods'",Usage.committed]
```

### Layer 1 — direct adapter (same host as JVM)

No agent, no item key — argv3 must be the **logical** key (real `"` around the bean). `__esc_json` builds gateway JSON (layer 4).

**Preferred** — single-quoted arg (no confusion with `\"` / `\\"`):

```bash
zabbix_java_gw_adapter localhost 1090 \
  'jmx.discovery[beans,"*:type=GarbageCollector,name=*"]'

zabbix_java_gw_adapter localhost 1090 \
  'jmx["java.lang:type=MemoryPool,name=CodeHeap '"'"'non-nmethods'"'"'",Usage.committed]' | jq .
```

Double-quoted arg (bash turns `\"` → `"` in argv3):

```bash
zabbix_java_gw_adapter localhost 1090 \
  "jmx[\"java.lang:type=MemoryPool,name=CodeHeap 'non-nmethods'\",Usage.committed]" | jq .
```

See **§1.2** for auth, pre-`__esc_json` adapter, and failure modes verified on `eu2`.

### Layer 2 — `zabbix_get` / template (current — works with adapter `__esc_json`)

**`\\"`** (two backslashes + quote) before each inner `"` around the bean/pattern. Verified on `app-host.example`:

```bash
# GC discovery
zabbix_get -s app-host.example -k \
  'z_java_gw_adapter_lo[1090,"jmx.discovery[beans,\\"*:type=GarbageCollector,name=*\\"]"]' \
  | sed -re 's/\\//g' -e 's/\{?\"data\":\[\{\"value\":\"//' \
        -e 's/(\{|\}\],)\"response\":\"success\"[,\}]//g' -e 's/\}\]\}\"\}\]\}/\}\]\}/' | jq

# Hard case — comma, spaces, single quotes in pool name (shell '"'"' for embedded ')
zabbix_get -s app-host.example -k \
  'z_java_gw_adapter_lo[1090,"jmx[\\"java.lang:type=MemoryPool,name=CodeHeap '"'non-nmethods'"'\\",Usage.committed]"]' | jq .
```

Template item (same escaping as `zabbix_get` above):

```text
z_java_gw_adapter_lo[{#JMXPORT},"jmx[\\"{#JMXOBJ}\\",Usage.committed]"]
z_java_gw_adapter_lo[{#JMXPORT},"jmx.discovery[beans,\\"*:type=GarbageCollector,name=*\\"]"]
```

### Layer 3 — legacy shipped template / old copy-paste (`\\\\\"`)

Still present in `template/template_generic_java_z_j_gw_a_lo.yaml`. Four backslashes before inner `"` — needed when the adapter did **not** JSON-escape and gateway quoting was duplicated in the item key. **Re-export with layer 2** (`\\"`) when using current `zabbix_java_gw_adapter` with `__esc_json`.

```bash
# Old zabbix_get style (four backslashes inside single-quoted -k)
zabbix_get -s app-host.example -k \
  'z_java_gw_adapter_lo[1090,"jmx.discovery[beans,\\\\\"*:type=GarbageCollector,name=*\\\\\"]"]' \
  | sed -re 's/\\//g' -e 's/\{?\"data\":\[\{\"value\":\"//' \
        -e 's/(\{|\}\],)\"response\":\"success\"[,\}]//g' -e 's/\}\]\}\"\}\]\}/\}\]\}/' | jq

# As exported in YAML (what you see in the template file)
# key: 'z_java_gw_adapter_lo[{#JMXPORT},"jmx.discovery[beans,\\\\\"*:type=GarbageCollector,name=*\\\\\"]"]'
# key: 'z_java_gw_adapter_lo[{#JMXPORT},"jmx[\\\\\"{#JMXOBJ}\\\\\",Usage.committed]"]'
```

Compare layer 2 vs 3 for the same discovery — only the backslash count in the agent key changes; logical JMX and gateway payload (via `__esc_json`) should match after migration.

### Does not work — common mistakes

**No agent-layer escapes** — inner `"` breaks `$2` on commas:

```bash
zabbix_get -s app-host.example -k 'z_java_gw_adapter_lo[1090,"jmx.discovery[beans,"*:type=GarbageCollector,name=*"]"]'
```

**Single quotes as pattern delimiters** — gateway JSON invalid (pattern must use `"`, not `'`):

```bash
zabbix_get -s app-host.example -k "z_java_gw_adapter_lo[1090,\"jmx.discovery[beans,'*:type=GarbageCollector,name=*']\"]"
# gateway sees: "keys":["jmx.discovery[beans,'*:type=GarbageCollector,name=*']"]  ← wrong
```

**Layer 1 quoting pasted into layer 2** — direct-adapter `'jmx["bean",attr]'` is not a valid `zabbix_get` key as-is; translate to layer 2 (`\\"` before inner `"`).

### Unwrap gateway envelope (`jq`) — layer 2 discovery

```bash
zabbix_get -s app-host.example -k \
  'z_java_gw_adapter_lo[1090,"jmx.discovery[beans,\\"*:type=GarbageCollector,name=*\\"]"]' \
  | jq -r '.data[0].value' | sed 's/\\//g' | jq .
```

Or one `jq` chain if `fromjson` accepts the inner string on your jq version:

```bash
zabbix_get -s app-host.example -k \
  'z_java_gw_adapter_lo[1090,"jmx.discovery[beans,\\"*:type=GarbageCollector,name=*\\"]"]' \
  | jq -r '.data[0].value' | jq -R 'fromjson'
```

Expected output (G1 JVM example):

```json
{
  "data": [
    {
      "{#JMXOBJ}": "java.lang:name=G1 Young Generation,type=GarbageCollector",
      "{#JMXDOMAIN}": "java.lang",
      "{#JMXNAME}": "G1 Young Generation",
      "{#JMXTYPE}": "GarbageCollector"
    },
    {
      "{#JMXOBJ}": "java.lang:name=G1 Old Generation,type=GarbageCollector",
      "{#JMXDOMAIN}": "java.lang",
      "{#JMXNAME}": "G1 Old Generation",
      "{#JMXTYPE}": "GarbageCollector"
    }
  ]
}
```

Memory pools — same unwrap; use MemoryPool pattern in the `-k` key:

```bash
zabbix_get -s app-host.example -k \
  'z_java_gw_adapter_lo[1090,"jmx.discovery[beans,\\"*:type=MemoryPool,name=*\\"]"]' \
  | jq -r '.data[0].value' | sed 's/\\//g' | jq .
```

Same target via legacy agent key — **layer 2** vs **layer 3**:

```bash
# layer 2 (current)
zabbix_get -s app-host.example -k \
  'z_java_gw_adapter_lo[1090,"jmx.discovery[beans,\\"*:type=MemoryPool,name=*\\"]"]' \
  | sed -re 's/\\//g' -e 's/\{?\"data\":\[\{\"value\":\"//' \
        -e 's/(\{|\}\],)\"response\":\"success\"[,\}]//g' -e 's/\}\]\}\"\}\]\}/\}\]\}/' | jq

# layer 3 (old shipped template)
zabbix_get -s app-host.example -k \
  'z_java_gw_adapter_lo[1090,"jmx.discovery[beans,\\\\\"*:type=MemoryPool,name=*\\\\\"]"]' \
  | sed -re 's/\\//g' -e 's/\{?\"data\":\[\{\"value\":\"//' \
        -e 's/(\{|\}\],)\"response\":\"success\"[,\}]//g' -e 's/\}\]\}\"\}\]\}/\}\]\}/' | jq
```

---

## 1. Direct adapter (same host as JVM)

Syntax:

```bash
/usr/local/bin/zabbix_java_gw_adapter <host> <jmx_port> <jmx_key> [username] [password]
```

Gateway is always `localhost:10052` (hardcoded). `<host>` is the JMX target — use `localhost` with `jmxremote.local.only=true`.

### 1.1 Simple attribute (heap used)

```bash
JMX_PORT=1090

/usr/local/bin/zabbix_java_gw_adapter localhost "$JMX_PORT" \
  'jmx["java.lang:type=Memory",HeapMemoryUsage.used]'
```

With JMX auth:

```bash
/usr/local/bin/zabbix_java_gw_adapter localhost "$JMX_PORT" \
  'jmx["java.lang:type=Memory",HeapMemoryUsage.used]' USER PASS
```

Pretty-print JSON:

```bash
/usr/local/bin/zabbix_java_gw_adapter localhost "$JMX_PORT" \
  'jmx["java.lang:type=Memory",HeapMemoryUsage.used]' | jq .
```

### 1.2 Memory pool with special characters in the name

Pool **`CodeHeap 'non-nmethods'`** — comma, spaces, and **literal single quotes** in the JMX bean name. Target attribute: `Usage.committed`.

#### 1.2.1 Direct CLI quoting lab (`eu2`, with JMX auth)

Verified on production host. Same port/user/pass; only the **third-argument quoting** changes.

| # | Command (abbrev.) | Result |
|---|-------------------|--------|
| A | Pre-`__esc_json` adapter (`zabbix_java_gw_adapter2`): `"jmx[\"…CodeHeap 'non-nmethods'…\",Usage.committed]"` | **OK** — `value: "3342336"` |
| B | Current adapter + `\'` around pool quotes | **FAIL** — gateway JSON broken (`Unterminated array…`) |
| C | Current adapter + `'"'"'` shell idiom inside double-quoted arg | **Bad** — `response: success` but JMX `error` (truncated bean name) |
| D | Current adapter + `\\\"` around bean `"` + literal `'` in pool name | **OK** — `value: "3342336"` |

**A — old adapter without `__esc_json`** (historical / `adapter2` on host):

```bash
# argv3 after bash: jmx["java.lang:type=MemoryPool,name=CodeHeap 'non-nmethods'",Usage.committed]
zabbix_java_gw_adapter2 localhost 1090 \
  "jmx[\"java.lang:type=MemoryPool,name=CodeHeap 'non-nmethods'\",Usage.committed]" \
  admin 'Pi31415926!' | jq
```

**B — do not escape single quotes with backslash** — `\'` puts `\` into argv3; `__esc_json` doubles it and breaks the JSON body:

```bash
zabbix_java_gw_adapter localhost 1090 \
  "jmx[\"java.lang:type=MemoryPool,name=CodeHeap \'non-nmethods\'\",Usage.committed]" \
  admin 'Pi31415926!' | jq
# {"response":"failed","error":"Unterminated array at character 150 of {\"request\":\"java gateway jmx\"…"}
```

**C — do not reuse the `zabbix_get` `'"'"'` trick in a double-quoted direct CLI arg** (that idiom is for single-quoted `-k '…'` only):

```bash
zabbix_java_gw_adapter localhost 1090 \
  "jmx[\\\"java.lang:type=MemoryPool,name=CodeHeap '"'non-nmethods'"\\\",Usage.committed]" \
  admin 'Pi31415926!' | jq
# {"response":"success","data":[{"error":"java.lang:type=MemoryPool,name=CodeHeap 'non-nmethods"}]}
```

**D — current adapter, verified** — `\\\"` in bash double quotes → `\"` in argv3; pool `'…'` stays literal:

```bash
zabbix_java_gw_adapter localhost 1090 \
  "jmx[\\\"java.lang:type=MemoryPool,name=CodeHeap 'non-nmethods'\\\",Usage.committed]" \
  admin 'Pi31415926!' | jq
# {"response":"success","data":[{"value":"3342336"}]}
```

**Also works (logical argv3)** — single-quoted third arg or `"jmx[\"…'…'…\",attr]"` (same as row A argv3; `__esc_json` emits correct gateway JSON):

```bash
zabbix_java_gw_adapter localhost 1090 \
  'jmx["java.lang:type=MemoryPool,name=CodeHeap '"'"'non-nmethods'"'"'",Usage.committed]' \
  admin 'Pi31415926!' | jq

zabbix_java_gw_adapter localhost 1090 \
  "jmx[\"java.lang:type=MemoryPool,name=CodeHeap 'non-nmethods'\",Usage.committed]" \
  admin 'Pi31415926!' | jq
```

**Rules for layer 1 (direct CLI)**

| Do | Don't |
|----|-------|
| Literal `'` inside the bean name (`CodeHeap 'non-nmethods'`) | `\'` around pool-name quotes |
| Single-quoted `'jmx["…",…]'` for the logical key | `'"'"'` inside a double-quoted adapter arg |
| Double-quoted `"jmx[\"…\",…]"` → logical argv3 | Copy layer-2 `\\"` from `zabbix_get` into direct CLI without translating |
| Row D `\\\"` form if you always probe from double-quoted bash | Assume row A syntax still applies to pre-`__esc_json` adapters on the same host |

#### 1.2.2 Without auth (quick probe)

```bash
JMX_PORT=1090

zabbix_java_gw_adapter localhost "$JMX_PORT" \
  'jmx["java.lang:type=MemoryPool,name=CodeHeap '"'"'non-nmethods'"'"'",Usage.committed]' | jq .

zabbix_java_gw_adapter localhost "$JMX_PORT" \
  "jmx[\"java.lang:type=MemoryPool,name=Code Cache\",Usage.used]" | jq .
```

### 1.3 JMX discovery — garbage collectors (beans mode, template LLD)

Pattern from [Zabbix JMX LLD docs](https://www.zabbix.com/documentation/3.4/en/manual/discovery/low_level_discovery/jmx).  
Template **JVM GC discovery** uses this key (per `{#JMXPORT}` from `jvm.discovery[Z_J_gw_A_lo]`).

Direct adapter (**layer 1** — note `\"` inside single-quoted arg, not `\\"`):

```bash
JMX_PORT=1090

/usr/local/bin/zabbix_java_gw_adapter localhost "$JMX_PORT" \
  'jmx.discovery[beans,\"*:type=GarbageCollector,name=*\"]'
```

From Zabbix server via agent — **layer 2** (current) and **layer 3** (old template) for the same LLD rule:

```bash
# layer 2 — \\"
zabbix_get -s app-host.example -k \
  'z_java_gw_adapter_lo[1090,"jmx.discovery[beans,\\"*:type=GarbageCollector,name=*\\"]"]' \
  | sed -re 's/\\//g' \
        -e 's/\{?\"data\":\[\{\"value\":\"//' \
        -e 's/(\{|\}\],)\"response\":\"success\"[,\}]//g' \
        -e 's/\}\]\}\"\}\]\}/\}\]\}/' \
  | jq .

# layer 3 — \\\\\" (as in shipped template_generic_java_z_j_gw_a_lo.yaml)
zabbix_get -s app-host.example -k \
  'z_java_gw_adapter_lo[1090,"jmx.discovery[beans,\\\\\"*:type=GarbageCollector,name=*\\\\\"]"]' \
  | sed -re 's/\\//g' \
        -e 's/\{?\"data\":\[\{\"value\":\"//' \
        -e 's/(\{|\}\],)\"response\":\"success\"[,\}]//g' \
        -e 's/\}\]\}\"\}\]\}/\}\]\}/' \
  | jq .
```

Expected LLD JSON (G1 example):

```json
{
  "data": [
    {
      "{#JMXOBJ}": "java.lang:name=G1 Young Generation,type=GarbageCollector",
      "{#JMXDOMAIN}": "java.lang",
      "{#JMXNAME}": "G1 Young Generation",
      "{#JMXTYPE}": "GarbageCollector"
    },
    {
      "{#JMXOBJ}": "java.lang:name=G1 Old Generation,type=GarbageCollector",
      "{#JMXDOMAIN}": "java.lang",
      "{#JMXNAME}": "G1 Old Generation",
      "{#JMXTYPE}": "GarbageCollector"
    }
  ]
}
```

Item prototypes — **layer 0** logical form (what `{#JMXOBJ}` expands to):

```text
jmx["{#JMXOBJ}",CollectionCount]
```

In a template item key that becomes **layer 2** or **layer 3** escaping around `{#JMXOBJ}` (see quick reference above).

### 1.4 JMX discovery — garbage collectors (attributes mode)

```bash
JMX_PORT=1090

/usr/local/bin/zabbix_java_gw_adapter localhost "$JMX_PORT" \
  'jmx.discovery[attributes,\"*:type=GarbageCollector,name=*\"]'
```

Strip escaping and parse with `jq`:

```bash
/usr/local/bin/zabbix_java_gw_adapter localhost "$JMX_PORT" \
  'jmx.discovery[attributes,\"*:type=GarbageCollector,name=*\"]' \
  | sed -re 's/\\//g' \
        -e 's/\{\"data\":\[\{\"value\":\"//' \
        -e 's/\"\}\],\"response\":\"success\"\}//' \
  | jq .
```

Alternative sed (slightly more tolerant of response shape):

```bash
/usr/local/bin/zabbix_java_gw_adapter localhost "$JMX_PORT" \
  'jmx.discovery[attributes,\"*:type=GarbageCollector,name=*\"]' \
  | sed -re 's/\\//g' \
        -e 's/\{?\"data\":\[\{\"value\":\"//' \
        -e 's/(\{|\}\],)\"response\":\"success\"[,\}]//g' \
        -e 's/\}\]\}\"\}\]\}/\}\]\}/' \
  | jq .
```

### 1.5 JMX discovery — memory pools (beans mode, template LLD)

Same pattern as GC (section 1.3). Template **JVM MemoryPool discovery** — compare agent-key layers:

```bash
# layer 2
zabbix_get -s app-host.example -k \
  'z_java_gw_adapter_lo[1090,"jmx.discovery[beans,\\"*:type=MemoryPool,name=*\\"]"]' \
  | sed -re 's/\\//g' \
        -e 's/\{?\"data\":\[\{\"value\":\"//' \
        -e 's/(\{|\}\],)\"response\":\"success\"[,\}]//g' \
        -e 's/\}\]\}\"\}\]\}/\}\]\}/' \
  | jq .

# layer 3
zabbix_get -s app-host.example -k \
  'z_java_gw_adapter_lo[1090,"jmx.discovery[beans,\\\\\"*:type=MemoryPool,name=*\\\\\"]"]' \
  | sed -re 's/\\//g' \
        -e 's/\{?\"data\":\[\{\"value\":\"//' \
        -e 's/(\{|\}\],)\"response\":\"success\"[,\}]//g' \
        -e 's/\}\]\}\"\}\]\}/\}\]\}/' \
  | jq .
```

Item prototypes use `{#JMXOBJ}` and `{#JMXNAME}` from the LLD payload.

---

## 2. Via zabbix-agent UserParameter (`z_java_gw_adapter_lo`)

Agent config: `UserParameter=z_java_gw_adapter_lo[*], /usr/local/bin/zabbix_java_gw_adapter localhost $1 "$2" $3 $4`

Macro layout: `z_java_gw_adapter_lo[JMX_PORT,"jmx_key"]` or with auth `$3 $4` = user pass.

Run **from a host that can query the agent** (Zabbix server/proxy or the app host itself):

### 2.1 GC discovery through agent (beans — same as template LLD)

Layer 2 vs layer 3 for the same check (pick one; prefer layer 2 with current adapter):

```bash
# layer 2
zabbix_get -s app-host.example -k \
  'z_java_gw_adapter_lo[1090,"jmx.discovery[beans,\\"*:type=GarbageCollector,name=*\\"]"]' \
  | sed -re 's/\\//g' \
        -e 's/\{?\"data\":\[\{\"value\":\"//' \
        -e 's/(\{|\}\],)\"response\":\"success\"[,\}]//g' \
        -e 's/\}\]\}\"\}\]\}/\}\]\}/' \
  | jq .

# layer 3
zabbix_get -s app-host.example -k \
  'z_java_gw_adapter_lo[1090,"jmx.discovery[beans,\\\\\"*:type=GarbageCollector,name=*\\\\\"]"]' \
  | sed -re 's/\\//g' \
        -e 's/\{?\"data\":\[\{\"value\":\"//' \
        -e 's/(\{|\}\],)\"response\":\"success\"[,\}]//g' \
        -e 's/\}\]\}\"\}\]\}/\}\]\}/' \
  | jq .
```

See section 1.3 for sample output (`{#JMXOBJ}`, `{#JMXNAME}`, `{#JMXDOMAIN}`, `{#JMXTYPE}`).

### 2.2 Memory pool attribute through agent

Same hard bean at each layer:

```bash
# layer 1 — direct adapter (logical argv3; see §1.2.1 for auth + failure modes)
zabbix_java_gw_adapter localhost 1090 \
  'jmx["java.lang:type=MemoryPool,name=CodeHeap '"'"'non-nmethods'"'"'",Usage.committed]' | jq .
zabbix_java_gw_adapter localhost 1090 \
  "jmx[\"java.lang:type=MemoryPool,name=Code Cache\",Usage.used]" | jq .
# layer 1 — verified double-quoted form with auth (eu2)
zabbix_java_gw_adapter localhost 1090 \
  "jmx[\\\"java.lang:type=MemoryPool,name=CodeHeap 'non-nmethods'\\\",Usage.committed]" \
  admin 'Pi31415926!' | jq .

# layer 2 — zabbix_get (Code Cache — spaces; CodeHeap — '"'"' for embedded ')
zabbix_get -s app-host.example -k \
  'z_java_gw_adapter_lo[1090,"jmx[\\"java.lang:type=MemoryPool,name=Code Cache\\",Usage.used]"]' | jq .
zabbix_get -s app-host.example -k \
  'z_java_gw_adapter_lo[1090,"jmx[\\"java.lang:type=MemoryPool,name=CodeHeap '"'non-nmethods'"'\\",Usage.committed]"]' | jq .

# layer 3 — old four-backslash style
zabbix_get -s app-host.example -k \
  'z_java_gw_adapter_lo[1090,"jmx[\\\\\"java.lang:type=MemoryPool,name=CodeHeap '"'non-nmethods'"'\\\\\",Usage.committed]"]' | jq .
```

LLD item prototypes after GC/MP discovery:

```text
# layer 2 (current)
z_java_gw_adapter_lo[{#JMXPORT},"jmx[\\"{#JMXOBJ}\\",Usage.used]"]

# layer 3 (legacy — migrate to layer 2)
z_java_gw_adapter_lo[{#JMXPORT},"jmx[\\\\\"{#JMXOBJ}\\\\\",Usage.used]"]
```

**Quoting by layer**

| Layer | Escaping |
|-------|----------|
| 1 — direct CLI | `'jmx["bean",attr]'` or `"jmx[\"bean\",attr]"` → logical argv3; with auth on eu2 also `"jmx[\\\"bean\\\",attr]"` |
| 2 — agent key (current) | **`\\"`** before each inner `"` around bean/pattern |
| 3 — agent key (legacy YAML) | **`\\\\\"`** — migrate to layer 2 with `__esc_json` adapter |
| 4 — gateway JSON | adapter `__esc_json` only — do not duplicate in template |
| Bean content (all layers) | spaces, `*`, `'` in pool names — literal, no extra escapes |

When building a new item: test **layer 1** on the app host, translate to **layer 2**, then paste into the template.

### 2.3 Local agent test

On the application host:

```bash
zabbix_get -s 127.0.0.1 -k \
  'z_java_gw_adapter_lo[1090,"jmx[\\"java.lang:type=Memory\\",HeapMemoryUsage.used]"]'
```

---

## 3. Common JMX keys (generic JVM monitoring)

```bash
JMX_PORT=1090
A="/usr/local/bin/zabbix_java_gw_adapter localhost $JMX_PORT"

# Heap
"$A" 'jmx["java.lang:type=Memory",HeapMemoryUsage.used]'
"$A" 'jmx["java.lang:type=Memory",HeapMemoryUsage.max]'

# Threads
"$A" 'jmx["java.lang:type=Threading",ThreadCount]'
"$A" 'jmx["java.lang:type=Threading",DaemonThreadCount]'

# Runtime
"$A" 'jmx["java.lang:type=Runtime",Uptime]'

# OperatingSystem (if exposed)
"$A" 'jmx["java.lang:type=OperatingSystem",ProcessCpuLoad]'
```

Single GC collector (after you know the name from discovery):

```bash
"$A" 'jmx["java.lang:type=GarbageCollector,name=G1 Young Generation",CollectionCount]'
```

---

## 4. Troubleshooting

```bash
# Gateway reachable?
exec 3<>/dev/tcp/localhost/10052 && echo OK || echo FAIL

# Gateway process
pgrep -af 'zabbix-java-gateway.*\.jar'

# JMX port listening (example)
ss -ltnp | grep ":1090"

# Adapter timeout (default 30s)
ZABBIX_JAVA_GW_ADAPTER_TIMEOUT=10 /usr/local/bin/zabbix_java_gw_adapter localhost 1090 \
  'jmx["java.lang:type=Memory",HeapMemoryUsage.used]'

# Failed response shape
/usr/local/bin/zabbix_java_gw_adapter localhost 1090 'jmx["java.lang:type=Memory",HeapMemoryUsage.used]' \
  | jq .
# expect: {"data":[{"value":"..."}],"response":"success"}
```

Typical failures:

| Symptom | Check |
|---------|--------|
| `gateway unreachable` | `zabbix-java-gateway` not running on `:10052` |
| empty / failed JMX | wrong port, JVM down, or `local.only` + wrong host (use `localhost`) |
| auth errors | pass user/pass args 4–5; loopback auth is optional but may be enabled |

---

## 5. Mapping to Zabbix template items

Generic template **Template App Generic Java Z_J_gw_A_lo** — as **shipped** (layer 3):

```text
z_java_gw_adapter_lo[{#JMXPORT},"jmx[\\\\\"java.lang:type=Memory\\\\\",HeapMemoryUsage.used]"]
z_java_gw_adapter_lo[{#JMXPORT},"jmx.discovery[beans,\\\\\"*:type=GarbageCollector,name=*\\\\\"]"]
z_java_gw_adapter_lo[{#JMXPORT},"jmx[\\\\\"{#JMXOBJ}\\\\\",CollectionCount]"]
```

After re-export with current adapter (layer 2):

```text
z_java_gw_adapter_lo[{#JMXPORT},"jmx[\\"java.lang:type=Memory\\",HeapMemoryUsage.used]"]
z_java_gw_adapter_lo[{#JMXPORT},"jmx.discovery[beans,\\"*:type=GarbageCollector,name=*\\"]"]
z_java_gw_adapter_lo[{#JMXPORT},"jmx[\\"{#JMXOBJ}\\",CollectionCount]"]
```

TRAP discovery fills `{#JMXPORT}` from `jvm.discovery[Z_J_gw_A_lo]`. GC and memory-pool LLD rule prototypes use `{#JMXOBJ}` / `{#JMXNAME}` from template `jmx.discovery[beans,...]`. All other generic JVM metrics are template active item prototypes under the same parent rule.
