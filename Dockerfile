# =============================================================================
# ComfyUI Docker — Elenedeath/ComfyUI-Docker
# Fixes: numpy<2.0 (Reactor ABI), g++ (insightface build), Reactor deps baked in
# =============================================================================

ARG PYTORCH_VERSION=2.6.0
ARG CUDA_VERSION=12.4
ARG CUDNN_VERSION=9

# Allow passing in your host UID/GID (defaults 1000:1000)
ARG UID=1000
ARG GID=1000

FROM pytorch/pytorch:${PYTORCH_VERSION}-cuda${CUDA_VERSION}-cudnn${CUDNN_VERSION}-runtime

ARG COMFYUI_VERSION=0.17.1
ARG COMFYUI_MANAGER_VERSION=4.0.5

# Installs Git + build tools (g++ required for insightface Cython build)
# + OpenCV system libs
RUN apt-get update --assume-yes && \
    apt-get install --assume-yes \
        git \
        sudo \
        gcc \
        g++ \
        build-essential \
        libgl1 \
        libglx-mesa0 \
        libglib2.0-0 \
        libgomp1 \
        dnsutils && \
    rm -rf /var/cache/apt/archives /var/lib/apt/lists/*

# Clone ComfyUI
RUN git clone https://github.com/Comfy-Org/ComfyUI.git /opt/comfyui && \
    cd /opt/comfyui && git checkout "v${COMFYUI_VERSION}"

# Clone ComfyUI Manager (entrypoint will symlink it into custom_nodes/)
RUN git clone https://github.com/Comfy-Org/ComfyUI-Manager.git /opt/comfyui-manager && \
    cd /opt/comfyui-manager && git checkout ${COMFYUI_MANAGER_VERSION}

# =============================================================================
# CRITICAL: pin NumPy <2.0 BEFORE everything else.
# cv2 4.9, insightface 0.7.3 and onnxruntime-gpu 1.18 are compiled against
# NumPy 1.x ABI — NumPy 2.x causes "_ARRAY_API not found" at import time.
# This layer must come before any other pip install.
# =============================================================================
RUN pip install --no-cache-dir "numpy<2.0"

# Pin PyTorch stack with --no-deps so pip cannot upgrade numpy as a side-effect
RUN pip install --no-deps --no-cache-dir \
    torch==2.6.0 torchvision==0.21.0 torchaudio==2.6.0 \
    --index-url https://download.pytorch.org/whl/cu124

# Utility / monitoring deps (Crystools etc.)
# pillow intentionally left unpinned so ComfyUI requirements can resolve it
RUN pip install --no-cache-dir \
    deepdiff==8.6.1 pynvml py-cpuinfo piexif orderly-set pillow

# ComfyUI + ComfyUI-Manager Python requirements
RUN pip install --no-cache-dir \
    --requirement /opt/comfyui/requirements.txt \
    --requirement /opt/comfyui-manager/requirements.txt

# =============================================================================
# Reactor / InsightFace dependency stack — baked into the image so that
# container recreation never loses them (no more "No module named cv2").
# =============================================================================
RUN pip install --no-cache-dir \
    opencv-python==4.9.0.80 \
    insightface==0.7.3 \
    onnxruntime-gpu==1.18.0 \
    ultralytics \
    segment-anything \
    accelerate

# Build-time smoke tests — fail the build early if something is broken
RUN python -c "import cv2, insightface, onnxruntime; print('Reactor deps OK')"
RUN python -c "\
import numpy; \
v = tuple(int(x) for x in numpy.__version__.split('.')[:2]); \
assert v < (2, 0), f'NumPy {numpy.__version__} is >=2.0 — ABI will break cv2/onnxruntime!'; \
print(f'NumPy {numpy.__version__} OK')"

# Run as non-root
USER $UID:$GID

WORKDIR /opt/comfyui
EXPOSE 8188

ADD entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]