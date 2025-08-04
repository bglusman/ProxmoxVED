#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://storyteller.enjyn.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
    curl \
    sudo \
    mc \
    git \
    ca-certificates \
    build-essential \
    cmake \
    software-properties-common \
    sqlite3 \
    libsqlite3-dev \
    argon2 \
    wget \
    libelf1 \
    libnuma-dev \
    kmod \
    file \
    python3 \
    python3-pip \
    gcc \
    g++
msg_ok "Installed Dependencies"

msg_info "Installing FFmpeg"
$STD apt-get install -y ffmpeg
msg_ok "Installed FFmpeg"

msg_info "Setting Up Hardware Acceleration (GPU Support)"
$STD apt-get -y install va-driver-all ocl-icd-libopencl1 intel-opencl-icd vainfo intel-gpu-tools
if [[ "$CTTYPE" == "0" ]]; then
  chgrp video /dev/dri
  chmod 755 /dev/dri
  chmod 660 /dev/dri/*
  $STD adduser $(id -u -n) video
  $STD adduser $(id -u -n) render
fi
msg_ok "Set Up Hardware Acceleration"

NODE_VERSION="22" NODE_MODULE="yarn@latest" setup_nodejs

msg_info "Cloning Storyteller Repository"
cd /opt
$STD git clone https://gitlab.com/storyteller-platform/storyteller.git
cd /opt/storyteller
msg_ok "Cloned Storyteller Repository"

msg_info "Downloading Word List"
$STD wget https://raw.githubusercontent.com/dwyl/english-words/master/words.txt -O /opt/storyteller/web/words.txt
msg_ok "Downloaded Word List"

msg_info "Installing Dependencies"
$STD yarn install
msg_ok "Installed Dependencies"

msg_info "Building SQLite Extension"
cd /opt/storyteller/web
$STD gcc -g -fPIC -rdynamic -shared sqlite/uuid.c -o sqlite/uuid.c.so
msg_ok "Built SQLite Extension"

msg_info "Building EPUB Library"
cd /opt/storyteller
$STD yarn workspace @smoores/epub build:esm
msg_ok "Built EPUB Library"

msg_info "Building Web Application"
$STD yarn build:web

# Copy necessary files as per Dockerfile structure
cd /opt/storyteller/web/.next/standalone/web
mkdir -p sqlite
cp /opt/storyteller/web/sqlite/uuid.c.so ./sqlite/uuid.c.so 2>/dev/null || true
cp /opt/storyteller/web/words.txt ./words.txt 2>/dev/null || true

# Copy WASM files that aren't statically imported
mkdir -p work-dist
find /opt/storyteller/node_modules/@echogarden/speex-resampler-wasm/wasm/ -name "*.wasm" -exec cp {} ./work-dist/ \; 2>/dev/null || true
cp /opt/storyteller/node_modules/@echogarden/pffft-wasm/dist/simd/pffft.wasm ./work-dist/ 2>/dev/null || true
cp /opt/storyteller/node_modules/tiktoken/lite/tiktoken_bg.wasm ./work-dist/ 2>/dev/null || true
cp /opt/storyteller/node_modules/@echogarden/espeak-ng-emscripten/espeak-ng.data ./work-dist/ 2>/dev/null || true

# Copy echogarden files
mkdir -p /opt/storyteller/web/.next/standalone/data
mkdir -p /opt/storyteller/web/.next/standalone/dist
if [ -d "/opt/storyteller/node_modules/echogarden/data" ]; then
  cp -r /opt/storyteller/node_modules/echogarden/data/* /opt/storyteller/web/.next/standalone/data/ 2>/dev/null || true
fi
if [ -d "/opt/storyteller/node_modules/echogarden/dist" ]; then
  cp -r /opt/storyteller/node_modules/echogarden/dist/* /opt/storyteller/web/.next/standalone/dist/ 2>/dev/null || true
fi

# Copy SQL migrations
cp -r /opt/storyteller/web/migrations /opt/storyteller/web/.next/standalone/web/migrations

msg_ok "Built Web Application"

msg_info "Creating Data Directory"
mkdir -p /opt/storyteller/data
msg_ok "Created Data Directory"

msg_info "Creating Environment File"
cat <<EOF >/opt/storyteller/web/.next/standalone/web/.env
STORYTELLER_DATA_DIR=/opt/storyteller/data
PORT=8001
HOSTNAME=0.0.0.0
NODE_ENV=production
NEXT_TELEMETRY_DISABLED=1
STORYTELLER_WORKER=worker.cjs
SQLITE_NATIVE_BINDING=/opt/storyteller/web/.next/standalone/node_modules/better-sqlite3/build/Release/better_sqlite3.node
NVIDIA_VISIBLE_DEVICES=all
NVIDIA_DRIVER_CAPABILITIES=compute,utility
EOF
msg_ok "Created Environment File"

msg_info "Creating Service"
service_path="/etc/systemd/system/storyteller.service"
cat <<EOF >$service_path
[Unit]
Description=Storyteller - AI Text-to-Speech Platform
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=5
User=root
WorkingDirectory=/opt/storyteller/web/.next/standalone/web
Environment=STORYTELLER_DATA_DIR=/opt/storyteller/data
Environment=PORT=8001
Environment=HOSTNAME=0.0.0.0
Environment=NODE_ENV=production
Environment=NEXT_TELEMETRY_DISABLED=1
Environment=STORYTELLER_WORKER=worker.cjs
Environment=SQLITE_NATIVE_BINDING=/opt/storyteller/web/.next/standalone/node_modules/better-sqlite3/build/Release/better_sqlite3.node
Environment=NVIDIA_VISIBLE_DEVICES=all
Environment=NVIDIA_DRIVER_CAPABILITIES=compute,utility
ExecStart=/usr/bin/node --enable-source-maps server.js
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

$STD systemctl enable --now storyteller
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"