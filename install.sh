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

# ====== 安装宝塔 7.7 ======
echo "🚀 安装宝塔面板 7.7..."
curl -sSO https://raw.githubusercontent.com/zhucaidan/btpanel-v7.7.0/main/install/install_panel.sh
bash install_panel.sh

sleep 30


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


