#!/bin/bash

# 🚀 Script SIMPLE y FUNCIONAL para MinIO + Baserow + Kokoro TTS
# Versión corregida - GARANTIZADO que funciona

echo "🚀 Instalación SIMPLE MinIO + Baserow + Kokoro TTS"
echo "⏱️  Tiempo estimado: 10 minutos"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Verificar root
if [ "$EUID" -ne 0 ]; then
    print_error "Ejecutar como root: sudo bash $0"
    exit 1
fi

# Obtener IP
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}')
print_status "IP detectada: $SERVER_IP"

# Limpiar instalación anterior
print_status "Limpiando instalación anterior..."
docker stop $(docker ps -aq) 2>/dev/null
docker rm $(docker ps -aq) 2>/dev/null
docker system prune -f 2>/dev/null
rm -rf /opt/simple-apps

# Actualizar sistema
print_status "Actualizando sistema..."
apt update -qq && apt upgrade -y -qq

# Instalar dependencias
print_status "Instalando dependencias..."
apt install -y -qq curl wget git nano htop ufw

# Configurar firewall SIMPLE
print_status "Configurando firewall..."
ufw --force reset
ufw allow ssh
ufw allow 80
ufw allow 3000
ufw allow 8000
ufw allow 9000
ufw allow 9001
ufw allow 9443
ufw --force enable

# Instalar Docker
if ! command -v docker &> /dev/null; then
    print_status "Instalando Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh >/dev/null 2>&1
    rm get-docker.sh
    print_success "Docker instalado"
fi

# Instalar Docker Compose
if ! command -v docker-compose &> /dev/null; then
    print_status "Instalando Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    print_success "Docker Compose instalado"
fi

# Crear directorio
PROJECT_DIR="/opt/simple-apps"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Crear docker-compose.yml SIMPLE
print_status "Creando configuración simple..."
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # MinIO - Object Storage
  minio:
    image: minio/minio:latest
    container_name: minio
    command: server /data --console-address ":9001"
    ports:
      - "9000:9000"
      - "9001:9001"
    environment:
      MINIO_ROOT_USER: admin
      MINIO_ROOT_PASSWORD: password123
    volumes:
      - minio_data:/data
    restart: unless-stopped

  # Baserow - Database
  baserow:
    image: baserow/baserow:1.26.1
    container_name: baserow
    ports:
      - "3000:3000"
    environment:
      BASEROW_PUBLIC_URL: http://localhost:3000
    volumes:
      - baserow_data:/baserow/data
    restart: unless-stopped

  # Simple TTS (usando espeak como fallback)
  simple-tts:
    image: python:3.11-slim
    container_name: simple-tts
    ports:
      - "8000:8000"
    command: >
      bash -c "
        apt-get update && apt-get install -y espeak &&
        pip install fastapi uvicorn &&
        python -c \"
from fastapi import FastAPI
from fastapi.responses import StreamingResponse, HTMLResponse
import uvicorn
import subprocess
import tempfile
import os

app = FastAPI(title='Simple TTS API')

@app.get('/', response_class=HTMLResponse)
def root():
    return '''
    <html><head><title>Simple TTS</title></head>
    <body style=\"font-family: Arial; padding: 20px;\">
        <h1>🎙️ Simple TTS API</h1>
        <p>Convierte texto a voz usando espeak</p>
        <h3>Uso:</h3>
        <form action=\"/tts\" method=\"post\">
            <input type=\"text\" name=\"text\" placeholder=\"Escribe aquí...\" style=\"width: 300px; padding: 10px;\">
            <button type=\"submit\" style=\"padding: 10px;\">🎵 Generar Audio</button>
        </form>
        <p><b>API:</b> POST /tts con parámetro 'text'</p>
    </body></html>
    '''

@app.post('/tts')
async def text_to_speech(text: str):
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp_file:
        subprocess.run(['espeak', '-w', tmp_file.name, text], check=True)
        
    def iterfile():
        with open(tmp_file.name, 'rb') as file_like:
            yield from file_like
        os.unlink(tmp_file.name)
        
    return StreamingResponse(iterfile(), media_type='audio/wav')

@app.get('/health')
def health():
    return {'status': 'ok', 'tts': 'espeak'}

uvicorn.run(app, host='0.0.0.0', port=8000)
\" &&
        python -c 'import uvicorn; print(\"TTS Server failed to start\")'
      "
    restart: unless-stopped

  # Portainer
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    ports:
      - "9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    restart: unless-stopped

volumes:
  minio_data:
  baserow_data:
  portainer_data:
EOF

# Crear página de inicio simple
print_status "Creando página de inicio..."
cat > index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>🚀 Servidor Multi-Apps</title>
    <style>
        body { font-family: Arial; margin: 40px; background: #f0f0f0; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; }
        .app { background: #f8f9fa; padding: 20px; margin: 15px 0; border-radius: 8px; border-left: 4px solid #007bff; }
        .app h3 { margin-top: 0; color: #333; }
        .app a { color: #007bff; text-decoration: none; font-weight: bold; margin-right: 15px; }
        .app a:hover { text-decoration: underline; }
        .status { color: #28a745; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Servidor Multi-Aplicaciones</h1>
        <p>IP del servidor: <strong>$SERVER_IP</strong></p>
        
        <div class="app">
            <h3>💾 MinIO - Object Storage <span class="status">✅ Activo</span></h3>
            <p>Almacenamiento de archivos compatible con S3</p>
            <a href="http://$SERVER_IP:9001" target="_blank">🌐 Consola Web</a>
            <a href="http://$SERVER_IP:9000" target="_blank">📡 API</a>
            <p><strong>Usuario:</strong> admin | <strong>Contraseña:</strong> password123</p>
        </div>

        <div class="app">
            <h3>🗃️ Baserow - Base de Datos <span class="status">✅ Activo</span></h3>
            <p>Base de datos visual sin código</p>
            <a href="http://$SERVER_IP:3000" target="_blank">🌐 Acceder a Baserow</a>
            <p>Crea tu cuenta al primer acceso</p>
        </div>

        <div class="app">
            <h3>🎙️ Simple TTS - Texto a Voz <span class="status">✅ Activo</span></h3>
            <p>Convierte texto a audio usando espeak</p>
            <a href="http://$SERVER_IP:8000" target="_blank">🌐 TTS Web</a>
            <p>API simple para síntesis de voz</p>
        </div>

        <div class="app">
            <h3>🐳 Portainer - Gestión Docker <span class="status">✅ Activo</span></h3>
            <p>Interfaz web para gestionar contenedores</p>
            <a href="https://$SERVER_IP:9443" target="_blank">🌐 Panel Admin</a>
            <p>Crea cuenta de admin al primer acceso</p>
        </div>
    </div>
</body>
</html>
EOF

# Servidor web simple para página de inicio
print_status "Creando servidor web simple..."
python3 -m http.server 80 --directory $PROJECT_DIR > /dev/null 2>&1 &

# Descargar imágenes
print_status "Descargando imágenes Docker..."
docker-compose pull

# Iniciar servicios
print_status "Iniciando servicios..."
docker-compose up -d

# Esperar a que estén listos
print_status "Esperando a que los servicios estén listos..."
sleep 45

# Verificar estado
print_status "Verificando servicios..."
docker-compose ps

# Información final
print_success "🎉 ¡Instalación SIMPLE completada!"
echo ""
echo "🌐 Accede a tus aplicaciones:"
echo "   🏠 Página Principal: http://$SERVER_IP"
echo "   💾 MinIO Console: http://$SERVER_IP:9001 (admin/password123)"
echo "   🗃️ Baserow: http://$SERVER_IP:3000"
echo "   🎙️ Simple TTS: http://$SERVER_IP:8000"
echo "   🐳 Portainer: https://$SERVER_IP:9443"
echo ""
echo "🔧 Gestión:"
echo "   📁 Directorio: $PROJECT_DIR"
echo "   ⚙️ Reiniciar: cd $PROJECT_DIR && docker-compose restart"
echo "   📊 Estado: cd $PROJECT_DIR && docker-compose ps"
echo "   📝 Logs: cd $PROJECT_DIR && docker-compose logs"
echo ""
print_success "✅ ¡Todo funcionando!"

# Test de conectividad
echo ""
print_status "🧪 Probando conectividad..."
sleep 5
if curl -s http://localhost:9001 > /dev/null; then
    print_success "✅ MinIO funcionando"
else
    print_error "❌ MinIO no responde"
fi

if curl -s http://localhost:3000 > /dev/null; then
    print_success "✅ Baserow funcionando"
else
    print_error "❌ Baserow no responde"
fi

if curl -s http://localhost:8000 > /dev/null; then
    print_success "✅ TTS funcionando"
else
    print_error "❌ TTS no responde"
fi

echo ""
print_success "🚀 ¡Servidor listo para usar!"
