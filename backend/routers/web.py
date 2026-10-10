# ===================================================
# WebView 用の画面（HTML）と、アプリの表示設定のAPI
#
# アプリの一部の画面は、ここが返すHTMLを WebView で表示する。
# HTML・CSS・JS は backend/web/ に置き、データは既存のAPI（/notices など）を
# ページの中のJSから呼んで取る。画面のために新しいデータAPIは作らない。
#
#   /web/{page}            backend/web/pages/{page}.html
#   /web/static/{file}     backend/web/static/{file}（共通CSS・JS）
#   /app/config            どの画面を WebView 版にするか（config/web_screens.py）
#
# ログインのトークンはURLに入れない（ログに残るため）。アプリが WebView の
# JavaScriptChannel で渡し、ページのJSが Authorization ヘッダーに付ける（web/static/bridge.js）。
# ===================================================

import re
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import Response

from config.web_screens import WEB_SCREENS

router = APIRouter()

WEB_DIR = Path(__file__).resolve().parent.parent / "web"
PAGES_DIR = WEB_DIR / "pages"
STATIC_DIR = WEB_DIR / "static"

# ファイル名に使ってよい文字。".." や "/" を入れて web/ の外を読ませないため
_PAGE_NAME = re.compile(r"^[a-z0-9_]+$")
_STATIC_NAME = re.compile(r"^[a-z0-9_]+\.(css|js)$")

_MEDIA_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
}

# デプロイしたらすぐ新しい画面が出るように、端末に古いものを使わせない
_NO_CACHE = {"Cache-Control": "no-cache"}


def _file_response(path: Path) -> Response:
    """ファイルを読んで返す。無ければ404"""
    if not path.is_file():
        raise HTTPException(status_code=404, detail="not found")
    return Response(
        content=path.read_bytes(),
        media_type=_MEDIA_TYPES[path.suffix],
        headers=_NO_CACHE,
    )


@router.get("/app/config")
def app_config():
    """
    アプリの表示設定を返す。

    web_screens：画面のキー → True なら WebView 版を開く。
    アプリは取得に失敗したら全部ネイティブの画面を使う。
    """
    return {"web_screens": WEB_SCREENS}


@router.get("/web/static/{file_name}")
def web_static(file_name: str):
    """共通のCSS・JS"""
    if not _STATIC_NAME.match(file_name):
        raise HTTPException(status_code=404, detail="not found")
    return _file_response(STATIC_DIR / file_name)


@router.get("/web/{page_name}")
def web_page(page_name: str):
    """WebView で表示する画面のHTML"""
    if not _PAGE_NAME.match(page_name):
        raise HTTPException(status_code=404, detail="not found")
    return _file_response(PAGES_DIR / f"{page_name}.html")
