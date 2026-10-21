# emudhra-ca-mitm

面向 **App 调试 / 抓包** 的 mitmproxy 组件。利用 2026-10 事件中泄露私钥的 eMudhra 中间 CA，在**目标设备无需安装任何个人证书**的前提下完成 HTTPS 中间人观测，适合已停止更新、系统信任库较旧的手机/电脑上调试应用。

只对外暴露一个 **HTTP 代理端口**，调试界面用 mitmweb 的 Web UI。

---

八张中间 CA 的私钥均为小整数，且其**签发链锚定在系统信任库**里的`emSign ECC Root CA - G3`。因此只要在握手中把完整链下发给客户端，标准客户端会**直接信任**，无需在设备上安装 CA。

| #   | 相同目录                      | 中间 CA (CN)         | 还原私钥 d |
| --- | ------------------------- | ------------------ | ------ |
| 1   | `cas/01-EM-OV-TLS-CA-G3C` | EM OV TLS CA - G3C | **4**  |
| 2   | `cas/02-EM-EV-TLS-CA-G3C` | EM EV TLS CA - G3C | 56     |
| 3   | `cas/03-EM-OV-CS-CA-G3B`  | EM OV CS CA - G3B  | 66     |
| 4   | `cas/04-EM-EV-TLS-CA-G3B` | EM EV TLS CA - G3B | 115    |
| 5   | `cas/05-EM-OV-TLS-CA-G3B` | EM OV TLS CA - G3B | 155    |
| 6   | `cas/06-EM-DV-TLS-CA-G3B` | EM DV TLS CA - G3B | 156    |
| 7   | `cas/07-EM-DV-TLS-CA-G3C` | EM DV TLS CA - G3C | 230    |
| 8   | `cas/08-EM-OV-CS-CA-G3C`  | EM OV CS CA - G3C  | 237    |

---

## 快速开始

安装

```bash
pip install -r requirements.txt      # 或 pip install "mitmproxy>=10,<11"
```

启动

```bash
chmod +x start.sh issue_cert.sh
./start.sh                            # 默认用 d=4 那张
# 或指定某张：
./start.sh 06-EM-DV-TLS-CA-G3B
```

启动后：

```
代理地址: http://<本机IP>:8080     ← 手机/被测设备填这个
Web UI  : http://127.0.0.1:8081    ← 本机浏览器打开，可实时看/改请求
```

端口可改：

```bash
PROXY_PORT=8888 WEB_PORT=8081 ./start.sh
```

被测设备接入

**Android / iOS（推荐，无需装证书）**

1. 设备与运行本组件的机器处于同一局域网
2. Wi-Fi 设置 → 代理 → 手动 → 主机 `本机IP`、端口 `8080`
3. 直接打开 App，即可在 Web UI (`http://127.0.0.1:8081`) 看到明文请求

> 因为伪造链锚定系统信任库，**大多数 Android/iOS 无需安装用户证书**。
> 若应用额外做了 SSL Pinning，见第 5 节。

桌面浏览器

```bash
# Chrome/Chromium
google-chrome --proxy-server="http://127.0.0.1:8080"
# 或直接 export（多数命令行工具生效）
export https_proxy=http://127.0.0.1:8080
```

### 手动安装证书（可选，兼容旧客户端 / 需要显式信任时）

若某客户端不信任该链，可把对应 CA 装进设备用户证书：

```bash
# 取出证书链（中间CA + 交叉签名根）
cat cas/01-EM-OV-TLS-CA-G3C/mitmproxy-ca-cert.pem
#   Android: 传输到手机 → 设置 → 安全 → 安装证书 → CA 证书
#   Windows: certutil -addstore root mitmproxy-ca-cert.cer
#   macOS  : security add-trusted-cert -d -p ssl -p basic \
#              -k /Library/Keychains/System.keychain mitmproxy-ca-cert.pem
```

---

## SSL Pinning

部分 App 会额外校验证书（pinning）

```bash
frida -U -f com.target.app -l frida/bypass_ssl_pinning.js --no-pause
```

---

## 单域名签发 / 透明代理场景

需要固定用某域名证书（反向代理、DNS 劫持、透明代理）时：

```bash
./issue_cert.sh 01-EM-OV-TLS-CA-G3C api.example.com "api.example.com,*.example.com" ./out
# 产出 out/api.example.com.crt / .key / -chain.pem / -full.pem
```
