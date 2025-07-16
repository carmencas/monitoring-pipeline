#!/bin/bash
# nifi/init/init-nifi.sh

set -e

echo "=== NiFi Automated Setup ==="

# Función para esperar a que NiFi esté completamente listo
wait_for_nifi() {
    echo "Waiting for NiFi to be fully ready..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -f -s http://localhost:8080/nifi-api/system-diagnostics > /dev/null 2>&1; then
            echo "✅ NiFi is ready!"
            return 0
        fi
        echo "⏳ Attempt $attempt/$max_attempts: NiFi is not ready yet..."
        sleep 10
        ((attempt++))
    done
    
    echo "❌ ERROR: NiFi failed to start after $max_attempts attempts"
    return 1
}

# Función para obtener el root process group ID
get_root_pg_id() {
    local root_pg_response=$(curl -s http://localhost:8080/nifi-api/process-groups/root)
    local root_pg_id=$(echo "$root_pg_response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo "$root_pg_id"
}

# Función para importar template
import_template() {
    local template_path="/opt/nifi/nifi-current/templates/metrics_flow.xml"
    
    if [ ! -f "$template_path" ]; then
        echo "❌ Template file not found: $template_path"
        return 1
    fi
    
    echo "📥 Importing template from: $template_path"
    
    # Importar template usando multipart/form-data
    local response=$(curl -s -w "%{http_code}" -o /tmp/import_response.json \
        -X POST "http://localhost:8080/nifi-api/process-groups/root/templates/upload" \
        -F "template=@$template_path")
    
    local http_code="${response: -3}"
    
    if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
        echo "✅ Template imported successfully!"
        return 0
    else
        echo "❌ Failed to import template. HTTP Code: $http_code"
        echo "Response:"
        cat /tmp/import_response.json
        return 1
    fi
}

# Función para obtener el ID del template importado
get_template_id() {
    local templates_response=$(curl -s "http://localhost:8080/nifi-api/process-groups/root/templates")
    
    # Buscar template por nombre (asumiendo que se llama "Metrics Flow" o similar)
    local template_id=$(echo "$templates_response" | grep -A 10 -B 10 "metrics" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -z "$template_id" ]; then
        # Fallback: obtener el primer template disponible
        template_id=$(echo "$templates_response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    fi
    
    echo "$template_id"
}

# Función para instanciar template
instantiate_template() {
    local template_id=$(get_template_id)
    
    if [ -z "$template_id" ]; then
        echo "❌ Cannot instantiate template: ID not found"
        return 1
    fi
    
    echo "🚀 Instantiating template with ID: $template_id"
    
    # Instanciar template en el root process group
    local response=$(curl -s -w "%{http_code}" -o /tmp/instantiate_response.json \
        -X POST "http://localhost:8080/nifi-api/process-groups/root/template-instance" \
        -H "Content-Type: application/json" \
        -d "{
            \"templateId\": \"$template_id\",
            \"originX\": 100.0,
            \"originY\": 100.0
        }")
    
    local http_code="${response: -3}"
    
    if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
        echo "✅ Template instantiated successfully!"
        return 0
    else
        echo "❌ Failed to instantiate template. HTTP Code: $http_code"
        echo "Response:"
        cat /tmp/instantiate_response.json
        return 1
    fi
}

# Función para obtener todos los procesadores
get_processors() {
    local root_pg_id=$(get_root_pg_id)
    curl -s "http://localhost:8080/nifi-api/process-groups/$root_pg_id/processors"
}

# Función para iniciar todos los procesadores
start_processors() {
    echo "🔄 Starting all processors..."
    
    local processors_response=$(get_processors)
    local processor_ids=$(echo "$processors_response" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    
    if [ -z "$processor_ids" ]; then
        echo "❌ No processors found to start"
        return 1
    fi
    
    local started_count=0
    
    for processor_id in $processor_ids; do
        echo "▶️  Starting processor: $processor_id"
        
        # Obtener revisión actual del procesador
        local processor_info=$(curl -s "http://localhost:8080/nifi-api/processors/$processor_id")
        local revision=$(echo "$processor_info" | grep -o '"version":[0-9]*' | head -1 | cut -d':' -f2)
        
        if [ -z "$revision" ]; then
            revision=0
        fi
        
        # Iniciar procesador
        local response=$(curl -s -w "%{http_code}" -o /tmp/start_response.json \
            -X PUT "http://localhost:8080/nifi-api/processors/$processor_id/run-status" \
            -H "Content-Type: application/json" \
            -d "{
                \"revision\": {\"version\": $revision},
                \"state\": \"RUNNING\"
            }")
        
        local http_code="${response: -3}"
        
        if [ "$http_code" = "200" ]; then
            echo "✅ Processor $processor_id started successfully"
            ((started_count++))
        else
            echo "❌ Failed to start processor $processor_id. HTTP Code: $http_code"
        fi
    done
    
    echo "🎉 Started $started_count processors"
    return 0
}

# Función para verificar el estado del flow
verify_flow() {
    echo "🔍 Verifying flow status..."
    
    local processors_response=$(get_processors)
    local running_count=$(echo "$processors_response" | grep -c '"state":"RUNNING"' || echo "0")
    local total_count=$(echo "$processors_response" | grep -c '"id":"' || echo "0")
    
    echo "📊 Flow Status:"
    echo "   - Total processors: $total_count"
    echo "   - Running processors: $running_count"
    
    if [ "$running_count" -gt 0 ]; then
        echo "✅ Flow is active and running!"
        return 0
    else
        echo "⚠️  Flow is not running. Manual intervention may be required."
        return 1
    fi
}

# Función principal
main() {
    echo "🚀 Starting NiFi automated setup..."
    
    # Paso 1: Esperar a que NiFi esté listo
    if ! wait_for_nifi; then
        echo "❌ NiFi setup failed: service not ready"
        exit 1
    fi
    
    # Paso 2: Verificar si ya hay procesadores (evitar duplicados)
    local existing_processors=$(get_processors)
    local processor_count=$(echo "$existing_processors" | grep -c '"id":"' || echo "0")
    
    if [ "$processor_count" -gt 0 ]; then
        echo "⚠️  Found $processor_count existing processors. Skipping template import."
        echo "🔄 Attempting to start existing processors..."
        start_processors
        verify_flow
        return 0
    fi
    
    # Paso 3: Importar template
    if import_template; then
        echo "📥 Template imported successfully"
        
        # Paso 4: Instanciar template
        if instantiate_template; then
            echo "🚀 Template instantiated successfully"
            
            # Paso 5: Esperar un poco para que los componentes se creen
            sleep 5
            
            # Paso 6: Iniciar procesadores
            if start_processors; then
                echo "▶️  Processors started successfully"
                
                # Paso 7: Verificar estado final
                verify_flow
            else
                echo "❌ Failed to start processors"
                exit 1
            fi
        else
            echo "❌ Failed to instantiate template"
            exit 1
        fi
    else
        echo "❌ Failed to import template"
        exit 1
    fi
    
    echo ""
    echo "🎉 === NiFi Setup Complete ==="
    echo "🌐 Access NiFi at: http://localhost:8080/nifi"
    echo "👤 Username: admin"
    echo "🔑 Password: ctsBtRBKHRAx69EqUghvvgEvjnaLjFEB"
    echo "📊 Metrics endpoint: http://localhost:8081/metrics"
    echo ""
}

# Ejecutar función principal
main "$@"
