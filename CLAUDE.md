# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Deployment repository for the Industrial IoT Observability Stack. Contains Docker Swarm/Compose configs, setup scripts, Grafana provisioning, example configs, and documentation. No source code — users clone this repo and run `./scripts/setup.sh` to get a full IIoT stack running.

## Key Files

- `stack.yml` — Docker Swarm stack (production, multi-node)
- `docker-compose.yml` — Docker Compose (single host / dev)
- `scripts/setup.sh` — One-command full setup (auto-installs Docker, inits Swarm, deploys)
- `scripts/deploy.sh` — Redeploy after config changes
- `grafana/provisioning/` — Auto-configures InfluxDB datasource + pre-built dashboard on Grafana startup
- `config/mqtt-reader-example.yaml` — Default reader config (synced from source repo)
- `GUIDE.md` — Detailed sensor/reader configuration guide with JSON path mapping examples

## Deployment Flow

1. User clones this repo → runs `./scripts/setup.sh`
2. Script auto-detects architecture (amd64/arm64), installs Docker if needed, inits Swarm or falls back to Compose
3. Pulls images from `ghcr.io/sandun-s/industrial-iot-observability-stack/*`
4. Deploys all services: mosquitto, influxdb, grafana, web-ui, mqtt-reader, to-postgres
5. User opens Web UI at `http://<ip>:8080`, configures readers/sensors from the browser

## Services

| Service | Port | Image |
|---------|------|-------|
| mosquitto | 1883, 9001 | eclipse-mosquitto:2 |
| influxdb | 8086 | influxdb:1.8 |
| grafana | 3000 | grafana/grafana:latest |
| web-ui | 8080 | ghcr.io/.../web-ui |
| mqtt-reader | — | ghcr.io/.../mqtt-reader |
| to-postgres | 8089 | ghcr.io/.../to-postgres |

## Image Tagging

Images are tagged with architecture: `<component>:amd64.latest` and `<component>:arm64.latest`. The setup script auto-detects the host architecture and updates tags with `sed`.
