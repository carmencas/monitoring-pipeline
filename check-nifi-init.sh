#!/bin/bash

echo "🔍 Verificando ejecución de init-nifi.sh..."

# Buscar en logs de Docker si se ejecutó el script
echo ""
echo "📄 Buscando evidencia de ejecución en logs de NiFi:"
docker compose logs nifi | grep -E "NiFi Automated Setup|NiFi Setup Complete|Executing init-nifi.sh|Template imported|Processor.*started"

# Verificar si el flag existe dentro del contenedor
echo ""
echo "📁 Comprobando si existe setup-complete.flag dentro del contenedor:"
docker compose exec nifi sh -c '[ -f /opt/nifi/init/setup-complete.flag ] && echo "✅ Flag encontrado" || echo "❌ Flag NO encontrado"'

# Comprobación del template importado (opcional)
echo ""
echo "📊 Verificando si hay procesadores en el flow:"
docker compose exec nifi curl -s http://localhost:8080/nifi-api/process-groups/root/processors | grep -c '"id"' | awk '{print "🔢 Procesadores encontrados: "$1}'

echo ""
echo "✅ Verificación completa"
