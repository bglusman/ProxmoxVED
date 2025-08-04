#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://storyteller.enjyn.com/

APP="Storyteller"
var_tags="${var_tags:-ai;text-to-speech;audiobook}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    if [[ ! -d /opt/storyteller ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    
    msg_info "Stopping ${APP} Service"
    systemctl stop storyteller
    msg_ok "Stopped ${APP} Service"

    msg_info "Backing up Current Installation"
    if [[ -d /opt/storyteller_backup ]]; then
        rm -rf /opt/storyteller_backup
    fi
    cp -r /opt/storyteller /opt/storyteller_backup
    msg_ok "Created Backup"

    cd /opt/storyteller
    msg_info "Updating ${APP}"
    $STD git fetch --all
    $STD git reset --hard origin/main
    $STD yarn install
    
    # Build SQLite extension
    cd /opt/storyteller/web
    $STD gcc -g -fPIC -rdynamic -shared sqlite/uuid.c -o sqlite/uuid.c.so
    
    # Build EPUB library and web app
    cd /opt/storyteller
    $STD yarn workspace @smoores/epub build:esm
    $STD yarn build:web
    
    # Copy necessary files as per Dockerfile structure
    cd /opt/storyteller/web/.next/standalone/web
    mkdir -p sqlite
    cp /opt/storyteller/web/sqlite/uuid.c.so ./sqlite/uuid.c.so 2>/dev/null || true
    cp /opt/storyteller/web/words.txt ./words.txt 2>/dev/null || true
    
    # Copy WASM files
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
    
    msg_ok "Updated ${APP}"

    msg_info "Starting ${APP} Service"
    systemctl enable -q --now storyteller
    msg_ok "Started ${APP} Service"
    
    msg_ok "Updated Successfully!"
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8001${CL}"