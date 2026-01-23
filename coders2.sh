#!/bin/bash

# AI Platform Auto Installer v2.0 - FIXED
# Developer: RizzDevs
# Documentation: https://coders1.vercel.app
# Perbaikan: 502 Bad Gateway, DNS Cloudflare, Health Checks, Model Loading
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
echo "╔══════════════════════════════════════════════════════════╗"
echo "║       AI Platform Auto Installer v2.0 FIXED              ║"
echo "║  Coding | Chat | Image | Video | TTS | Translation      ║"
echo "║         🔧 502 Error Fixed + Auto DNS Setup              ║"
echo "║                                                          ║"
echo "║  Developer: RizzDevs                                     ║"
echo "║  Documentation: https://coders1.vercel.app               ║"
echo "╚══════════════════════════════════════════════════════════╝"
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
    
    # Dapatkan zone name dari API
    ZONE_NAME=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID" \
        -H "Authorization: Bearer $CF_API_KEY" \
        -H "Content-Type: application/json" | jq -r '.result.name')
    
    echo
    print_info "Domain utama Anda: $ZONE_NAME"
    echo
    echo "Pilih jenis domain:"
    echo "1. Subdomain (contoh: ai.${ZONE_NAME})"
    echo "2. Domain utama (${ZONE_NAME})"
    read -p "Pilihan [1-2]: " domain_type
    
    if [[ $domain_type == "2" ]]; then
        DOMAIN="$ZONE_NAME"
        print_info "Menggunakan domain utama: $DOMAIN"
    else
        read -p "Masukkan nama subdomain (contoh: ai): " SUBDOMAIN
        DOMAIN="$SUBDOMAIN.$ZONE_NAME"
        print_info "Menggunakan subdomain: $DOMAIN"
    fi
    
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
Environment="OLLAMA_ORIGINS=*"
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
        pip install -q TTS flask flask-cors
        
        # Create API server
        cat > server.py <<'EOF'
from flask import Flask, request, send_file, jsonify
from flask_cors import CORS
from TTS.api import TTS
import os
import tempfile

app = Flask(__name__)
CORS(app)

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
# FUNGSI SETUP WEB CHAT INTERFACE (FIXED)
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
    
    # Create backend API dengan CORS fix
    cat > app.py <<'PYEOF'
from flask import Flask, request, jsonify, render_template_string
from flask_cors import CORS
import requests
import json

app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*"}})

OLLAMA_API = "http://localhost:11434/api/generate"
OLLAMA_TAGS = "http://localhost:11434/api/tags"

@app.route('/health')
def health():
    """Health check endpoint"""
    try:
        resp = requests.get(OLLAMA_TAGS, timeout=2)
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

@app.route('/api/chat', methods=['POST', 'OPTIONS'])
def chat():
    if request.method == 'OPTIONS':
        return '', 204
        
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
            timeout=120
        )
        
        if response.status_code == 200:
            result = response.json()
            return jsonify({
                'response': result.get('response', ''),
                'model': model
            })
        else:
            return jsonify({'error': f'Ollama API error: {response.status_code}'}), 500
            
    except requests.exceptions.Timeout:
        return jsonify({'error': 'Request timeout - model might be loading'}), 504
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/models', methods=['GET', 'OPTIONS'])
def get_models():
    """Get available models dari Ollama"""
    if request.method == 'OPTIONS':
        return '', 204
        
    try:
        response = requests.get(OLLAMA_TAGS, timeout=10)
        if response.status_code == 200:
            models = response.json().get('models', [])
            model_list = [m['name'] for m in models]
            return jsonify({'models': model_list, 'count': len(model_list)})
        return jsonify({'models': [], 'count': 0, 'error': 'Failed to fetch models'})
    except Exception as e:
        return jsonify({'models': [], 'count': 0, 'error': str(e)})

HTML_TEMPLATE = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AI Chat Platform - RizzDevs</title>
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
        
        .chat-header .credit {
            font-size: 11px;
            opacity: 0.8;
            margin-top: 8px;
        }
        
        .chat-header .credit a {
            color: #fff;
            text-decoration: underline;
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
            background: white;
        }
        
        .model-selector select:disabled {
            background: #e9ecef;
            cursor: not-allowed;
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
            white-space: pre-wrap;
            word-wrap: break-word;
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
        
        .message.system .message-content {
            background: #fff3cd;
            color: #856404;
            max-width: 90%;
            margin: 0 auto;
            text-align: center;
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
        
        .send-button:hover:not(:disabled) {
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
            animation: blink 2s infinite;
        }
        
        .status-indicator.error {
            background: #dc3545;
        }
        
        @keyframes blink {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
    </style>
</head>
<body>
    <div class="chat-container">
        <div class="chat-header">
            <h1>🤖 AI Chat Platform</h1>
            <p><span class="status-indicator" id="statusDot"></span><span id="statusText">Initializing...</span></p>
            <div class="credit">
                Developer: <strong>RizzDevs</strong> | 
                <a href="https://coders1.vercel.app" target="_blank">Documentation</a>
            </div>
        </div>
        
        <div class="model-selector">
            <select id="modelSelect" disabled>
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
                    disabled
                >
                <button type="submit" class="send-button" id="sendButton" disabled>Send</button>
            </form>
        </div>
    </div>
    
    <script>
        const chatMessages = document.getElementById('chatMessages');
        const chatForm = document.getElementById('chatForm');
        const messageInput = document.getElementById('messageInput');
        const sendButton = document.getElementById('sendButton');
        const modelSelect = document.getElementById('modelSelect');
        const statusDot = document.getElementById('statusDot');
        const statusText = document.getElementById('statusText');
        
        let modelsLoaded = false;
        
        // Update status
        function updateStatus(text, isError = false) {
            statusText.textContent = text;
            if (isError) {
                statusDot.classList.add('error');
            } else {
                statusDot.classList.remove('error');
            }
        }
        
        // Load available models with retry
        async function loadModels(retryCount = 0) {
            const maxRetries = 5;
            
            try {
                updateStatus('Loading models...');
                const response = await fetch('/api/models', {
                    method: 'GET',
                    headers: {
                        'Content-Type': 'application/json'
                    }
                });
                
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }
                
                const data = await response.json();
                
                modelSelect.innerHTML = '';
                
                if (data.models && data.models.length > 0) {
                    data.models.forEach(model => {
                        const option = document.createElement('option');
                        option.value = model;
                        option.textContent = model;
                        modelSelect.appendChild(option);
                    });
                    
                    modelSelect.disabled = false;
                    messageInput.disabled = false;
                    sendButton.disabled = false;
                    modelsLoaded = true;
                    
                    updateStatus(`Powered by Local AI Models (${data.count} available)`);
                    console.log(`Loaded ${data.count} models:`, data.models);
                } else {
                    throw new Error('No models available');
                }
            } catch (error) {
                console.error('Error loading models:', error);
                
                if (retryCount < maxRetries) {
                    const waitTime = Math.min(1000 * Math.pow(2, retryCount), 10000);
                    updateStatus(`Loading models... (retry ${retryCount + 1}/${maxRetries})`, true);
                    setTimeout(() => loadModels(retryCount + 1), waitTime);
                } else {
                    modelSelect.innerHTML = '<option value="">Failed to load models - check Ollama service</option>';
                    updateStatus('Error: Models not available', true);
                    
                    // Add system message
                    addMessage('⚠️ Unable to load AI models. Please check if Ollama service is running: systemctl status ollama', false, true);
                }
            }
        }
        
        // Add message to chat
        function addMessage(content, isUser = false, isSystem = false) {
            const messageDiv = document.createElement('div');
            messageDiv.className = `message ${isUser ? 'user' : isSystem ? 'system' : 'ai'}`;
            
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
            if (!message || !modelsLoaded) return;
            
            const selectedModel = modelSelect.value;
            if (!selectedModel) {
                addMessage('⚠️ Please select a model first', false, true);
                return;
            }
            
            // Add user message
            addMessage(message, true);
            messageInput.value = '';
            
            // Disable input
            sendButton.disabled = true;
            messageInput.disabled = true;
            sendButton.textContent = 'Thinking...';
            
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
                
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }
                
                const data = await response.json();
                
                if (data.error) {
                    addMessage('❌ Error: ' + data.error, false, true);
                } else {
                    addMessage(data.response, false);
                }
            } catch (error) {
                console.error('Chat error:', error);
                addMessage('❌ Failed to send message: ' + error.message, false, true);
            } finally {
                sendButton.disabled = false;
                messageInput.disabled = false;
                sendButton.textContent = 'Send';
                messageInput.focus();
            }
        });
        
        // Load models on page load
        window.addEventListener('load', () => {
            // Wait a bit for Ollama to be ready
            setTimeout(() => loadModels(), 1000);
        });
    </script>
</body>
</html>
'''

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001, debug=False)
PYEOF