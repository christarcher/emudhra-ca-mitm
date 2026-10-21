#!/usr/bin/env bash
# start.sh —— 启动 mitmweb（mitmproxy 三件套的 Web UI 版）
#   代理端口与 Web 观测界面都监听 0.0.0.0，方便在内网里从别的机器连。
#   端口默认 28080 / 28081，避开常见服务（8080/8081 等）。
#   默认关闭 block_global，允许外部客户端连接代理。
#
# 用法:
#   ./start.sh                       # 默认用 01-EM-OV-TLS-CA-G3C (d=4)
#   ./start.sh 06-EM-DV-TLS-CA-G3B   # 指定某张泄露CA
#   PROXY_PORT=28888 WEB_PORT=28081 ./start.sh
#   WEB_PASSWORD=mysecret ./start.sh # 自定义 Web UI 固定 token（见下）
#
# 关于 Web UI 的 token：
#   mitmproxy 11+ 默认给 mitmweb 加了鉴权，每次启动随机生成一个 token，
#   要去终端里抄很麻烦。这里用 --set web_password=<固定值> 把它钉死，
#   之后一直用同一个 token 即可。访问方式二选一：
#     1) 浏览器打开 http://<本机IP>:$WEB_PORT/?token=<WEB_PASSWORD> （首次登录后写 cookie，可长期免输）
#     2) 打开 http://<本机IP>:$WEB_PORT/ 后在弹窗里输入 <WEB_PASSWORD>
#   mitmproxy 10 及更早没有该鉴权，本脚本会自动跳过、无需 token。
#   注意：Web UI 绑到 0.0.0.0 后，全内网都能访问，唯一的防线就是这个 token，
#   请把默认值 emudhra 改成不易猜的（WEB_PASSWORD=... ）。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CA_DIR="${1:-01-EM-OV-TLS-CA-G3C}"
PROXY_PORT="${PROXY_PORT:-28080}"
WEB_PORT="${WEB_PORT:-28081}"
# 监听地址：默认 0.0.0.0 便于内网里从别的机器连。只想本机用就 WEB_HOST=127.0.0.1。
WEB_HOST="${WEB_HOST:-0.0.0.0}"
PROXY_HOST="${PROXY_HOST:-0.0.0.0}"
# 固定 token。留空（WEB_PASSWORD= ）则退回 mitmproxy 默认的随机 token。
WEB_PASSWORD="${WEB_PASSWORD:-emudhra}"

# 首次运行自动创建 venv 并安装 requirements.txt 里锁定版本的 mitmproxy，
# 之后直接复用 .venv（已在 .gitignore 中）。这样拉下仓库即可用，无需手动装依赖。
VENV="$HERE/.venv"
if [ ! -x "$VENV/bin/mitmweb" ]; then
  # mitmproxy 12（固定 token 功能所需）要求 Python >= 3.12，否则 pip 会报难懂的错。
  PYTHON="${PYTHON:-python3}"
  if ! "$PYTHON" -c 'import sys; sys.exit(0 if sys.version_info[:2] >= (3,12) else 1)' 2>/dev/null; then
    echo "[!] 需要 Python >= 3.12（mitmproxy 12 的要求）。当前: $("$PYTHON" -V 2>&1 || echo '未找到 python3')"
    echo "    装好 3.12+ 后，可用 PYTHON=/path/to/python3.12 ./start.sh 指定解释器。"
    exit 1
  fi
  echo "[*] 首次运行：创建 venv 并安装 mitmproxy（需联网，仅此一次）..."
  "$PYTHON" -m venv "$VENV"
  "$VENV/bin/pip" install --upgrade pip >/dev/null
  "$VENV/bin/pip" install -r "$HERE/requirements.txt"
fi
MITMWEB="$VENV/bin/mitmweb"
MITMDUMP="$VENV/bin/mitmdump"

CA_PEM="$HERE/cas/$CA_DIR/mitmproxy-ca.pem"
if [ ! -f "$CA_PEM" ]; then
  echo "[!] 找不到 CA: $CA_PEM"
  echo "    可选:"; ls "$HERE/cas"
  exit 1
fi

# mitmproxy 只从 confdir/mitmproxy-ca.pem 读取 CA（私钥+证书链），
# 用一个临时 confdir 指向选定 CA，避免污染仓库。
WORK="$(mktemp -d)"
cp "$CA_PEM" "$WORK/mitmproxy-ca.pem"
trap 'rm -rf "$WORK"' EXIT

# 探测 mitmproxy 主版本号：只有 11+ 才有 web_password 选项，
# 对 10 传该选项会报 "unknown option" 直接退出，所以要按版本区分。
MITM_MAJOR="$("$MITMDUMP" --version 2>/dev/null | awk '/^Mitmproxy:/{split($2,a,"."); print a[1]; exit}')"
MITM_MAJOR="${MITM_MAJOR:-0}"

WEB_AUTH_ARGS=()
if [ "$MITM_MAJOR" -ge 11 ] && [ -n "$WEB_PASSWORD" ]; then
  WEB_AUTH_ARGS=(--set "web_password=$WEB_PASSWORD")
  WEB_LOGIN="http://<本机IP>:$WEB_PORT/?token=$WEB_PASSWORD   (本机也可用 127.0.0.1)"
else
  WEB_LOGIN="http://<本机IP>:$WEB_PORT/    (此 mitmproxy 版本无需 token)"
fi

echo "=============================================="
echo " eMudhra CA MITM   (app 调试用 / 旧手机免装证书)"
echo "  使用 CA : $CA_DIR"
echo "  代理地址: http://<本机IP>:$PROXY_PORT   <-- 手机填这个"
echo "  Web UI  : $WEB_LOGIN"
echo "            <-- 浏览器打开（已固定 token，无需再抄终端）"
echo "  停止    : Ctrl-C"
echo "=============================================="

# 代理与 Web UI 默认都绑 0.0.0.0，便于内网里从别的机器访问（可用 WEB_HOST/PROXY_HOST 改）。
exec "$MITMWEB" \
  --set confdir="$WORK" \
  --set block_global=false \
  --listen-host "$PROXY_HOST" --listen-port "$PROXY_PORT" \
  --web-host "$WEB_HOST" --web-port "$WEB_PORT" \
  -s "$HERE/addon.py" \
  ${WEB_AUTH_ARGS[@]+"${WEB_AUTH_ARGS[@]}"} \
  "$@"
