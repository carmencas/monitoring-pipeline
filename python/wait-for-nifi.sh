#!/bin/bash
echo "Waiting for NiFi to be ready..."
until curl -f http://nifi:8080/nifi/; do
  echo "NiFi is not ready yet..."
  sleep 5
done
echo "NiFi is ready!"
