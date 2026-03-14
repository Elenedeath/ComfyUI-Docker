#!/usr/bin/env bash

# ComfyUI Docker Startup File v1.0.2 by John Aldred
# http://www.johnaldred.com
# http://github.com/kaouthia

set -e

# === FIX DNS (anti-Quad9 timeout TrueNAS) ===
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf
echo "search localdomain" >> /etc/resolv.conf
echo "↳ DNS fixé: 8.8.8.8 + 1.1.1.1"

# DNS check
nslookup github.com 8.8.8.8 >/dev/null 2>&1 && echo "↳ DNS OK" || echo "↳ DNS FAIL"

# --- Force ComfyUI-Manager config (uv off, no file logging, safe DB) ---
# Make sure user dirs exist and are writable (handles Windows bind mounts)
mkdir -p /opt/comfyui/user/default /opt/comfyui/user/__manager
chown -R "$(id -u)":"$(id -g)" /opt/comfyui/user || true
chmod -R u+rwX /opt/comfyui/user || true

CFG_DIR="/opt/comfyui/user/__manager"
CFG_FILE="$CFG_DIR/config.ini"

DB_DIR="/opt/comfyui/user/default"
DB_PATH="${DB_DIR}/manager.db"
SQLITE_URL="sqlite:////${DB_PATH}"

mkdir -p "$CFG_DIR"

if [ ! -f "$CFG_FILE" ]; then
  echo "↳ Creating ComfyUI-Manager config.ini (uv OFF, no file logging, DB cache)"
  cat > "$CFG_FILE" <<EOF
[default]
use_uv = False
file_logging = False
db_mode = cache
database_url = ${SQLITE_URL}
security_level = weak
network_mode = public
always_lazy_install = False
bypass_ssl = True
EOF
fi

# --- Prepare custom nodes ---
CN_DIR=/opt/comfyui/custom_nodes
INIT_MARKER="$CN_DIR/.custom_nodes_initialized"

declare -A REPOS=(
  ["ComfyUI-Manager"]="https://github.com/Comfy-Org/ComfyUI-Manager.git"
  ["ComfyUI_essentials"]="https://github.com/cubiq/ComfyUI_essentials.git"
  ["ComfyUI-Crystools"]="https://github.com/crystian/ComfyUI-Crystools.git"
  ["rgthree-comfy"]="https://github.com/rgthree/rgthree-comfy.git"
  ["ComfyUI-KJNodes"]="https://github.com/kijai/ComfyUI-KJNodes.git"
  ["ComfyUI_UltimateSDUpscale"]="https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git"
)

if [ ! -f "$INIT_MARKER" ]; then
  echo "↳ First run: initializing custom_nodes…"
  mkdir -p "$CN_DIR"
  for name in "${!REPOS[@]}"; do
    url="${REPOS[$name]}"
    target="$CN_DIR/$name"
    if [ -d "$target" ]; then
      echo "  ↳ $name already exists, skipping clone"
    else
      echo "  ↳ Cloning $name"
      git clone --depth 1 "$url" "$target"
    fi
  done

  echo "↳ Installing/upgrading dependencies…"
  for dir in "$CN_DIR"/*/; do
    req="$dir/requirements.txt"
    if [ -f "$req" ]; then
      echo "  ↳ pip install --break-system-packages --no-deps -r $req"
      python -m pip install --break-system-packages --no-cache-dir --no-deps -r "$req"
    fi
  done

  # Create marker file
  touch "$INIT_MARKER"
else
  echo "↳ Custom nodes already initialized, skipping clone and dependency installation."
fi

echo "↳ Launching ComfyUI"
exec python main.py --listen 0.0.0.0