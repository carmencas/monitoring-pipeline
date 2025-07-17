#!/bin/bash
echo "Waiting for NiFi full setup to complete..."

while [ ! -f /opt/nifi/init/setup-complete.flag ]; do
  echo "NiFi setup still in progress..."
  sleep 5
done

echo "✅ NiFi setup complete!"
