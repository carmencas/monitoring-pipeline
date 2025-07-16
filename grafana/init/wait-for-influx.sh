#!/bin/bash
echo "Waiting for InfluxDB to be ready..."
until curl -f http://influxdb:8086/health; do
  echo "InfluxDB is not ready yet..."
  sleep 2
done
echo "InfluxDB is ready!"
