#!/usr/bin/env bash
# issue_cert.sh —— 用某张泄露CA为指定域名单独签发证书（透明代理/反向代理/固定域名场景用）
#
# 用法: ./issue_cert.sh <CA目录> <域名> [SAN,...] [输出目录]
# 例:   ./issue_cert.sh 01-EM-OV-TLS-CA-G3C api.example.com "api.example.com,*.example.com" ./out
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CA_DIR="${1:?用法: $0 <CA目录> <域名> [SAN] [输出目录]}"
DOMAIN="${2:?缺少域名}"
SAN="${3:-$DOMAIN}"
OUT="${4:-./out}"
mkdir -p "$OUT"

KEY="$HERE/cas/$CA_DIR/ca.key"
CRT="$HERE/cas/$CA_DIR/mitmproxy-ca-cert.pem"
[ -f "$KEY" ] || { echo "[!] 找不到 $KEY"; exit 1; }

openssl ecparam -genkey -name prime256v1 -noout -out "$OUT/$DOMAIN.key"
openssl req -new -key "$OUT/$DOMAIN.key" -subj "/C=CN/O=Debug/CN=$DOMAIN" -out "$OUT/$DOMAIN.csr"

cat > "$OUT/$DOMAIN.ext" <<EOF
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=serverAuth
subjectAltName=$(echo "$SAN" | sed 's/[^,]*/DNS:&/g')
EOF

# 用中间CA签发。CRT 文件里第1张即该中间CA，第2张是交叉签名根。
awk '/BEGIN CERT/{n++} n==1{print} /END CERT/{if(n==1)exit}' "$CRT" > "$OUT/_ca.pem"
openssl x509 -req -in "$OUT/$DOMAIN.csr" -CA "$OUT/_ca.pem" -CAkey "$KEY" \
  -CAcreateserial -days 397 -sha384 -extfile "$OUT/$DOMAIN.ext" -out "$OUT/$DOMAIN.crt"
cp "$CRT" "$OUT/$DOMAIN-chain.pem"
cat "$OUT/$DOMAIN.key" "$OUT/$DOMAIN.crt" > "$OUT/$DOMAIN-full.pem"

echo "[+] 已签发: $OUT/$DOMAIN.crt"
openssl x509 -in "$OUT/$DOMAIN.crt" -noout -subject -issuer
rm -f "$OUT/_ca.pem" "$OUT/$DOMAIN.csr" "$OUT/$DOMAIN.ext"