#!/bin/bash
# nifi/init/init-nifi.sh - Versión simplificada, sin espera interna

echo "=== NiFi Automated Setup (Improved) ==="

# Punto de entrada a la API de NiFi
NIFI_API_BASE="http://localhost:8080/nifi-api"
TEMPLATE_PATH="/opt/nifi/nifi-current/templates/metrics_flow.xml"

# Logging con timestamp
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Obtiene el ID del process group raíz
get_root_pg_id() {
  local resp
  if ! resp=$(curl -s --max-time 5 "$NIFI_API_BASE/process-groups/root"); then
    log "⚠️  No pude consultar root process-group"
    echo ""
    return
  fi
  echo "$resp" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4
}

# Cuenta cuántos procesadores ya existen
check_existing_processors() {
  local pg
  pg=$(get_root_pg_id)
  if [ -z "$pg" ]; then
    echo 0
    return
  fi
  local resp
  resp=$(curl -s --max-time 5 "$NIFI_API_BASE/process-groups/$pg/processors") || echo ""
  echo "$resp" | grep -c '"id":"' || echo 0
}

# Importa la plantilla XML (si existe)
import_template() {
  if [ ! -f "$TEMPLATE_PATH" ]; then
    log "⚠️  No existe plantilla en $TEMPLATE_PATH, skip import"
    return
  fi
  log "📥 Importando template desde $TEMPLATE_PATH"
  local code
  code=$(curl -s --max-time 30 -w "%{http_code}" -o /tmp/import.json \
    -X POST "$NIFI_API_BASE/process-groups/root/templates/upload" \
    -F "template=@$TEMPLATE_PATH")
  if [[ "$code" =~ ^(200|201)$ ]]; then
    log "✅ Template importado OK"
  else
    log "⚠️  Import template HTTP $code"
  fi
}

# Crea un ListenHTTP básico si no hay plantilla
create_basic_flow() {
  log "🔧 Creando procesador ListenHTTP básico"
  local pg
  pg=$(get_root_pg_id)
  if [ -z "$pg" ]; then
    log "❌ No obtuve root PG ID"
    return
  fi
  local payload='{
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
  local code
  code=$(curl -s --max-time 20 -w "%{http_code}" -o /tmp/flow.json \
    -X POST "$NIFI_API_BASE/process-groups/$pg/processors" \
    -H "Content-Type: application/json" \
    -d "$payload")
  if [[ "$code" =~ ^(200|201)$ ]]; then
    log "✅ ListenHTTP creado"
  else
    log "⚠️  Falló creación ListenHTTP (HTTP $code)"
  fi
}

# Arranca todos los procesadores que encuentre
start_processors() {
  log "🔄 Iniciando todos los procesadores"
  local pg ids info rev code
  pg=$(get_root_pg_id)
  if [ -z "$pg" ]; then
    log "❌ No obtuve root PG ID"
    return
  fi
  local resp
  resp=$(curl -s --max-time 10 "$NIFI_API_BASE/process-groups/$pg/processors") || echo ""
  ids=$(echo "$resp" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
  for id in $ids; do
    log "▶️  Arrancando $id"
    info=$(curl -s --max-time 5 "$NIFI_API_BASE/processors/$id") || echo ""
    rev=$(echo "$info" | grep -o '"version":[0-9]*' | head -1 | cut -d':' -f2)
    rev=${rev:-0}
    code=$(curl -s --max-time 10 -w "%{http_code}" -o /tmp/run.json \
      -X PUT "$NIFI_API_BASE/processors/$id/run-status" \
      -H "Content-Type: application/json" \
      -d "{\"revision\":{\"version\":$rev},\"state\":\"RUNNING\"}")
    if [ "$code" = "200" ]; then
      log "✅ Processor $id iniciado"
    else
      log "⚠️  Falló start $id (HTTP $code)"
    fi
  done
}

# ‼️ Aquí comienza el flujo principal
main() {
  log "🚀 Ejecutando NiFi init script…"

  local existing
  existing=$(check_existing_processors)
  log "Encontrados $existing procesadores existentes"

  if [ "$existing" -gt 0 ]; then
    log "⚠️  Ya hay procesadores, solo arranco los existentes"
    start_processors
  else
    log "📦 No hay procesadores, setup completo:"
    import_template
    sleep 3
    create_basic_flow
    sleep 5
    start_processors
  fi

  # Marco como terminado (flag sin fallo crítico)
  touch /opt/nifi/init/setup-complete.flag || log "⚠️ No pude crear setup-complete.flag"

  log "🎉 NiFi init finalizado"
}

main "$@"
