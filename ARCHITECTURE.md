# Industrial IoT Observability Stack — Architecture

## Overview

The IIoT Stack is a lightweight, Docker Swarm-native observability pipeline for industrial IoT data. It follows a simple ETL pattern:

```
MQTT (ingest) → MQTT Reader (transform) → InfluxDB (store) → Grafana (visualize)
```

## Component Architecture

```
┌──────────────┐     ┌──────────────────┐     ┌────────────┐     ┌──────────┐
│  MQTT Broker  │────▶│  MQTT Reader     │────▶│  InfluxDB  │────▶│  Grafana │
│  (Mosquitto)  │     │  (Go container)  │     │   v1.8     │     │          │
│  :1883        │     │                  │     │  :8086     │     │  :3000   │
└──────────────┘     └──────────────────┘     └────────────┘     └──────────┘
       ▲                                            ▲                  │
       │                                    ┌───────┴──────┐          │
       │                                    │   Web UI     │◄─────────┘
       │                                    │   (Go, :8080)│  (Grafana API)
       │                                    │              │
       │                                    │ - Reader CRUD│
       │                                    │ - InfluxDB   │
       │                                    │   query proxy│
       │                                    │ - Dashboard  │
       │                                    │   management │
       │                                    └──────────────┘
       │                                            │
       └────────────────────────────────────────────┘
                  (Web UI manages reader configs)
```

## Data Flow

### 1. Ingestion (MQTT → Reader)
An MQTT reader subscribes to configured topics on an MQTT broker. Each message is parsed according to its sensor configuration:

- **JSON payloads**: Values extracted using GJSON path expressions (e.g., `temperature`, `supply_air.temp`)
- **CSV payloads**: Values mapped by column index

### 2. Transformation (Reader → InfluxDB)
The reader converts each extracted value into an InfluxDB line protocol data point:
```
measurement,device=sensor_name,reading=field_key,location=rack1 value=23.5 1718000000000000
```

Standard tags added to every point:
- `device` — Sensor name
- `reading` — Field key
- `reader` — Reader instance name

User-defined tags from the sensor config are also included. `{{topic.N}}` placeholders are resolved to MQTT topic segments for dynamic tagging.

### 3. Storage (InfluxDB)
InfluxDB v1.8 stores time-series data in the `iiot` database. Each measurement corresponds to a sensor group (e.g., `environment`, `hvac`, `power`). No authentication is enabled — designed for isolated networks.

### 4. Visualization (Grafana)
Grafana connects to InfluxDB via a pre-provisioned datasource. Two dashboard mechanisms:

1. **Provisioned dashboard** — `iiot-overview.json` loads at startup with template variables that auto-discover measurements, devices, and readings from InfluxDB
2. **API-created dashboards** — The Web UI backend generates per-measurement dashboards via Grafana's REST API when the user clicks "Auto-Create Dashboards"

## Scaling: Multiple MQTT Endpoints

Each MQTT broker endpoint gets its own reader container. This provides:

- **Isolation** — Reader failure for one broker doesn't affect others
- **Independent config** — Each reader has its own YAML config file
- **Resource control** — Per-container memory/CPU limits

To add a reader for a new MQTT broker:
1. Create a YAML config file (`config/my-broker.yaml`)
2. Add a service to `stack.yml` or `docker-compose.yml`
3. Run `./scripts/deploy.sh`

## Web UI API

The Web UI backend (port 8080) provides a REST API:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/health` | GET | Health check |
| `/api/status` | GET | System component status |
| `/api/readers` | GET | List configured readers |
| `/api/readers/:name/sensors` | GET | List sensors in a reader |
| `/api/readers/:name/sensors` | POST | Add sensor to reader |
| `/api/influx/measurements` | GET | List InfluxDB measurements |
| `/api/influx/query?q=` | GET | Run InfluxQL query |
| `/api/influx/latest` | GET | Get latest readings |
| `/api/grafana/dashboards` | GET/POST/DELETE | Manage Grafana dashboards |
| `/api/grafana/datasource` | GET | Ensure InfluxDB datasource |

All endpoints are unauthenticated (designed for isolated homelab/industrial networks).

## Network

All services communicate over the `iiot-net` Docker overlay network (Swarm) or bridge network (Compose). Port mappings:

| Port | Service | External |
|------|---------|----------|
| 1883 | Mosquitto | Yes |
| 8086 | InfluxDB | Yes |
| 3000 | Grafana | Yes |
| 8080 | Web UI | Yes |
| — | MQTT Reader | No (internal only) |

## Raspberry Pi Considerations

- **64-bit OS recommended** — All images are built for `arm64`
- **512MB minimum RAM** — The full stack uses ~256MB at idle
- **SD card wear** — Consider mounting InfluxDB data volume on external storage for production use
- **MQTT broker** — Eclipse Mosquitto 2.x runs well on Pi with default config

## Security

This stack is designed for **isolated industrial/homelab networks**. It intentionally avoids:

- TLS encryption (add a reverse proxy like Nginx/Traefik if needed)
- User authentication (Grafana has basic admin/admin; add OAuth if needed)
- API authentication (add a reverse proxy with auth if exposing to the internet)

For production deployments on shared networks, consider:
1. Placing the stack behind a VPN (WireGuard/Tailscale)
2. Adding Nginx as a TLS-terminating reverse proxy
3. Enabling InfluxDB authentication
4. Using Grafana OAuth for user management
