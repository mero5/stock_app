# ===================================================
# WebView 用の画面（routers/web.py）と /app/config
#
# ・/web/{page} は backend/web/pages/ のHTMLだけを返し、外のファイルは読ませない
# ・/app/config の web_screens は、アプリの WebScreen と同じキーで bool を返す
# ===================================================

import os

from fastapi.testclient import TestClient

# main.py は import した瞬間に OpenAI のクライアントを作り、鍵が無いとエラーになる（通信はしない）
os.environ.setdefault("OPENAI_API_KEY", "testing")

import main  # noqa: E402
from config.web_screens import WEB_SCREENS  # noqa: E402

client = TestClient(main.app)


def test_notices_page_returns_html():
    res = client.get("/web/notices")
    assert res.status_code == 200
    assert res.headers["content-type"].startswith("text/html")
    assert res.headers["cache-control"] == "no-cache"
    assert "static/bridge.js" in res.text
    assert "static/notices.js" in res.text


def test_static_files_are_served():
    for name, media in [("app.css", "text/css"), ("bridge.js", "text/javascript"), ("notices.js", "text/javascript")]:
        res = client.get(f"/web/static/{name}")
        assert res.status_code == 200, name
        assert res.headers["content-type"].startswith(media), name


def test_unknown_page_is_404():
    assert client.get("/web/no_such_page").status_code == 404
    assert client.get("/web/static/no_such.css").status_code == 404


def test_cannot_read_outside_web_dir():
    # ".." やドット入りの名前・ほかの拡張子は受け付けない
    for path in ["/web/..%2Fmain", "/web/notices.html", "/web/static/..%2F..%2Fmain.py", "/web/static/notices.html"]:
        assert client.get(path).status_code == 404, path


def test_app_config_lists_web_screens():
    res = client.get("/app/config")
    assert res.status_code == 200
    screens = res.json()["web_screens"]
    assert screens == WEB_SCREENS
    assert all(isinstance(v, bool) for v in screens.values())
    assert "notice_history" in screens
