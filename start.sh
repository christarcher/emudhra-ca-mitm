#!/usr/bin/env bash
# start.sh —— 启动 mitmweb（mitmproxy 三件套的 Web UI 版）
#   只对外暴露一个 HTTP 代理端口；Web 调试界面只监听 127.0.0.1。
#
# 用法:
#   ./start.sh                       # 默认用 01-EM-OV-TLS-CA-G3C (d=4)
#   ./start.sh 06-EM-DV-TLS-CA-G3B   # 指定某张泄露CA
#   PROXY_PORT=8888 WEB_PORT=8081 ./start.sh
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CA_DIR="${1:-01-EM-OV-TLS-CA-G3C}"
PROXY_PORT="${PROXY_PORT:-8080}"
WEB_PORT="${WEB_PORT:-8081}"

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

echo "=============================================="
echo " eMudhra CA MITM   (app 调试用 / 旧手机免装证书)"
echo "  使用 CA : $CA_DIR"
echo "  代理地址: http://<本机IP>:$PROXY_PORT   <-- 手机填这个"
echo "  Web UI  : http://127.0.0.1:$WEB_PORT    <-- 本机浏览器打开"
echo "  停止    : Ctrl-C"
echo "=============================================="

exec mitmweb \
  --set confdir="$WORK" \
  --listen-host 0.0.0.0 --listen-port "$PROXY_PORT" \
  --web-host 127.0.0.1 --web-port "$WEB_PORT" \
  -s "$HERE/addon.py" \
  "$@"