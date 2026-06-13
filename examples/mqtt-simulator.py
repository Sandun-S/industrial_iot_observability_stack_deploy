#!/usr/bin/env python3
"""
IIoT MQTT Simulator — Test data publisher for the Industrial IoT Observability Stack.

Publishes random temperature and humidity data to MQTT topics for testing
the MQTT Reader → InfluxDB → Grafana pipeline.

Usage:
  pip install paho-mqtt
  python mqtt-simulator.py --host localhost --port 1883

Environment variables:
  MQTT_HOST  — MQTT broker host (default: localhost)
  MQTT_PORT  — MQTT broker port (default: 1883)
  INTERVAL   — Publish interval in seconds (default: 5)
"""

import json
import random
import time
import os
import argparse

try:
    import paho.mqtt.client as mqtt
except ImportError:
    print("Error: paho-mqtt not installed. Run: pip install paho-mqtt")
    exit(1)


def create_client(client_id):
    client = mqtt.Client(client_id=client_id)
    client.connect(
        host=os.getenv("MQTT_HOST", "localhost"),
        port=int(os.getenv("MQTT_PORT", "1883")),
        keepalive=60,
    )
    client.loop_start()
    return client


def main():
    parser = argparse.ArgumentParser(description="IIoT MQTT Test Data Simulator")
    parser.add_argument("--host", default=os.getenv("MQTT_HOST", "localhost"), help="MQTT broker host")
    parser.add_argument("--port", type=int, default=int(os.getenv("MQTT_PORT", "1883")), help="MQTT broker port")
    parser.add_argument("--interval", type=float, default=float(os.getenv("INTERVAL", "5")), help="Publish interval (seconds)")
    args = parser.parse_args()

    print(f"=== IIoT MQTT Simulator ===")
    print(f"Broker: {args.host}:{args.port}")
    print(f"Interval: {args.interval}s")
    print(f"Publishing test data... (Ctrl+C to stop)")
    print()

    client = create_client("iiot-simulator")

    # Simulate multiple sensors
    sensors = [
        {
            "name": "Server Room Temperature",
            "topic": "sensors/server-room/temperature",
            "fields": {"temperature": lambda: round(random.uniform(18.0, 28.0), 1)},
        },
        {
            "name": "Server Room Humidity",
            "topic": "sensors/server-room/humidity",
            "fields": {"humidity": lambda: round(random.uniform(30.0, 70.0), 1)},
        },
        {
            "name": "HVAC Unit 1",
            "topic": "hvac/unit-01/status",
            "fields": {
                "supply_temp": lambda: round(random.uniform(12.0, 18.0), 1),
                "return_temp": lambda: round(random.uniform(20.0, 26.0), 1),
                "fan_speed": lambda: round(random.uniform(40.0, 100.0), 1),
                "filter_status": lambda: "clean" if random.random() > 0.1 else "dirty",
            },
        },
        # CSV-format power meter
        {
            "name": "Power Meter Main",
            "topic": "power/main-meter/values",
            "csv": lambda: f"{round(random.uniform(220, 240), 1)},{round(random.uniform(10, 50), 2)},{round(random.uniform(2000, 12000), 1)},{round(random.uniform(100, 500), 2)}",
            "use_raw": True,
        },
        # Test topic matching the default example config
        {
            "name": "Test Sensor",
            "topic": "iiot/test",
            "fields": {"value": lambda: round(random.uniform(0, 100), 2)},
        },
    ]

    try:
        while True:
            for sensor in sensors:
                if sensor.get("use_raw"):
                    payload = sensor["csv"]()
                else:
                    data = {k: v() for k, v in sensor["fields"].items()}
                    payload = json.dumps(data)

                client.publish(sensor["topic"], payload, qos=1)
                print(f"[{time.strftime('%H:%M:%S')}] {sensor['topic']} → {payload}")

            time.sleep(args.interval)

    except KeyboardInterrupt:
        print("\nStopped.")
        client.loop_stop()
        client.disconnect()


if __name__ == "__main__":
    main()
