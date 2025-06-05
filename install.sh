#!/bin/bash

# 🚀 Instalación automática de MinIO + Baserow + Kokoro TTS
# Para uso en DigitalOcean con Ubuntu 22.04

echo "🚀 Instalando MinIO + Baserow + Kokoro TTS..."
echo "⏱️  Tiempo estimado: 10-15 minutos"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar si se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    print_error "Este script debe ejecutarse como root (usar sudo)"
    exit 1
fi

# Obtener IP del servidor
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}')
print_status "IP del servidor detectada: $SERVER_IP"

# Actualizar sistema
print_status "Actualizando sistema..."
apt update -qq && apt upgrade -y -qq

# Instalar dependencias básicas
print_status "Instalando dependencias..."
apt install -y -qq curl wget git nano htop ufw software-properties-common

# Configurar firewall
print_status "Configurando firewall..."
ufw allow ssh
ufw allow 80
ufw allow 443
ufw allow 9443  # Portainer
ufw --force enable
print_success "Firewall configurado"

# Instalar Docker
if ! command -v docker &> /dev/null; then
    print_status "Instalando Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    print_success "Docker instalado"
else
    print_warning "Docker ya está instalado"
fi

# Instalar Docker Compose
if ! command -v docker-compose &> /dev/null; then
    print_status "Instalando Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    print_success "Docker Compose instalado"
else
    print_warning "Docker Compose ya está instalado"
fi

# Crear directorio del proyecto
PROJECT_DIR="/opt/three-apps"
print_status "Creando directorio del proyecto en $PROJECT_DIR..."
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Crear docker-compose.yml
print_status "Creando docker-compose.yml..."
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # MinIO - Object Storage (S3 compatible)
  minio:
    image: minio/minio:latest
    container_name: minio
    command: server /data --console-address ":9001"
    ports:
      - "9000:9000"  # API
      - "9001:9001"  # Web UI
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin123
    volumes:
      - minio_data:/data
    networks:
      - app_network
    restart: unless-stopped

  # Baserow - Database UI (No-code database)
  baserow:
    image: baserow/baserow:1.26.1
    container_name: baserow
    ports:
      - "3000:3000"
    environment:
      BASEROW_PUBLIC_URL: http://localhost:3000
      DATABASE_URL: postgresql://baserow:baserow_password@postgres:5432/baserow
      REDIS_URL: redis://redis:6379
    volumes:
      - baserow_data:/baserow/data
    depends_on:
      - postgres
      - redis
    networks:
      - app_network
    restart: unless-stopped

  # PostgreSQL para Baserow
  postgres:
    image: postgres:15
    container_name: postgres
    environment:
      POSTGRES_DB: baserow
      POSTGRES_USER: baserow
      POSTGRES_PASSWORD: baserow_password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - app_network
    restart: unless-stopped

  # Redis para Baserow
  redis:
    image: redis:7-alpine
    container_name: redis
    volumes:
      - redis_data:/data
    networks:
      - app_network
    restart: unless-stopped

  # Kokoro TTS - Text to Speech
  kokoro-tts:
    build:
      context: .
      dockerfile_inline: |
        FROM python:3.11-slim
        RUN apt-get update && apt-get install -y git espeak-ng curl build-essential
        RUN pip install kokoro fastapi uvicorn soundfile
        WORKDIR /app
        COPY tts_server.py /app/main.py
        EXPOSE 8000
        CMD ["python", "main.py"]
    container_name: kokoro-tts
    ports:
      - "8000:8000"
    volumes:
      - kokoro_cache:/root/.cache
    networks:
      - app_network
    restart: unless-stopped

  # Nginx Reverse Proxy
  nginx:
    image: nginx:alpine
    container_name: nginx-proxy
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
    depends_on:
      - minio
      - baserow
      - kokoro-tts
    networks:
      - app_network
    restart: unless-stopped

  # Portainer - Docker Management UI
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    ports:
      - "9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks:
      - app_network
    restart: unless-stopped

volumes:
  minio_data:
  baserow_data:
  postgres_data:
  redis_data:
  kokoro_cache:
  portainer_data:

networks:
  app_network:
    driver: bridge
EOF

# Crear servidor TTS simplificado
print_status "Creando servidor Kokoro TTS..."
cat > tts_server.py << 'EOF'
from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse, HTMLResponse
import uvicorn
import tempfile
import os
import io

app = FastAPI(title='Kokoro TTS API', version='1.0.0')

# Intentar importar kokoro, si falla usar TTS básico
try:
    from kokoro import KPipeline
    pipeline = KPipeline(lang_code='a')
    KOKORO_AVAILABLE = True
except ImportError:
    KOKORO_AVAILABLE = False
    import subprocess

@app.get('/', response_class=HTMLResponse)
def root():
    return '''
    <html>
    <head><title>Kokoro TTS API</title></head>
    <body style="font-family: Arial; padding: 20px;">
        <h1>🎙️ Kokoro TTS API</h1>
        <p><strong>Estado:</strong> ''' + ('🟢 Kokoro disponible' if KOKORO_AVAILABLE else '🟡 Fallback mode') + '''</p>
        <h2>Uso:</h2>
        <p><strong>POST /tts</strong> - Convertir texto a voz</p>
        <p><strong>GET /voices</strong> - Lista de voces disponibles</p>
        <h3>Ejemplo:</h3>
        <pre>curl -X POST "http://''' + os.getenv('SERVER_IP', 'localhost') + ''':8000/tts" -d "text=Hola mundo&voice=af_bella"</pre>
    </body>
    </html>
    '''

@app.post('/tts')
async def text_to_speech(text: str, voice: str = 'af_bella'):
    try:
        if KOKORO_AVAILABLE:
            generator = pipeline(text, voice=voice)
            audio_data = None
            for i, (gs, ps, audio) in enumerate(generator):
                audio_data = audio
                break
            
            if audio_data is None:
                raise HTTPException(status_code=500, detail='Failed to generate audio')
            
            # Guardar como WAV temporal
            with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp_file:
                import soundfile as sf
                sf.write(tmp_file.name, audio_data, 24000)
                
            def iterfile():
                with open(tmp_file.name, 'rb') as file_like:
                    yield from file_like
                os.unlink(tmp_file.name)
                
            return StreamingResponse(iterfile(), media_type='audio/wav')
        else:
            # Fallback: usar espeak
            with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp_file:
                subprocess.run(['espeak', '-w', tmp_file.name, text], check=True)
                
            def iterfile():
                with open(tmp_file.name, 'rb') as file_like:
                    yield from file_like
                os.unlink(tmp_file.name)
                
            return StreamingResponse(iterfile(), media_type='audio/wav')
            
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get('/voices')
def get_voices():
    if KOKORO_AVAILABLE:
        voices = [
            'af_alloy', 'af_aoede', 'af_bella', 'af_heart', 
            'af_jessica', 'af_kore', 'af_nicole', 'af_nova', 
            'af_river', 'af_sarah', 'af_sky', 'am_adam', 
            'am_daniel', 'am_eric', 'am_michael'
        ]
    else:
        voices = ['default (espeak)']
    return {'voices': voices, 'kokoro_available': KOKORO_AVAILABLE}

@app.get('/health')
def health():
    return {'status': 'ok', 'kokoro_available': KOKORO_AVAILABLE}

if __name__ == '__main__':
    uvicorn.run(app, host='0.0.0.0', port=8000)
EOF

# Crear configuración nginx simplificada
print_status "Creando configuración Nginx..."
cat > nginx.conf << EOF
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    server {
        listen 80 default_server;
        server_name _;

        location / {
            return 200 '<!DOCTYPE html>
<html>
<head>
    <title>🚀 Servidor Multi-Herramientas</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 0; padding: 20px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; }
        .container { max-width: 1000px; margin: 0 auto; }
        h1 { color: white; text-align: center; margin-bottom: 40px; text-shadow: 0 2px 4px rgba(0,0,0,0.3); }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
        .app { background: white; padding: 25px; border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.1); transition: transform 0.2s; }
        .app:hover { transform: translateY(-2px); }
        .app h2 { color: #333; margin-top: 0; font-size: 1.4em; }
        .app p { color: #666; line-height: 1.5; }
        .app a { display: inline-block; background: #007bff; color: white; padding: 8px 16px; text-decoration: none; border-radius: 6px; margin: 5px 5px 5px 0; transition: background 0.2s; }
        .app a:hover { background: #0056b3; }
        .status { float: right; padding: 4px 8px; border-radius: 20px; font-size: 12px; font-weight: 500; }
        .running { background: #d4edda; color: #155724; }
        .info { background: rgba(255,255,255,0.1); color: white; padding: 20px; border-radius: 8px; margin-top: 30px; text-align: center; }
        code { background: rgba(0,0,0,0.1); padding: 2px 6px; border-radius: 4px; font-family: monospace; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Servidor Multi-Herramientas</h1>
        
        <div class="grid">
            <div class="app">
                <h2>💾 MinIO <span class="status running">🟢 Activo</span></h2>
                <p>Almacenamiento de archivos compatible con AWS S3</p>
                <a href="http://$SERVER_IP:9001" target="_blank">🌐 Consola Web</a>
                <a href="http://$SERVER_IP:9000" target="_blank">📡 API</a>
                <p><strong>👤 Usuario:</strong> <code>minioadmin</code><br>
                <strong>🔑 Contraseña:</strong> <code>minioadmin123</code></p>
            </div>

            <div class="app">
                <h2>🗃️ Baserow <span class="status running">🟢 Activo</span></h2>
                <p>Base de datos visual sin código (como Airtable)</p>
                <a href="http://$SERVER_IP:3000" target="_blank">🌐 Acceder a Baserow</a>
                <p>Crea tablas, formularios y obtén APIs automáticamente</p>
            </div>

            <div class="app">
                <h2>🎙️ Kokoro TTS <span class="status running">🟢 Activo</span></h2>
                <p>Síntesis de voz con IA (82M parámetros)</p>
                <a href="http://$SERVER_IP:8000" target="_blank">🌐 API Web</a>
                <a href="http://$SERVER_IP:8000/voices" target="_blank">🎵 Ver Voces</a>
                <p>Convierte texto a audio natural de alta calidad</p>
            </div>

            <div class="app">
                <h2>🐳 Portainer <span class="status running">🟢 Activo</span></h2>
                <p>Gestión visual de contenedores Docker</p>
                <a href="https://$SERVER_IP:9443" target="_blank">🌐 Panel Admin</a>
                <p>Monitorea, actualiza y gestiona todos los servicios</p>
            </div>
        </div>

        <div class="info">
            <h3>📡 Información del Servidor</h3>
            <p><strong>IP:</strong> $SERVER_IP | <strong>Estado:</strong> ✅ Todas las aplicaciones funcionando</p>
            <p>💡 <strong>Tip:</strong> Guarda esta página en favoritos para acceso rápido</p>
        </div>
    </div>
</body>
</html>';
            add_header Content-Type text/html;
        }

        location /health {
            access_log off;
            return 200 "OK";
            add_header Content-Type text/plain;
        }
    }
}
EOF

# Crear script de gestión
print_status "Creando scripts de gestión..."
cat > manage.sh << 'EOF'
#!/bin/bash

case "$1" in
    start)
        echo "🚀 Iniciando servicios..."
        docker-compose up -d
        echo "✅ Servicios iniciados"
        ;;
    stop)
        echo "🛑 Deteniendo servicios..."
        docker-compose down
        echo "✅ Servicios detenidos"
        ;;
    restart)
        echo "🔄 Reiniciando servicios..."
        docker-compose down && docker-compose up -d
        echo "✅ Servicios reiniciados"
        ;;
    status)
        echo "📊 Estado de los servicios:"
        docker-compose ps
        ;;
    logs)
        if [ -n "$2" ]; then
            docker-compose logs -f $2
        else
            docker-compose logs -f
        fi
        ;;
    update)
        echo "⬆️ Actualizando imágenes..."
        docker-compose pull
        docker-compose down
        docker-compose up -d
        echo "✅ Actualización completada"
        ;;
    backup)
        echo "💾 Creando backup..."
        DATE=$(date +%Y%m%d_%H%M%S)
        mkdir -p backups
        docker run --rm -v three-apps_minio_data:/minio_data -v three-apps_baserow_data:/baserow_data -v three-apps_postgres_data:/postgres_data -v $(pwd)/backups:/backup ubuntu tar czf /backup/backup_$DATE.tar.gz minio_data baserow_data postgres_data
        echo "✅ Backup creado: backups/backup_$DATE.tar.gz"
        ;;
    *)
        echo "🚀 Gestión de servicios MinIO + Baserow + Kokoro TTS"
        echo ""
        echo "Uso: $0 {start|stop|restart|status|logs|update|backup}"
        echo ""
        echo "Comandos:"
        echo "  start   - Iniciar todos los servicios"
        echo "  stop    - Detener todos los servicios"
        echo "  restart - Reiniciar todos los servicios"
        echo "  status  - Ver estado de los servicios"
        echo "  logs    - Ver logs (añadir nombre del servicio para logs específicos)"
        echo "  update  - Actualizar todas las imágenes"
        echo "  backup  - Crear backup de los datos"
        echo ""
        exit 1
        ;;
esac
EOF

chmod +x manage.sh

# Crear servicio systemd
print_status "Configurando servicio systemd..."
cat > /etc/systemd/system/three-apps.service << EOF
[Unit]
Description=Three Apps Stack (MinIO + Baserow + Kokoro TTS)
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable three-apps.service

# Configurar logrotate
print_status "Configurando rotación de logs..."
cat > /etc/logrotate.d/three-apps << 'EOF'
/var/lib/docker/containers/*/*.log {
    rotate 7
    daily
    compress
    size=10M
    missingok
    delaycompress
    copytruncate
}
EOF

# Crear cron para backup automático
print_status "Configurando backup automático..."
(crontab -l 2>/dev/null; echo "0 2 * * * cd $PROJECT_DIR && ./manage.sh backup") | crontab -

# Descargar imágenes
print_status "Descargando imágenes Docker (esto puede tomar varios minutos)..."
cd $PROJECT_DIR
docker-compose pull

# Iniciar servicios
print_status "Iniciando servicios..."
docker-compose up -d

# Esperar a que los servicios estén listos
print_status "Esperando a que los servicios estén listos..."
sleep 30

# Verificar estado
print_status "Verificando estado de los servicios..."
docker-compose ps

# Mostrar información final
print_success "🎉 ¡Instalación completada!"
echo ""
echo "🌐 Accede a tus aplicaciones:"
echo "   📋 Panel Principal: http://$SERVER_IP"
echo "   💾 MinIO Console: http://$SERVER_IP:9001 (minioadmin/minioadmin123)"
echo "   🗃️ Baserow: http://$SERVER_IP:3000"
echo "   🎙️ Kokoro TTS: http://$SERVER_IP:8000"
echo "   🐳 Portainer: https://$SERVER_IP:9443"
echo ""
echo "🔧 Gestión:"
echo "   📁 Directorio: $PROJECT_DIR"
echo "   ⚙️ Comandos: ./manage.sh {start|stop|restart|status|logs|update|backup}"
echo "   📊 Estado: systemctl status three-apps"
echo ""
echo "💾 Backup automático configurado para las 2:00 AM diariamente"
echo ""
print_warning "🔒 Recuerda cambiar las contraseñas por defecto en producción"
print_success "✅ ¡Tu servidor multi-herramientas está listo!"
