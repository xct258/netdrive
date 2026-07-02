#!/bin/bash

# ============================================================
# 服务启动脚本
# 功能：启动 OpenList 和 FileBrowser 服务
#       每个服务都以后台进程方式运行（nohup）
# ============================================================

# 工作目录（宿主机挂载目录）
DRIVE_DIR=/rec

# 启动脚本存放目录（初始化组件时下载到 /usr/local/bin/）
DRIVE_START_SH_DIR=/usr/local/bin

# 引入日志文件
source ${DRIVE_START_SH_DIR}/log.sh
# 设置日志相关参数
LOG_BASE_DIR=${DRIVE_DIR}/log  # 日志存放路径
LOG_APP_NAME="服务启动日志"  # 日志应用名称

# --------------------------------------------------
# 启动 OpenList 服务
# OpenList 是一个文件列表服务，支持多存储源
# 官方启动方式：./openlist server
# 数据目录（含配置文件）存放在 /rec/openlist
# OpenList 默认监听端口：5244
# --------------------------------------------------
start_openlist() {
    local binary="/app/openlist/openlist"

    if [ ! -f "$binary" ]; then
        log warn "[OpenList] 未找到程序文件 ${binary}，跳过启动"
        return 1
    fi

    local data_dir="${DRIVE_DIR}/openlist/data"
    mkdir -p "$data_dir"

    local needs_init=false
    if [ -z "$(ls -A "$data_dir" 2>/dev/null)" ]; then
        needs_init=true
        log -f info "[OpenList] 检测到首次启动，正在生成随机密码..."
    else
        log info "[OpenList] 正在启动..."
    fi

    # 启动 OpenList 服务
    if [ "$needs_init" = true ]; then
        nohup "$binary" server --data "$data_dir" > /tmp/openlist_startup.log 2>&1 &
    else
        nohup "$binary" server --data "$data_dir" > /dev/null 2>&1 &
    fi

    # 等待进程启动
    local wait_seconds=10
    local pid=""
    local binary_name
    binary_name=$(basename "$binary")
    for ((i = 1; i <= wait_seconds; i++)); do
        pid=$(pidof "$binary_name" 2>/dev/null)
        if [ -n "$pid" ]; then
            break
        fi
        sleep 1
    done

    if [ -z "$pid" ]; then
        log error "[OpenList] 启动失败，未检测到运行中的进程"
        return 1
    fi

    # 首次启动：提取随机密码并输出到控制台
    if [ "$needs_init" = true ]; then
        sleep 2
        local ol_password
        ol_password=$(grep -i "password" /tmp/openlist_startup.log 2>/dev/null | head -1)
        if [ -n "$ol_password" ]; then
            log -f info "[OpenList] ${ol_password}"
            log -f info "[OpenList] 初始账号和密码见上方日志，请登录后修改密码"
        else
            log -f info "[OpenList] 未提取到密码，原始日志:"
            cat /tmp/openlist_startup.log >> "$LOG_FILE"
            log -f warn "[OpenList] 密码信息见上方日志，请查看 docker logs"
        fi
        rm -f /tmp/openlist_startup.log
    fi

    log info "[OpenList] 启动成功 (PID ${pid})"
    return 0
}

# --------------------------------------------------
# 启动 FileBrowser 服务
# FileBrowser 是一个网页文件管理器
# 监听 5470 端口，以 /mnt 为根目录（宿主机 /）
# 数据库文件存放在 /rec/filebrowser/filebrowser.db
# --------------------------------------------------
start_filebrowser() {
    local binary="/app/filebrowser/filebrowser"

    if [ ! -f "$binary" ]; then
        log warn "[FileBrowser] 未找到程序文件 ${binary}，跳过启动"
        return 1
    fi

    local db_dir="${DRIVE_DIR}/filebrowser"
    mkdir -p "$db_dir"

    local is_first_run=false
    if [ ! -f "${db_dir}/filebrowser.db" ]; then
        is_first_run=true
        log -f info "[FileBrowser] 检测到首次启动，正在生成随机密码..."
    fi

    # 启动 FileBrowser
    if [ "$is_first_run" = true ]; then
        nohup "$binary" \
            -a 0.0.0.0 \
            -p 5470 \
            -d "${db_dir}/filebrowser.db" \
            -r /mnt \
            > /tmp/filebrowser_startup.log 2>&1 &
    else
        nohup "$binary" \
            -a 0.0.0.0 \
            -p 5470 \
            -d "${db_dir}/filebrowser.db" \
            -r /mnt \
            > /dev/null 2>&1 &
    fi

    # 等待进程启动（先确认进程运行，再提取密码）
    local wait_seconds=10
    local fb_pid=""
    local fb_binary_name
    fb_binary_name=$(basename "$binary")
    for ((i = 1; i <= wait_seconds; i++)); do
        fb_pid=$(pidof "$fb_binary_name" 2>/dev/null)
        if [ -n "$fb_pid" ]; then
            break
        fi
        sleep 1
    done

    if [ -z "$fb_pid" ]; then
        log -f info "[FileBrowser] 启动失败，未检测到运行中的进程"
        return 1
    fi

    # 首次启动：确认进程运行后，再提取密码
    if [ "$is_first_run" = true ]; then
        sleep 2
        local fb_password
        fb_password=$(grep -i "password" /tmp/filebrowser_startup.log 2>/dev/null | head -1)
        if [ -n "$fb_password" ]; then
            log -f info "[FileBrowser] ${fb_password}"
            log -f info "[FileBrowser] 初始账号和密码见上方日志，请登录后修改密码"
        else
            log -f info "[FileBrowser] 未提取到密码，原始日志:"
            cat /tmp/filebrowser_startup.log >> "$LOG_FILE"
            log -f info "[FileBrowser] 密码信息见上方日志，请查看 docker logs"
        fi
        rm -f /tmp/filebrowser_startup.log
    fi

    log info "[FileBrowser] 启动成功 (PID ${fb_pid})"
    return 0
}

# --------------------------------------------------
# 主流程：根据参数启动指定服务
# 不带参数时启动所有服务
# --------------------------------------------------
ALL_OK=true

if [ $# -eq 0 ]; then
    start_openlist || ALL_OK=false
    start_filebrowser || ALL_OK=false
else
    for arg in "$@"; do
        case "$arg" in
            openlist)   start_openlist || ALL_OK=false ;;
            filebrowser) start_filebrowser || ALL_OK=false ;;
            *)          log warn "[start-services] 未知服务: ${arg}，跳过" ;;
        esac
    done
fi

# 输出启动结果汇总
if [ $# -eq 0 ]; then
    if [ "$ALL_OK" = true ]; then
        log info "所有服务已正常启动"
    else
        log error "部分服务启动失败，请检查日志文件"
    fi
fi
