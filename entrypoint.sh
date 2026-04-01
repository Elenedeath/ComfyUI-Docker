#!/usr/bin/env bash
set -e

# === Fix DNS (anti-Quad9 timeout TrueNAS) ===
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf
nslookup github.com 8.8.8.8 >/dev/null 2>&1 && echo "DNS OK" || echo "DNS FAIL"

# === ComfyUI-Manager config ===
mkdir -p /opt/comfyui/user/__manager /opt/comfyui/user/default
CFG="/opt/comfyui/user/__manager/config.ini"
if [ ! -f "$CFG" ]; then
  cat > "$CFG" <<EOINI
[default]
use_uv = False
file_logging = False
db_mode = cache
security_level = weak
network_mode = public
always_lazy_install = False
bypass_ssl = True
EOINI
  echo "config.ini created"
fi

# === Initialize custom_nodes (first run only) ===
CN_DIR=/opt/comfyui/custom_nodes
INIT_MARKER="$CN_DIR/.initialized"

declare -A REPOS=(
  ["ComfyUI-Manager"]="https://github.com/Comfy-Org/ComfyUI-Manager.git"
  ["rgthree-comfy"]="https://github.com/rgthree/rgthree-comfy.git"
  ["ComfyUI-Crystools"]="https://github.com/crystian/ComfyUI-Crystools.git"
  ["ComfyUI_UltimateSDUpscale"]="https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git"
  ["ComfyUI_essentials"]="https://github.com/cubiq/ComfyUI_essentials.git"
  ["ComfyUI-MultiGPU"]="https://github.com/pollockjj/ComfyUI-MultiGPU.git"
  ["comfyui-tooling-nodes"]="https://github.com/Acly/comfyui-tooling-nodes.git"
  ["ComfyUI-LLM-Session"]="https://github.com/kantan-kanto/ComfyUI-LLM-Session.git"
  ["ComfyUI-KJNodes"]="https://github.com/kijai/ComfyUI-KJNodes.git"
  ["comfyui-reactor"]="https://github.com/Gourieff/comfyui-reactor.git"
  ["ComfyUI_IPAdapter_plus"]="https://github.com/cubiq/ComfyUI_IPAdapter_plus.git"
  ["ComfyUI Impact Pack"]="https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
  ["ComfyUI Impact Subpack"]="https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git"
)

if [ ! -f "$INIT_MARKER" ]; then
  echo "First run: cloning custom_nodes..."
  mkdir -p "$CN_DIR"
  for name in "${!REPOS[@]}"; do
    url="${REPOS[$name]}"
    target="$CN_DIR/$name"
    if [ ! -d "$target" ]; then
      echo "  Cloning $name"
      git clone --depth 1 "$url" "$target" || echo "  WARN: failed to clone $name"
    fi
  done

  echo "Installing custom_node requirements..."
  for dir in "$CN_DIR"/*/; do
    req="$dir/requirements.txt"
    if [ -f "$req" ]; then
      echo "  pip install -r $req"
      pip install --no-cache-dir -r "$req" || true
    fi
  done

  touch "$INIT_MARKER"
  echo "Initialization complete."
else
  echo "Custom nodes already initialized."
fi

echo "Launching ComfyUI..."
exec python main.py --listen 0.0.0.0