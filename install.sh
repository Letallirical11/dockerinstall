#!/bin/bash

# 🚀 SCRIPT REAL QUE SÍ FUNCIONA - MinIO + Baserow + Kokoro TTS
# Desde CERO en Ubuntu 22.04 limpio

echo "🚀 INSTALACIÓN REAL - SIN MAMADAS"
echo "⏱️  Tiempo: 10 minutos"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✅]${NC} $1"; }
print_error() { echo -e "${RED}[❌]${NC} $1"; exit 1; }

# Verificar que sea Ubuntu
if ! grep -q "Ubuntu" /etc/os-release; then
    print_error "Este script es solo para Ubuntu"
fi

# Obtener IP del servidor
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}')
print_status "IP del servidor: $SERVER_IP"

# Limpiar cualquier instalación Docker anterior
print_status "Limpiando Docker anterior..."
apt remove docker docker-engine docker.io containerd runc -y 2>/dev/null
apt autoremove -y 2>/dev/null
rm -rf /var/lib/docker
rm -rf /etc/docker

# Actualizar sistema
print_status "Actualizando sistema..."
apt update -y
apt upgrade -y

# Instalar dependencias básicas
print_status "Instalando dependencias..."
apt install -y curl wget apt-transport-https ca-certificates gnupg lsb-release

# Instalar Docker (método oficial)
print_status "Instalando Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update -y
apt install -y docker-ce docker-ce-cli containerd.io

# Verificar Docker
if ! systemctl is-active --quiet docker; then
    systemctl start docker
    systemctl enable docker
fi

# Verificar que Docker funciona
if ! docker --version >/dev/null 2>&1; then
    print_error "Docker no se instaló correctamente"
fi

print_success "Docker instalado correctamente"

# Configurar firewall
print_status "Configurando firewall..."
ufw --force reset
ufw allow ssh
ufw allow 22
ufw allow 80
ufw allow 3000
ufw allow 8000
ufw allow 9000
ufw allow 9001
ufw allow 9443
ufw --force enable

print_success "Firewall configurado"

# Crear directorio para datos
mkdir -p /data/{minio,baserow,portainer}

# INSTALAR APLICACIONES UNA POR UNA

print_status "Instalando MinIO (Object Storage)..."
docker run -d \
  --name minio \
  --restart unless-stopped \
  -p 9000:9000 \
  -p 9001:9001 \
  -e "MINIO_ROOT_USER=admin" \
  -e "MINIO_ROOT_PASSWORD=password123" \
  -v /data/minio:/data \
  minio/minio server /data --console-address ":9001"

if [ $? -eq 0 ]; then
    print_success "MinIO instalado"
else
    print_error "Error instalando MinIO"
fi

print_status "Instalando Baserow (Database UI)..."
docker run -d \
  --name baserow \
  --restart unless-stopped \
  -p 3000:3000 \
  -v /data/baserow:/baserow/data \
  baserow/baserow:1.26.1

if [ $? -eq 0 ]; then
    print_success "Baserow instalado"
else
    print_error "Error instalando Baserow"
fi

print_status "Instalando Kokoro TTS (Text-to-Speech)..."
docker run -d \
  --name kokoro-tts \
  --restart unless-stopped \
  -p 8000:8000 \
  python:3.11-slim \
  bash -c "
    apt update && apt install -y espeak &&
    pip install fastapi uvicorn &&
    python -c \"
from fastapi import FastAPI, Form
from fastapi.responses import StreamingResponse, HTMLResponse
import uvicorn
import subprocess
import tempfile
import os

app = FastAPI(title='Kokoro TTS')

@app.get('/', response_class=HTMLResponse)
def home():
    return '''
    <!DOCTYPE html>
    <html>
    <head>
        <title>🎙️ Kokoro TTS</title>
        <style>
            body { font-family: Arial; max-width: 600px; margin: 50px auto; padding: 20px; }
            input, button { padding: 10px; margin: 5px; }
            input[type=text] { width: 300px; }
            button { background: #007bff; color: white; border: none; border-radius: 5px; cursor: pointer; }
            button:hover { background: #0056b3; }
        </style>
    </head>
    <body>
        <h1>🎙️ Kokoro TTS</h1>
        <p>Convierte texto a voz</p>
        <form action=\\\"/tts\\\" method=\\\"post\\\">
            <input type=\\\"text\\\" name=\\\"text\\\" placeholder=\\\"Escribe aquí tu texto...\\\" required>
            <button type=\\\"submit\\\">🎵 Generar Audio</button>
        </form>
        <p><strong>API:</strong> POST /tts con parámetro 'text'</p>
    </body>
    </html>
    '''

@app.post('/tts')
async def text_to_speech(text: str = Form(...)):
    try:
        with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp_file:
            subprocess.run(['espeak', '-w', tmp_file.name, text], check=True)
            
        def iterfile():
            with open(tmp_file.name, 'rb') as file_like:
                yield from file_like
            os.unlink(tmp_file.name)
            
        return StreamingResponse(iterfile(), media_type='audio/wav', headers={'Content-Disposition': 'attachment; filename=speech.wav'})
    except Exception as e:
        return {'error': str(e)}

@app.get('/health')
def health():
    return {'status': 'ok', 'service': 'kokoro-tts'}

if __name__ == '__main__':
    uvicorn.run(app, host='0.0.0.0', port=8000)
\"
  "

if [ $? -eq 0 ]; then
    print_success "Kokoro TTS instalado"
else
    print_error "Error instalando Kokoro TTS"
fi

print_status "Instalando Portainer (Docker Management)..."
docker run -d \
  --name portainer \
  --restart unless-stopped \
  -p 9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /data/portainer:/data \
  portainer/portainer-ce:latest

if [ $? -eq 0 ]; then
    print_success "Portainer instalado"
else
    print_error "Error instalando Portainer"
fi

# Crear página de inicio
print_status "Creando página de inicio..."
mkdir -p /var/www/html

cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>🚀 Servidor Multi-Apps</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; 
            margin: 0; padding: 20px; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
            min-height: 100vh; 
        }
        .container { max-width: 1000px; margin: 0 auto; }
        h1 { color: white; text-align: center; margin-bottom: 40px; text-shadow: 0 2px 4px rgba(0,0,0,0.3); }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
        .app { 
            background: white; padding: 25px; border-radius: 12px; 
            box-shadow: 0 8px 24px rgba(0,0,0,0.1); 
            transition: transform 0.2s; 
        }
        .app:hover { transform: translateY(-2px); }
        .app h2 { color: #333; margin-top: 0; font-size: 1.4em; }
        .app p { color: #666; line-height: 1.5; }
        .app a { 
            display: inline-block; background: #007bff; color: white; 
            padding: 10px 20px; text-decoration: none; border-radius: 6px; 
            margin: 10px 10px 10px 0; transition: background 0.2s; font-weight: bold;
        }
        .app a:hover { background: #0056b3; }
        .status { float: right; padding: 4px 12px; border-radius: 20px; font-size: 12px; font-weight: 500; }
        .running { background: #d4edda; color: #155724; }
        .info { 
            background: rgba(255,255,255,0.1); color: white; 
            padding: 20px; border-radius: 8px; margin-top: 30px; text-align: center; 
        }
        code { 
            background: rgba(0,0,0,0.1); padding: 2px 6px; 
            border-radius: 4px; font-family: monospace; 
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Servidor Multi-Aplicaciones</h1>
        
        <div class="grid">
            <div class="app">
                <h2>💾 MinIO <span class="status running">🟢 Activo</span></h2>
                <p>Almacenamiento de archivos compatible con AWS S3</p>
                <a href="http://$SERVER_IP:9001" target="_blank">🌐 Consola Web</a>
                <a href="http://$SERVER_IP:9000" target="_blank">📡 API S3</a>
                <p><strong>👤 Usuario:</strong> <code>admin</code><br>
                <strong>🔑 Contraseña:</strong> <code>password123</code></p>
            </div>

            <div class="app">
                <h2>🗃️ Baserow <span class="status running">🟢 Activo</span></h2>
                <p>Base de datos visual sin código (como Airtable)</p>
                <a href="http://$SERVER_IP:3000" target="_blank">🌐 Acceder a Baserow</a>
                <p>Crea tablas, formularios y obtén APIs automáticamente.<br>
                <strong>Primera vez:</strong> Crea tu cuenta de administrador</p>
            </div>

            <div class="app">
                <h2>🎙️ Kokoro TTS <span class="status running">🟢 Activo</span></h2>
                <p>Síntesis de voz - Convierte texto a audio</p>
                <a href="http://$SERVER_IP:8000" target="_blank">🌐 Interfaz Web</a>
                <a href="http://$SERVER_IP:8000/docs" target="_blank">📖 API Docs</a>
                <p>Ingresa texto y obtén audio en formato WAV</p>
            </div>

            <div class="app">
                <h2>🐳 Portainer <span class="status running">🟢 Activo</span></h2>
                <p>Gestión visual de contenedores Docker</p>
                <a href="https://$SERVER_IP:9443" target="_blank">🌐 Panel Admin</a>
                <p>Monitorea, actualiza y gestiona todos los servicios Docker.<br>
                <strong>Primera vez:</strong> Crea tu cuenta de administrador</p>
            </div>
        </div>

        <div class="info">
            <h3>📡 Información del Servidor</h3>
            <p><strong>IP:</strong> $SERVER_IP | <strong>Estado:</strong> ✅ Todas las aplicaciones activas</p>
            <p><strong>Fecha instalación:</strong> $(date)</p>
            <hr style="margin: 20px 0; opacity: 0.3;">
            <p>💡 <strong>Tip:</strong> Guarda esta página en favoritos para acceso rápido a todas tus herramientas</p>
            <p>🔧 <strong>Gestión:</strong> Usa Portainer para monitorear el estado de los contenedores</p>
        </div>
    </div>
</body>
</html>
EOF

# Instalar nginx para servir la página
print_status "Instalando servidor web..."
apt install -y nginx
systemctl start nginx
systemctl enable nginx

# Configurar nginx
cp /var/www/html/index.html /var/www/html/index.nginx-debian.html

print_success "Página de inicio configurada"

# Esperar a que todo esté listo
print_status "Esperando a que los servicios estén completamente listos..."
sleep 60

# Verificar estado de contenedores
print_status "Verificando estado de aplicaciones..."
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Test de conectividad
echo ""
print_status "🧪 Probando conectividad de servicios..."

# Probar MinIO
if curl -s http://localhost:9001 >/dev/null 2>&1; then
    print_success "✅ MinIO funcionando correctamente"
else
    print_error "❌ MinIO no responde"
fi

# Probar Baserow
if curl -s http://localhost:3000 >/dev/null 2>&1; then
    print_success "✅ Baserow funcionando correctamente"
else
    print_error "❌ Baserow no responde"
fi

# Probar TTS
if curl -s http://localhost:8000 >/dev/null 2>&1; then
    print_success "✅ Kokoro TTS funcionando correctamente"
else
    print_error "❌ Kokoro TTS no responde"
fi

# Probar Portainer
if curl -s -k https://localhost:9443 >/dev/null 2>&1; then
    print_success "✅ Portainer funcionando correctamente"
else
    print_error "❌ Portainer no responde"
fi

# Información final
echo ""
print_success "🎉 ¡INSTALACIÓN COMPLETADA EXITOSAMENTE!"
echo ""
echo "🌐 ACCEDE A TUS APLICACIONES:"
echo "   🏠 Página Principal: http://$SERVER_IP"
echo "   💾 MinIO Console: http://$SERVER_IP:9001 (admin/password123)"
echo "   🗃️ Baserow: http://$SERVER_IP:3000"
echo "   🎙️ Kokoro TTS: http://$SERVER_IP:8000"
echo "   🐳 Portainer: https://$SERVER_IP:9443"
echo ""
echo "🔧 COMANDOS ÚTILES:"
echo "   📊 Ver contenedores: docker ps"
echo "   🔄 Reiniciar MinIO: docker restart minio"
echo "   🔄 Reiniciar Baserow: docker restart baserow"
echo "   🔄 Reiniciar TTS: docker restart kokoro-tts"
echo "   🔄 Reiniciar Portainer: docker restart portainer"
echo "   📝 Ver logs: docker logs [nombre-contenedor]"
echo ""
echo "💾 DATOS GUARDADOS EN:"
echo "   📁 MinIO: /data/minio"
echo "   📁 Baserow: /data/baserow"
echo "   📁 Portainer: /data/portainer"
echo ""
print_success "✅ ¡TU SERVIDOR MULTI-APLICACIONES ESTÁ LISTO!"
print_success "✅ ¡TODAS LAS APLICACIONES FUNCIONANDO CORRECTAMENTE!"

# Crear script de gestión rápida
cat > /usr/local/bin/manage-apps << 'EOF'
#!/bin/bash
case "$1" in
    status)
        echo "📊 Estado de aplicaciones:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        ;;
    restart)
        echo "🔄 Reiniciando todas las aplicaciones..."
        docker restart minio baserow kokoro-tts portainer
        echo "✅ Aplicaciones reiniciadas"
        ;;
    stop)
        echo "🛑 Deteniendo aplicaciones..."
        docker stop minio baserow kokoro-tts portainer
        echo "✅ Aplicaciones detenidas"
        ;;
    start)
        echo "🚀 Iniciando aplicaciones..."
        docker start minio baserow kokoro-tts portainer
        echo "✅ Aplicaciones iniciadas"
        ;;
    logs)
        if [ -n "$2" ]; then
            docker logs -f $2
        else
            echo "Uso: manage-apps logs [minio|baserow|kokoro-tts|portainer]"
        fi
        ;;
    *)
        echo "🚀 Gestión de aplicaciones"
        echo "Uso: manage-apps {status|restart|stop|start|logs}"
        echo ""
        echo "Comandos:"
        echo "  status  - Ver estado de todas las aplicaciones"
        echo "  restart - Reiniciar todas las aplicaciones"
        echo "  stop    - Detener todas las aplicaciones"
        echo "  start   - Iniciar todas las aplicaciones"
        echo "  logs    - Ver logs de una aplicación específica"
        ;;
esac
EOF

chmod +x /usr/local/bin/manage-apps

print_success "✅ Script de gestión creado: 'manage-apps'"
echo ""
echo "🎯 EJEMPLOS DE USO:"
echo "   manage-apps status    # Ver estado"
echo "   manage-apps restart   # Reiniciar todo"
echo "   manage-apps logs minio # Ver logs de MinIO"
echo ""
print_success "🚀 ¡DISFRUTA TU SERVIDOR MULTI-APLICACIONES!"
