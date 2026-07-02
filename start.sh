#!/bin/bash

DRIVE_DIR=/rec
DRIVE_START_SH_DIR=/usr/local/bin

source ${DRIVE_START_SH_DIR}/log.sh
LOG_BASE_DIR=${DRIVE_DIR}/log
LOG_APP_NAME="容器主脚本"

UPDATE_INTERVAL=$((15 * 24 * 60 * 60))
# --------------------------------------------------
# 信号处理：优雅关闭子进程
# --------------------------------------------------
cleanup() {
    log info "收到停止信号，正在关闭服务..."
    pkill -f "^/app/openlist/openlist" 2>/dev/null
    pkill -f "^/app/filebrowser/filebrowser" 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT SIGQUIT

# --------------------------------------------------
# Token 管理：统一使用 GITHUB_TOKEN
# 1. 从环境变量读取并持久化
# 2. 导出到环境供子进程（check-update.sh）使用
# --------------------------------------------------
TOKEN_FILE="${DRIVE_START_SH_DIR}/.github_token"
if [ -n "$GITHUB_TOKEN" ]; then
  echo "$GITHUB_TOKEN" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
elif [ -f "$TOKEN_FILE" ]; then
  GITHUB_TOKEN=$(cat "$TOKEN_FILE")
fi
export GITHUB_TOKEN

# --------------------------------------------------
# 初始化工作目录
# --------------------------------------------------
mkdir -p ${DRIVE_DIR}/openlist ${DRIVE_DIR}/filebrowser ${DRIVE_DIR}/rclone

# --------------------------------------------------
# 初始化版本信息
# --------------------------------------------------
if [ -f /app/version.txt ] && [ ! -f ${DRIVE_DIR}/version.txt ]; then
    cp /app/version.txt ${DRIVE_DIR}/version.txt
    log info "已从构建镜像初始化版本信息"
fi

# --------------------------------------------------
# 下载 rclone 配置文件
# --------------------------------------------------
RCLONE_CONF_URL="https://raw.githubusercontent.com/xct258/Documentation/main/rclone/rclone.conf"

if [ -f ${DRIVE_DIR}/rclone/rclone.conf ]; then
    log info "rclone 配置文件已存在"
else
    if [ -n "$GITHUB_TOKEN" ]; then
        log info "正在从私有仓库下载 rclone 配置文件..."
        if curl -sf --retry 3 --retry-delay 5 \
            -H "Authorization: Bearer ${GITHUB_TOKEN}" \
            "$RCLONE_CONF_URL" -o ${DRIVE_DIR}/rclone/rclone.conf; then
            log success "rclone 配置文件下载成功"
            local now; now=$(date '+%Y-%m-%d %H:%M:%S')
            if grep -q "^UPDATED_RCLONE_CONFIG=" "${DRIVE_DIR}/version.txt" 2>/dev/null; then
                sed -i "s|^UPDATED_RCLONE_CONFIG=.*|UPDATED_RCLONE_CONFIG=${now}|" "${DRIVE_DIR}/version.txt"
            else
                echo "UPDATED_RCLONE_CONFIG=${now}" >> "${DRIVE_DIR}/version.txt"
            fi
        else
            log error "rclone 配置文件下载失败，请检查 GITHUB_TOKEN 是否有效"
        fi
    else
        log warn "GITHUB_TOKEN 未设置，跳过 rclone 配置文件下载"
    fi
fi

if [ -f ${DRIVE_DIR}/rclone/rclone.conf ]; then
    rm -f /root/.config/rclone/rclone.conf
    mkdir -p /root/.config/rclone
    ln -sf ${DRIVE_DIR}/rclone/rclone.conf /root/.config/rclone/rclone.conf
    log info "rclone 配置符号链接已就绪"
fi

log info "容器启动，检查组件更新..."
bash ${DRIVE_START_SH_DIR}/check-update.sh

log info "正在启动服务..."
bash ${DRIVE_START_SH_DIR}/start-services.sh

# --------------------------------------------------
# 定期（每 15 天）检查更新并热重启
# --------------------------------------------------
while true; do
    sleep ${UPDATE_INTERVAL}
    log_reset_session
    log info "正在定期检查更新..."

    bash ${DRIVE_START_SH_DIR}/check-update.sh
    rc=$?

    if [ $rc -eq 2 ]; then
        log info "有组件已更新，正在重启已更新的服务..."
        while IFS= read -r component; do
            case "$component" in
                OpenList)
                    log info "重启 OpenList..."
                    pkill -f "^/app/openlist/openlist" 2>/dev/null
                    sleep 2
                    bash ${DRIVE_START_SH_DIR}/start-services.sh openlist
                    log info "OpenList 已重启"
                    ;;
                FileBrowser)
                    log info "重启 FileBrowser..."
                    pkill -f "^/app/filebrowser/filebrowser" 2>/dev/null
                    sleep 2
                    bash ${DRIVE_START_SH_DIR}/start-services.sh filebrowser
                    log info "FileBrowser 已重启"
                    ;;
                Rclone)
                    log info "rclone 二进制已更新 (无需重启)"
                    ;;
                RcloneConfig)
                    log info "rclone 配置文件已更新 (无需重启)"
                    ;;
            esac
        done < /tmp/.updated_list
        rm -f /tmp/.updated_list
    fi
done
