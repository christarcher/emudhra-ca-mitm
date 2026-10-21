# emudhra-ca-mitm

面向 **App 调试 / 抓包** 的 mitmproxy 组件。利用 2026-10 事件中泄露私钥的 eMudhra 中间 CA，在**目标设备无需安装任何个人证书**的前提下完成 HTTPS 中间人观测，适合已停止更新、系统信任库较旧的手机/电脑上调试应用。

对外提供一个 **HTTP 代理端口**（默认 `28080`）和一个 **Web 观测界面**（mitmweb，默认
`28081`）。两者都监听 `0.0.0.0`，方便在内网里从别的机器连；Web UI 由固定 token 保护。

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

只需要装好 **Python 3.12+**（mitmproxy 12 的硬性要求，见下方说明）。依赖不用手动
装——`start.sh` 首次运行会自动在 `.venv/` 里创建虚拟环境并安装 `requirements.txt`
中锁定版本的 mitmproxy（`.venv/` 已在 `.gitignore`，不污染仓库），之后复用。
Python 低于 3.12 时脚本会先报错提示，不会装到一半失败。

```bash
chmod +x start.sh issue_cert.sh
./start.sh                            # 首次会自动建 venv 装依赖（需联网，仅此一次）
# 或指定某张：
./start.sh 06-EM-DV-TLS-CA-G3B
```

> 想用自己已有的 Python 解释器建 venv：`PYTHON=/path/to/python3 ./start.sh`。
> 想升级 mitmproxy：改 `requirements.txt` 的版本号，删掉 `.venv/`，下次启动会重建。

启动后：

```
代理地址: http://<本机IP>:28080                 ← 手机/被测设备填这个
Web UI  : http://<本机IP>:28081/?token=emudhra  ← 浏览器打开，可实时看/改请求
                                                   （本机也可用 127.0.0.1）
```

- 端口默认 **28080 / 28081**，避开 8080/8081 等常见服务。
- 代理与 Web UI 都绑 `0.0.0.0`，内网里的其它机器也能连（查本机 IP：Linux `ip a`，Windows `ipconfig`）。
- Web UI 的 `?token=` 见下一节；首次带 token 打开后会写 cookie，之后免输。

端口可改：

```bash
PROXY_PORT=28888 WEB_PORT=28081 ./start.sh
```

### 外部客户端连接

Windows 的 `start.ps1` 和 Linux / macOS 的 `start.sh` 默认传入
`--set block_global=false`，允许外部客户端连接代理，无需额外参数或环境变量。
更新脚本后请停止当前服务并重新启动，解决
`Client connection from ... killed by block_global option.` 报错。
设备仍需能访问监听地址和端口，防火墙也需允许连接；Web UI 使用原有 token。

### 固定 Web UI 的 token（不用每次抄终端）

从 **mitmproxy 12**（CVE-2025-23217 的修复）起，mitmweb 默认给 Web UI 加了强制
鉴权，每次启动随机生成一个 token，要去终端里抄很烦。本仓库用
`--set web_password=<固定值>` 把它钉死，默认值 `emudhra`，之后一直用同一个链接即可：

```
http://<本机IP>:28081/?token=emudhra      # 本机也可用 http://127.0.0.1:28081/?token=emudhra
```

首次用这个带 `?token=` 的链接打开后，mitmweb 会写一个长期 cookie，之后直接开
`http://<本机IP>:28081/` 也不用再输。想改成自己的 token：

```bash
WEB_PASSWORD=mysecret ./start.sh           # 之后用 ?token=mysecret
WEB_PASSWORD= ./start.sh                    # 留空 = 退回官方随机 token
```

> - 该 token 同时就是 Web UI 的登录口令，打开页面时也可直接在弹窗里输入。
> - `web_password` 支持 argon2 哈希（以 `$` 开头的值按哈希处理），需要更隐蔽时可用。
> - 固定 token 功能是 **mitmproxy 12 专属**，而 12.x 要求 **Python ≥3.12**；这也是
>   `requirements.txt` 锁 `mitmproxy==12.2.3` 的原因。脚本仍保留版本探测，低于 12
>   的环境会自动跳过 token（但本仓库 venv 固定装 12，正常不会触发）。
> - **安全提醒**：Web UI 绑在 `0.0.0.0`，全内网都能访问，唯一的防线就是这个 token。
>   内网调试时请务必把默认的 `emudhra` 改成不易猜的值（`WEB_PASSWORD=...`）。拿到
>   token 的人能看到全部明文流量、改包重放。不用时及时 Ctrl-C 关掉，别暴露到公网
>   （CVE-2025-23217）。只在本机调试、不需要别的机器连时，可回到仅本机监听：
>   `WEB_HOST=127.0.0.1 ./start.sh`（代理口也可用 `PROXY_HOST=127.0.0.1`）。

---

## Windows 上使用

Windows 有两条路：**原生 PowerShell 脚本（推荐）** 或 WSL / Git Bash 里跑 `start.sh`。

### 方式 A：原生 PowerShell（`start.ps1`）

1. 装 Python **3.12+**（[python.org](https://www.python.org/downloads/windows/) 或 `winget install Python.Python.3.12`），安装时勾选 *Add to PATH*。用 `python --version` 确认版本；依赖由脚本自动装。
2. 启动（在仓库目录的 PowerShell 里）。首次运行会自动建 `.venv\` 并装依赖（需联网，仅此一次）：

   ```powershell
   .\start.ps1                              # 默认 01-EM-OV-TLS-CA-G3C (d=4)
   .\start.ps1 -NoBrowser                   # 启动服务后手动打开 Web UI
   .\start.ps1 06-EM-DV-TLS-CA-G3B          # 指定某张泄露CA
   $env:PROXY_PORT=28888; $env:WEB_PORT=28081; .\start.ps1
   $env:WEB_PASSWORD="mysecret"; .\start.ps1
   $env:WEB_HOST="127.0.0.1"; .\start.ps1   # 只想本机访问 Web UI 时
   ```

   若 `python` 不在 PATH，可改用启动器：`$env:PYTHON="py"; .\start.ps1`。

   首次若报“禁止运行脚本”，二选一：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\start.ps1      # 临时放行一次
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned       # 当前用户永久放行
   ```

   `start.ps1` 与 `start.sh` 行为完全一致：首次自动建 venv 装依赖、固定 token、
   用临时 confdir 挂载选定 CA、退出时清理。

3. 让被测设备连上：Windows 防火墙首次会弹窗，勾选允许 `python` 在
   **专用网络**上通信；手机代理填 `本机IP:28080`。查本机 IP：`ipconfig`。

### Windows PowerShell 5.1 中文乱码 / ParserError

`start.ps1` 使用 **UTF-8 with BOM** 编码，以兼容 Windows 自带的 PowerShell 5.1。
编辑后请保留此编码：不带 BOM 的 UTF-8 会被 PowerShell 5.1 按系统 ANSI 编码
（中文 Windows 通常是 GBK）读取，可能报“字符串缺少终止符”“数组索引表达式丢失”
等语法错误。`chcp 65001` 或调整执行策略无法修正脚本文件的读取编码。

如果使用的是旧版脚本，可在仓库目录运行一次下面的命令，再启动：

```powershell
python -c "from pathlib import Path; p=Path('start.ps1'); s=p.read_text(encoding='utf-8-sig'); p.write_bytes(s.encode('utf-8-sig'))"
.\start.ps1
```

### 方式 B：WSL / Git Bash

在 WSL 或 Git Bash 里直接按上面的 Linux 步骤跑 `./start.sh` 即可。
注意 WSL 的网络是独立子网，手机要连的是 **Windows 主机的局域网 IP**，可能需要
`netsh interface portproxy` 端口转发；若只在本机调试桌面浏览器则无此问题。

### Windows 下手动装证书（仅在客户端不认伪造链时才需要）

```powershell
# 导入到“受信任的根证书颁发机构”（需管理员 PowerShell）
certutil -addstore root cas\01-EM-OV-TLS-CA-G3C\mitmproxy-ca-cert.cer
# 用完清理（按 CN 删除）
certutil -delstore root "EM OV TLS CA - G3C"
```

> 多数情况下伪造链锚定系统信任库，**无需**这一步。

被测设备接入

**Android / iOS（推荐，无需装证书）**

1. 设备与运行本组件的机器处于同一局域网
2. Wi-Fi 设置 → 代理 → 手动 → 主机 `本机IP`、端口 `28080`
3. 直接打开 App，即可在 Web UI (`http://<本机IP>:28081/?token=emudhra`) 看到明文请求

> 因为伪造链锚定系统信任库，**大多数 Android/iOS 无需安装用户证书**。
> 若应用额外做了 SSL Pinning，见第 5 节。

桌面浏览器

```bash
# Chrome/Chromium
google-chrome --proxy-server="http://127.0.0.1:28080"
# 或直接 export（多数命令行工具生效）
export https_proxy=http://127.0.0.1:28080
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
