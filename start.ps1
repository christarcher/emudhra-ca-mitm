# start.ps1 —— 启动 mitmweb（Windows / PowerShell 版，等价于 start.sh）
#   代理端口与 Web 观测界面都监听 0.0.0.0，方便在内网里从别的机器连。
#   端口默认 28080 / 28081，避开常见服务。
#
# 用法（在 PowerShell 里）:
#   .\start.ps1                              # 默认用 01-EM-OV-TLS-CA-G3C (d=4)
#   .\start.ps1 06-EM-DV-TLS-CA-G3B          # 指定某张泄露CA
#   $env:PROXY_PORT=28888; $env:WEB_PORT=28081; .\start.ps1
#   $env:WEB_PASSWORD="mysecret"; .\start.ps1   # 自定义 Web UI 固定 token
#
# 首次运行若提示脚本被禁止执行:
#   powershell -ExecutionPolicy Bypass -File .\start.ps1
# 或当前用户放开一次:
#   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
#
# 关于 Web UI 的 token：mitmproxy 11+ 每次启动会随机生成 token，这里用
#   --set web_password=<固定值> 钉死；访问 http://<本机IP>:<WEB_PORT>/?token=<WEB_PASSWORD>
#   首次登录后写 cookie，可长期免输。mitmproxy 10 及更早无此鉴权，脚本自动跳过。
#   注意：Web UI 绑到 0.0.0.0 后全内网可访问，唯一防线就是该 token，
#   请把默认值 emudhra 改成不易猜的（$env:WEB_PASSWORD="..."）。

[CmdletBinding()]
param(
    [string]$CaDir = "01-EM-OV-TLS-CA-G3C",
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Definition

$ProxyPort   = if ($env:PROXY_PORT)             { $env:PROXY_PORT }   else { "28080" }
$WebPort     = if ($env:WEB_PORT)               { $env:WEB_PORT }     else { "28081" }
# 监听地址：默认 0.0.0.0 便于内网里从别的机器连。只想本机用就 $env:WEB_HOST="127.0.0.1"。
$WebHost     = if ($env:WEB_HOST)               { $env:WEB_HOST }     else { "0.0.0.0" }
$ProxyHost   = if ($env:PROXY_HOST)             { $env:PROXY_HOST }   else { "0.0.0.0" }
# 固定 token；设成空字符串则退回 mitmproxy 默认的随机 token。
$WebPassword = if ($null -ne $env:WEB_PASSWORD) { $env:WEB_PASSWORD } else { "emudhra" }

# 首次运行自动创建 venv 并安装 requirements.txt 里锁定版本的 mitmproxy，
# 之后直接复用 .venv（已在 .gitignore 中）。拉下仓库即可用，无需手动装依赖。
$Venv      = Join-Path $Here ".venv"
$PyScripts = Join-Path $Venv "Scripts"
$MitmWeb   = Join-Path $PyScripts "mitmweb.exe"
$MitmDump  = Join-Path $PyScripts "mitmdump.exe"
$VenvPy    = Join-Path $PyScripts "python.exe"
if (-not (Test-Path $MitmWeb)) {
    # mitmproxy 12（固定 token 功能所需）要求 Python >= 3.12，否则 pip 会报难懂的错。
    $Python = if ($env:PYTHON) { $env:PYTHON } else { "python" }
    & $Python -c "import sys; sys.exit(0 if sys.version_info[:2] >= (3,12) else 1)" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] 需要 Python >= 3.12（mitmproxy 12 的要求）。当前: $(& $Python -V 2>&1)"
        Write-Host "    装好 3.12+ 后，可用 `$env:PYTHON='py'; .\start.ps1 指定解释器。"
        exit 1
    }
    Write-Host "[*] 首次运行：创建 venv 并安装 mitmproxy（需联网，仅此一次）..."
    & $Python -m venv $Venv
    if ($LASTEXITCODE -ne 0) {
        throw "创建 Python 虚拟环境失败，请检查上面的错误。"
    }
    & $VenvPy -m pip install --upgrade pip | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "升级 pip 失败，请检查网络连接和上面的错误。"
    }
    & $VenvPy -m pip install -r (Join-Path $Here "requirements.txt")
    if ($LASTEXITCODE -ne 0) {
        throw "安装 mitmproxy 失败，请检查上面的 pip 错误后重新运行脚本。"
    }
}

$CaPem = Join-Path $Here "cas\$CaDir\mitmproxy-ca.pem"
if (-not (Test-Path $CaPem)) {
    Write-Host "[!] 找不到 CA: $CaPem"
    Write-Host "    可选:"
    Get-ChildItem (Join-Path $Here "cas") -Directory | ForEach-Object { "      $($_.Name)" }
    exit 1
}

# mitmproxy 只从 confdir/mitmproxy-ca.pem 读取 CA（私钥+证书链），
# 用一个临时 confdir 指向选定 CA，避免污染仓库。
$TempRoot = (Resolve-Path -LiteralPath $env:TEMP).Path
$Work = Join-Path $TempRoot ("emudhra-mitm-" + (New-Guid))
New-Item -ItemType Directory -Path $Work | Out-Null
Copy-Item $CaPem (Join-Path $Work "mitmproxy-ca.pem")

# 探测 mitmproxy 主版本号：只有 11+ 才有 web_password 选项。
$Major = 0
$verLine = (& $MitmDump --version 2>$null | Select-String '^Mitmproxy:')
if ($verLine -and ($verLine.Line -match 'Mitmproxy:\s*(\d+)')) { $Major = [int]$Matches[1] }

$AuthArgs = @()
if ($Major -ge 11 -and $WebPassword -ne "") {
    $AuthArgs = @("--set", "web_password=$WebPassword")
    $WebLogin = "http://<本机IP>:$WebPort/?token=$WebPassword   (本机也可用 127.0.0.1)"
} else {
    $WebLogin = "http://<本机IP>:$WebPort/    (此 mitmproxy 版本无需 token)"
}
if ($NoBrowser) {
    $AuthArgs += @("--set", "web_open_browser=false")
}

Write-Host "=============================================="
Write-Host " eMudhra CA MITM   (app 调试用 / 旧手机免装证书)"
Write-Host "  使用 CA : $CaDir"
Write-Host "  代理地址: http://<本机IP>:$ProxyPort   <-- 手机填这个"
Write-Host "  Web UI  : $WebLogin"
Write-Host "            <-- 浏览器打开（已固定 token，无需再抄终端）"
Write-Host "  停止    : Ctrl-C"
Write-Host "=============================================="

# 代理与 Web UI 默认都绑 0.0.0.0，便于内网里从别的机器访问（可用 WEB_HOST/PROXY_HOST 改）。
try {
    & $MitmWeb `
        --set confdir="$Work" `
        --listen-host $ProxyHost --listen-port $ProxyPort `
        --web-host $WebHost --web-port $WebPort `
        -s (Join-Path $Here "addon.py") `
        @AuthArgs
} finally {
    if ((Split-Path -Parent $Work) -eq $TempRoot -and (Split-Path -Leaf $Work) -like "emudhra-mitm-*") {
        Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
