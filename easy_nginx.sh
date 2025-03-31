#!/bin/bash

# 检查是否以 root 用户运行
if [ "$(id -u)" -ne 0 ]; then
  echo "请以 root 用户运行此脚本。"
  exit 1
fi

# 安装 Nginx
install_nginx() {
  echo "正在安装 Nginx..."
  apt update && apt install -y nginx
  if [ $? -eq 0 ]; then
    echo "Nginx 安装完成！"
  else
    echo "Nginx 安装失败，请检查日志。"
    exit 1
  fi
}

# 配置反向代理
add_proxy() {
  read -p "请输入域名： " domain
  read -p "请输入反向代理的目标端口： " target_port
  
  config_file="/etc/nginx/sites-available/$domain"
  echo "正在添加反向代理配置..."

  cat > "$config_file" <<EOL
server {
    listen 80;
    server_name $domain;

    location / {
        proxy_pass http://127.0.0.1:$target_port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL

  ln -s "$config_file" "/etc/nginx/sites-enabled/"
  systemctl reload nginx

  echo "反向代理 $domain -> http://127.0.0.1:$target_port 配置完成！"
}

# 删除反向代理配置
delete_proxy() {
  read -p "请输入要删除的域名： " domain
  config_file="/etc/nginx/sites-available/$domain"

  if [ -f "$config_file" ]; then
    rm "$config_file"
    rm "/etc/nginx/sites-enabled/$domain"
    systemctl reload nginx
    echo "$domain 配置已删除！"
  else
    echo "未找到配置文件：$domain"
  fi
}

# 查看所有反向代理配置
list_proxies() {
  echo "当前所有反向代理配置："
  ls /etc/nginx/sites-available
}

# 检查 Nginx 是否正在运行
nginx_status() {
  systemctl is-active --quiet nginx
  if [ $? -eq 0 ]; then
    echo -e "\033[32mNginx 正在运行。\033[0m"  # Green color for running
  else
    echo -e "\033[31mNginx 未运行。\033[0m"  # Red color for not running
  fi
}

# 重启 Nginx
restart_nginx() {
  echo "正在重启 Nginx..."
  systemctl restart nginx
  if [ $? -eq 0 ]; then
    echo "Nginx 重启成功！"
  else
    echo "Nginx 重启失败，请检查日志。"
  fi
}

# 修改反向代理配置
modify_proxy() {
  list_proxies
  read -p "请输入要修改的域名： " domain
  config_file="/etc/nginx/sites-available/$domain"

  if [ -f "$config_file" ]; then
    echo "当前配置如下："
    cat "$config_file"
    read -p "请输入新的反向代理目标端口： " target_port

    # 更新配置文件
    sed -i "s|proxy_pass http://127.0.0.1:.*|proxy_pass http://127.0.0.1:$target_port;|" "$config_file"

    # 重载 Nginx 配置
    systemctl reload nginx
    echo "$domain 的反向代理目标端口已更新为 $target_port。"
  else
    echo "未找到配置文件：$domain"
  fi
}

# 主菜单
while true; do
  # 显示 Nginx 状态
  nginx_status
  
  echo "========================================="
  echo "Nginx 反向代理管理脚本"
  echo "1. 安装 Nginx"
  echo "2. 添加反向代理"
  echo "3. 删除反向代理"
  echo "4. 查看所有反向代理配置"
  echo "5. 修改反向代理配置"
  echo "6. 重启 Nginx"
  echo "7. 退出"
  read -p "请选择操作： " choice
  
  case $choice in
    1)
      install_nginx
      ;;
    2)
      add_proxy
      ;;
    3)
      delete_proxy
      ;;
    4)
      list_proxies
      ;;
    5)
      modify_proxy
      ;;
    6)
      restart_nginx
      ;;
    7)
      echo "退出脚本"
      exit 0
      ;;
    *)
      echo "无效的选择，请重新选择。"
      ;;
  esac
done
