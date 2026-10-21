"""
addon.py —— mitmweb 流量记录插件。

作用:
  * 把每个请求/响应摘要追加到 flows.log（便于 grep 调试）
  * 可选把响应体存到 bodies/（设 MITM_SAVE_BODY=1）
  * 高亮记录常见鉴权头，方便看 app 的接口调用

启动时由 start.sh 自动加载: mitmweb -s addon.py
"""
import os

from mitmproxy import http

HERE = os.path.dirname(os.path.abspath(__file__))
LOG = os.environ.get("MITM_LOG", os.path.join(HERE, "flows.log"))
SAVE_BODY = os.environ.get("MITM_SAVE_BODY", "0") == "1"
BODY_DIR = os.path.join(HERE, "bodies")
MAX_BODY = 4 * 1024 * 1024


def _log(line: str) -> None:
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def request(flow: http.HTTPFlow) -> None:
    h = flow.request.headers
    auth = h.get("Authorization", "")
    key = h.get("X-Api-Key", h.get("apikey", ""))
    _log(
        f">> {flow.request.method} {flow.request.pretty_url} "
        f"UA={h.get('User-Agent','-')} "
        f"Auth={auth[:32]} ApiKey={key[:32]}"
    )


def response(flow: http.HTTPFlow) -> None:
    r = flow.response
    _log(
        f"<< {r.status_code} {flow.request.pretty_url} "
        f"len={len(r.content)} ctype={r.headers.get('content-type','-')}"
    )
    if SAVE_BODY and r.content and len(r.content) <= MAX_BODY:
        import hashlib
        os.makedirs(BODY_DIR, exist_ok=True)
        name = hashlib.md5(flow.request.pretty_url.encode()).hexdigest()[:16]
        with open(os.path.join(BODY_DIR, name + ".bin"), "wb") as f:
            f.write(r.content)