#!/usr/bin/env bash
# 宝塔 7.7 一键安装 + 优化 + 修复脚本
# 适配：Ubuntu / CentOS
# 作者：整合优化版

set -e

# ====== root 检查 ======
if [ "$(id -u)" != "0" ]; then
  echo "❌ 请使用 root 用户执行"
  exit 1
fi

# ====== 系统识别 ======
OS=""
if grep -qi ubuntu /etc/os-release; then
  OS="ubuntu"
elif grep -qi debian /etc/os-release; then
  OS="debian"
elif grep -qi centos /etc/os-release; then
  OS="centos"
else
  echo "❌ 不支持的系统"
  exit 1
fi

echo "✅ 系统识别：$OS"

# ====== 基础依赖 ======
echo "📦 安装基础依赖..."
if [ "$OS" = "centos" ]; then
  yum install -y wget curl unzip tar lsof socat nfs-utils
else
  apt update -y
  apt install -y wget curl unzip tar lsof socat nfs-common
fi

# ====== 检测宝塔是否已安装 ======
BT_DIR="/www/server/panel"
if [ -d "$BT_DIR" ]; then
  echo ""
  echo "⚠️  检测到系统已安装宝塔面板！"
  echo "📂 安装目录：$BT_DIR"
  echo ""
  read -p "是否重新安装？[y/N]： " reinstall_bt
  if [[ ! "$reinstall_bt" =~ ^[Yy]$ ]]; then
    echo "⏭️  跳过宝塔安装，直接执行优化和修复..."
    SKIP_BT_INSTALL=true
  else
    echo "🔄 准备重新安装宝塔面板..."
    SKIP_BT_INSTALL=false
  fi
else
  SKIP_BT_INSTALL=false
fi

# ====== 安装宝塔 7.7 ======
if [ "$SKIP_BT_INSTALL" = false ]; then
  echo "🚀 安装宝塔面板 7.7..."
  curl -sSO https://raw.githubusercontent.com/zhucaidan/btpanel-v7.7.0/main/install/install_panel.sh
  bash install_panel.sh
  sleep 30
fi


# ====== 终端修复 ======
echo "🔧 修复SSH终端错误"
cp /www/server/panel/class/flask_sockets.py /www/server/panel/class/flask_sockets.py.bak
sed -i 's/self\.url_map\.add(Rule(rule, endpoint=f))/self.url_map.add(Rule(rule, endpoint=f, websocket=True))/g' /www/server/panel/class/flask_sockets.py 

# ====== 插件过期修复 ======
echo "🔧 修复插件到期限制..."
PLUGIN_JSON="/www/server/panel/data/plugin.json"
if [ -f "$PLUGIN_JSON" ]; then
  sed -i 's/"endtime":[ ]*-1/"endtime":999999999999/g' "$PLUGIN_JSON"
  chattr +i "$PLUGIN_JSON" || true
fi

# ====== 去绑定 / 去推荐 / 去弹窗 ======
echo "🧹 执行宝塔优化补丁..."
wget -O /root/bt_optimize.sh http://f.cccyun.cc/bt/optimize.sh
bash /root/bt_optimize.sh || true

# ====== Flask websocket/send_file 错误修复 ======
echo "🩹 修复 Flask websocket / send_file 报错..."
FLASK_FILE="/www/server/panel/class/flask_sockets.py"
if [ -f "$FLASK_FILE" ]; then
  cp $FLASK_FILE ${FLASK_FILE}.bak
  sed -i 's/self\.url_map\.add(Rule(rule, endpoint=f))/self.url_map.add(Rule(rule, endpoint=f, websocket=True))/g' $FLASK_FILE
fi

# ====== SSL 证书申请错误修复 ======
echo "🔐 修复 SSL 证书申请错误..."
ACME_FILE="/www/server/panel/class/acme_v2.py"
if [ -f "$ACME_FILE" ]; then
  cp $ACME_FILE ${ACME_FILE}.bak
  sed -i 's/X509Req\.set_version(2)/X509Req.set_version(0)/g' $ACME_FILE
fi



# ====== 修改宝塔端口为 8181 ======
echo "🔧 修改宝塔面板端口为 8181..."
PORT_FILE="/www/server/panel/data/port.pl"
if [ -f "$PORT_FILE" ]; then
  echo "8181" > "$PORT_FILE"
  # 更新防火墙规则
  if [ "$OS" = "centos" ]; then
    firewall-cmd --permanent --add-port=8181/tcp 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
  else
    ufw allow 8181/tcp 2>/dev/null || true
  fi
  echo "✅ 端口已修改为 8181"
else
  echo "⚠️  未找到端口配置文件，可能需要手动修改"
fi

# ====== 重启宝塔 ======
echo "🔄 重启宝塔面板..."
bt restart


# ====== 完成 ======
IP=$(curl -s ifconfig.me || echo "服务器IP")
echo ""
echo "🎉 宝塔 7.7 安装 + 优化 + 修复完成"
echo "👉 面板访问地址：http://${IP}:8181"
echo "👉 查看账号密码：bt default"
echo ""

# ====== Docker 安装询问 ======
echo ""
echo "🐳 是否安装 Docker?"
read -p "请输入 [yes/no]： " install_docker

if [[ "$install_docker" =~ ^[Yy][Ee][Ss]$ ]]; then
  echo "📦 开始安装 Docker..."
  if [ "$OS" = "centos" ]; then
    # CentOS 安装 Docker
    yum install -y yum-utils device-mapper-persistent-data lvm2
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum install -y docker-ce docker-ce-cli containerd.io
  else
    # Ubuntu/Debian 安装 Docker
    apt install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    apt update -y
    apt install -y docker-ce docker-ce-cli containerd.io
  fi

  # 启动 Docker
  systemctl start docker
  systemctl enable docker

  # 安装 Docker Compose
  echo "📦 安装 Docker Compose..."
  curl -L "https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose

  echo "✅ Docker 安装完成"
  docker --version
  docker-compose --version
else
  echo "⏭️  跳过 Docker 安装"
fi

# ====== 修改面板标题为主机名 ======
echo ""
echo "🏷️  是否将面板标题修改为主机名?"
read -p "请输入 [yes/no]： " change_title
if [[ "$change_title" =~ ^[Yy][Ee][Ss]$ ]]; then
  echo "🔧 修改面板标题为主机名..."
  HOSTNAME=$(hostname)
  TITLE_FILE="/www/server/panel/class/public.py"
  if [ -f "$TITLE_FILE" ]; then
    sed -i 's/G-title.*=.*"宝塔Linux面板"/G_title = "\u6211\u7684\u670d\u52a1\u5668 - '$HOSTNAME'"/g' "$TITLE_FILE" 2>/dev/null || true
    echo "✅ 面板标题已修改为: $HOSTNAME"
  fi
else
  echo "⏭️  跳过标题修改"
fi

# ====== 安全加固建议 ======
echo ""
echo "🔒 安全建议："
echo "1️⃣  修改默认端口（当前：8181）"
echo "2️⃣  修改默认密码"
echo "3️⃣  绑定域名访问"
echo "4️⃣  启用二次验证"
echo ""
echo "💡 使用以下命令管理面板："
echo "   bt default           # 查看默认信息"
echo "   bt 14                # 修改面板端口"
echo "   bt 5                 # 修改面板密码"
echo "   bt 6                 # 绑定域名"
echo ""

# ====== 系统优化建议 ======
echo "⚡ 系统优化建议："
echo "1️⃣  配置 SSH 密钥登录（更安全）"
echo "2️⃣  禁用 root 远程登录（可选）"
echo "3️⃣  配置防火墙规则"
echo "4️⃣  定期备份数据"
echo ""
echo "📚 常用命令："
echo "   systemctl restart bt  # 重启面板"
echo "   bt stop              # 停止面板"
echo "   bt start             # 启动面板"
echo "   bt restart           # 重启面板"
echo ""

