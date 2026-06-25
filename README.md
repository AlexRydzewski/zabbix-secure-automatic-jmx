# Strict Secure JMX monitoring with Zabbix — generic JVM package

Self-contained package for pattern **Z_J_gw_A_lo** (Zabbix + Java gateway + Active agent + localhost JMX).

Install on any Java host with `jmxremote.local.only=true`. Wire your application with an `INSTANCE_COLLECTOR` hook only.

## Layout

```
├── bin/zabbix_java_gw_adapter      # gateway protocol client
├── bin/zabbix_jvm_discovery        # TRAP discovery (JVM + GC + MP)
├── lib/jvm-discovery-core.sh       # shared discovery logic
├── zabbix_agentd.d/                # UserParameter z_java_gw_adapter_lo
├── template/                       # Zabbix template (neutral trap keys)
├── etc/default/                    # config example
├── cron/                           # optional system cron snippet
├── examples/                       # instance collector example
└── install.sh
```

## Trap discovery keys (default)

| Key | Content |
|-----|---------|
| `zabbix.jvm.discovery` | `{#SERVERID}`, `{#APPNAME}`, `{#JMXPORT}`, … |
| `zabbix.jmx_jvm_gc.discovery` | `{#JMXNAME}`, `{#JMXGCOBJ}` |
| `zabbix.jmx_jvm_mp.discovery` | `{#JMXNAME}`, `{#JMXMPOBJ}` |

Override in `/etc/default/zabbix_jvm_discovery`.

## Instance collector contract

Create a bash file and set `INSTANCE_COLLECTOR` to its path. It must define:

```bash
jvm_discovery_collect_instances() {
    jvm_discovery_add_instance SERVER_ID APP_NAME APP_DIR PID JMXPORT [HOST]
}
```

See `examples/instance-collector.example.sh`.

## Install

```bash
cd java-generic && sudo ./install.sh
# edit /etc/default/zabbix_jvm_discovery — set INSTANCE_COLLECTOR
sudo systemctl restart zabbix-agent zabbix-java-gateway
# import template/template_generic_java_z_j_gw_a_lo.yaml in Zabbix
```

Enable discovery cron: `cron/zabbix_jvm_discovery.cron` → `/etc/cron.d/`

## Requirements

- `zabbix-agent` (active), `zabbix-java-gateway` on `localhost:10052`
- JVM: `com.sun.management.jmxremote.local.only=true`, per-instance `jmxremote.port`

## References

- [Zabbix blog: JMX via Java gateway from the agent](https://blog.zabbix.com/new-monitoring-possibilities-for-java-applications-in-zabbix-3-4/5972/)
- [Zabbix Java gateway](https://www.zabbix.com/documentation/current/en/manual/concepts/java)
