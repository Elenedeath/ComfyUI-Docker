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
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /opt/comfyui

# Clone ComfyUI Manager (entrypoint will symlink it into custom_nodes/)
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git \
    /opt/comfyui/custom_nodes/ComfyUI-Manager

# =============================================================================
# CRITICAL: pin NumPy <2.0 BEFORE everything else.
# cv2 4.9, insightface 0.7.3 and onnxruntime-gpu 1.18 are compiled against
# NumPy 1.x ABI — NumPy 2.x causes "_ARRAY_API not found" at import time.
# This layer must come before any other pip install.
# =============================================================================
# Global pip constraint: forbid NumPy 2.x everywhere
RUN echo "numpy<2.0" > /opt/constraints.txt
ENV PIP_CONSTRAINT=/opt/constraints.txt

RUN pip install --no-cache-dir "numpy==1.26.4"

# Pin PyTorch stack with --no-deps so pip cannot upgrade numpy as a side-effect
RUN pip install --no-deps --no-cache-dir \
    torch==2.6.0 torchvision==0.21.0 torchaudio==2.6.0 \
    --index-url https://download.pytorch.org/whl/cu124

# Utility / monitoring deps (Crystools etc.)
# pillow intentionally left unpinned so ComfyUI requirements can resolve it
RUN pip install --no-cache-dir \
    deepdiff==8.6.1 nvidia-ml-py py-cpuinfo piexif orderly-set pillow

# ComfyUI + ComfyUI-Manager Python requirements
RUN pip install --no-cache-dir \
    -r /opt/comfyui/requirements.txt \
    -r /opt/comfyui-manager/requirements.txt

# =============================================================================
# Reactor / InsightFace dependency stack — baked into the image so that
# container recreation never loses them (no more "No module named cv2").
# =============================================================================
RUN pip install --no-cache-dir \
    opencv-python==4.9.0.80 \
    insightface==0.7.3 \
    onnxruntime-gpu==1.18.0 \
    segment-anything \
    accelerate

RUN pip install --no-deps --no-cache-dir ultralytics
RUN pip install --no-cache-dir \
    matplotlib scipy pandas tqdm pyyaml requests psutil py-cpuinfo seaborn

RUN pip install --no-cache-dir --force-reinstall "opencv-python==4.9.0.80"
RUN pip install --no-cache-dir --force-reinstall "numpy==1.26.4"

RUN pip uninstall -y pynvml 2>/dev/null || true

# Build-time smoke tests — fail the build early if something is broken
RUN python -c "import numpy; v=numpy.__version__; assert v.startswith('1.'), f'NumPy {v} >=2.0!'; print(v)"
RUN python -c "import cv2, insightface, onnxruntime; print('Reactor deps OK')"

# Run as non-root
USER $UID:$GID

WORKDIR /opt/comfyui
EXPOSE 8188

ADD entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]