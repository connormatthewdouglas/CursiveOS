#!/usr/bin/env bash
# CursiveOS setup-intel-arc.sh
# One-shot setup: Intel compute runtime (OpenCL) + Level Zero + Ollama
# Enables Intel Arc GPU for AI inference on Bittensor mining rigs.
# Tested on: Linux Mint 22.3 / Ubuntu 24.04 (Noble), Intel Arc A750, kernel 6.17
# Usage: ./setup-intel-arc.sh

set -euo pipefail

if [[ -z "${TAO_SUDO_PASS:-}" ]]; then
    read -rsp "[CursiveOS] sudo password: " TAO_SUDO_PASS && echo
fi
SP="$TAO_SUDO_PASS"
export TAO_SUDO_PASS
s()  { echo "$SP" | sudo -S "$@" 2>/dev/null; }
sc() { echo "$SP" | sudo -S bash -c "$1"; }

log() { echo "[CursiveOS] $1"; }

log "Intel Arc GPU + Ollama setup"
log "========================================"

# ── 1. Intel GPU compute runtime ─────────────────────────────────────────────
log "Adding Intel GPU repository..."
sc 'wget -qO /tmp/intel-graphics.key https://repositories.intel.com/graphics/intel-graphics.key
gpg --keyserver keyserver.ubuntu.com --recv-keys 28DA432DAAC8BAEA 2>/dev/null
gpg --export 28DA432DAAC8BAEA > /usr/share/keyrings/intel-graphics.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/intel-graphics.gpg] https://repositories.intel.com/gpu/ubuntu noble client" > /etc/apt/sources.list.d/intel-graphics.list'

log "Updating package lists..."
s apt-get update -qq

log "Installing Intel compute runtime + Level Zero..."
# Upgrade libigdgmm12 first — Ubuntu ships an older version than Intel requires
s apt-get install -y --allow-downgrades libigdgmm12=22.5.2-1018~24.04
s apt-get install -y intel-opencl-icd intel-level-zero-gpu level-zero clinfo

log "Verifying OpenCL..."
if clinfo | grep -q "Arc"; then
    log "✓ Intel Arc detected via OpenCL: $(clinfo | grep 'Device Name' | grep -v platform | head -1 | awk -F: '{print $2}' | xargs)"
else
    log "WARNING: Arc not detected via clinfo — check driver install"
fi

# ── 2. User permissions ───────────────────────────────────────────────────────
log "Adding user to render + video groups (required for GPU compute)..."
sc "usermod -aG render,video $(logname) 2>/dev/null || usermod -aG render,video $SUDO_USER 2>/dev/null || true"
log "  Note: log out and back in for group changes to take effect"

# ── 3. Ollama ─────────────────────────────────────────────────────────────────
if command -v ollama &>/dev/null; then
    log "Ollama already installed: $(ollama --version)"
else
    log "Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh -o /tmp/ollama-install.sh
    sc 'sh /tmp/ollama-install.sh' 2>/dev/null
    log "✓ Ollama installed: $(ollama --version)"
fi

# ── 4. Configure ollama for Intel Arc (Vulkan backend) ───────────────────────
log "Configuring Ollama to use Intel Arc via Vulkan..."
sc 'mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/intel-arc.conf << EOF
[Service]
Environment="OLLAMA_VULKAN=1"
Environment="GGML_VK_VISIBLE_DEVICES=0"
EOF
systemctl daemon-reload
systemctl restart ollama'

sleep 3

# ── 5. Verify GPU inference ───────────────────────────────────────────────────
log "Verifying GPU inference (pulling tinyllama if needed)..."
if ollama list | grep -q "tinyllama"; then
    log "tinyllama already present"
else
    ollama pull tinyllama
fi

log "Running test inference..."
ollama run tinyllama "say: arc gpu working" --nowordwrap 2>/dev/null | grep -v "^\[" | grep -v "^$" | head -3 || true

PROCESSOR=$(ollama ps 2>/dev/null | grep tinyllama | awk '{print $4, $5}' || echo "unknown")
log "Inference processor: $PROCESSOR"

if echo "$PROCESSOR" | grep -qi "gpu"; then
    log "✓ Intel Arc A750 running inference on GPU"
else
    log "WARNING: Model not on GPU. Check: journalctl -u ollama | grep -i vulkan"
fi

log "========================================"
log "Setup complete."
log "Run inference: ollama run tinyllama 'your prompt'"
log "Check GPU:     ollama ps"
log "Monitor GPU:   intel_gpu_top"
