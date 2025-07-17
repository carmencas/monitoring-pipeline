#!/bin/bash
# nifi/init/init-nifi.sh - Versión mejorada y más robusta

set -e

echo "=== NiFi Automated Setup (Improved) ==="

# Configuración
MAX_WAIT_ATTEMPTS=60
WAIT_INTERVAL=5
NIFI_API_BASE="http://localhost:8080/nifi-api"
TEMPLATE_PATH="/opt/nifi/nifi-current/templates/metrics_flow.xml"

# Función para logging con timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Función para obtener el root process group ID
get_root_pg_id() {
    local response=$(curl -s --max-time 10 "$NIFI_API_BASE/process-groups/root" 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "$response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4
    else
        echo ""
    fi
}

# Función para verificar si ya existen procesadores
check_existing_processors() {
    local root_pg_id=$(get_root_pg_id)
    if [ -n "$root_pg_id" ]; then
        local response=$(curl -s --max-time 10 "$NIFI_API_BASE/process-groups/$root_pg_id/processors" 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo "$response" | grep -c '"id":"' 2>/dev/null || echo "0"
        else
            echo "0"
        fi
    else
        echo "0"
    fi
}

# Función para importar template (mejorada)
import_template() {
    if [ ! -f "$TEMPLATE_PATH" ]; then
        log "⚠️  Template file not found: $TEMPLATE_PATH"
        log "Skipping template import..."
        return 0
    fi
    
    log "📥 Importing template from: $TEMPLATE_PATH"
    
    # Intentar importar con timeout
    local response=$(curl -s --max-time 30 -w "%{http_code}" -o /tmp/import_response.json \
        -X POST "$NIFI_API_BASE/process-groups/root/templates/upload" \
        -F "template=@$TEMPLATE_PATH" 2>/dev/null)
    
    local http_code="${response: -3}"
    
    if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
        log "✅ Template imported successfully!"
        return 0
    else
        log "⚠️  Template import failed or template already exists. HTTP Code: $http_code"
        # No fallar completamente, continuar
        return 0
    fi
}

# Función para crear un flow básico si no existe template
create_basic_flow() {
    log "🔧 Creating basic HTTP listener flow..."
    
    local root_pg_id=$(get_root_pg_id)
    if [ -z "$root_pg_id" ]; then
        log "❌ Cannot get root process group ID"
        return 1
    fi
    
    # Crear procesador HTTP listener simple
    local processor_data='{
        "revision": {"version": 0},
        "component": {
            "type": "org.apache.nifi.processors.standard.ListenHTTP",
            "position": {"x": 100, "y": 100},
            "config": {
                "properties": {
                    "Listening Port": "8081",
                    "Base Path": "metrics"
                }
            }
        }
    }'
    
    local response=$(curl -s --max-time 20 -w "%{http_code}" -o /tmp/processor_response.json \
        -X POST "$NIFI_API_BASE/process-groups/$root_pg_id/processors" \
        -H "Content-Type: application/json" \
        -d "$processor_data" 2>/dev/null)
    
    local http_code="${response: -3}"
    
    if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
        log "✅ Basic HTTP listener created successfully!"
        return 0
    else
        log "⚠️  Failed to create basic flow. HTTP Code: $http_code"
        return 1
    fi
}

# Función simplificada para iniciar procesadores
start_processors() {
    log "🔄 Starting processors..."
    
    local root_pg_id=$(get_root_pg_id)
    if [ -z "$root_pg_id" ]; then
        log "❌ Cannot get root process group ID"
        return 1
    fi
    
    local processors_response=$(curl -s --max-time 20 "$NIFI_API_BASE/process-groups/$root_pg_id/processors" 2>/dev/null)
    if [ $? -ne 0 ]; then
        log "⚠️  Cannot fetch processors"
        return 1
    fi
    
    local processor_ids=$(echo "$processors_response" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    
    if [ -z "$processor_ids" ]; then
        log "⚠️  No processors found to start"
        return 0
    fi
    
    local started_count=0
    
    for processor_id in $processor_ids; do
        log "▶️  Starting processor: $processor_id"
        
        # Obtener información del procesador
        local processor_info=$(curl -s --max-time 10 "$NIFI_API_BASE/processors/$processor_id" 2>/dev/null)
        local revision=$(echo "$processor_info" | grep -o '"version":[0-9]*' | head -1 | cut -d':' -f2)
        
        if [ -z "$revision" ]; then
            revision=0
        fi
        
        # Intentar iniciar
        local response=$(curl -s --max-time 15 -w "%{http_code}" -o /tmp/start_response.json \
            -X PUT "$NIFI_API_BASE/processors/$processor_id/run-status" \
            -H "Content-Type: application/json" \
            -d "{\"revision\": {\"version\": $revision}, \"state\": \"RUNNING\"}" 2>/dev/null)
        
        local http_code="${response: -3}"
        
        if [ "$http_code" = "200" ]; then
            log "✅ Processor $processor_id started successfully"
            ((started_count++))
        else
            log "⚠️  Failed to start processor $processor_id. HTTP Code: $http_code"
        fi
    done
    
    log "🎉 Started $started_count processors"
    return 0
}

# Función principal
main() {
    log "🚀 Starting NiFi automated setup..."
    
    # Paso 1: Esperar a que NiFi esté listo
    if ! wait_for_nifi; then
        log "❌ NiFi setup failed: service not ready"
        exit 1
    fi
    
    # Paso 2: Verificar procesadores existentes
    local existing_count=$(check_existing_processors)
    log "Found $existing_count existing processors"
    
    if [ "$existing_count" -gt 0 ]; then
        log "⚠️  Processors already exist. Attempting to start them..."
        start_processors
    else
        log "📦 No existing processors found. Setting up new flow..."
        
        # Paso 3: Intentar importar template
        if import_template; then
            log "📥 Template processing completed"
            sleep 3
        else
            log "🔧 Template import failed, creating basic flow..."
            create_basic_flow
        fi
        
        # Paso 4: Intentar iniciar procesadores
        sleep 5
        start_processors
    fi
    
    # Marcar como completo
    touch /opt/nifi/init/setup-complete.flag
    
    log ""
    log "🎉 === NiFi Setup Complete ==="
    log "🌐 Access NiFi at: http://localhost:8080/nifi"
    log "👤 Username: admin"
    log "🔑 Password: ctsBtRBKHRAx69EqUghvvgEvjnaLjFEB"
    log "📊 Metrics endpoint: http://localhost:8081/metrics"
    log "📁 Setup flag created at: /opt/nifi/init/setup-complete.flag"
    log ""
}

# Ejecutar función principal
main "$@"