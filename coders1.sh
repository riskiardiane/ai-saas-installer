#!/bin/bash

# AI Platform Auto Installer v2.0 - FIXED
# Perbaikan: 502 Bad Gateway, DNS Cloudflare, Health Checks
# Mendukung berbagai model AI: Coding, Chat, Image Gen, Video Gen, TTS, dll

set -e

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Fungsi untuk print dengan warna
print_info() {
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

print_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Banner
clear
echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║       AI Platform Auto Installer v2.0 FIXED          ║"
echo "║  Coding | Chat | Image | Video | TTS | Translation  ║"
echo "║         🔧 502 Error Fixed + Auto DNS Setup          ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check root
if [[ $EUID -ne 0 ]]; then
   print_error "Script ini harus dijalankan sebagai root"
   exit 1
fi

# Variabel global
INSTALL_DIR="/opt/ai-platform"
NGINX_CONF="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
LOG_FILE="/var/log/ai-platform-install.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

# ==========================================
# FUNGSI INSTALASI DEPENDENCIES
# ==========================================

install_dependencies() {
    print_step "Menginstal dependencies sistem..."
    log "Installing system dependencies"
    
    apt-get update -qq
    apt-get install -y -qq curl wget git build-essential python3 python3-pip python3-venv \
                       software-properties-common apt-transport-https ca-certificates \
                       gnupg lsb-release jq unzip net-tools dnsutils ufw \
                       > /dev/null 2>&1
    
    print_success "Dependencies terinstal"
    log "Dependencies installed successfully"
}

# ==========================================
# FUNGSI INSTALASI DOCKER
# ==========================================

install_docker() {
    if command -v docker &> /dev/null; then
        print_warning "Docker sudah terinstal"
        log "Docker already installed"
        return
    fi
    
    print_step "Menginstal Docker..."
    log "Installing Docker"
    
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh > /dev/null 2>&1
    systemctl enable docker > /dev/null 2>&1
    systemctl start docker
    
    # Install Docker Compose
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
         -o /usr/local/bin/docker-compose 2>/dev/null
    chmod +x /usr/local/bin/docker-compose
    
    print_success "Docker terinstal (Version: $(docker --version | cut -d' ' -f3))"
    log "Docker installed successfully"
}

# ==========================================
# FUNGSI INSTALASI NVIDIA DOCKER (GPU)
# ==========================================

install_nvidia_docker() {
    read -p "Apakah server memiliki GPU NVIDIA? (Y/N): " gpu_choice
    if [[ $gpu_choice =~ ^[Yy]$ ]]; then
        print_step "Menginstal NVIDIA Docker Runtime..."
        log "Installing NVIDIA Docker Runtime"
        
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
        curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
        curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
            tee /etc/apt/sources.list.d/nvidia-docker.list
        
        apt-get update -qq
        apt-get install -y -qq nvidia-docker2 > /dev/null 2>&1
        systemctl restart docker
        
        print_success "NVIDIA Docker Runtime terinstal"
        log "NVIDIA Docker Runtime installed"
        USE_GPU=true
    else
        USE_GPU=false
        print_info "Instalasi tanpa GPU support"
        log "Installation without GPU support"
    fi
}

# ==========================================
# FUNGSI INSTALASI NGINX
# ==========================================

install_nginx() {
    read -p "Install Nginx sebagai reverse proxy? (Y/N): " nginx_choice
    if [[ ! $nginx_choice =~ ^[Yy]$ ]]; then
        INSTALL_NGINX=false
        return
    fi
    
    INSTALL_NGINX=true
    print_step "Menginstal Nginx..."
    log "Installing Nginx"
    
    apt-get install -y -qq nginx > /dev/null 2>&1
    
    # Konfigurasi Nginx untuk menghindari 502
    cat > /etc/nginx/nginx.conf <<'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 4096;
    multi_accept on;
    use epoll;
}

http {
    # Basic Settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;
    
    # Timeouts untuk mencegah 502
    proxy_connect_timeout 600;
    proxy_send_timeout 600;
    proxy_read_timeout 600;
    send_timeout 600;
    
    # Buffer settings untuk mencegah 502
    proxy_buffer_size 128k;
    proxy_buffers 4 256k;
    proxy_busy_buffers_size 256k;
    
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    
    # Gzip Settings
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript 
               application/json application/javascript application/xml+rss 
               application/rss+xml font/truetype font/opentype 
               application/vnd.ms-fontobject image/svg+xml;
    
    # Virtual Host Configs
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF
    
    systemctl enable nginx > /dev/null 2>&1
    systemctl start nginx
    
    print_success "Nginx terinstal dengan konfigurasi anti-502"
    log "Nginx installed with anti-502 configuration"
}

# ==========================================
# FUNGSI INSTALASI DATABASE
# ==========================================

install_database() {
    read -p "Install Database (PostgreSQL)? (Y/N): " db_choice
    if [[ ! $db_choice =~ ^[Yy]$ ]]; then
        INSTALL_DB=false
        return
    fi
    
    INSTALL_DB=true
    read -p "Database name [ai_platform]: " DB_NAME
    DB_NAME=${DB_NAME:-ai_platform}
    
    read -p "Database user [aiuser]: " DB_USER
    DB_USER=${DB_USER:-aiuser}
    
    read -sp "Database password: " DB_PASSWORD
    echo
    DB_PASSWORD=${DB_PASSWORD:-$(openssl rand -base64 16)}
    
    print_step "Menginstal PostgreSQL..."
    log "Installing PostgreSQL"
    
    apt-get install -y -qq postgresql postgresql-contrib > /dev/null 2>&1
    
    # Konfigurasi database
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;" 2>/dev/null || true
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';" 2>/dev/null || true
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;" 2>/dev/null || true
    
    print_success "PostgreSQL terinstal"
    print_info "Database: $DB_NAME | User: $DB_USER | Password: $DB_PASSWORD"
    log "PostgreSQL installed - DB: $DB_NAME"
    
    # Simpan credentials
    cat > $INSTALL_DIR/db-credentials.txt <<EOF
Database Name: $DB_NAME
Database User: $DB_USER
Database Password: $DB_PASSWORD
EOF
    chmod 600 $INSTALL_DIR/db-credentials.txt
}

# ==========================================
# FUNGSI VALIDASI DAN SETUP CLOUDFLARE DNS
# ==========================================

validate_cloudflare_credentials() {
    local zone_id=$1
    local api_key=$2
    
    # Test API credentials
    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id" \
        -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json")
    
    success=$(echo $response | jq -r '.success')
    
    if [ "$success" = "true" ]; then
        return 0
    else
        return 1
    fi
}

setup_cloudflare() {
    read -p "Setup Cloudflare DNS? (Y/N): " cf_choice
    if [[ ! $cf_choice =~ ^[Yy]$ ]]; then
        SETUP_CF=false
        return
    fi
    
    SETUP_CF=true
    
    print_step "Konfigurasi Cloudflare DNS..."
    echo
    print_info "📌 Cara mendapatkan Cloudflare credentials:"
    echo "   1. Login ke https://dash.cloudflare.com"
    echo "   2. Pilih domain Anda"
    echo "   3. Zone ID ada di sidebar kanan bawah"
    echo "   4. API Token: My Profile > API Tokens > Create Token"
    echo "      - Pilih 'Edit zone DNS' template"
    echo "      - Zone Resources: Include > Specific zone > [domain Anda]"
    echo
    
    while true; do
        read -p "Cloudflare Zone ID: " CF_ZONE_ID
        read -p "Cloudflare API Token: " CF_API_KEY
        
        print_info "Memvalidasi credentials..."
        if validate_cloudflare_credentials "$CF_ZONE_ID" "$CF_API_KEY"; then
            print_success "Cloudflare credentials valid!"
            break
        else
            print_error "Credentials tidak valid! Silakan coba lagi."
            read -p "Coba lagi? (Y/N): " retry
            [[ ! $retry =~ ^[Yy]$ ]] && return
        fi
    done
    
    read -p "Subdomain (contoh: ai untuk ai.domain.com): " SUBDOMAIN
    
    # Dapatkan zone name dari API
    ZONE_NAME=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID" \
        -H "Authorization: Bearer $CF_API_KEY" \
        -H "Content-Type: application/json" | jq -r '.result.name')
    
    DOMAIN="$SUBDOMAIN.$ZONE_NAME"
    
    # Dapatkan IP public
    PUBLIC_IP=$(curl -s https://api.ipify.org)
    
    print_info "Domain: $DOMAIN"
    print_info "IP Server: $PUBLIC_IP"
    
    # Cek apakah record sudah ada
    print_step "Mengecek DNS record yang ada..."
    RECORD_CHECK=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?name=$DOMAIN" \
        -H "Authorization: Bearer $CF_API_KEY" \
        -H "Content-Type: application/json")
    
    RECORD_ID=$(echo $RECORD_CHECK | jq -r '.result[0].id')
    
    if [ "$RECORD_ID" != "null" ] && [ -n "$RECORD_ID" ]; then
        # Update existing record
        print_step "Mengupdate DNS record yang ada..."
        UPDATE_RESULT=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$RECORD_ID" \
            -H "Authorization: Bearer $CF_API_KEY" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"$DOMAIN\",\"content\":\"$PUBLIC_IP\",\"ttl\":1,\"proxied\":false}")
        
        if [ "$(echo $UPDATE_RESULT | jq -r '.success')" = "true" ]; then
            print_success "DNS record berhasil diupdate"
        else
            print_error "Gagal update DNS record"
            echo $UPDATE_RESULT | jq '.'
        fi
    else
        # Create new record
        print_step "Membuat DNS record baru..."
        CREATE_RESULT=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CF_API_KEY" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"$DOMAIN\",\"content\":\"$PUBLIC_IP\",\"ttl\":1,\"proxied\":false}")
        
        if [ "$(echo $CREATE_RESULT | jq -r '.success')" = "true" ]; then
            print_success "DNS record berhasil dibuat"
        else
            print_error "Gagal membuat DNS record"
            echo $CREATE_RESULT | jq '.'
        fi
    fi
    
    print_warning "⚠️  PENTING: DNS Proxied diset ke OFF (DNS only) untuk mencegah 502"
    print_info "Anda bisa mengaktifkan proxy Cloudflare setelah SSL terinstall"
    
    # Wait for DNS propagation
    print_step "Menunggu DNS propagasi (30 detik)..."
    sleep 30
    
    # Verify DNS
    print_step "Verifikasi DNS..."
    RESOLVED_IP=$(dig +short $DOMAIN @1.1.1.1 | tail -n1)
    
    if [ "$RESOLVED_IP" = "$PUBLIC_IP" ]; then
        print_success "DNS berhasil diverifikasi! $DOMAIN → $PUBLIC_IP"
    else
        print_warning "DNS belum sepenuhnya propagasi. Tunggu 5-10 menit."
        print_info "Resolved IP: $RESOLVED_IP | Expected: $PUBLIC_IP"
    fi
    
    log "Cloudflare DNS configured: $DOMAIN → $PUBLIC_IP"
}

# ==========================================
# FUNGSI KONFIGURASI FIREWALL
# ==========================================

setup_firewall() {
    print_step "Konfigurasi Firewall (UFW)..."
    log "Configuring firewall"
    
    ufw --force enable > /dev/null 2>&1
    ufw default deny incoming > /dev/null 2>&1
    ufw default allow outgoing > /dev/null 2>&1
    
    ufw allow 22/tcp > /dev/null 2>&1  # SSH
    ufw allow 80/tcp > /dev/null 2>&1  # HTTP
    ufw allow 443/tcp > /dev/null 2>&1 # HTTPS
    
    print_success "Firewall dikonfigurasi (Port 22, 80, 443 terbuka)"
    log "Firewall configured"
}

# ==========================================
# FUNGSI PILIH MODEL AI
# ==========================================

select_ai_models() {
    print_info "Pilih model AI yang akan diinstal:"
    echo
    
    # Coding Models
    read -p "1. Install Qwen Coder (Code Generation)? (Y/N): " model_qwen
    
    # Chat Models
    read -p "2. Install Llama 3 (General Chat)? (Y/N): " model_llama
    read -p "3. Install Mistral (Fast Chat)? (Y/N): " model_mistral
    
    # Image Generation
    read -p "4. Install Stable Diffusion XL (Image Generation)? (Y/N): " model_sdxl
    
    # Text-to-Speech
    read -p "5. Install Coqui TTS (Text-to-Speech)? (Y/N): " model_tts
    
    # Vision
    read -p "6. Install LLaVA (Vision/Image Understanding)? (Y/N): " model_vision
    
    echo
    # Web Chat Interface
    read -p "7. Aktifkan Chat AI Web Interface? (Y/N): " enable_web_chat
    
    log "Model selection completed"
}

# ==========================================
# FUNGSI SETUP OLLAMA (untuk model chat & code)
# ==========================================

setup_ollama() {
    if [[ $model_qwen =~ ^[Yy]$ ]] || [[ $model_llama =~ ^[Yy]$ ]] || [[ $model_mistral =~ ^[Yy]$ ]] || [[ $model_vision =~ ^[Yy]$ ]]; then
        print_step "Menginstal Ollama..."
        log "Installing Ollama"
        
        curl -fsSL https://ollama.com/install.sh | sh > /dev/null 2>&1
        
        # Konfigurasi Ollama service untuk bind ke semua interface
        mkdir -p /etc/systemd/system/ollama.service.d
        cat > /etc/systemd/system/ollama.service.d/override.conf <<EOF
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF
        
        systemctl daemon-reload
        systemctl enable ollama > /dev/null 2>&1
        systemctl restart ollama
        
        print_info "Menunggu Ollama service siap (15 detik)..."
        sleep 15
        
        # Verify Ollama is running
        if curl -s http://localhost:11434/api/tags > /dev/null; then
            print_success "Ollama service berjalan"
        else
            print_error "Ollama service gagal start"
            systemctl status ollama
        fi
        
        # Pull models
        if [[ $model_qwen =~ ^[Yy]$ ]]; then
            print_info "Downloading Qwen Coder (ini akan memakan waktu)..."
            ollama pull qwen2.5-coder:7b
            print_success "Qwen Coder terinstall"
        fi
        
        if [[ $model_llama =~ ^[Yy]$ ]]; then
            print_info "Downloading Llama 3..."
            ollama pull llama3.2:3b
            print_success "Llama 3 terinstall"
        fi
        
        if [[ $model_mistral =~ ^[Yy]$ ]]; then
            print_info "Downloading Mistral..."
            ollama pull mistral:7b
            print_success "Mistral terinstall"
        fi
        
        if [[ $model_vision =~ ^[Yy]$ ]]; then
            print_info "Downloading LLaVA..."
            ollama pull llava:7b
            print_success "LLaVA terinstall"
        fi
        
        print_success "Ollama dan model terinstal"
        log "Ollama installed with selected models"
    fi
}

# ==========================================
# FUNGSI SETUP STABLE DIFFUSION
# ==========================================

setup_image_generation() {
    if [[ $model_sdxl =~ ^[Yy]$ ]]; then
        print_step "Setup Image Generation dengan ComfyUI..."
        log "Installing ComfyUI"
        
        mkdir -p $INSTALL_DIR/comfyui
        cd $INSTALL_DIR/comfyui
        
        # Clone ComfyUI
        git clone https://github.com/comfyanonymous/ComfyUI.git > /dev/null 2>&1
        cd ComfyUI
        
        # Install dependencies
        python3 -m venv venv
        source venv/bin/activate
        pip install -q torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
        pip install -q -r requirements.txt
        
        # Download models
        mkdir -p models/checkpoints
        
        print_info "Downloading Stable Diffusion XL (ini file besar ~6.5GB)..."
        wget -q --show-progress -O models/checkpoints/sd_xl_base_1.0.safetensors \
            "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors"
        
        # Create systemd service
        cat > /etc/systemd/system/comfyui.service <<EOF
[Unit]
Description=ComfyUI Image Generation
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR/comfyui/ComfyUI
Environment="PATH=$INSTALL_DIR/comfyui/ComfyUI/venv/bin"
ExecStart=$INSTALL_DIR/comfyui/ComfyUI/venv/bin/python main.py --listen 0.0.0.0 --port 8188
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        systemctl enable comfyui > /dev/null 2>&1
        systemctl start comfyui
        
        sleep 5
        
        print_success "ComfyUI terinstal di port 8188"
        log "ComfyUI installed on port 8188"
    fi
}

# ==========================================
# FUNGSI SETUP TEXT-TO-SPEECH
# ==========================================

setup_tts() {
    if [[ $model_tts =~ ^[Yy]$ ]]; then
        print_step "Setup Coqui TTS..."
        log "Installing TTS service"
        
        mkdir -p $INSTALL_DIR/tts
        cd $INSTALL_DIR/tts
        
        python3 -m venv venv
        source venv/bin/activate
        pip install -q TTS flask
        
        # Create API server
        cat > server.py <<'EOF'
from flask import Flask, request, send_file, jsonify
from TTS.api import TTS
import os
import tempfile

app = Flask(__name__)

# Initialize TTS
try:
    tts = TTS("tts_models/multilingual/multi-dataset/xtts_v2")
    print("TTS model loaded successfully")
except Exception as e:
    print(f"Error loading TTS model: {e}")
    tts = None

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy", "model_loaded": tts is not None})

@app.route('/tts', methods=['POST'])
def text_to_speech():
    if tts is None:
        return jsonify({"error": "TTS model not loaded"}), 500
    
    try:
        data = request.json
        text = data.get('text', '')
        language = data.get('language', 'en')
        
        if not text:
            return jsonify({"error": "No text provided"}), 400
        
        # Create temp file
        with tempfile.NamedTemporaryFile(delete=False, suffix='.wav') as tmp:
            output_path = tmp.name
        
        tts.tts_to_file(text=text, language=language, file_path=output_path)
        
        return send_file(output_path, mimetype='audio/wav')
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF
        
        # Create systemd service
        cat > /etc/systemd/system/tts.service <<EOF
[Unit]
Description=TTS Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR/tts
Environment="PATH=$INSTALL_DIR/tts/venv/bin"
ExecStart=$INSTALL_DIR/tts/venv/bin/python server.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        systemctl enable tts > /dev/null 2>&1
        systemctl start tts
        
        sleep 5
        
        print_success "TTS Service terinstal di port 5000"
        log "TTS service installed on port 5000"
    fi
}

# ==========================================
# FUNGSI SETUP WEB CHAT INTERFACE
# ==========================================

setup_web_chat() {
    if [[ ! $enable_web_chat =~ ^[Yy]$ ]]; then
        return
    fi
    
    print_step "Setup Web Chat Interface..."
    log "Installing web chat interface"
    
    mkdir -p $INSTALL_DIR/web-chat
    cd $INSTALL_DIR/web-chat
    
    python3 -m venv venv
    source venv/bin/activate
    pip install -q flask flask-cors requests markdown pygments
    
    # Create backend API dengan health check
    cat > app.py <<'PYEOF'
from flask import Flask, request, jsonify, render_template_string
from flask_cors import CORS
import requests
import json
import markdown
from pygments import highlight
from pygments.lexers import get_lexer_by_name, guess_lexer
from pygments.formatters import HtmlFormatter
import re

app = Flask(__name__)
CORS(app)

OLLAMA_API = "http://localhost:11434/api/generate"

@app.route('/health')
def health():
    """Health check endpoint"""
    try:
        resp = requests.get("http://localhost:11434/api/tags", timeout=2)
        ollama_status = "healthy" if resp.status_code == 200 else "unhealthy"
    except:
        ollama_status = "unhealthy"
    
    return jsonify({
        "status": "healthy",
        "ollama": ollama_status
    })

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE)

@app.route('/api/chat', methods=['POST'])
def chat():
    try:
        data = request.json
        message = data.get('message', '')
        model = data.get('model', 'llama3.2:3b')
        
        if not message:
            return jsonify({'error': 'No message provided'}), 400
        
        # Stream response from Ollama
        response = requests.post(
            OLLAMA_API,
            json={
                'model': model,
                'prompt': message,
                'stream': False
            },
            timeout=60
        )
        
        if response.status_code == 200:
            result = response.json()
            return jsonify({
                'response': result.get('response', ''),
                'model': model
            })
        else:
            return jsonify({'error': 'Ollama API error'}), 500
            
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/models', methods=['GET'])
def get_models():
    """Get available models dari Ollama"""
    try:
        response = requests.get("http://localhost:11434/api/tags", timeout=5)
        if response.status_code == 200:
            models = response.json().get('models', [])
            return jsonify({'models': [m['name'] for m in models]})
        return jsonify({'models': []})
    except:
        return jsonify({'models': []})

HTML_TEMPLATE = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AI Chat Platform</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        
        .chat-container {
            width: 90%;
            max-width: 900px;
            height: 90vh;
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            display: flex;
            flex-direction: column;
            overflow: hidden;
        }
        
        .chat-header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            text-align: center;
        }
        
        .chat-header h1 {
            font-size: 24px;
            margin-bottom: 5px;
        }
        
        .chat-header p {
            font-size: 14px;
            opacity: 0.9;
        }
        
        .model-selector {
            padding: 15px 20px;
            background: #f8f9fa;
            border-bottom: 1px solid #dee2e6;
        }
        
        .model-selector select {
            width: 100%;
            padding: 10px;
            border: 1px solid #ced4da;
            border-radius: 8px;
            font-size: 14px;
        }
        
        .chat-messages {
            flex: 1;
            overflow-y: auto;
            padding: 20px;
            background: #f8f9fa;
        }
        
        .message {
            margin-bottom: 20px;
            display: flex;
            align-items: flex-start;
        }
        
        .message.user {
            flex-direction: row-reverse;
        }
        
        .message-content {
            max-width: 70%;
            padding: 12px 16px;
            border-radius: 18px;
            line-height: 1.5;
        }
        
        .message.user .message-content {
            background: #667eea;
            color: white;
            margin-left: 10px;
        }
        
        .message.ai .message-content {
            background: white;
            color: #333;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
            margin-right: 10px;
        }
        
        .chat-input-container {
            padding: 20px;
            background: white;
            border-top: 1px solid #dee2e6;
        }
        
        .chat-input-form {
            display: flex;
            gap: 10px;
        }
        
        .chat-input {
            flex: 1;
            padding: 12px 16px;
            border: 2px solid #ced4da;
            border-radius: 25px;
            font-size: 14px;
            outline: none;
            transition: border-color 0.3s;
        }
        
        .chat-input:focus {
            border-color: #667eea;
        }
        
        .send-button {
            padding: 12px 30px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            border-radius: 25px;
            font-size: 14px;
            font-weight: 600;
            cursor: pointer;
            transition: transform 0.2s;
        }
        
        .send-button:hover {
            transform: scale(1.05);
        }
        
        .send-button:disabled {
            opacity: 0.6;
            cursor: not-allowed;
            transform: scale(1);
        }
        
        .loading {
            display: inline-block;
            width: 8px;
            height: 8px;
            border-radius: 50%;
            background: #667eea;
            animation: pulse 1.5s ease-in-out infinite;
        }
        
        @keyframes pulse {
            0%, 100% { opacity: 0.3; }
            50% { opacity: 1; }
        }
        
        .status-indicator {
            display: inline-block;
            width: 10px;
            height: 10px;
            border-radius: 50%;
            background: #28a745;
            margin-right: 5px;
        }
    </style>
</head>
<body>
    <div class="chat-container">
        <div class="chat-header">
            <h1>🤖 AI Chat Platform</h1>
            <p><span class="status-indicator"></span>Powered by Local AI Models</p>
        </div>
        
        <div class="model-selector">
            <select id="modelSelect">
                <option value="">Loading models...</option>
            </select>
        </div>
        
        <div class="chat-messages" id="chatMessages">
            <div class="message ai">
                <div class="message-content">
                    👋 Hello! I'm your AI assistant. How can I help you today?
                </div>
            </div>
        </div>
        
        <div class="chat-input-container">
            <form class="chat-input-form" id="chatForm">
                <input 
                    type="text" 
                    class="chat-input" 
                    id="messageInput" 
                    placeholder="Type your message..."
                    autocomplete="off"
                >
                <button type="submit" class="send-button" id="sendButton">Send</button>
            </form>
        </div>
    </div>
    
    <script>
        const chatMessages = document.getElementById('chatMessages');
        const chatForm = document.getElementById('chatForm');
        const messageInput = document.getElementById('messageInput');
        const sendButton = document.getElementById('sendButton');
        const modelSelect = document.getElementById('modelSelect');
        
        // Load available models
        async function loadModels() {
            try {
                const response = await fetch('/api/models');
                const data = await response.json();
                
                modelSelect.innerHTML = '';
                if (data.models && data.models.length > 0) {
                    data.models.forEach(model => {
                        const option = document.createElement('option');
                        option.value = model;
                        option.textContent = model;
                        modelSelect.appendChild(option);
                    });
                } else {
                    modelSelect.innerHTML = '<option value="">No models available</option>';
                }
            } catch (error) {
                console.error('Error loading models:', error);
                modelSelect.innerHTML = '<option value="">Error loading models</option>';
            }
        }
        
        // Add message to chat
        function addMessage(content, isUser = false) {
            const messageDiv = document.createElement('div');
            messageDiv.className = `message ${isUser ? 'user' : 'ai'}`;
            
            const contentDiv = document.createElement('div');
            contentDiv.className = 'message-content';
            contentDiv.textContent = content;
            
            messageDiv.appendChild(contentDiv);
            chatMessages.appendChild(messageDiv);
            
            // Scroll to bottom
            chatMessages.scrollTop = chatMessages.scrollHeight;
        }
        
        // Send message
        chatForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            
            const message = messageInput.value.trim();
            if (!message) return;
            
            const selectedModel = modelSelect.value;
            if (!selectedModel) {
                alert('Please wait for models to load');
                return;
            }
            
            // Add user message
            addMessage(message, true);
            messageInput.value = '';
            
            // Disable input
            sendButton.disabled = true;
            sendButton.textContent = 'Sending...';
            
            try {
                const response = await fetch('/api/chat', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        message: message,
                        model: selectedModel
                    })
                });
                
                const data = await response.json();
                
                if (data.error) {
                    addMessage('Error: ' + data.error, false);
                } else {
                    addMessage(data.response, false);
                }
            } catch (error) {
                addMessage('Error: Failed to send message', false);
            } finally {
                sendButton.disabled = false;
                sendButton.textContent = 'Send';
                messageInput.focus();
            }
        });
        
        // Load models on page load
        loadModels();
    </script>
</body>
</html>
'''

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001, debug=False)
PYEOF
    
    # Create systemd service
    cat > /etc/systemd/system/web-chat.service <<EOF
[Unit]
Description=Web Chat Interface
After=network.target ollama.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR/web-chat
Environment="PATH=$INSTALL_DIR/web-chat/venv/bin"
ExecStart=$INSTALL_DIR/web-chat/venv/bin/python app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable web-chat > /dev/null 2>&1
    systemctl start web-chat
    
    sleep 3
    
    print_success "Web Chat Interface terinstal di port 5001"
    log "Web chat interface installed on port 5001"
}

# ==========================================
# FUNGSI SETUP NGINX REVERSE PROXY (FIXED)
# ==========================================

setup_nginx_config() {
    if [[ $INSTALL_NGINX == true ]] && [[ $SETUP_CF == true ]]; then
        print_step "Konfigurasi Nginx reverse proxy (Anti-502)..."
        log "Configuring Nginx reverse proxy"
        
        cat > $NGINX_CONF/ai-platform <<EOF
# Upstream definitions dengan health checks
upstream ollama_backend {
    server 127.0.0.1:11434 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

upstream comfyui_backend {
    server 127.0.0.1:8188 max_fails=3 fail_timeout=30s;
}

upstream tts_backend {
    server 127.0.0.1:5000 max_fails=3 fail_timeout=30s;
}

upstream webchat_backend {
    server 127.0.0.1:5001 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

server {
    listen 80;
    server_name $DOMAIN;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Logging
    access_log /var/log/nginx/ai-platform-access.log;
    error_log /var/log/nginx/ai-platform-error.log;
    
    # File upload limit
    client_max_body_size 100M;
    client_body_buffer_size 128k;
    
    # Timeouts untuk mencegah 502
    proxy_connect_timeout 600s;
    proxy_send_timeout 600s;
    proxy_read_timeout 600s;
    send_timeout 600s;
    
    # Buffer settings
    proxy_buffering on;
    proxy_buffer_size 128k;
    proxy_buffers 4 256k;
    proxy_busy_buffers_size 256k;
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "OK - AI Platform Running";
        add_header Content-Type text/plain;
    }
    
    # Ollama API
    location /api/ollama/ {
        proxy_pass http://ollama_backend/;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # No caching untuk API
        proxy_cache_bypass \$http_upgrade;
        proxy_no_cache 1;
        
        # Keepalive
        proxy_set_header Connection "";
    }
    
    # ComfyUI
    location /comfyui/ {
        proxy_pass http://comfyui_backend/;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        
        proxy_cache_bypass \$http_upgrade;
    }
    
    # TTS Service
    location /tts/ {
        proxy_pass http://tts_backend/;
        
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        
        # Timeout lebih lama untuk TTS processing
        proxy_read_timeout 300s;
    }
    
    # Web Chat Interface (Root)
    location / {
        proxy_pass http://webchat_backend;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_cache_bypass \$http_upgrade;
        
        # Keepalive
        proxy_set_header Connection "";
    }
}
EOF
        
        # Remove default site
        rm -f $NGINX_ENABLED/default
        
        # Enable new config
        ln -sf $NGINX_CONF/ai-platform $NGINX_ENABLED/
        
        # Test config
        if nginx -t 2>/dev/null; then
            systemctl reload nginx
            print_success "Nginx dikonfigurasi dengan anti-502 protection"
            log "Nginx configured successfully"
        else
            print_error "Nginx configuration test failed"
            nginx -t
        fi
    fi
}

# ==========================================
# FUNGSI INSTALL SSL (Let's Encrypt)
# ==========================================

install_ssl() {
    if [[ $INSTALL_NGINX == true ]] && [[ $SETUP_CF == true ]]; then
        echo
        read -p "Install SSL Certificate dengan Let's Encrypt? (Y/N): " ssl_choice
        if [[ $ssl_choice =~ ^[Yy]$ ]]; then
            print_step "Menginstal Certbot..."
            log "Installing SSL certificate"
            
            apt-get install -y -qq certbot python3-certbot-nginx > /dev/null 2>&1
            
            print_info "Mendapatkan SSL certificate untuk $DOMAIN..."
            
            # Certbot dengan auto-renewal
            certbot --nginx -d $DOMAIN \
                --non-interactive \
                --agree-tos \
                --email admin@$DOMAIN \
                --redirect
            
            if [ $? -eq 0 ]; then
                print_success "SSL Certificate terinstal dan auto-renewal diaktifkan"
                log "SSL certificate installed successfully"
                
                # Test auto-renewal
                certbot renew --dry-run > /dev/null 2>&1
                print_success "Auto-renewal SSL berhasil dikonfigurasi"
                
                echo
                print_info "🔒 Sekarang Anda bisa mengaktifkan Cloudflare Proxy (Orange Cloud)"
                print_info "   untuk mendapatkan proteksi DDoS dan caching"
            else
                print_error "Gagal menginstal SSL certificate"
                print_info "Pastikan DNS sudah propagasi penuh dan port 80/443 terbuka"
            fi
        fi
    fi
}

# ==========================================
# FUNGSI HEALTH CHECK SEMUA SERVICES
# ==========================================

check_services_health() {
    print_step "Melakukan health check semua services..."
    echo
    
    local all_healthy=true
    
    # Check Ollama
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        print_success "✓ Ollama: Running (Port 11434)"
    else
        print_error "✗ Ollama: Not responding"
        all_healthy=false
    fi
    
    # Check ComfyUI
    if [[ $model_sdxl =~ ^[Yy]$ ]]; then
        if systemctl is-active --quiet comfyui; then
            print_success "✓ ComfyUI: Running (Port 8188)"
        else
            print_error "✗ ComfyUI: Not running"
            all_healthy=false
        fi
    fi
    
    # Check TTS
    if [[ $model_tts =~ ^[Yy]$ ]]; then
        if curl -s http://localhost:5000/health > /dev/null 2>&1; then
            print_success "✓ TTS Service: Running (Port 5000)"
        else
            print_error "✗ TTS Service: Not responding"
            all_healthy=false
        fi
    fi
    
    # Check Web Chat
    if [[ $enable_web_chat =~ ^[Yy]$ ]]; then
        if curl -s http://localhost:5001/health > /dev/null 2>&1; then
            print_success "✓ Web Chat: Running (Port 5001)"
        else
            print_error "✗ Web Chat: Not responding"
            all_healthy=false
        fi
    fi
    
    # Check Nginx
    if [[ $INSTALL_NGINX == true ]]; then
        if systemctl is-active --quiet nginx; then
            print_success "✓ Nginx: Running"
        else
            print_error "✗ Nginx: Not running"
            all_healthy=false
        fi
    fi
    
    echo
    if [ "$all_healthy" = true ]; then
        print_success "✓ Semua services berjalan dengan baik!"
    else
        print_warning "⚠ Beberapa services mengalami masalah. Cek log untuk detail."
    fi
}

# ==========================================
# FUNGSI CREATE TROUBLESHOOTING GUIDE
# ==========================================

create_troubleshooting_guide() {
    print_step "Membuat troubleshooting guide..."
    
    cat > $INSTALL_DIR/TROUBLESHOOTING.md <<'EOF'
# AI Platform Troubleshooting Guide

## 🔧 Masalah Umum dan Solusi

### 1. Error 502 Bad Gateway

**Penyebab:**
- Service backend belum sepenuhnya start
- Timeout terlalu pendek
- Service crash atau tidak responding

**Solusi:**
```bash
# Check service status
systemctl status ollama
systemctl status web-chat
systemctl status nginx

# Restart services
systemctl restart ollama
systemctl restart web-chat
systemctl restart nginx

# Check logs
journalctl -u ollama -f
journalctl -u web-chat -f
tail -f /var/log/nginx/ai-platform-error.log
```

### 2. DNS Tidak Resolve

**Penyebab:**
- DNS belum propagasi
- Cloudflare proxy aktif terlalu cepat

**Solusi:**
```bash
# Check DNS
dig +short yourdomain.com
nslookup yourdomain.com 1.1.1.1

# Wait for propagation (bisa 5-60 menit)
# Pastikan Cloudflare proxy OFF saat setup SSL pertama kali
```

### 3. Ollama Not Responding

**Solusi:**
```bash
# Restart Ollama
systemctl restart ollama

# Check if models loaded
ollama list

# Test API
curl http://localhost:11434/api/tags
```

### 4. Web Chat Tidak Muncul

**Solusi:**
```bash
# Check service
systemctl status web-chat

# Check logs
journalctl -u web-chat -n 50

# Manual test
curl http://localhost:5001/health

# Restart service
systemctl restart web-chat
```

### 5. SSL Certificate Gagal

**Solusi:**
```bash
# Pastikan port 80/443 terbuka
ufw allow 80/tcp
ufw allow 443/tcp

# Pastikan DNS sudah resolve
dig +short yourdomain.com

# Matikan Cloudflare proxy (DNS only)
# Retry certbot
certbot --nginx -d yourdomain.com --force-renewal
```

## 📊 Monitoring Commands

```bash
# Check all services
systemctl status ollama web-chat nginx

# Check ports
netstat -tlnp | grep -E '11434|5001|80|443'

# Real-time logs
tail -f /var/log/nginx/ai-platform-error.log

# System resources
htop
df -h
free -h
```

## 🔄 Restart All Services

```bash
systemctl restart ollama
systemctl restart web-chat
systemctl restart comfyui  # jika terinstall
systemctl restart tts       # jika terinstall
systemctl restart nginx
```

## 📝 Configuration Files

- Nginx config: `/etc/nginx/sites-available/ai-platform`
- Ollama service: `/etc/systemd/system/ollama.service.d/override.conf`
- Web chat service: `/etc/systemd/system/web-chat.service`
- Installation log: `/var/log/ai-platform-install.log`

## 🆘 Emergency Recovery

Jika sistem tidak stabil:

```bash
# Stop all services
systemctl stop nginx web-chat ollama comfyui tts

# Check for port conflicts
netstat -tlnp

# Restart one by one
systemctl start ollama
sleep 10
systemctl start web-chat
sleep 5
systemctl start nginx

# Verify
curl http://localhost:11434/api/tags
curl http://localhost:5001/health
```
EOF

    chmod 644 $INSTALL_DIR/TROUBLESHOOTING.md
    print_success "Troubleshooting guide dibuat di $INSTALL_DIR/TROUBLESHOOTING.md"
}

# ==========================================
# FUNGSI CREATE MANAGEMENT SCRIPT
# ==========================================

create_management_script() {
    print_step "Membuat management script..."
    
    cat > /usr/local/bin/ai-platform <<'EOF'
#!/bin/bash

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     AI Platform Management Menu      ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
    echo
    echo "1. Status Semua Services"
    echo "2. Restart Semua Services"
    echo "3. View Logs"
    echo "4. Health Check"
    echo "5. Update Models"
    echo "6. Troubleshooting Guide"
    echo "7. Exit"
    echo
    read -p "Pilih opsi [1-7]: " choice
    
    case $choice in
        1) show_status ;;
        2) restart_services ;;
        3) view_logs ;;
        4) health_check ;;
        5) update_models ;;
        6) show_troubleshooting ;;
        7) exit 0 ;;
        *) echo "Invalid option"; sleep 2; show_menu ;;
    esac
}

show_status() {
    echo
    echo -e "${CYAN}=== Services Status ===${NC}"
    systemctl status ollama --no-pager -l
    systemctl status web-chat --no-pager -l
    systemctl status nginx --no-pager -l
    echo
    read -p "Press enter to continue..."
    show_menu
}

restart_services() {
    echo
    echo -e "${YELLOW}Restarting all services...${NC}"
    systemctl restart ollama
    sleep 5
    systemctl restart web-chat
    systemctl restart nginx
    echo -e "${GREEN}All services restarted!${NC}"
    sleep 2
    show_menu
}

view_logs() {
    echo
    echo "1. Ollama Logs"
    echo "2. Web Chat Logs"
    echo "3. Nginx Error Logs"
    echo "4. Back"
    read -p "Choose: " log_choice
    
    case $log_choice in
        1) journalctl -u ollama -f ;;
        2) journalctl -u web-chat -f ;;
        3) tail -f /var/log/nginx/ai-platform-error.log ;;
        4) show_menu ;;
    esac
}

health_check() {
    echo
    echo -e "${CYAN}=== Health Check ===${NC}"
    
    if curl -s http://localhost:11434/api/tags > /dev/null; then
        echo -e "${GREEN}✓ Ollama: Healthy${NC}"
    else
        echo -e "${RED}✗ Ollama: Unhealthy${NC}"
    fi
    
    if curl -s http://localhost:5001/health > /dev/null; then
        echo -e "${GREEN}✓ Web Chat: Healthy${NC}"
    else
        echo -e "${RED}✗ Web Chat: Unhealthy${NC}"
    fi
    
    if systemctl is-active --quiet nginx; then
        echo -e "${GREEN}✓ Nginx: Running${NC}"
    else
        echo -e "${RED}✗ Nginx: Not Running${NC}"
    fi
    
    echo
    read -p "Press enter to continue..."
    show_menu
}

update_models() {
    echo
    echo -e "${CYAN}Available models to update:${NC}"
    ollama list
    echo
    read -p "Enter model name to pull/update (or 'back'): " model
    
    if [ "$model" != "back" ]; then
        ollama pull $model
        echo
        read -p "Press enter to continue..."
    fi
    
    show_menu
}

show_troubleshooting() {
    cat /opt/ai-platform/TROUBLESHOOTING.md | less
    show_menu
}

show_menu
EOF
    
    chmod +x /usr/local/bin/ai-platform
    print_success "Management script dibuat: ai-platform"
}

# ==========================================
# FUNGSI CREATE DASHBOARD
# ==========================================

create_dashboard() {
    print_step "Membuat dashboard informasi..."
    
    mkdir -p $INSTALL_DIR
    
    cat > $INSTALL_DIR/dashboard.html <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AI Platform Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 40px 20px;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        .header {
            text-align: center;
            color: white;
            margin-bottom: 40px;
        }
        .header h1 {
            font-size: 48px;
            margin-bottom: 10px;
        }
        .header p {
            font-size: 18px;
            opacity: 0.9;
        }
        .services {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .service-card {
            background: white;
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            transition: transform 0.3s;
        }
        .service-card:hover {
            transform: translateY(-5px);
        }
        .service-card h2 {
            color: #667eea;
            margin-bottom: 15px;
            display: flex;
            align-items: center;
        }
        .status-dot {
            display: inline-block;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            background: #28a745;
            margin-right: 10px;
            animation: pulse 2s infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        .endpoint {
            background: #f8f9fa;
            padding: 12px;
            border-radius: 8px;
            font-family: 'Courier New', monospace;
            font-size: 13px;
            margin: 10px 0;
            word-break: break-all;
        }
        .description {
            color: #666;
            font-size: 14px;
            line-height: 1.6;
        }
        .button {
            display: inline-block;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 10px 20px;
            border-radius: 8px;
            text-decoration: none;
            margin-top: 10px;
            transition: transform 0.2s;
        }
        .button:hover {
            transform: scale(1.05);
        }
        .info-box {
            background: white;
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
        }
        .info-box h3 {
            color: #667eea;
            margin-bottom: 15px;
        }
        .info-box ul {
            list-style: none;
            padding: 0;
        }
        .info-box li {
            padding: 8px 0;
            border-bottom: 1px solid #eee;
        }
        .info-box li:last-child {
            border-bottom: none;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🤖 AI Platform</h1>
            <p>Your Self-Hosted AI Infrastructure</p>
        </div>
        
        <div class="services">
            <div class="service-card">
                <h2><span class="status-dot"></span>Chat Interface</h2>
                <p class="description">Web-based AI chat with multiple models</p>
                <div class="endpoint">https://$DOMAIN/</div>
                <a href="https://$DOMAIN/" class="button" target="_blank">Open Chat</a>
            </div>
            
            <div class="service-card">
                <h2><span class="status-dot"></span>Ollama API</h2>
                <p class="description">REST API for AI text generation</p>
                <div class="endpoint">POST https://$DOMAIN/api/ollama/api/generate</div>
                <p class="description" style="margin-top:10px"><strong>Available Models:</strong></p>
                <ul style="padding-left:20px; margin-top:5px">
EOF

    # Add installed models to dashboard
    [[ $model_qwen =~ ^[Yy]$ ]] && echo '                    <li>qwen2.5-coder:7b</li>' >> $INSTALL_DIR/dashboard.html
    [[ $model_llama =~ ^[Yy]$ ]] && echo '                    <li>llama3.2:3b</li>' >> $INSTALL_DIR/dashboard.html
    [[ $model_mistral =~ ^[Yy]$ ]] && echo '                    <li>mistral:7b</li>' >> $INSTALL_DIR/dashboard.html
    [[ $model_vision =~ ^[Yy]$ ]] && echo '                    <li>llava:7b</li>' >> $INSTALL_DIR/dashboard.html
    
    cat >> $INSTALL_DIR/dashboard.html <<EOF
                </ul>
            </div>
            
$(if [[ $model_sdxl =~ ^[Yy]$ ]]; then cat <<'SDXL'
            <div class="service-card">
                <h2><span class="status-dot"></span>Image Generation</h2>
                <p class="description">ComfyUI for Stable Diffusion XL</p>
                <div class="endpoint">https://$DOMAIN/comfyui/</div>
                <a href="https://$DOMAIN/comfyui/" class="button" target="_blank">Open ComfyUI</a>
            </div>
SDXL
fi)
            
$(if [[ $model_tts =~ ^[Yy]$ ]]; then cat <<'TTS'
            <div class="service-card">
                <h2><span class="status-dot"></span>Text-to-Speech</h2>
                <p class="description">Multilingual TTS API</p>
                <div class="endpoint">POST https://$DOMAIN/tts/tts</div>
                <p class="description" style="margin-top:10px">Example:</p>
                <pre style="background:#f8f9fa;padding:10px;border-radius:5px;font-size:12px;overflow-x:auto;">
{
  "text": "Hello world",
  "language": "en"
}</pre>
            </div>
TTS
fi)
        </div>
        
        <div class="info-box">
            <h3>📚 Quick Start</h3>
            <ul>
                <li><strong>Chat:</strong> Visit https://$DOMAIN and start chatting</li>
                <li><strong>API:</strong> Use curl or any HTTP client to access the APIs</li>
                <li><strong>Management:</strong> Run <code>ai-platform</code> command for service management</li>
                <li><strong>Troubleshooting:</strong> Check /opt/ai-platform/TROUBLESHOOTING.md</li>
                <li><strong>Logs:</strong> /var/log/nginx/ai-platform-error.log</li>
            </ul>
        </div>
    </div>
</body>
</html>
EOF

    if [[ $INSTALL_NGINX == true ]]; then
        cp $INSTALL_DIR/dashboard.html /var/www/html/dashboard.html 2>/dev/null || true
    fi
    
    print_success "Dashboard dibuat di $INSTALL_DIR/dashboard.html"
}

# ==========================================
# MAIN INSTALLATION
# ==========================================

main() {
    print_info "Memulai instalasi AI Platform v2.0..."
    log "Installation started"
    
    # Create install directory
    mkdir -p $INSTALL_DIR
    
    # Install dependencies
    install_dependencies
    
    # Install Docker
    install_docker
    install_nvidia_docker
    
    # Install Nginx
    install_nginx
    
    # Install Database
    install_database
    
    # Setup Cloudflare
    setup_cloudflare
    
    # Setup Firewall
    setup_firewall
    
    # Select models
    select_ai_models
    
    # Setup services
    setup_ollama
    setup_image_generation
    setup_tts
    setup_web_chat
    
    # Configure Nginx
    setup_nginx_config
    
    # Install SSL
    install_ssl
    
    # Health check
    sleep 5
    check_services_health
    
    # Create management tools
    create_troubleshooting_guide
    create_management_script
    create_dashboard
    
    # Summary
    echo
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              INSTALASI SELESAI!                      ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo
    
    if [[ $SETUP_CF == true ]]; then
        echo -e "${CYAN}🌐 Website:${NC}"
        echo -e "   https://$DOMAIN"
        echo
        
        [[ $enable_web_chat =~ ^[Yy]$ ]] && echo -e "${CYAN}💬 Chat Interface:${NC} https://$DOMAIN"
        [[ $model_sdxl =~ ^[Yy]$ ]] && echo -e "${CYAN}🎨 ComfyUI:${NC} https://$DOMAIN/comfyui/"
        echo
    fi
    
    echo -e "${CYAN}📊 Local Services:${NC}"
    [[ $model_qwen =~ ^[Yy]$ ]] || [[ $model_llama =~ ^[Yy]$ ]] || [[ $model_mistral =~ ^[Yy]$ ]] && \
        echo "   • Ollama API: http://localhost:11434"
    [[ $enable_web_chat =~ ^[Yy]$ ]] && \
        echo "   • Web Chat: http://localhost:5001"
    [[ $model_sdxl =~ ^[Yy]$ ]] && \
        echo "   • ComfyUI: http://localhost:8188"
    [[ $model_tts =~ ^[Yy]$ ]] && \
        echo "   • TTS Service: http://localhost:5000"
    
    echo
    echo -e "${CYAN}🛠️  Management:${NC}"
    echo "   • Run: ai-platform (untuk menu management)"
    echo "   • Troubleshooting: cat /opt/ai-platform/TROUBLESHOOTING.md"
    echo "   • Logs: tail -f /var/log/ai-platform-install.log"
    
    echo
    echo -e "${CYAN}📝 Important Notes:${NC}"
    echo "   1. Jika menggunakan Cloudflare, set Proxy ke OFF (DNS only) dulu"
    echo "   2. Install SSL certificate sebelum mengaktifkan Cloudflare proxy"
    echo "   3. Untuk 502 errors, jalankan: systemctl restart ollama web-chat nginx"
    echo "   4. Default models sudah terinstall, Anda bisa pull lebih banyak"
    
    if [[ $INSTALL_DB == true ]]; then
        echo
        echo -e "${CYAN}🗄️  Database Credentials:${NC}"
        echo "   Saved in: /opt/ai-platform/db-credentials.txt"
    fi
    
    echo
    echo -e "${GREEN}✅ Setup complete! Selamat menggunakan AI Platform!${NC}"
    echo
    
    log "Installation completed successfully"
}

# Run main installation
main