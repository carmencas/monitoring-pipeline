#!/bin/bash

# Esperar a que NiFi esté completamente iniciado
echo "Waiting for NiFi to be fully ready..."
until curl -f http://localhost:8080/nifi-api/system-diagnostics > /dev/null 2>&1; do
  echo "NiFi is not ready yet..."
  sleep 5
done

echo "NiFi is ready! Setting up templates and processors..."

# Importar template (si existe)
if [ -f "/opt/nifi/nifi-current/templates/metrics_flow.xml" ]; then
  echo "Importing template..."
  # Aquí podrías usar la API de NiFi para importar el template
  # Por simplicidad, asumimos que se importa manualmente la primera vez
fi

# Crear los procesadores necesarios programáticamente
echo "Creating processors via NiFi API..."

# Obtener el root process group ID
ROOT_PG_ID=$(curl -s http://localhost:8080/nifi-api/process-groups/root | jq -r '.id')

# Crear ListenHTTP processor
curl -X POST "http://localhost:8080/nifi-api/process-groups/${ROOT_PG_ID}/processors" \
  -H "Content-Type: application/json" \
  -d '{
    "revision": {"version": 0},
    "component": {
      "type": "org.apache.nifi.processors.standard.ListenHTTP",
      "name": "Listen for Metrics",
      "config": {
        "properties": {
          "Listening Port": "8081",
          "Base Path": "metrics"
        }
      }
    }
  }'

echo "NiFi setup completed!"
