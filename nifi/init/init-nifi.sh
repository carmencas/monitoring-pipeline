{\rtf1\ansi\ansicpg1252\cocoartf2822
\cocoatextscaling0\cocoaplatform0{\fonttbl\f0\fswiss\fcharset0 Helvetica;}
{\colortbl;\red255\green255\blue255;}
{\*\expandedcolortbl;;}
\paperw11900\paperh16840\margl1440\margr1440\vieww11520\viewh8400\viewkind0
\pard\tx720\tx1440\tx2160\tx2880\tx3600\tx4320\tx5040\tx5760\tx6480\tx7200\tx7920\tx8640\pardirnatural\partightenfactor0

\f0\fs24 \cf0 #!/bin/bash\
\
# Esperar a que NiFi est\'e9 completamente iniciado\
echo "Waiting for NiFi to be fully ready..."\
until curl -f http://localhost:8080/nifi-api/system-diagnostics > /dev/null 2>&1; do\
  echo "NiFi is not ready yet..."\
  sleep 5\
done\
\
echo "NiFi is ready! Importing template..."\
\
# Obtener el root process group ID\
ROOT_PG_ID=$(curl -s http://localhost:8080/nifi-api/process-groups/root | jq -r '.id')\
\
# Verificar si ya existe un template importado\
EXISTING_TEMPLATES=$(curl -s http://localhost:8080/nifi-api/flow/templates | jq -r '.templates[].template.name')\
\
if [[ $EXISTING_TEMPLATES == *"metrics_flow"* ]]; then\
  echo "Template already exists, skipping import..."\
else\
  # Importar template desde archivo XML\
  if [ -f "/opt/nifi/nifi-current/templates/metrics_flow.xml" ]; then\
    echo "Importing template from XML file..."\
    \
    # Subir el template usando la API\
    curl -X POST "http://localhost:8080/nifi-api/process-groups/$\{ROOT_PG_ID\}/templates/upload" \\\
      -F "template=@/opt/nifi/nifi-current/templates/metrics_flow.xml"\
    \
    echo "Template imported successfully!"\
  else\
    echo "Template file not found at /opt/nifi/nifi-current/templates/metrics_flow.xml"\
    exit 1\
  fi\
fi\
\
# Obtener el ID del template importado\
TEMPLATE_ID=$(curl -s http://localhost:8080/nifi-api/flow/templates | jq -r '.templates[] | select(.template.name=="metrics_flow") | .id')\
\
if [ -z "$TEMPLATE_ID" ]; then\
  echo "Could not find template ID"\
  exit 1\
fi\
\
echo "Template ID: $TEMPLATE_ID"\
\
# Verificar si el template ya est\'e1 instanciado\
EXISTING_PROCESSORS=$(curl -s "http://localhost:8080/nifi-api/process-groups/$\{ROOT_PG_ID\}/processors" | jq -r '.processors[].component.name')\
\
if [[ $EXISTING_PROCESSORS == *"Listen for Metrics"* ]]; then\
  echo "Template already instantiated, skipping..."\
else\
  # Instanciar el template en el root process group\
  echo "Instantiating template..."\
  \
  INSTANTIATE_RESPONSE=$(curl -X POST "http://localhost:8080/nifi-api/process-groups/$\{ROOT_PG_ID\}/template-instance" \\\
    -H "Content-Type: application/json" \\\
    -d "\{\
      \\"templateId\\": \\"$\{TEMPLATE_ID\}\\",\
      \\"originX\\": 100,\
      \\"originY\\": 100\
    \}")\
  \
  echo "Template instantiated successfully!"\
fi\
\
# Iniciar todos los procesadores\
echo "Starting all processors..."\
curl -X PUT "http://localhost:8080/nifi-api/flow/process-groups/$\{ROOT_PG_ID\}" \\\
  -H "Content-Type: application/json" \\\
  -d '\{\
    "id": "'$\{ROOT_PG_ID\}'",\
    "state": "RUNNING"\
  \}'\
\
echo "NiFi setup completed! All processors should be running."}