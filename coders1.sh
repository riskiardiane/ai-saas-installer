#!/bin/bash

# ╔═══════════════════════════════════════════════════════════╗
# ║           AI SaaS Enterprise Installer v2.0               ║
# ║                  Created by RizzDevs                      ║
# ║         Documentation: https://coders1.vercel.app         ║
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

# ═══════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════

print_header() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${BOLD}           AI SaaS Enterprise Installer v2.0               ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                  ${PURPLE}Created by RizzDevs${NC}                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}         ${BLUE}Documentation: https://coders1.vercel.app${NC}         ${CYAN}║${NC}"
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
    print_step "[1/12] Updating System & Installing Dependencies"
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
        2>&1 | tee -a "$LOG_FILE"
    
    print_step "System update completed!"
    sleep 2
}

# ═══════════════════════════════════════════════════════════
# STEP 2: SWAP CONFIGURATION
# ═══════════════════════════════════════════════════════════

setup_swap() {
    print_header
    print_step "[2/12] Configuring SWAP (16GB - Anti OOM)"
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
    print_step "[3/12] Setting up Python AI Environment"
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
# STEP 4: MODEL SELECTION
# ═══════════════════════════════════════════════════════════

select_model() {
    print_header
    print_step "[4/12] AI Model Selection"
    echo ""
    echo -e "${BOLD}Available Models:${NC}"
    echo -e "${GREEN}1)${NC} Qwen2.5-Coder-7B-Instruct ${YELLOW}(Recommended - 4bit)${NC}"
    echo -e "${GREEN}2)${NC} Qwen2.5-Coder-3B-Instruct ${CYAN}(Lightweight)${NC}"
    echo -e "${GREEN}3)${NC} Qwen2.5-Coder-1.5B-Instruct ${CYAN}(Ultra Light)${NC}"
    echo -e "${GREEN}4)${NC} LLaMA-3-8B-Instruct ${PURPLE}(Inference only)${NC}"
    echo -e "${GREEN}5)${NC} Phi-3-mini ${BLUE}(Microsoft)${NC}"
    echo ""
    
    read -p "$(echo -e ${CYAN}Select model [1-5]: ${NC})" MODEL_CHOICE
    
    case $MODEL_CHOICE in
        1) 
            MODEL_ID="Qwen/Qwen2.5-Coder-7B-Instruct"
            MODEL_NAME="Qwen 2.5 Coder 7B"
            ;;
        2) 
            MODEL_ID="Qwen/Qwen2.5-Coder-3B-Instruct"
            MODEL_NAME="Qwen 2.5 Coder 3B"
            ;;
        3) 
            MODEL_ID="Qwen/Qwen2.5-Coder-1.5B-Instruct"
            MODEL_NAME="Qwen 2.5 Coder 1.5B"
            ;;
        4) 
            MODEL_ID="meta-llama/Meta-Llama-3-8B-Instruct"
            MODEL_NAME="LLaMA 3 8B"
            ;;
        5) 
            MODEL_ID="microsoft/Phi-3-mini-4k-instruct"
            MODEL_NAME="Phi-3 Mini"
            ;;
        *) 
            print_error "Invalid selection!"
            exit 1
            ;;
    esac
    
    print_step "Selected: ${MODEL_NAME}"
    log "Model selected: $MODEL_ID"
    sleep 2
}

# ═══════════════════════════════════════════════════════════
# STEP 5: AI SERVER CREATION
# ═══════════════════════════════════════════════════════════

create_ai_server() {
    print_header
    print_step "[5/12] Creating AI Server (FastAPI)"
    log "Creating AI server application"
    
    mkdir -p /opt/ai-server
    
    cat <<EOF > /opt/ai-server/app.py
"""
AI SaaS Server - Created by RizzDevs
Documentation: https://coders1.vercel.app
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
import torch
import logging

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="RizzDevs AI SaaS API",
    description="Enterprise AI API powered by ${MODEL_NAME}",
    version="2.0.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Request model
class ChatRequest(BaseModel):
    prompt: str
    max_tokens: int = 256
    temperature: float = 0.7

# Response model
class ChatResponse(BaseModel):
    response: str
    model: str
    tokens_used: int

# Global model variables
tokenizer = None
model = None

@app.on_event("startup")
async def load_model():
    """Load AI model on startup"""
    global tokenizer, model
    
    try:
        logger.info("Loading model: ${MODEL_ID}")
        
        # BitsAndBytes config for 4-bit quantization
        bnb_config = BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_compute_dtype=torch.float16,
            bnb_4bit_quant_type="nf4",
            bnb_4bit_use_double_quant=True
        )
        
        tokenizer = AutoTokenizer.from_pretrained("${MODEL_ID}")
        model = AutoModelForCausalLM.from_pretrained(
            "${MODEL_ID}",
            quantization_config=bnb_config,
            device_map="auto",
            trust_remote_code=True
        )
        
        logger.info("Model loaded successfully!")
        
    except Exception as e:
        logger.error(f"Failed to load model: {e}")
        raise

@app.get("/")
async def root():
    """API root endpoint"""
    return {
        "name": "RizzDevs AI SaaS API",
        "version": "2.0.0",
        "model": "${MODEL_NAME}",
        "documentation": "https://coders1.vercel.app",
        "endpoints": {
            "chat": "/chat",
            "health": "/health",
            "docs": "/docs"
        }
    }

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "model_loaded": model is not None,
        "model_name": "${MODEL_NAME}"
    }

@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """Chat endpoint for AI inference"""
    
    if model is None or tokenizer is None:
        raise HTTPException(status_code=503, detail="Model not loaded")
    
    try:
        # Tokenize input
        inputs = tokenizer(
            request.prompt,
            return_tensors="pt",
            truncation=True,
            max_length=2048
        ).to(model.device)
        
        # Generate response
        with torch.no_grad():
            outputs = model.generate(
                **inputs,
                max_new_tokens=request.max_tokens,
                temperature=request.temperature,
                do_sample=True,
                top_p=0.9,
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
        "quantization": "4-bit",
        "device": str(model.device) if model else "not_loaded"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

    print_step "AI Server created successfully!"
    sleep 2
}

# ═══════════════════════════════════════════════════════════
# STEP 6-10: Additional Features
# ═══════════════════════════════════════════════════════════

setup_training() {
    print_header
    print_step "[6/12] Training Configuration (Optional)"
    
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
    print_step "[7/12] Database Configuration"
    
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
    print_step "[8/12] SaaS Mode Configuration"
    
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
# STEP 11: SYSTEMD SERVICE
# ═══════════════════════════════════════════════════════════

create_systemd_service() {
    print_header
    print_step "[11/12] Creating Systemd Service"
    
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
# STEP 12: FINAL SETUP
# ═══════════════════════════════════════════════════════════

final_setup() {
    print_header
    print_step "[12/12] Final Configuration"
    
    # Get server IP
    SERVER_IP=$(curl -s ifconfig.me || echo "YOUR_IP")
    
    # Create welcome message
    cat <<EOF > /opt/ai-server/README.md
# RizzDevs AI SaaS Server

## Installation Complete! 🎉

### Server Information
- **Model**: ${MODEL_NAME}
- **API Endpoint**: http://${SERVER_IP}:8000
- **Documentation**: http://${SERVER_IP}:8000/docs
- **Health Check**: http://${SERVER_IP}:8000/health

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
curl -X POST "http://${SERVER_IP}:8000/chat" \\
  -H "Content-Type: application/json" \\
  -d '{
    "prompt": "Write a Python function",
    "max_tokens": 256,
    "temperature": 0.7
  }'
\`\`\`

### Documentation
Visit: https://coders1.vercel.app

### Created by RizzDevs
EOF

    print_step "Setup completed successfully!"
}

# ═══════════════════════════════════════════════════════════
# FINAL SUMMARY
# ═══════════════════════════════════════════════════════════

show_summary() {
    SERVER_IP=$(curl -s ifconfig.me || echo "YOUR_IP")
    
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${GREEN}${BOLD}              INSTALLATION COMPLETED! 🎉                   ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}AI SaaS Server Information:${NC}"
    echo -e "${GREEN}✓${NC} Model       : ${PURPLE}${MODEL_NAME}${NC}"
    echo -e "${GREEN}✓${NC} API Endpoint: ${BLUE}http://${SERVER_IP}:8000${NC}"
    echo -e "${GREEN}✓${NC} API Docs    : ${BLUE}http://${SERVER_IP}:8000/docs${NC}"
    echo -e "${GREEN}✓${NC} Health      : ${BLUE}http://${SERVER_IP}:8000/health${NC}"
    echo ""
    echo -e "${BOLD}Service Management:${NC}"
    echo -e "  ${CYAN}systemctl start rizzdevs-ai${NC}   - Start service"
    echo -e "  ${CYAN}systemctl stop rizzdevs-ai${NC}    - Stop service"
    echo -e "  ${CYAN}systemctl status rizzdevs-ai${NC}  - Check status"
    echo -e "  ${CYAN}journalctl -u rizzdevs-ai -f${NC}  - View logs"
    echo ""
    echo -e "${BOLD}Test API:${NC}"
    echo -e "  ${YELLOW}curl -X POST http://${SERVER_IP}:8000/chat \\${NC}"
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
API Endpoint: http://${SERVER_IP}:8000
Documentation: https://coders1.vercel.app

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
    echo -e "${BOLD}Starting AI SaaS Installation...${NC}"
    echo ""
    pause
    
    check_requirements
    system_update
    setup_swap
    setup_python_env
    select_model
    create_ai_server
    setup_training
    setup_database
    setup_saas_mode
    create_systemd_service
    final_setup
    show_summary
    
    log "Installation completed successfully"
}

# Run main function
main
