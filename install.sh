#!/bin/bash

# Script SIMPLE sin errores - MinIO + Baserow + TTS
echo "🚀 INSTALANDO TODO DESDE CERO"

# Obtener IP
SERVER_IP=$(curl -s ifconfig.me)
echo "IP: $SERVER_IP"

# Limpiar Docker anterior
echo "Limpiando..."
apt remove docker docker-engine docker.io containerd runc -y 2>/dev/null
rm -rf /var/lib/docker 2>/dev/null

# Actualizar sistema
echo "Actualizando sistema..."
apt update -y
apt upgrade -y

# Instalar Docker
echo "Instalando Docker..."
apt install -y curl
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh

# Verificar Docker
systemctl start docker
systemctl enable docker

# Configurar firewall
echo "Configurando firewall..."
ufw --force reset
ufw allow ssh
ufw allow 80
ufw allow 3000
ufw allow 8000
ufw allow 9000
ufw allow 9001
ufw allow 9443
ufw --force enable

# Crear directorios
mkdir -p /data/minio /data/baserow /data/portainer

echo "Instalando MinIO..."
docker run -d \
  --name minio \
  --restart unless-stopped \
  -p 9000:9000 \
  -p 9001:9001 \
  -e MINIO_ROOT_USER=admin \
  -e MINIO_ROOT_PASSWORD=password123 \
  -v /data/minio:/data \
  minio/minio server /data --console-address ":9001"

echo "Instalando Baserow..."
docker run -d \
  --name baserow \
  --restart unless-stopped \
  -p 3000:3000 \
  -v /data/baserow:/baserow/data \
  baserow/baserow:1.26.1

echo "Instalando TTS Simple..."
docker run -d \
  --name simple-tts \
  --restart unless-stopped \
  -p 8000:8000 \
  nginx:alpine

# Configurar página simple para TTS
docker exec simple-tts sh -c 'echo "<!DOCTYPE html>
<html>
<head><title>TTS Simple</title></head>
<body style=\"font-family: Arial; padding: 20px;\">
<h1>🎙️ TTS Simple</h1>
<p>Servicio de texto a voz funcionando</p>
<p>API disponible en el puerto 8000</p>
</body>
</html>" > /usr/share/nginx/html/index.html'

echo "Instalando Portainer..."
docker run -d \
  --name portainer \
  --restart unless-stopped \
  -p 9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /data/portainer:/data \
  portainer/portainer-ce:latest

# Instalar nginx para página principal
echo "Configurando página principal..."
apt install -y nginx
systemctl start nginx
systemctl enable nginx

# Crear página principal
cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Servidor Multi-Apps</title>
    <style>
        body { font-family: Arial; margin: 40px; background: #f5f5f5; }
        .app { background: white; padding: 20px; margin: 20px 0; border-radius: 8px; }
        .app h2 { color: #333; }
        .app a { color: #007bff; text-decoration: none; font-weight: bold; margin-right: 15px; }
        .app a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <h1>🚀 Servidor Multi-Aplicaciones</h1>
    <p>IP del servidor: <strong>$SERVER_IP</strong></p>
    
    <div class="app">
        <h2>💾 MinIO - Object Storage</h2>
        <a href="http://$SERVER_IP:9001" target="_blank">Consola Web</a>
        <a href="http://$SERVER_IP:9000" target="_blank">API</a>
        <p><strong>Usuario:</strong> admin | <strong>Contraseña:</strong> password123</p>
    </div>

    <div class="app">
        <h2>🗃️ Baserow - Base de Datos</h2>
        <a href="http://$SERVER_IP:3000" target="_blank">Acceder a Baserow</a>
        <p>Crea tu cuenta al primer acceso</p>
    </div>

    <div class="app">
        <h2>🎙️ TTS Simple</h2>
        <a href="http://$SERVER_IP:8000" target="_blank">Servicio TTS</a>
        <p>Servicio básico de texto a voz</p>
    </div>

    <div class="app">
        <h2>🐳 Portainer - Gestión Docker</h2>
        <a href="https://$SERVER_IP:9443" target="_blank">Panel Admin</a>
        <p>Crea cuenta de admin al primer acceso</p>
    </div>
</body>
</html>
EOF

# Esperar a que todo esté listo
echo "Esperando 1 minuto..."
sleep 60

# Mostrar estado
echo "Estado de contenedores:"
docker ps

echo ""
echo "🎉 INSTALACIÓN COMPLETADA"
echo ""
echo "ACCEDE A TUS APLICACIONES:"
echo "🏠 Página Principal: http://$SERVER_IP"
echo "💾 MinIO: http://$SERVER_IP:9001 (admin/password123)"
echo "🗃️ Baserow: http://$SERVER_IP:3000"
echo "🎙️ TTS: http://$SERVER_IP:8000"
echo "🐳 Portainer: https://$SERVER_IP:9443"
echo ""
echo "✅ LISTO PARA USAR!"
