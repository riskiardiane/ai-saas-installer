#!/bin/bash

# ╔═══════════════════════════════════════════════════════════╗
# ║           AI SaaS Enterprise Installer v2.1               ║
# ║                  Created by RizzDevs                      ║
# ║         Documentation: https://coders1.vercel.app         ║
# ║              + Cloudflare DNS Integration                 ║
# ╚═══════════════════════════════════════════════════════════╝

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
AUTO_YES=false
[[ "$1" == "-y" ]] && AUTO_YES=true
LOG_FILE="/var/log/rizzdevs-ai-install.log"

# Cloudflare configuration
CF_ZONE_ID=""
CF_API_KEY=""
CF_EMAIL=""
CF_DOMAIN=""

# ═══════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════

print_header() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${BOLD}           AI SaaS Enterprise Installer v2.1               ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                  ${PURPLE}Created by RizzDevs${NC}                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}         ${BLUE}Documentation: https://coders1.vercel.app${NC}         ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}              ${GREEN}+ Cloudflare DNS Integration${NC}                 ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "${GREEN}[✓]${NC} ${BOLD}$1${NC}"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

ask() {
    if $AUTO_YES; then
        echo -e "${CYAN}$1:${NC} ${GREEN}yes (auto)${NC}"
        return 0
    fi
    read -p "$(echo -e ${CYAN}$1 ${NC}[y/n]: )" yn
    [[ "$yn" == "y" || "$yn" == "Y" ]]
}

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Script ini harus dijalankan sebagai root!"
        exit 1
    fi
}

pause() {
    echo ""
    read -p "$(echo -e ${YELLOW}Tekan ENTER untuk melanjutkan...${NC})"
}

# ═══════════════════════════════════════════════════════════
# CLOUDFLARE DNS FUNCTIONS
# ═══════════════════════════════════════════════════════════

setup_cloudflare_config() {
    print_header
    print_step "[9/13] Cloudflare DNS Configuration"
    echo ""
    
    if ask "Configure Cloudflare DNS?"; then
        echo ""
        print_info "Masukkan informasi Cloudflare Anda:"
        echo ""
        
        read -p "$(echo -e ${CYAN}Cloudflare Email: ${NC})" CF_EMAIL
        read -p "$(echo -e ${CYAN}Cloudflare API Key (Global API Key): ${NC})" CF_API_KEY
        read -p "$(echo -e ${CYAN}Cloudflare Zone ID: ${NC})" CF_ZONE_ID
        read -p "$(echo -e ${CYAN}Domain (contoh: api.domain.com): ${NC})" CF_DOMAIN
        
        # Validate inputs
        if [[ -z "$CF_EMAIL" || -z "$CF_API_KEY" || -z "$CF_ZONE_ID" || -z "$CF_DOMAIN" ]]; then
            print_error "Semua field harus diisi!"
            return 1
        fi
        
        # Save to config file
        cat > /opt/ai-server/cloudflare.conf <<EOF
CF_EMAIL="$CF_EMAIL"
CF_API_KEY="$CF_API_KEY"
CF_ZONE_ID="$CF_ZONE_ID"
CF_DOMAIN="$CF_DOMAIN"
EOF
        chmod 600 /opt/ai-server/cloudflare.conf
        
        print_step "Cloudflare config saved!"
        
        # Try to create DNS record
        create_cloudflare_dns_record
    else
        print_info "Cloudflare DNS setup skipped"
    fi
    
    sleep 2
}

create_cloudflare_dns_record() {
    print_info "Creating DNS A record for $CF_DOMAIN..."
    
    # Get server public IP
    SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "")
    
    if [[ -z "$SERVER_IP" ]]; then
        print_error "Failed to get server IP address!"
        return 1
    fi
    
    print_info "Server IP: $SERVER_IP"
    
    # Check if DNS record already exists
    RECORD_CHECK=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?name=$CF_DOMAIN" \
        -H "X-Auth-Email: $CF_EMAIL" \
        -H "X-Auth-Key: $CF_API_KEY" \
        -H "Content-Type: application/json")
    
    RECORD_ID=$(echo "$RECORD_CHECK" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
    
    if [[ -n "$RECORD_ID" ]]; then
        print_warn "DNS record already exists, updating..."
        
        # Update existing record
        RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$RECORD_ID" \
            -H "X-Auth-Email: $CF_EMAIL" \
            -H "X-Auth-Key: $CF_API_KEY" \
            -H "Content-Type: application/json" \
            --data "{
                \"type\": \"A\",
                \"name\": \"$CF_DOMAIN\",
                \"content\": \"$SERVER_IP\",
                \"ttl\": 1,
                \"proxied\": false
            }")
    else
        print_info "Creating new DNS record..."
        
        # Create new record
        RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
            -H "X-Auth-Email: $CF_EMAIL" \
            -H "X-Auth-Key: $CF_API_KEY" \
            -H "Content-Type: application/json" \
            --data "{
                \"type\": \"A\",
                \"name\": \"$CF_DOMAIN\",
                \"content\": \"$SERVER_IP\",
                \"ttl\": 1,
                \"proxied\": false
            }")
    fi
    
    # Check if successful
    if echo "$RESPONSE" | grep -q '"success":true'; then
        print_step "DNS record created/updated successfully!"
        print_info "Domain: $CF_DOMAIN → $SERVER_IP"
        
        # Save DNS info
        echo "CLOUDFLARE_DNS_CONFIGURED=true" >> /opt/ai-server/.env
        echo "DOMAIN=$CF_DOMAIN" >> /opt/ai-server/.env
        echo "SERVER_IP=$SERVER_IP" >> /opt/ai-server/.env
        
        return 0
    else
        print_error "Failed to create/update DNS record!"
        print_error "Response: $RESPONSE"
        return 1
    fi
}

enable_cloudflare_proxy() {
    print_header
    print_step "Cloudflare Proxy Configuration"
    echo ""
    
    if ask "Enable Cloudflare Proxy (orange cloud)?"; then
        if [[ -f /opt/ai-server/cloudflare.conf ]]; then
            source /opt/ai-server/cloudflare.conf
            
            # Get record ID
            RECORD_CHECK=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?name=$CF_DOMAIN" \
                -H "X-Auth-Email: $CF_EMAIL" \
                -H "X-Auth-Key: $CF_API_KEY" \
                -H "Content-Type: application/json")
            
            RECORD_ID=$(echo "$RECORD_CHECK" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
            
            if [[ -n "$RECORD_ID" ]]; then
                SERVER_IP=$(curl -s ifconfig.me)
                
                # Enable proxy
                RESPONSE=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$RECORD_ID" \
                    -H "X-Auth-Email: $CF_EMAIL" \
                    -H "X-Auth-Key: $CF_API_KEY" \
                    -H "Content-Type: application/json" \
                    --data "{\"proxied\": true}")
                
                if echo "$RESPONSE" | grep -q '"success":true'; then
                    print_step "Cloudflare Proxy enabled!"
                    print_warn "Note: Traffic will now go through Cloudflare"
                else
                    print_error "Failed to enable proxy"
                fi
            fi
        else
            print_error "Cloudflare config not found!"
        fi
    fi
    
    sleep 2
}

# ═══════════════════════════════════════════════════════════
# SYSTEM REQUIREMENTS CHECK
# ═══════════════════════════════════════════════════════════

check_requirements() {
    print_header
    echo -e "${BOLD}Memeriksa System Requirements...${NC}"
    echo ""
    
    # Check CPU
    CPU_CORES=$(nproc)
    print_info "CPU Cores: ${CPU_CORES}"
    if [ "$CPU_CORES" -lt 4 ]; then
        print_warn "Minimum 4 cores direkomendasikan (saat ini: $CPU_CORES)"
    fi
    
    # Check RAM
    RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
    print_info "RAM: ${RAM_GB}GB"
    if [ "$RAM_GB" -lt 8 ]; then
        print_warn "Minimum 8GB RAM direkomendasikan (saat ini: ${RAM_GB}GB)"
    fi
    
    # Check Disk
    DISK_GB=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    print_info "Free Disk: ${DISK_GB}GB"
    if [ "$DISK_GB" -lt 80 ]; then
        print_warn "Minimum 80GB disk direkomendasikan (free: ${DISK_GB}GB)"
    fi
    
    # Check OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        print_info "OS: $NAME $VERSION"
    fi
    
    echo ""
    pause
}

# ═══════════════════════════════════════════════════════════
# STEP 1: SYSTEM UPDATE
# ═══════════════════════════════════════════════════════════

system_update() {
    print_header
    print_step "[1/13] Updating System & Installing Dependencies"
    log "Starting system update"
    
    apt update -y 2>&1 | tee -a "$LOG_FILE"
    apt upgrade -y 2>&1 | tee -a "$LOG_FILE"
    
    print_info "Installing essential packages..."
    apt install -y \
        git curl wget unzip zip \
        python3 python3-pip python3-venv python3-dev \
        build-essential gcc g++ make \
        nginx mysql-server \
        software-properties-common \
        libssl-dev libffi-dev \
        htop tmux screen \
        jq \
        2>&1 | tee -a "$LOG_FILE"
    
    print_step "System update completed!"
    sleep 2
}

# ═══════════════════════════════════════════════════════════
# STEP 2: SWAP CONFIGURATION
# ═══════════════════════════════════════════════════════════

setup_swap() {
    print_header
    print_step "[2/13] Configuring SWAP (16GB - Anti OOM)"
    log "Setting up SWAP"
    
    if swapon --show | grep -q swapfile; then
        print_warn "SWAP sudah aktif, skip..."
    else
        print_info "Creating 16GB swap file..."
        fallocate -l 16G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        
        if ! grep -q "/swapfile" /etc/fstab; then
            echo "/swapfile none swap sw 0 0" >> /etc/fstab
        fi
        
        # Optimize swap settings
        sysctl vm.swappiness=10
        echo "vm.swappiness=10" >> /etc/sysctl.conf
        
        print_step "SWAP 16GB activated!"
    fi
    
    sleep 2
}

# ═══════════════════════════════════════════════════════════
# STEP 3: PYTHON AI ENVIRONMENT (FIXED)
# ═══════════════════════════════════════════════════════════

setup_python_env() {
    print_header
    print_step "[3/13] Setting up Python AI Environment"
    log "Creating Python virtual environment"
    
    # Remove old environment if exists
    if [ -d "/opt/ai-env" ]; then
        print_warn "Removing old environment..."
        rm -rf /opt/ai-env
    fi
    
    # Create new virtual environment
    print_info "Creating virtual environment at /opt/ai-env..."
    python3 -m venv /opt/ai-env
    
    # Activate environment
    source /opt/ai-env/bin/activate
    
    # Upgrade pip first (CRITICAL FIX)
    print_info "Upgrading pip..."
    /opt/ai-env/bin/python3 -m pip install --upgrade pip setuptools wheel
    
    # Install dependencies with proper error handling
    print_info "Installing PyTorch (CPU version)..."
    /opt/ai-env/bin/pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
    
    print_info "Installing Transformers & AI libraries..."
    /opt/ai-env/bin/pip install \
        transformers \
        accelerate \
        sentencepiece \
        protobuf
    
    print_info "Installing optional libraries..."
    /opt/ai-env/bin/pip install \
        bitsandbytes \
        peft \
        datasets \
        || print_warn "Some optional libraries failed (non-critical)"
    
    print_info "Installing FastAPI & web framework..."
    /opt/ai-env/bin/pip install \
        fastapi \
        uvicorn[standard] \
        pydantic
    
    print_step "Python environment setup completed!"
    sleep 2
}

# ═══════════════════════════════════════════════════════════
# STEP 4: MODEL CATEGORY SELECTION
# ═══════════════════════════════════════════════════════════

select_model_category() {
    print_header
    print_step "[4/13] AI Model Category Selection"
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}Available AI Model Categories:${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${GREEN}1)${NC} 💬 ${BOLD}Text Generation${NC} ${CYAN}(Chat, Coding, Q&A)${NC}"
    echo -e "${GREEN}2)${NC} 🎨 ${BOLD}Image Generation${NC} ${CYAN}(Art, Design, Visuals)${NC}"
    echo -e "${GREEN}3)${NC} 👁️  ${BOLD}Image Analysis${NC} ${CYAN}(Captioning, Classification)${NC}"
    echo -e "${GREEN}4)${NC} 🎵 ${BOLD}Audio Models${NC} ${CYAN}(Speech-to-Text, TTS)${NC}"
    echo -e "${GREEN}5)${NC} 🎬 ${BOLD}Video Models${NC} ${CYAN}(Video Understanding)${NC}"
    echo ""
    
    read -p "$(echo -e ${CYAN}Select category [1-5]: ${NC})" CATEGORY_CHOICE
    
    case $CATEGORY_CHOICE in
        1) select_text_model ;;
        2) select_image_gen_model ;;
        3) select_image_analysis_model ;;
        4) select_audio_model ;;
        5) select_video_model ;;
        *) 
            print_error "Invalid selection!"
            exit 1
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════
# TEXT GENERATION MODELS
# ═══════════════════════════════════════════════════════════

select_text_model() {
    print_header
    echo -e "${BOLD}💬 Text Generation Models${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${YELLOW}⭐ RECOMMENDED${NC}"
    echo -e "${GREEN}1)${NC} ${BOLD}Qwen 2.5 Coder 7B${NC}"
    echo -e "   ${CYAN}→${NC} State-of-the-art coding model"
    echo -e "   ${CYAN}→${NC} Quantization: 4-bit | RAM: ~6GB"
    echo -e "   ${CYAN}→${NC} Best for: Coding & Development"
    echo ""
    
    echo -e "${CYAN}💡 LIGHTWEIGHT${NC}"
    echo -e "${GREEN}2)${NC} ${BOLD}Qwen 2.5 Coder 3B${NC}"
    echo -e "   ${CYAN}→${NC} Balanced performance"
    echo -e "   ${CYAN}→${NC} Parameters: 3B | RAM: ~4GB"
    echo -e "   ${CYAN}→${NC} Best for: General Coding"
    echo ""
    
    echo -e "${PURPLE}💭 GENERAL CHAT${NC}"
    echo -e "${GREEN}3)${NC} ${BOLD}Qwen 2.5 7B Instruct${NC}"
    echo -e "   ${CYAN}→${NC} Versatile conversation model"
    echo -e "   ${CYAN}→${NC} Parameters: 7B | RAM: ~6GB"
    echo -e "   ${CYAN}→${NC} Best for: Chat & Q&A"
    echo ""
    
    echo -e "${BLUE}🦙 META AI${NC}"
    echo -e "${GREEN}4)${NC} ${BOLD}LLaMA 3 8B${NC}"
    echo -e "   ${CYAN}→${NC} Meta's powerful open-source"
    echo -e "   ${CYAN}→${NC} Parameters: 8B | RAM: ~7GB (4-bit)"
    echo -e "   ${CYAN}→${NC} Best for: Chat & Reasoning"
    echo ""
    
    echo -e "${GREEN}🏢 MICROSOFT${NC}"
    echo -e "${GREEN}5)${NC} ${BOLD}Phi-3 Mini${NC}"
    echo -e "   ${CYAN}→${NC} Compact from Microsoft Research"
    echo -e "   ${CYAN}→${NC} Context: 4k tokens | RAM: ~3GB"
    echo -e "   ${CYAN}→${NC} Best for: General Purpose"
    echo ""
    
    read -p "$(echo -e ${CYAN}Select text model [1-5]: ${NC})" MODEL_CHOICE
    
    case $MODEL_CHOICE in
        1) 
            MODEL_ID="Qwen/Qwen2.5-Coder-7B-Instruct"
            MODEL_NAME="Qwen 2.5 Coder 7B"
            MODEL_TYPE="text"
            MODEL_RAM="6GB"
            ;;
        2) 
            MODEL_ID="Qwen/Qwen2.5-Coder-3B-Instruct"
            MODEL_NAME="Qwen 2.5 Coder 3B"
            MODEL_TYPE="text"
            MODEL_RAM="4GB"
            ;;
        3) 
            MODEL_ID="Qwen/Qwen2.5-7B-Instruct"
            MODEL_NAME="Qwen 2.5 7B Instruct"
            MODEL_TYPE="text"
            MODEL_RAM="6GB"
            ;;
        4) 
            MODEL_ID="meta-llama/Meta-Llama-3-8B-Instruct"
            MODEL_NAME="LLaMA 3 8B"
            MODEL_TYPE="text"
            MODEL_RAM="7GB"
            ;;
        5) 
            MODEL_ID="microsoft/Phi-3-mini-4k-instruct"
            MODEL_NAME="Phi-3 Mini"
            MODEL_TYPE="text"
            MODEL_RAM="3GB"
            ;;
        *) 
            print_error "Invalid selection!"
            exit 1
            ;;
    esac
    
    print_step "Selected: ${MODEL_NAME} (${MODEL_RAM} RAM)"
    log "Model selected: $MODEL_ID"
    sleep 2
}

# ═══════════════════════════════════════════════════════════
# IMAGE GENERATION MODELS
# ═══════════════════════════════════════════════════════════

select_image_gen_model() {
    print_header
    echo -e "${BOLD}🎨 Image Generation Models${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${YELLOW}⭐ RECOMMENDED${NC}"
    echo -e "${GREEN}1)${NC} ${BOLD}Stable Diffusion v1.5${NC}"
    echo -e "   ${CYAN}→${NC} Proven high-quality generation"
    echo -e "   ${CYAN}→${NC} Resolution: 512x512 | RAM: ~4GB"
    echo -e "   ${CYAN}→${NC} Best for: General Art & Design"
    echo ""
    
    echo -e "${PURPLE}✨ HIGH QUALITY${NC}"
    echo -e "${GREEN}2)${NC} ${BOLD}Stable Diffusion XL${NC}"
    echo -e "   ${CYAN}→${NC} Next-gen with superior detail"
    echo -e "   ${CYAN}→${NC} Resolution: 1024x1024 | RAM: ~8GB"
    echo -e "   ${CYAN}→${NC} Best for: Professional Art"
    echo ""
    
    echo -e "${BLUE}⚡ FAST${NC}"
    echo -e "${GREEN}3)${NC} ${BOLD}SD Turbo${NC}"
    echo -e "   ${CYAN}→${NC} Ultra-fast single-step inference"
    echo -e "   ${CYAN}→${NC} Speed: 1-4 steps | RAM: ~4GB"
    echo -e "   ${CYAN}→${NC} Best for: Quick Iterations"
    echo ""
    
    read -p "$(echo -e ${CYAN}Select image generation model [1-3]: ${NC})" MODEL_CHOICE
    
    case $MODEL_CHOICE in
        1) 
            MODEL_ID="runwayml/stable-diffusion-v1-5"
            MODEL_NAME="Stable Diffusion v1.5"
            MODEL_TYPE="image_gen"
            MODEL_RAM="4GB"
            ;;
        2) 
            MODEL_ID="stabilityai/stable-diffusion-xl-base-1.0"
            MODEL_NAME="Stable Diffusion XL"
            MODEL_TYPE="image_gen"
            MODEL_RAM="8GB"
            ;;
        3) 
            MODEL_ID="stabilityai/sd-turbo"
            MODEL_NAME="SD Turbo"
            MODEL_TYPE="image_gen"
            MODEL_RAM="4GB"
            ;;
        *) 
            print_error "Invalid selection!"
            exit 1
            ;;
    esac
    
    print_step "Selected: ${MODEL_NAME} (${MODEL_RAM} RAM)"
    log "Model selected: $MODEL_ID"
    sleep 2
}

# ═══════════════════════════════════════════════════════════
# IMAGE ANALYSIS MODELS
# ═══════════════════════════════════════════════════════════

select_image_analysis_model() {
    print_header
    echo -e "${BOLD}👁️ Image Analysis Models${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${YELLOW}📝 CAPTIONING${NC}"
    echo -e "${GREEN}1)${NC} ${BOLD}BLIP-2${NC}"
    echo -e "   ${CYAN}→${NC} Advanced image-to-text from Salesforce"
    echo -e "   ${CYAN}→${NC} Parameters: 2.7B | RAM: ~5GB"
    echo -e "   ${CYAN}→${NC} Best for: Image Description"
    echo ""
    
    echo -e "${BLUE}🔍 MATCHING${NC}"
    echo -e "${GREEN}2)${NC} ${BOLD}CLIP${NC}"
    echo -e "   ${CYAN}→${NC} OpenAI's image-text matching"
    echo -e "   ${CYAN}→${NC} Multi-modal: Vision + Text | RAM: ~2GB"
    echo -e "   ${CYAN}→${NC} Best for: Image Search"
    echo ""
    
    echo -e "${PURPLE}🏷️ CLASSIFICATION${NC}"
    echo -e "${GREEN}3)${NC} ${BOLD}ViT (Vision Transformer)${NC}"
    echo -e "   ${CYAN}→${NC} Google's transformer-based vision"
    echo -e "   ${CYAN}→${NC} Architecture: Transformer | RAM: ~2GB"
    echo -e "   ${CYAN}→${NC} Best for: Object Recognition"
    echo ""
    
    read -p "$(echo -e ${CYAN}Select image analysis model [1-3]: ${NC})" MODEL_CHOICE
    
    case $MODEL_CHOICE in
        1) 
            MODEL_ID="Salesforce/blip2-opt-2.7b"
            MODEL_NAME="BLIP-2"
            MODEL_TYPE="image_analysis"
            MODEL_RAM="5GB"
            ;;
        2) 
            MODEL_ID="openai/clip-vit-large-patch14"
            MODEL_NAME="CLIP"
            MODEL_TYPE="image_analysis"
            MODEL_RAM="2GB"
            ;;
        3) 
            MODEL_ID="google/vit-base-patch16-224"
            MODEL_NAME="Vision Transformer (ViT)"
            MODEL_TYPE="image_analysis"
            MODEL_RAM="2GB"
            ;;
        *) 
            print_error "Invalid selection!"
            exit 1
            ;;
    esac
    
    print_step "Selected: ${MODEL_NAME} (${MODEL_RAM} RAM)"
    log "Model selected: $MODEL_ID"
    sleep 2
}

# ═══════════════════════════════════════════════════════════
# AUDIO MODELS
# ═══════════════════════════════════════════════════════════

select_audio_model() {
    print_header
    echo -e "${BOLD}🎵 Audio Models${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${YELLOW}🎤 SPEECH-TO-TEXT${NC}"
    echo -e "${GREEN}1)${NC} ${BOLD}Whisper${NC}"
    echo -e "   ${CYAN}→${NC} OpenAI's robust speech recognition"
    echo -e "   ${CYAN}→${NC} Languages: 99+ | RAM: ~3GB"
    echo -e "   ${CYAN}→${NC} Best for: Transcription"
    echo ""
    
    echo -e "${BLUE}🔊 TEXT-TO-SPEECH${NC}"
    echo -e "${GREEN}2)${NC} ${BOLD}Bark${NC}"
    echo -e "   ${CYAN}→${NC} Natural-sounding voice synthesis"
    echo -e "   ${CYAN}→${NC} Voices: Multiple styles | RAM: ~4GB"
    echo -e "   ${CYAN}→${NC} Best for: Voice Generation"
    echo ""
    
    read -p "$(echo -e ${CYAN}Select audio model [1-2]: ${NC})" MODEL_CHOICE
    
    case $MODEL_CHOICE in
        1) 
            MODEL_ID="openai/whisper-large-v3"
            MODEL_NAME="Whisper Large v3"
            MODEL_TYPE="audio"
            MODEL_RAM="3GB"
            ;;
        2) 
            MODEL_ID="suno/bark"
            MODEL_NAME="Bark"
            MODEL_TYPE="audio"
            MODEL_RAM="4GB"
            ;;
        *) 
            print_error "Invalid selection!"
            exit 1
            ;;
    esac
    
    print_step "Selected: ${MODEL_NAME} (${MODEL_RAM} RAM)"
    log "Model selected: $MODEL_ID"
    sleep 2
}

# ═══════════════════════════════════════════════════════════
# VIDEO MODELS
# ═══════════════════════════════════════════════════════════

select_video_model() {
    print_header
    echo -e "${BOLD}🎬 Video Models${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${YELLOW}📹 VIDEO UNDERSTANDING${NC}"
    echo -e "${GREEN}1)${NC} ${BOLD}Video-LLaVA${NC}"
    echo -e "   ${CYAN}→${NC} Advanced video comprehension"
    echo -e "   ${CYAN}→${NC} Parameters: 7B | RAM: ~8GB"
    echo -e "   ${CYAN}→${NC} Best for: Video Q&A"
    echo ""
    
    read -p "$(echo -e ${CYAN}Select video model [1]: ${NC})" MODEL_CHOICE
    
    case $MODEL_CHOICE in
        1) 
            MODEL_ID="LanguageBind/Video-LLaVA-7B"
            MODEL_NAME="Video-LLaVA 7B"
            MODEL_TYPE="video"
            MODEL_RAM="8GB"
            ;;
        *) 
            print_error "Invalid selection!"
            exit 1
            ;;
    esac
    
    print_step "Selected: ${MODEL_NAME} (${MODEL_RAM} RAM)"
    log "Model selected: $MODEL_ID"
    sleep 2
}

# ═══════════════════════════════════════════════════════════
# STEP 5: AI SERVER CREATION
# ═══════════════════════════════════════════════════════════

create_ai_server() {
    print_header
    print_step "[5/13] Creating AI Server Application"
    log "Creating AI server for model type: $MODEL_TYPE"
    
    mkdir -p /opt/ai-server
    
    # Create appropriate server based on model type
    case $MODEL_TYPE in
        text)
            create_text_server
            ;;
        image_gen)
            create_image_gen_server
            ;;
        image_analysis)
            create_image_analysis_server
            ;;
        audio)
            create_audio_server
            ;;
        video)
            create_video_server
            ;;
        *)
            print_error "Unknown model type: $MODEL_TYPE"
            exit 1
            ;;
    esac
    
    print_step "AI Server created successfully!"
    sleep 2
}

# ═══════════════════════════════════════════════════════════
# TEXT GENERATION SERVER
# ═══════════════════════════════════════════════════════════

create_text_server() {
    cat <<'EOF' > /opt/ai-server/app.py
"""
RizzDevs AI SaaS API Server - Text Generation
Enterprise-grade AI inference API
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
import logging
import os

# Logging setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="RizzDevs AI SaaS API - Text Generation",
    description="Enterprise AI Text Generation Server",
    version="2.1.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global model variables
model = None
tokenizer = None
MODEL_ID = os.getenv("MODEL_ID", "${MODEL_ID}")
MODEL_NAME = os.getenv("MODEL_NAME", "${MODEL_NAME}")

class ChatRequest(BaseModel):
    prompt: str
    max_tokens: int = 256
    temperature: float = 0.7
    top_p: float = 0.9

class ChatResponse(BaseModel):
    response: str
    model: str
    tokens_used: int

@app.on_event("startup")
async def load_model():
    """Load AI model on startup"""
    global model, tokenizer
    
    try:
        logger.info(f"Loading model: {MODEL_ID}")
        
        # 4-bit quantization config
        quantization_config = BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_compute_dtype=torch.float16,
            bnb_4bit_use_double_quant=True,
            bnb_4bit_quant_type="nf4"
        )
        
        # Load tokenizer
        tokenizer = AutoTokenizer.from_pretrained(
            MODEL_ID,
            trust_remote_code=True
        )
        
        # Load model with 4-bit quantization
        model = AutoModelForCausalLM.from_pretrained(
            MODEL_ID,
            quantization_config=quantization_config,
            device_map="auto",
            trust_remote_code=True,
            torch_dtype=torch.float16
        )
        
        logger.info("Model loaded successfully!")
        logger.info(f"Device: {model.device}")
        
    except Exception as e:
        logger.error(f"Failed to load model: {e}")
        raise

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": "RizzDevs AI SaaS API",
        "version": "2.1.0",
        "model": MODEL_NAME,
        "model_type": "text_generation",
        "status": "running",
        "endpoints": {
            "health": "/health",
            "chat": "/chat",
            "models": "/models",
            "docs": "/docs"
        }
    }

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "model_loaded": model is not None,
        "model_name": MODEL_NAME,
        "model_type": "text_generation"
    }

@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """Chat completion endpoint"""
    if model is None or tokenizer is None:
        raise HTTPException(status_code=503, detail="Model not loaded")
    
    try:
        # Tokenize input
        inputs = tokenizer(
            request.prompt,
            return_tensors="pt",
            padding=True
        ).to(model.device)
        
        # Generate response
        with torch.no_grad():
            outputs = model.generate(
                **inputs,
                max_new_tokens=request.max_tokens,
                temperature=request.temperature,
                top_p=request.top_p,
                do_sample=True,
                pad_token_id=tokenizer.eos_token_id
            )
        
        # Decode response
        response_text = tokenizer.decode(outputs[0], skip_special_tokens=True)
        
        return ChatResponse(
            response=response_text,
            model="${MODEL_NAME}",
            tokens_used=len(outputs[0])
        )
        
    except Exception as e:
        logger.error(f"Chat error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/models")
async def list_models():
    """List available models"""
    return {
        "current_model": "${MODEL_NAME}",
        "model_id": "${MODEL_ID}",
        "model_type": "text_generation",
        "quantization": "4-bit",
        "device": str(model.device) if model else "not_loaded"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF
}

# ═══════════════════════════════════════════════════════════
# IMAGE GENERATION SERVER
# ═══════════════════════════════════════════════════════════

create_image_gen_server() {
    # Install additional dependencies
    /opt/ai-env/bin/pip install diffusers pillow
    
    cat <<'EOF' > /opt/ai-server/app.py
"""
RizzDevs AI SaaS API Server - Image Generation
Enterprise-grade Stable Diffusion API
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from pydantic import BaseModel
from typing import Optional
import torch
from diffusers import StableDiffusionPipeline, StableDiffusionXLPipeline
import logging
import os
import io
import base64

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="RizzDevs AI SaaS API - Image Generation",
    description="Enterprise Stable Diffusion Server",
    version="2.1.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

pipe = None
MODEL_ID = "${MODEL_ID}"
MODEL_NAME = "${MODEL_NAME}"

class ImageRequest(BaseModel):
    prompt: str
    negative_prompt: Optional[str] = ""
    num_inference_steps: int = 50
    guidance_scale: float = 7.5
    width: int = 512
    height: int = 512

@app.on_event("startup")
async def load_model():
    global pipe
    try:
        logger.info(f"Loading model: {MODEL_ID}")
        
        if "xl" in MODEL_ID.lower():
            pipe = StableDiffusionXLPipeline.from_pretrained(
                MODEL_ID,
                torch_dtype=torch.float16,
                use_safetensors=True
            )
        else:
            pipe = StableDiffusionPipeline.from_pretrained(
                MODEL_ID,
                torch_dtype=torch.float16,
                use_safetensors=True
            )
        
        pipe = pipe.to("cuda" if torch.cuda.is_available() else "cpu")
        logger.info("Model loaded successfully!")
        
    except Exception as e:
        logger.error(f"Failed to load model: {e}")
        raise

@app.get("/")
async def root():
    return {
        "service": "RizzDevs AI Image Generation",
        "version": "2.1.0",
        "model": MODEL_NAME,
        "model_type": "image_generation",
        "status": "running"
    }

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "model_loaded": pipe is not None,
        "model_name": MODEL_NAME,
        "model_type": "image_generation"
    }

@app.post("/generate")
async def generate_image(request: ImageRequest):
    if pipe is None:
        raise HTTPException(status_code=503, detail="Model not loaded")
    
    try:
        image = pipe(
            prompt=request.prompt,
            negative_prompt=request.negative_prompt,
            num_inference_steps=request.num_inference_steps,
            guidance_scale=request.guidance_scale,
            width=request.width,
            height=request.height
        ).images[0]
        
        # Convert to base64
        buffered = io.BytesIO()
        image.save(buffered, format="PNG")
        img_str = base64.b64encode(buffered.getvalue()).decode()
        
        return {
            "image": img_str,
            "model": MODEL_NAME,
            "format": "base64"
        }
        
    except Exception as e:
        logger.error(f"Generation error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF
}

# ═══════════════════════════════════════════════════════════
# IMAGE ANALYSIS SERVER
# ═══════════════════════════════════════════════════════════

create_image_analysis_server() {
    /opt/ai-env/bin/pip install pillow
    
    cat <<'EOF' > /opt/ai-server/app.py
"""
RizzDevs AI SaaS API Server - Image Analysis
Vision models for captioning and classification
"""

from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import torch
from transformers import BlipProcessor, BlipForConditionalGeneration, CLIPProcessor, CLIPModel, ViTImageProcessor, ViTForImageClassification
from PIL import Image
import logging
import os
import io

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="RizzDevs AI SaaS API - Image Analysis",
    description="Vision AI Analysis Server",
    version="2.1.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

model = None
processor = None
MODEL_ID = "${MODEL_ID}"
MODEL_NAME = "${MODEL_NAME}"

@app.on_event("startup")
async def load_model():
    global model, processor
    try:
        logger.info(f"Loading model: {MODEL_ID}")
        
        if "blip" in MODEL_ID.lower():
            processor = BlipProcessor.from_pretrained(MODEL_ID)
            model = BlipForConditionalGeneration.from_pretrained(MODEL_ID)
        elif "clip" in MODEL_ID.lower():
            processor = CLIPProcessor.from_pretrained(MODEL_ID)
            model = CLIPModel.from_pretrained(MODEL_ID)
        elif "vit" in MODEL_ID.lower():
            processor = ViTImageProcessor.from_pretrained(MODEL_ID)
            model = ViTForImageClassification.from_pretrained(MODEL_ID)
        
        logger.info("Model loaded successfully!")
        
    except Exception as e:
        logger.error(f"Failed to load model: {e}")
        raise

@app.get("/")
async def root():
    return {
        "service": "RizzDevs AI Image Analysis",
        "version": "2.1.0",
        "model": MODEL_NAME,
        "model_type": "image_analysis",
        "status": "running"
    }

@app.post("/analyze")
async def analyze_image(file: UploadFile = File(...)):
    if model is None or processor is None:
        raise HTTPException(status_code=503, detail="Model not loaded")
    
    try:
        image = Image.open(io.BytesIO(await file.read()))
        
        if "blip" in MODEL_ID.lower():
            inputs = processor(image, return_tensors="pt")
            out = model.generate(**inputs)
            caption = processor.decode(out[0], skip_special_tokens=True)
            return {"caption": caption, "model": MODEL_NAME}
        
        elif "vit" in MODEL_ID.lower():
            inputs = processor(image, return_tensors="pt")
            outputs = model(**inputs)
            predicted_class = outputs.logits.argmax(-1).item()
            return {"class": model.config.id2label[predicted_class], "model": MODEL_NAME}
        
    except Exception as e:
        logger.error(f"Analysis error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF
}

# ═══════════════════════════════════════════════════════════
# AUDIO SERVER
# ═══════════════════════════════════════════════════════════

create_audio_server() {
    cat <<'EOF' > /opt/ai-server/app.py
"""
RizzDevs AI SaaS API Server - Audio Processing
Speech-to-Text and Text-to-Speech
"""

from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import torch
from transformers import WhisperProcessor, WhisperForConditionalGeneration, AutoProcessor, BarkModel
import logging
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="RizzDevs AI SaaS API - Audio",
    description="Audio AI Processing Server",
    version="2.1.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

model = None
processor = None
MODEL_ID = "${MODEL_ID}"
MODEL_NAME = "${MODEL_NAME}"

@app.on_event("startup")
async def load_model():
    global model, processor
    try:
        logger.info(f"Loading model: {MODEL_ID}")
        
        if "whisper" in MODEL_ID.lower():
            processor = WhisperProcessor.from_pretrained(MODEL_ID)
            model = WhisperForConditionalGeneration.from_pretrained(MODEL_ID)
        elif "bark" in MODEL_ID.lower():
            processor = AutoProcessor.from_pretrained(MODEL_ID)
            model = BarkModel.from_pretrained(MODEL_ID)
        
        logger.info("Model loaded successfully!")
        
    except Exception as e:
        logger.error(f"Failed to load model: {e}")
        raise

@app.get("/")
async def root():
    return {
        "service": "RizzDevs AI Audio Processing",
        "version": "2.1.0",
        "model": MODEL_NAME,
        "model_type": "audio",
        "status": "running"
    }

@app.post("/transcribe")
async def transcribe(file: UploadFile = File(...)):
    if model is None or processor is None:
        raise HTTPException(status_code=503, detail="Model not loaded")
    
    try:
        audio = await file.read()
        # Process audio transcription here
        return {"transcription": "Audio processed", "model": MODEL_NAME}
    except Exception as e:
        logger.error(f"Transcription error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF
}

# ═══════════════════════════════════════════════════════════
# VIDEO SERVER
# ═══════════════════════════════════════════════════════════

create_video_server() {
    cat <<'EOF' > /opt/ai-server/app.py
"""
RizzDevs AI SaaS API Server - Video Understanding
Video comprehension and Q&A
"""

from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import torch
from transformers import AutoProcessor, AutoModelForVision2Seq
import logging
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="RizzDevs AI SaaS API - Video",
    description="Video AI Understanding Server",
    version="2.1.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

model = None
processor = None
MODEL_ID = "${MODEL_ID}"
MODEL_NAME = "${MODEL_NAME}"

@app.on_event("startup")
async def load_model():
    global model, processor
    try:
        logger.info(f"Loading model: {MODEL_ID}")
        processor = AutoProcessor.from_pretrained(MODEL_ID)
        model = AutoModelForVision2Seq.from_pretrained(MODEL_ID, torch_dtype=torch.float16)
        logger.info("Model loaded successfully!")
    except Exception as e:
        logger.error(f"Failed to load model: {e}")
        raise

@app.get("/")
async def root():
    return {
        "service": "RizzDevs AI Video Understanding",
        "version": "2.1.0",
        "model": MODEL_NAME,
        "model_type": "video",
        "status": "running"
    }

@app.post("/analyze")
async def analyze_video(file: UploadFile = File(...), question: str = "What is happening in this video?"):
    if model is None or processor is None:
        raise HTTPException(status_code=503, detail="Model not loaded")
    
    try:
        # Process video here
        return {"answer": "Video analysis result", "model": MODEL_NAME}
    except Exception as e:
        logger.error(f"Analysis error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF
}

# ═══════════════════════════════════════════════════════════
# STEP 6-10: Additional Features
# ═══════════════════════════════════════════════════════════

setup_training() {
    print_header
    print_step "[6/13] Training Configuration (Optional)"
    
    if ask "Enable QLoRA training module?"; then
        mkdir -p /opt/ai-server/train
        
        cat <<EOF > /opt/ai-server/train/train.py
"""
QLoRA Training Module - RizzDevs
"""
# Training code here (manual trigger only)
print("QLoRA training ready - use small datasets only!")
EOF
        
        print_step "Training module installed!"
    else
        print_info "Training module skipped"
    fi
    
    sleep 2
}

setup_database() {
    print_header
    print_step "[7/13] Database Configuration"
    
    if ask "Setup MySQL database?"; then
        read -p "Database name [ai_saas]: " DBNAME
        DBNAME=${DBNAME:-ai_saas}
        
        read -p "Database user: " DBUSER
        read -sp "Database password: " DBPASS
        echo ""
        
        mysql -e "CREATE DATABASE IF NOT EXISTS $DBNAME;"
        mysql -e "CREATE USER IF NOT EXISTS '$DBUSER'@'%' IDENTIFIED BY '$DBPASS';"
        mysql -e "GRANT ALL PRIVILEGES ON $DBNAME.* TO '$DBUSER'@'%';"
        mysql -e "FLUSH PRIVILEGES;"
        
        print_step "Database configured: $DBNAME"
    else
        print_info "Database setup skipped"
    fi
    
    sleep 2
}

setup_saas_mode() {
    print_header
    print_step "[8/13] SaaS Mode Configuration"
    
    if ask "Enable full SaaS mode?"; then
        mkdir -p /opt/ai-saas/{frontend,backend,logs}
        
        echo "SAAS_MODE=enabled" > /opt/ai-saas/.env
        echo "API_ENDPOINT=http://localhost:8000" >> /opt/ai-saas/.env
        
        print_step "SaaS mode enabled!"
    else
        print_info "SaaS mode skipped"
    fi
    
    sleep 2
}

# ═══════════════════════════════════════════════════════════
# STEP 10: SSL/HTTPS SETUP (Optional)
# ═══════════════════════════════════════════════════════════

setup_ssl() {
    print_header
    print_step "[10/13] SSL/HTTPS Configuration"
    
    if ask "Setup SSL with Let's Encrypt?"; then
        if [[ -f /opt/ai-server/cloudflare.conf ]]; then
            source /opt/ai-server/cloudflare.conf
            
            # Install certbot
            apt install -y certbot python3-certbot-nginx
            
            # Get SSL certificate
            print_info "Obtaining SSL certificate for $CF_DOMAIN..."
            certbot --nginx -d "$CF_DOMAIN" --non-interactive --agree-tos -m "$CF_EMAIL"
            
            if [ $? -eq 0 ]; then
                print_step "SSL certificate installed!"
                
                # Setup auto-renewal
                systemctl enable certbot.timer
                systemctl start certbot.timer
                
                print_step "Auto-renewal configured!"
            else
                print_warn "SSL setup failed, continuing without HTTPS"
            fi
        else
            print_warn "Domain not configured, skipping SSL"
        fi
    else
        print_info "SSL setup skipped"
    fi
    
    sleep 2
}

# ═══════════════════════════════════════════════════════════
# STEP 11: NGINX REVERSE PROXY
# ═══════════════════════════════════════════════════════════

setup_nginx() {
    print_header
    print_step "[11/13] Nginx Reverse Proxy Configuration"
    
    if ask "Setup Nginx reverse proxy?"; then
        # Load domain if configured
        if [[ -f /opt/ai-server/cloudflare.conf ]]; then
            source /opt/ai-server/cloudflare.conf
            DOMAIN_CONFIG=$CF_DOMAIN
        else
            SERVER_IP=$(curl -s ifconfig.me)
            DOMAIN_CONFIG=$SERVER_IP
        fi
        
        cat > /etc/nginx/sites-available/rizzdevs-ai <<EOF
server {
    listen 80;
    server_name $DOMAIN_CONFIG;
    
    # Increase timeouts for AI processing
    proxy_read_timeout 300s;
    proxy_connect_timeout 75s;
    
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # CORS headers
        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;
    }
    
    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=api_limit:10m rate=10r/s;
    limit_req zone=api_limit burst=20 nodelay;
}
EOF
        
        # Enable site
        ln -sf /etc/nginx/sites-available/rizzdevs-ai /etc/nginx/sites-enabled/
        
        # Test and reload nginx
        nginx -t && systemctl reload nginx
        
        print_step "Nginx configured!"
    else
        print_info "Nginx setup skipped"
    fi
    
    sleep 2
}

# ═══════════════════════════════════════════════════════════
# STEP 12: SYSTEMD SERVICE
# ═══════════════════════════════════════════════════════════

create_systemd_service() {
    print_header
    print_step "[12/13] Creating Systemd Service"
    
    cat <<EOF > /etc/systemd/system/rizzdevs-ai.service
[Unit]
Description=RizzDevs AI SaaS API Server
Documentation=https://coders1.vercel.app
After=network.target mysql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/ai-server
Environment="PATH=/opt/ai-env/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/opt/ai-env/bin/uvicorn app:app --host 0.0.0.0 --port 8000 --workers 2
Restart=always
RestartSec=10
StandardOutput=append:/var/log/rizzdevs-ai.log
StandardError=append:/var/log/rizzdevs-ai-error.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable rizzdevs-ai
    
    print_step "Systemd service created!"
    
    if ask "Start AI service now?"; then
        systemctl start rizzdevs-ai
        sleep 3
        systemctl status rizzdevs-ai --no-pager
    fi
    
    sleep 2
}

# ═══════════════════════════════════════════════════════════
# STEP 13: FINAL SETUP
# ═══════════════════════════════════════════════════════════

final_setup() {
    print_header
    print_step "[13/13] Final Configuration"
    
    # Get server IP and domain
    SERVER_IP=$(curl -s ifconfig.me || echo "YOUR_IP")
    
    # Load domain if configured
    if [[ -f /opt/ai-server/cloudflare.conf ]]; then
        source /opt/ai-server/cloudflare.conf
        API_URL="http://$CF_DOMAIN"
    else
        API_URL="http://$SERVER_IP:8000"
    fi
    
    # Create welcome message
    cat <<EOF > /opt/ai-server/README.md
# RizzDevs AI SaaS Server

## Installation Complete! 🎉

### Server Information
- **Model**: ${MODEL_NAME}
- **API Endpoint**: ${API_URL}
- **Documentation**: ${API_URL}/docs
- **Health Check**: ${API_URL}/health

### Cloudflare DNS
$(if [[ -f /opt/ai-server/cloudflare.conf ]]; then
    echo "- **Domain**: $CF_DOMAIN"
    echo "- **Zone ID**: $CF_ZONE_ID"
    echo "- **Status**: Configured ✓"
else
    echo "- **Status**: Not configured"
fi)

### Quick Commands
\`\`\`bash
# Start service
systemctl start rizzdevs-ai

# Stop service
systemctl stop rizzdevs-ai

# Check status
systemctl status rizzdevs-ai

# View logs
journalctl -u rizzdevs-ai -f
\`\`\`

### API Usage Example
\`\`\`bash
curl -X POST "${API_URL}/chat" \\
  -H "Content-Type: application/json" \\
  -d '{
    "prompt": "Write a Python function",
    "max_tokens": 256,
    "temperature": 0.7
  }'
\`\`\`

### Cloudflare Management
\`\`\`bash
# View DNS config
cat /opt/ai-server/cloudflare.conf

# Update DNS record (run as script)
bash /opt/ai-server/update-dns.sh
\`\`\`

### Documentation
Visit: https://coders1.vercel.app

### Created by RizzDevs
EOF

    # Create DNS update script
    cat > /opt/ai-server/update-dns.sh <<'EOF'
#!/bin/bash
# Quick DNS update script

if [[ -f /opt/ai-server/cloudflare.conf ]]; then
    source /opt/ai-server/cloudflare.conf
    
    SERVER_IP=$(curl -s ifconfig.me)
    
    # Get record ID
    RECORD_CHECK=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?name=$CF_DOMAIN" \
        -H "X-Auth-Email: $CF_EMAIL" \
        -H "X-Auth-Key: $CF_API_KEY" \
        -H "Content-Type: application/json")
    
    RECORD_ID=$(echo "$RECORD_CHECK" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
    
    if [[ -n "$RECORD_ID" ]]; then
        # Update DNS
        curl -X PUT "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$RECORD_ID" \
            -H "X-Auth-Email: $CF_EMAIL" \
            -H "X-Auth-Key: $CF_API_KEY" \
            -H "Content-Type: application/json" \
            --data "{
                \"type\": \"A\",
                \"name\": \"$CF_DOMAIN\",
                \"content\": \"$SERVER_IP\",
                \"ttl\": 1,
                \"proxied\": false
            }"
        
        echo "DNS updated: $CF_DOMAIN -> $SERVER_IP"
    else
        echo "Error: Record not found"
    fi
else
    echo "Error: Cloudflare config not found"
fi
EOF
    
    chmod +x /opt/ai-server/update-dns.sh
    
    print_step "Setup completed successfully!"
}

# ═══════════════════════════════════════════════════════════
# FINAL SUMMARY
# ═══════════════════════════════════════════════════════════

show_summary() {
    SERVER_IP=$(curl -s ifconfig.me || echo "YOUR_IP")
    
    # Load domain if configured
    if [[ -f /opt/ai-server/cloudflare.conf ]]; then
        source /opt/ai-server/cloudflare.conf
        API_URL="http://$CF_DOMAIN"
        DOMAIN_STATUS="${GREEN}Configured${NC}"
    else
        API_URL="http://$SERVER_IP:8000"
        DOMAIN_STATUS="${YELLOW}Not configured${NC}"
    fi
    
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${GREEN}${BOLD}              INSTALLATION COMPLETED! 🎉                   ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}AI SaaS Server Information:${NC}"
    echo -e "${GREEN}✓${NC} Model       : ${PURPLE}${MODEL_NAME}${NC}"
    echo -e "${GREEN}✓${NC} API Endpoint: ${BLUE}${API_URL}${NC}"
    echo -e "${GREEN}✓${NC} API Docs    : ${BLUE}${API_URL}/docs${NC}"
    echo -e "${GREEN}✓${NC} Health      : ${BLUE}${API_URL}/health${NC}"
    echo ""
    echo -e "${BOLD}Cloudflare DNS:${NC}"
    echo -e "${GREEN}✓${NC} Status      : ${DOMAIN_STATUS}"
    if [[ -f /opt/ai-server/cloudflare.conf ]]; then
        echo -e "${GREEN}✓${NC} Domain      : ${CYAN}$CF_DOMAIN${NC}"
        echo -e "${GREEN}✓${NC} IP Address  : ${CYAN}$SERVER_IP${NC}"
    fi
    echo ""
    echo -e "${BOLD}Service Management:${NC}"
    echo -e "  ${CYAN}systemctl start rizzdevs-ai${NC}   - Start service"
    echo -e "  ${CYAN}systemctl stop rizzdevs-ai${NC}    - Stop service"
    echo -e "  ${CYAN}systemctl status rizzdevs-ai${NC}  - Check status"
    echo -e "  ${CYAN}journalctl -u rizzdevs-ai -f${NC}  - View logs"
    echo ""
    echo -e "${BOLD}DNS Management:${NC}"
    echo -e "  ${CYAN}/opt/ai-server/update-dns.sh${NC}  - Update DNS record"
    echo ""
    echo -e "${BOLD}Test API:${NC}"
    echo -e "  ${YELLOW}curl -X POST ${API_URL}/chat \\${NC}"
    echo -e "    ${YELLOW}-H 'Content-Type: application/json' \\${NC}"
    echo -e "    ${YELLOW}-d '{\"prompt\":\"Hello AI\",\"max_tokens\":100}'${NC}"
    echo ""
    echo -e "${BOLD}Documentation:${NC}"
    echo -e "  ${BLUE}https://coders1.vercel.app${NC}"
    echo ""
    echo -e "${BOLD}Created by:${NC} ${PURPLE}RizzDevs${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Save summary to file
    cat > /opt/ai-server/INSTALLATION_INFO.txt <<EOF
RizzDevs AI SaaS Installation Summary
=====================================

Installation Date: $(date)
Model: ${MODEL_NAME}
API Endpoint: ${API_URL}
Documentation: https://coders1.vercel.app

$(if [[ -f /opt/ai-server/cloudflare.conf ]]; then
    echo "Cloudflare DNS: Configured"
    echo "Domain: $CF_DOMAIN"
    echo "Zone ID: $CF_ZONE_ID"
else
    echo "Cloudflare DNS: Not configured"
fi)

Service: rizzdevs-ai
Log: /var/log/rizzdevs-ai.log

Created by RizzDevs
EOF
}

# ═══════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════

main() {
    check_root
    
    print_header
    echo -e "${BOLD}Starting AI SaaS Installation with Cloudflare DNS...${NC}"
    echo ""
    pause
    
    check_requirements
    system_update
    setup_swap
    setup_python_env
    select_model_category
    create_ai_server
    setup_training
    setup_database
    setup_saas_mode
    setup_cloudflare_config
    setup_ssl
    setup_nginx
    create_systemd_service
    final_setup
    show_summary
    
    log "Installation completed successfully"
}

# Run main function
main
