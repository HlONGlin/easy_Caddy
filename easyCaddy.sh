#!/usr/bin/env bash
# caddy_proxy_tool.sh
# 功能：
#   1) 自动安装/卸载 Caddy
#   2) 配置反向代理（支持多个反向代理，配置时只需输入上游服务端口）
#   3) 查看 Caddy 服务状态（在菜单界面显示）
#   4) 查看当前反向代理配置，并显示上游服务是否在运行
#   5) 删除指定的反向代理配置
#   6) 重启 Caddy 服务
#   7) 一键删除 Caddy（卸载并删除配置文件）
# 适用于 Debian/Ubuntu 系列系统

# Caddyfile 默认路径
CADDYFILE="/etc/caddy/Caddyfile"
CADDY_CONFIG_DIR="/etc/caddy"
BACKUP_CADDYFILE="${CADDYFILE}.bak"

# 反向代理配置存储
PROXY_CONFIG_FILE="/root/caddy_reverse_proxies.txt"

#--------------------------------------------
# 检查 Caddy 是否已安装
#--------------------------------------------
function check_caddy_installed() {
    if command -v caddy >/dev/null 2>&1; then
        return 0  # 已安装
    else
        return 1  # 未安装
    fi
}

#--------------------------------------------
# 安装 Caddy（官方仓库）
#--------------------------------------------
function install_caddy() {
    echo "开始安装 Caddy..."
    # 安装依赖
    sudo apt-get update
    sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl

    # 添加官方 GPG key
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
        | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg

    # 添加官方源
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
        | sudo tee /etc/apt/sources.list.d/caddy-stable.list

    # 更新并安装 Caddy
    sudo apt-get update
    sudo apt-get install -y caddy

    if check_caddy_installed; then
        echo "Caddy 安装成功！"
    else
        echo "Caddy 安装失败，请检查日志。"
        exit 1
    fi
}

#--------------------------------------------
# 检查指定端口服务是否在运行
#--------------------------------------------
function check_port_running() {
    local port=$1
    if timeout 1 bash -c "echo > /dev/tcp/127.0.0.1/$port" 2>/dev/null; then
        echo "运行中"
    else
        echo "未运行"
    fi
}

#--------------------------------------------
# 配置反向代理（只需输入上游服务端口，默认使用 http://127.0.0.1:端口）
#--------------------------------------------
function setup_reverse_proxy() {
    echo "请输入上游服务端口（例如 8080）："
    read port
    if [ -z "$port" ]; then
        echo "端口输入不能为空。"
        return
    fi
    # 自动构造上游地址
    upstream="http://127.0.0.1:${port}"

    # 检查 Caddyfile 是否备份过，没有则备份一下
    if [ ! -f "$BACKUP_CADDYFILE" ]; then
        sudo cp "$CADDYFILE" "$BACKUP_CADDYFILE"
    fi

    # 添加新的反向代理配置到 Caddyfile，使用通配符 * 表示所有域名
    echo "配置反向代理：* -> $upstream"
    echo "* {
    reverse_proxy $upstream
}" | sudo tee -a "$CADDYFILE" >/dev/null

    # 将配置信息保存到代理配置列表文件
    echo "* -> $upstream" >> "$PROXY_CONFIG_FILE"

    # 重启 Caddy 以应用配置
    echo "正在重启 Caddy 服务以应用新配置..."
    sudo systemctl restart caddy

    # 检查上游服务状态
    status=$(check_port_running "$port")
    echo "上游服务（127.0.0.1:${port}）状态：$status"
    echo "Caddy 服务状态："
    sudo systemctl status caddy --no-pager
}

#--------------------------------------------
# 查看 Caddy 服务状态
#--------------------------------------------
function show_caddy_status() {
    if check_caddy_installed; then
        echo "Caddy 服务状态："
        sudo systemctl status caddy --no-pager
    else
        echo "系统中未安装 Caddy。"
    fi
}

#--------------------------------------------
# 查看反向代理配置，并显示上游服务状态
#--------------------------------------------
function show_reverse_proxies() {
    if [ -f "$PROXY_CONFIG_FILE" ]; then
        echo "当前反向代理配置："
        lineno=0
        while IFS= read -r line; do
            lineno=$((lineno+1))
            # 从配置行中提取端口（假定格式为 "* -> http://127.0.0.1:端口"）
            port=$(echo "$line" | grep -oE '[0-9]{2,5}$')
            status=$(check_port_running "$port")
            echo "${lineno}) ${line} [上游服务状态：$status]"
        done < "$PROXY_CONFIG_FILE"
    else
        echo "没有配置任何反向代理。"
    fi
}

#--------------------------------------------
# 删除指定的反向代理
#--------------------------------------------
function delete_reverse_proxy() {
    show_reverse_proxies
    echo "请输入要删除的反向代理配置编号："
    read proxy_number
    if [ -z "$proxy_number" ]; then
        echo "无效的输入。"
        return
    fi

    # 删除对应行
    sed -i "${proxy_number}d" "$PROXY_CONFIG_FILE"

    # 重新生成 Caddyfile 配置（恢复为备份版本）
    echo "重新生成 Caddyfile 配置..."
    sudo cp "$BACKUP_CADDYFILE" "$CADDYFILE"

    # 根据代理配置列表重新添加剩余配置
    if [ -f "$PROXY_CONFIG_FILE" ]; then
        while IFS= read -r line; do
            # 将每行格式 "* -> http://127.0.0.1:端口" 转换成 Caddyfile 配置块
            upstream=$(echo "$line" | awk -F' -> ' '{print $2}')
            echo "* {
    reverse_proxy $upstream
}" | sudo tee -a "$CADDYFILE" >/dev/null
        done < "$PROXY_CONFIG_FILE"
    fi

    # 重启 Caddy 服务
    echo "重启 Caddy 服务..."
    sudo systemctl restart caddy
    echo "反向代理删除成功！"
}

#--------------------------------------------
# 重启 Caddy 服务
#--------------------------------------------
function restart_caddy() {
    echo "正在重启 Caddy 服务..."
    sudo systemctl restart caddy
    echo "Caddy 服务已重启。"
    sudo systemctl status caddy --no-pager
}

#--------------------------------------------
# 一键删除 Caddy（卸载并删除配置）
#--------------------------------------------
function remove_caddy() {
    echo "确定要卸载 Caddy 并删除配置文件吗？(y/n)"
    read confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # 停止并卸载
        sudo systemctl stop caddy
        sudo apt-get remove --purge -y caddy

        # 删除仓库源
        sudo rm -f /etc/apt/sources.list.d/caddy-stable.list
        sudo apt-get update

        # 删除配置文件
        if [ -f "$BACKUP_CADDYFILE" ]; then
            sudo rm -f "$CADDYFILE" "$BACKUP_CADDYFILE"
        else
            sudo rm -f "$CADDYFILE"
        fi

        # 删除反向代理配置文件
        if [ -f "$PROXY_CONFIG_FILE" ]; then
            sudo rm -f "$PROXY_CONFIG_FILE"
        fi

        echo "Caddy 已卸载并删除配置文件。"
    else
        echo "操作已取消。"
    fi
}

#--------------------------------------------
# 显示菜单（顶部显示 Caddy 运行状态）
#--------------------------------------------
function show_menu() {
    echo "============================================="
    # 显示 Caddy 运行状态
    caddy_status=$(systemctl is-active caddy 2>/dev/null)
    if [ "$caddy_status" == "active" ]; then
        echo "Caddy 状态：运行中"
    else
        echo "Caddy 状态：未运行"
    fi
    echo "           Caddy 一键部署 & 管理脚本          "
    echo "============================================="
    echo " 1) 安装 Caddy（如已安装则跳过）"
    echo " 2) 配置 & 启用反向代理（只需输入上游端口）"
    echo " 3) 查看 Caddy 服务状态"
    echo " 4) 查看当前反向代理配置（显示上游服务状态）"
    echo " 5) 删除指定的反向代理"
    echo " 6) 重启 Caddy 服务"
    echo " 7) 卸载 Caddy（删除配置）"
    echo " 0) 退出"
    echo "============================================="
}

#--------------------------------------------
# 主循环
#--------------------------------------------
while true; do
    show_menu
    read -p "请输入选项: " opt
    case "$opt" in
        1)
            if check_caddy_installed; then
                echo "Caddy 已安装，跳过安装。"
            else
                install_caddy
            fi
            ;;
        2)
            if ! check_caddy_installed; then
                echo "Caddy 未安装，先执行安装步骤。"
                install_caddy
            fi
            setup_reverse_proxy
            ;;
        3)
            show_caddy_status
            ;;
        4)
            show_reverse_proxies
            ;;
        5)
            delete_reverse_proxy
            ;;
        6)
            restart_caddy
            ;;
        7)
            remove_caddy
            ;;
        0)
            echo "退出脚本。"
            exit 0
            ;;
        *)
            echo "无效选项，请重新输入。"
            ;;
    esac
    echo
done
