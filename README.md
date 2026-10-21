# emudhra-ca-mitm

面向 **App 调试 / 抓包** 的 mitmproxy 组件。利用 2026-10 事件中泄露私钥的 eMudhra 中间 CA，
在**目标设备无需安装任何个人证书**的前提下完成 HTTPS 中间人观测——特别适合
**已停止更新、系统信任库较旧**的手机上调试应用。

只对外暴露一个 **HTTP 代理端口**，调试界面用 mitmweb 的 Web UI。

---

## 1. 背景

2026-10-19，Cloudflare 通报：与 eMudhra 关联的**八张中间证书**私钥可被还原（私钥是极小的整数），
攻击者可伪造任意域名的证书。本仓库从公开渠道还原出这八张中间 CA，供**授权范围内的 App 调试**使用。

八张中间 CA 的私钥均为小整数，且其**签发链锚定在系统信任库**里的
`emSign ECC Root CA - G3`。因此只要在握手中把完整链下发给客户端，标准客户端
（Android / iOS / 桌面）会**直接信任**，无需在设备上安装 CA。

| # | 相同目录 | 中间 CA (CN) | 还原私钥 d |
|---|---|---|---|
| 1 | `cas/01-EM-OV-TLS-CA-G3C` | EM OV TLS CA - G3C | **4** |
| 2 | `cas/02-EM-EV-TLS-CA-G3C` | EM EV TLS CA - G3C | 56 |
| 3 | `cas/03-EM-OV-CS-CA-G3B`  | EM OV CS CA - G3B  | 66 |
| 4 | `cas/04-EM-EV-TLS-CA-G3B` | EM EV TLS CA - G3B | 115 |
| 5 | `cas/05-EM-OV-TLS-CA-G3B` | EM OV TLS CA - G3B | 155 |
| 6 | `cas/06-EM-DV-TLS-CA-G3B` | EM DV TLS CA - G3B | 156 |
| 7 | `cas/07-EM-DV-TLS-CA-G3C` | EM DV TLS CA - G3C | 230 |
| 8 | `cas/08-EM-OV-CS-CA-G3C`  | EM OV CS CA - G3C  | 237 |

> 原理：中间 CA 用 EC P-384，但私钥 `d` 是小整数，`Q = d·G` 可用小标量穷举在秒级还原。
> 详见各目录 `INFO.txt`。

---

## 2. 工作原理

```
App / 浏览器(app 信任系统根)
        │  TLS
        ▼
   mitmweb 代理  ──展示的伪造链──►
        leaf(任意域名, 现签)
          ▲  EM ?V TLS CA - G3x   (泄露私钥的中间 CA)
          ▲  emSign Root TLS/CS CA - G3  (cross-signed)
          ▲  emSign ECC Root CA - G3   ← 设备系统信任库里的根
        │
        ▼  真正转发
     目标服务器
```

关键点：mitmproxy 的 CA 文件 `mitmproxy-ca.pem` 里**除签发 CA 外的证书会被当作链一起下发**
（`mitmproxy/certs.py: CertStore.from_files`）。我们把**交叉签名根**放进该文件，链就完整了，
客户端因此免装证书即可校验通过。

---

## 3. 快速开始

### 3.1 安装

```bash
pip install -r requirements.txt      # 或 pip install "mitmproxy>=10,<11"
```

### 3.2 启动

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

### 3.3 被测设备接入

**Android / iOS（推荐，无需装证书）**

1. 设备与运行本组件的机器处于同一局域网
2. Wi-Fi 设置 → 代理 → 手动 → 主机 `本机IP`、端口 `8080`
3. 直接打开 App，即可在 Web UI (`http://127.0.0.1:8081`) 看到明文请求

> 因为伪造链锚定系统信任库，**大多数 Android/iOS 无需安装用户证书**。
> 若应用额外做了 SSL Pinning，见第 5 节。

**桌面浏览器**

```bash
# Chrome/Chromium
google-chrome --proxy-server="http://127.0.0.1:8080"
# 或直接 export（多数命令行工具生效）
export https_proxy=http://127.0.0.1:8080
```

### 3.4 手动安装证书（可选，兼容旧客户端 / 需要显式信任时）

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

## 4. 目录结构

```
emudhra-ca-mitm/
├── start.sh                  # 启动 mitmweb（改 CA / 端口都在这里）
├── addon.py                  # 流量记录插件（flows.log + 可选存 body）
├── issue_cert.sh             # 用指定CA为某域名单独签发
├── requirements.txt
├── confdir/mitmproxy-ca.pem  # 默认CA（= cas/01-.../mitmproxy-ca.pem）
└── cas/
    └── 01-EM-OV-TLS-CA-G3C/
        ├── original/                   # eMudhra 仓库原始格式（.crt）
        ├── ca.key                      # 还原出的私钥 (d=4)
        ├── ca.pem                      # 私钥 + 完整链
        ├── mitmproxy-ca.pem            # mitmproxy confdir 直接可用
        ├── mitmproxy-ca-cert.pem       # 仅证书链（手动安装用）
        ├── mitmproxy-ca-cert.cer       # 同上，Android/Windows 友好
        └── INFO.txt                    # 元数据（CN / d / 有效期 / 链）
```

---

## 5. 遇到 SSL Pinning

部分 App 会额外校验证书（pinning）。先看第 3 节是否能直接抓到；若失败，用 Frida 旁路：

```bash
frida -U -f com.target.app -l frida/bypass_ssl_pinning.js --no-pause
```

脚本覆盖 Conscrypt / OkHttp3 / TrustKit / HostnameVerifier / WebView 等常见实现。
（详见 `frida/bypass_ssl_pinning.js` 注释。）

---

## 6. 单域名签发 / 透明代理场景

需要固定用某域名证书（反向代理、DNS 劫持、透明代理）时：

```bash
./issue_cert.sh 01-EM-OV-TLS-CA-G3C api.example.com "api.example.com,*.example.com" ./out
# 产出 out/api.example.com.crt / .key / -chain.pem / -full.pem
```

---

## 7. 排障

| 现象 | 处理 |
|---|---|
| 设备报证书不受信任 | 确认用的是 `mitmproxy-ca.pem`（含私钥+链），不是只剩中间CA；`./start.sh` 会自动处理 |
| 连接被重置 / CONNECT 失败 | 检查 `PROXY_PORT` 与设备代理端口一致；`--listen-host 0.0.0.0` 已开 |
| 抓不到明文（App 内报网络错） | 大概率是 pinning，走第 5 节 |
| Web UI 打不开 | 只监听 `127.0.0.1`，需在运行机上打开；换 `WEB_PORT` |
| 想换另一张 CA | `./start.sh <cas目录名>`，比较不同 CA 的兼容性 |

---

## 8. 技术要点

- mitmproxy 读取 `confdir/mitmproxy-ca.pem`，格式 = **PEM 私钥 + 若干 PEM 证书**；
  第一张证书为签发 CA，其余作为链下发（见 `mitmproxy/certs.py: CertStore.from_files`）。
- 掉签：多数 App 用的是 DV/OV，本仓库的 `EM DV/OV TLS CA` 系列命中率更高；
  纯 EV 校验（少数场景）可试 `EM EV TLS CA`。
- 链来源：eMudhra 官方仓库 `repository.emsign.com`；交叉签名根名 `crosssign/roottls-cg3`。