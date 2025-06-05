#!/bin/bash

echo "Instalando Docker y aplicaciones..."

# Obtener IP del servidor
SERVER_IP=$(curl -s ifconfig.me)
echo "IP del servidor: $SERVER_IP"

# Actualizar sistema
apt update -y
apt install -y curl

# Instalar Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh

# Iniciar Docker
systemctl start docker
systemctl enable docker

# Configurar firewall
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
mkdir -p /data

echo "Instalando MinIO..."
docker run -d --name minio --restart unless-stopped -p 9000:9000 -p 9001:9001 -e MINIO_ROOT_USER=admin -e MINIO_ROOT_PASSWORD=password123 -v /data:/data minio/minio server /data --console-address ":9001"

echo "Instalando Baserow..."
docker run -d --name baserow --restart unless-stopped -p 3000:3000 baserow/baserow:1.26.1

echo "Instalando TTS Simple..."
docker run -d --name simple-tts --restart unless-stopped -p 8000:8000 nginx:alpine

echo "Instalando Portainer..."
docker run -d --name portainer --restart unless-stopped -p 9443:9443 -v /var/run/docker.sock:/var/run/docker.sock portainer/portainer-ce

# Instalar nginx
apt install -y nginx
systemctl start nginx

# Crear página simple
echo '<!DOCTYPE html>
<html>
<head><title>Servidor Apps</title></head>
<body style="font-family: Arial; padding: 20px;">
<h1>Servidor Multi-Apps</h1>
<h2>MinIO</h2>
<p><a href="http://IP_PLACEHOLDER:9001">MinIO Console</a> (admin/password123)</p>
<h2>Baserow</h2>
<p><a href="http://IP_PLACEHOLDER:3000">Baserow Database</a></p>
<h2>TTS</h2>
<p><a href="http://IP_PLACEHOLDER:8000">TTS Service</a></p>
<h2>Portainer</h2>
<p><a href="https://IP_PLACEHOLDER:9443">Portainer Admin</a></p>
</body>
</html>' > /var/www/html/index.html

# Reemplazar placeholder con IP real
sed -i "s/IP_PLACEHOLDER/$SERVER_IP/g" /var/www/html/index.html

echo "Esperando 60 segundos..."
sleep 60

echo "Estado de contenedores:"
docker ps

echo ""
echo "INSTALACION COMPLETADA"
echo ""
echo "Accede a:"
echo "Pagina principal: http://$SERVER_IP"
echo "MinIO: http://$SERVER_IP:9001 (admin/password123)"
echo "Baserow: http://$SERVER_IP:3000"
echo "TTS: http://$SERVER_IP:8000"
echo "Portainer: https://$SERVER_IP:9443"
echo ""
echo "LISTO!"
