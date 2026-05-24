#!/usr/bin/env bash
# TradingAgents-Astock VPS 一键部署脚本
# 用法: bash scripts/vps_setup.sh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENV_DIR="$PROJECT_DIR/.venv"
STREAMLIT_PORT="${STREAMLIT_PORT:-8501}"

echo "============================================"
echo " TradingAgents-Astock VPS 部署"
echo "============================================"
echo ""

# ── 1. 安装系统依赖 ──────────────────────────────────────────────
echo "[1/7] 安装系统依赖（中文字体）..."
if command -v apt &>/dev/null; then
    sudo apt update -qq && sudo apt install -y -qq fonts-wqy-microhei 2>/dev/null && echo "   ✓ fonts-wqy-microhei 已安装" || echo "   - 字体包安装失败（不影响运行，PDF 可能缺中文）"
elif command -v yum &>/dev/null; then
    sudo yum install -y wqy-microhei-fonts 2>/dev/null && echo "   ✓ wqy-microhei-fonts 已安装" || echo "   - 字体包安装失败"
elif command -v dnf &>/dev/null; then
    sudo dnf install -y wqy-microhei-fonts 2>/dev/null && echo "   ✓ wqy-microhei-fonts 已安装" || echo "   - 字体包安装失败"
else
    echo "   - 未检测到包管理器，跳过（PDF 可能缺中文）"
fi

# ── 2. 检查 Python 版本 ──────────────────────────────────────────
echo "[2/7] 检查 Python 版本..."
PYTHON_VERSION="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
python3 -c "import sys; assert sys.version_info >= (3, 10), 'Python 3.10+ required'" 2>/dev/null || {
    echo "❌ 需要 Python 3.10+，当前版本: $(python3 --version 2>&1)"
    echo "   安装方法: apt install python3.12 python3.12-venv  (Ubuntu/Debian)"
    echo "   或:       yum install python3.12                    (CentOS/RHEL)"
    exit 1
}
echo "   ✓ $(python3 --version)"

# ── 2. 创建虚拟环境 ──────────────────────────────────────────────
echo "[3/7] 创建虚拟环境..."
if [ -f "$VENV_DIR/bin/activate" ]; then
    echo "   ✓ 虚拟环境已存在，跳过"
else
    # Clean up leftover broken venv from a previous failed run
    rm -rf "$VENV_DIR"
    # ensurepip is not always available on minimal VPS installs
    if ! python3 -c "import ensurepip" 2>/dev/null; then
        echo "   - 缺少 python3-venv，尝试安装..."
        if command -v apt &>/dev/null; then
            sudo apt update -qq && sudo apt install -y -qq "python${PYTHON_VERSION}-venv"
        elif command -v yum &>/dev/null; then
            sudo yum install -y "python${PYTHON_VERSION}-venv"
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y "python${PYTHON_VERSION}-venv"
        else
            echo "❌ 无法自动安装 python3-venv，请手动执行:"
            echo "   apt install python${PYTHON_VERSION}-venv"
            exit 1
        fi
        echo "   ✓ python${PYTHON_VERSION}-venv 已安装"
    fi
    python3 -m venv "$VENV_DIR"
    echo "   ✓ 虚拟环境已创建"
fi
source "$VENV_DIR/bin/activate"

# ── 3. 安装依赖 ──────────────────────────────────────────────────
echo "[4/7] 安装 Python 依赖..."
pip install --upgrade pip -q
pip install -r "$PROJECT_DIR/requirements.txt" -q
echo "   ✓ 依赖安装完成"

# ── 4. 配置环境变量 ──────────────────────────────────────────────
echo "[5/7] 配置 .env..."
if [ ! -f "$PROJECT_DIR/.env" ]; then
    if [ -f "$PROJECT_DIR/.env.example" ]; then
        cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
        echo "   ✓ 已从 .env.example 创建 .env"
    else
        touch "$PROJECT_DIR/.env"
        echo "   ✓ 已创建空 .env"
    fi
    echo ""
    echo "   ⚠️  重要: 请编辑 .env 填入 API Key 后再启动"
    echo "   编辑命令: nano $PROJECT_DIR/.env"
    echo ""
else
    echo "   ✓ .env 已存在，跳过"
fi

# ── 5. 安装 systemd 服务（可选）──────────────────────────────────
SERVICE_FILE="/etc/systemd/system/tradingagents.service"
echo "[6/7] systemd 服务..."
if [ -f "$SERVICE_FILE" ]; then
    echo "   ✓ 服务文件已存在，跳过"
elif command -v systemctl &>/dev/null; then
    read -r -p "   是否安装 systemd 服务（开机自启）？[Y/n] " REPLY
    REPLY="${REPLY:-y}"
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        sudo tee "$SERVICE_FILE" > /dev/null << SERVICEEOF
[Unit]
Description=TradingAgents-Astock Web UI
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$PROJECT_DIR
EnvironmentFile=$PROJECT_DIR/.env
Environment="STREAMLIT_SERVER_PORT=$STREAMLIT_PORT"
Environment="STREAMLIT_SERVER_HEADLESS=true"
Environment="STREAMLIT_SERVER_ENABLE_CORS=false"
Environment="STREAMLIT_BROWSER_GATHER_USAGE_STATS=false"
ExecStart=$VENV_DIR/bin/streamlit run web/app.py --server.port $STREAMLIT_PORT
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICEEOF
        sudo systemctl daemon-reload
        echo "   ✓ systemd 服务已安装"
        echo ""
        echo "   管理命令:"
        echo "     sudo systemctl start tradingagents     # 启动"
        echo "     sudo systemctl stop tradingagents      # 停止"
        echo "     sudo systemctl status tradingagents    # 状态"
        echo "     sudo systemctl enable tradingagents    # 开机自启"
        echo "     sudo journalctl -u tradingagents -f    # 查看日志"
    else
        echo "   - 跳过 systemd 服务"
    fi
else
    echo "   - 未检测到 systemd，跳过"
fi

# ── 6. 完成 ──────────────────────────────────────────────────────
echo "[7/7] 部署完成!"
echo ""
echo "============================================"
echo " 启动方式"
echo "============================================"
echo ""
echo "前台运行（调试用）:"
echo "  cd $PROJECT_DIR"
echo "  source .venv/bin/activate"
echo "  streamlit run web/app.py --server.port $STREAMLIT_PORT"
echo ""
echo "后台运行（nohup）:"
echo "  cd $PROJECT_DIR"
echo "  source .venv/bin/activate"
echo "  nohup streamlit run web/app.py --server.port $STREAMLIT_PORT --server.headless true > /tmp/tradingagents.log 2>&1 &"
echo ""
if [ -f "$SERVICE_FILE" ]; then
    echo "systemd 服务:"
    echo "  sudo systemctl start tradingagents"
    echo ""
fi
echo "访问地址: http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'YOUR_VPS_IP'):$STREAMLIT_PORT"
echo ""
echo "⚠️  安全提示:"
echo "  如对外暴露端口，建议配置防火墙 (ufw / firewalld)"
echo "  或通过 Nginx 反向代理 + HTTPS 访问"
echo "============================================"
