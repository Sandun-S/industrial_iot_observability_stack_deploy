# Sensor & Reader Configuration Guide

This guide explains how to configure MQTT readers and sensors through the Web UI. No YAML editing needed — everything is done from the browser.

---

## How Data Flows

```
MQTT Message Published          Sensor Config                 InfluxDB Written
─────────────────────           ─────────────                 ───────────────
Topic: sensors/room1/temp       topic: sensors/+/temp         measurement: environment
Payload: {"temp": 23.5}         json_path: temp               device=Room 1 Temp, reading=temp_c, value=23.5
```

1. An MQTT message arrives on a topic
2. The MQTT Reader checks if any sensor subscribes to that topic
3. If matched, it extracts values using JSON path (or CSV column index)
4. Values are written to InfluxDB with tags for filtering in Grafana

---

## Adding an MQTT Reader

A **Reader** represents one MQTT broker connection. Each reader runs as a separate Docker container and can have multiple sensors.

### Form Fields

| Field | Required | What it is | Example |
|-------|----------|------------|---------|
| **Reader Name** | Yes | A friendly name for this broker connection | `factory-sensors` |
| **Description** | No | What this reader does | `Temperature and humidity sensors in Building A` |
| **MQTT Broker URL** | Yes | The MQTT broker to connect to. Format: `tcp://host:port` | `tcp://192.168.1.100:1883` |
| **Client ID** | No | MQTT client identifier. Auto-generated if left empty | `iiot-factory-01` |
| **QoS** | No | Quality of Service: 0 (fire & forget), 1 (at least once), 2 (exactly once) | `1` |
| **Username** | No | MQTT broker username (if your broker requires auth) | `sensor_user` |
| **Password** | No | MQTT broker password | `my-secret-pass` |
| **InfluxDB URL** | No | Where to store data. Default is the built-in InfluxDB | `http://influxdb:8086` |
| **InfluxDB Database** | No | Which database to write to | `iiot` |
| **Sensor Name** | Yes | Name for your first sensor on this reader | `Server Room Temperature` |
| **MQTT Topic** | Yes | The MQTT topic to subscribe to. Supports `+` and `#` wildcards | `sensors/server-room/temperature` |
| **Measurement** | Yes | The InfluxDB measurement (table) to store data in | `environment` |
| **Field Key** | No | The name of the InfluxDB field to write | `temperature_c` |
| **JSON Path** | No | Where to find the value in the JSON payload. Use `.` for raw payload | `temperature` |

### Examples

**Using the built-in Mosquitto broker:**
| Field | Value |
|-------|-------|
| Reader Name | `local-sensors` |
| MQTT Broker URL | `tcp://mosquitto:1883` |

**Connecting to an external broker:**
| Field | Value |
|-------|-------|
| Reader Name | `cloud-broker` |
| MQTT Broker URL | `tcp://broker.hivemq.com:1883` |

**Connecting to a broker with authentication:**
| Field | Value |
|-------|-------|
| Reader Name | `secure-broker` |
| MQTT Broker URL | `tcp://192.168.5.10:8883` |
| Username | `my-sensor-user` |
| Password | `secure-password-here` |

---

## Adding a Sensor

A **Sensor** defines one MQTT topic subscription and how to extract data from its messages.

### Form Fields

| Field | Required | What it is | Example |
|-------|----------|------------|---------|
| **Sensor Name** | Yes | A descriptive name. Used as the `device` tag in InfluxDB | `Server Room Temperature` |
| **MQTT Topic** | Yes | The topic pattern to subscribe to | `sensors/server-room/temperature` |
| **Measurement** | Yes | The InfluxDB measurement name. Group related sensors under the same measurement | `environment` |
| **Field Mappings** | Yes | Maps values from the MQTT payload to InfluxDB fields | See below |
| **Tags** | No | Extra metadata attached to every data point. Used for filtering in Grafana | `location=server-room,building=main` |

### Field Mappings

Each field mapping extracts one value from the MQTT message:

| Field | What it is |
|-------|------------|
| **Field key** | The name of the value in InfluxDB (e.g. `temperature_c`, `humidity_pct`) |
| **JSON path** | Where to find the value in the JSON payload using GJSON syntax |
| **Type** | `float` for numbers with decimals, `int` for whole numbers, `string` for text |
| **Unit** | Display unit shown in Grafana (e.g. `°C`, `%`, `W`, `V`) |

---

## How JSON Path Mapping Works

The **JSON path** tells the reader where to find a value inside a JSON message.

### Simple (flat JSON)

```json
{"temperature": 23.5, "humidity": 45.0}
```

| Field Key | JSON Path | Extracted Value |
|-----------|-----------|----------------|
| `temperature_c` | `temperature` | `23.5` |
| `humidity_pct` | `humidity` | `45.0` |

### Nested JSON

```json
{"supply_air": {"temp": 18.2}, "return_air": {"temp": 24.1}, "fan": {"speed": 85}}
```

| Field Key | JSON Path | Extracted Value |
|-----------|-----------|----------------|
| `supply_temp_c` | `supply_air.temp` | `18.2` |
| `return_temp_c` | `return_air.temp` | `24.1` |
| `fan_speed_pct` | `fan.speed` | `85` |

Use dots to navigate nested objects. For arrays, use `array.0.field` for the first element.

### Raw value (no JSON)

If your device sends a plain number or text (not JSON), use `.` (a single dot) as the JSON path:

```
Topic: sensors/counter
Payload: 42
JSON Path: .
→ Extracts: 42
```

### Multiple fields from one message

One MQTT message can produce multiple InfluxDB data points. Add multiple field mappings:

```json
{"voltage": 230, "current": 15, "power": 3450, "frequency": 50}
```

| Field Key | JSON Path | Type | Unit |
|-----------|-----------|------|------|
| `voltage_v` | `voltage` | float | V |
| `current_a` | `current` | float | A |
| `power_w` | `power` | float | W |
| `frequency_hz` | `frequency` | float | Hz |

One message → four data points in InfluxDB.

---

## CSV Data Mapping

Some industrial devices send CSV (comma-separated values) instead of JSON:

```
230.5,15.2,3450.0,50.0
```

Instead of JSON paths, use **column index** (starting at 0):

| Field Key | Column Index | Type | Unit |
|-----------|-------------|------|------|
| `voltage_v` | 0 | float | V |
| `current_a` | 1 | float | A |
| `power_w` | 2 | float | W |
| `frequency_hz` | 3 | float | Hz |

To configure CSV in the sensor form, check "CSV mode" and set the delimiter (usually `,`). If the first row is a header, enable `skip_header`.

---

## Wildcard Topics

MQTT supports wildcards for subscribing to multiple topics:

| Wildcard | Meaning | Example |
|----------|---------|---------|
| `+` | Matches exactly one level | `sensors/+/temperature` matches `sensors/room1/temperature`, `sensors/warehouse/temperature` |
| `#` | Matches everything below | `sensors/#` matches `sensors/room1/temperature`, `sensors/room1/humidity`, `sensors/anything/deep/nested` |

### Dynamic Tags with `{{topic.N}}`

When using `+` wildcards, you can extract the matched segment as a tag:

| Topic pattern | Incoming topic | `{{topic.0}}` | `{{topic.1}}` | `{{topic.2}}` |
|---|---|---|---|---|
| `sensors/+/temperature` | `sensors/room1/temperature` | `sensors` | `room1` | `temperature` |

Example tag: `location={{topic.1}}` → resolves to `location=room1` or `location=warehouse`.

---

## What is a Measurement?

A **measurement** is like a table in InfluxDB. Group related sensors under the same measurement so they appear together in Grafana dashboards.

| Measurement | Sensors that belong here |
|-------------|------------------------|
| `environment` | Temperature, humidity, air quality, CO2 |
| `power` | Voltage, current, power factor, energy |
| `hvac` | Supply temp, return temp, fan speed, filter status |
| `machine_status` | RPM, vibration, runtime, oil pressure |

**Good practice:** Use the same measurement name for sensors you want to view together on one Grafana panel. Use different measurements for different equipment types.

---

## Tags vs Fields

| | Tags | Fields |
|---|---|---|
| **Purpose** | Metadata for filtering/grouping | Actual sensor values |
| **Stored as** | Indexed strings | Float, int, string |
| **Used for** | Grafana filters, grouping, WHERE clauses | Charts, graphs, values |
| **Example** | `location=server-room`, `building=main` | `temperature_c=23.5`, `humidity_pct=45` |
| **Cardinality** | Keep low (< 100k unique values) | Unlimited |

**Rule of thumb:** If you'd use it in a Grafana filter dropdown, it should be a tag. If it's a number you want to graph, it should be a field.

---

## Complete Example

**Scenario:** A factory has 3 temperature sensors publishing to MQTT. Each sensor publishes to its own topic with JSON payloads.

**MQTT messages:**
```
sensors/zone1/temp → {"celsius": 24.5, "humidity": 55}
sensors/zone2/temp → {"celsius": 26.1, "humidity": 48}
sensors/zone3/temp → {"celsius": 22.8, "humidity": 60}
```

**Best approach — one sensor with wildcard:**

| Field | Value |
|-------|-------|
| Sensor Name | `Factory Temperature` |
| MQTT Topic | `sensors/+/temp` |
| Measurement | `environment` |
| Field 1 key | `temperature_c` |
| Field 1 JSON path | `celsius` |
| Field 2 key | `humidity_pct` |
| Field 2 JSON path | `humidity` |
| Tags | `zone={{topic.1}}` |

One sensor handles all 3 zones. Each data point gets a `zone` tag (zone1, zone2, zone3) for filtering in Grafana.

---

## Troubleshooting

**"No measurements found in InfluxDB"**
- Check the MQTT reader is connected: look at docker logs for `mqtt-reader`
- Verify your MQTT broker URL and topic match
- Publish a test message: `mosquitto_pub -h localhost -t 'iiot/test' -m '{"value": 42}'`

**JSON path not extracting values**
- Check the path matches the actual JSON structure
- For nested objects use dots: `sensor.data.temperature`
- For raw non-JSON payloads use `.` (a single dot)
- Enable debug logging: set `LOG_LEVEL=debug` on the reader

**Wrong data type**
- If a number shows as `0` or empty, check the type setting (float/int/string)
- InfluxDB stores everything as float64. Use `string` type for text values like status codes
