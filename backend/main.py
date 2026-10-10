# ===================================================
# 株アプリ バックエンドAPI (FastAPI)
# ===================================================

import os
import requests
import yfinance as yf
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv
from openai import OpenAI
import google.generativeai as genai
import math
from fastapi.responses import JSONResponse
import json
from config.timeouts import JQUANTS_TIMEOUT, OPENAI_TIMEOUT_SEC, OPENAI_MAX_RETRIES
from fastapi import Request
from starlette.concurrency import run_in_threadpool
from services.auth import verify_request_token

# ===================================================
# APIキー設定
# ===================================================
load_dotenv()

JQUANTS_API_KEY = os.getenv("JQUANTS_API_KEY")
YOUTUBE_API_KEY = os.getenv("YOUTUBE_API_KEY")
GEMINI_API_KEY  = os.getenv("GEMINI_API_KEY")
OPENAI_API_KEY  = os.getenv("OPENAI_API_KEY")

# OpenAI・Geminiクライアント初期化
# （YouTubeクライアントは routers/youtube.py がリクエストごとに作る）
# （Geminiのモデルは各routerが genai.GenerativeModel() で都度作るので、ここでは configure だけ）
# timeout / max_retries を指定しないと 600秒 x 最大3回 待つことがある（config/timeouts.py）
openai_client = OpenAI(
    api_key=OPENAI_API_KEY,
    timeout=OPENAI_TIMEOUT_SEC,
    max_retries=OPENAI_MAX_RETRIES,
)
genai.configure(api_key=GEMINI_API_KEY)


# ===================================================
# FastAPIアプリ初期化
# ===================================================
app = FastAPI()

# uvicornのJSONレスポンスを上書き
import starlette.responses as _sr
_original_render = _sr.JSONResponse.render

def _safe_render(self, content):
    def fix_nan(o):
        if isinstance(o, float) and (math.isnan(o) or math.isinf(o)):
            return None
        if isinstance(o, dict):
            return {k: fix_nan(v) for k, v in o.items()}
        if isinstance(o, list):
            return [fix_nan(v) for v in o]
        return o
    return json.dumps(fix_nan(content), ensure_ascii=False).encode('utf-8')

_sr.JSONResponse.render = _safe_render

# CORS設定（Flutterからのアクセスを許可）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ===================================================
# ログインのトークン確認（段階1：確かめてログに出すだけ）
#
# Authorization ヘッダーの Cognito アクセストークンを確かめ、結果を
# request.state.auth に入れて、1リクエスト1行のログ（"[auth] ..."）を出す。
# まだ拒否はしない（古いアプリはトークンを送らないため）。詳しくは config/auth.py
# ===================================================
@app.middleware("http")
async def check_auth_token(request: Request, call_next):
    if request.method == "OPTIONS":  # CORS の事前確認は対象外
        return await call_next(request)
    # 初回だけ Cognito の公開鍵を取りに行く（通信）ので、別スレッドで確かめる
    result = await run_in_threadpool(verify_request_token, request.headers.get("authorization"))
    request.state.auth = result
    query_user_id = request.query_params.get("userId")
    mismatch = bool(result.user_id and query_user_id and query_user_id != result.user_id)
    # トークン自体はログに出さない
    print(
        f"[auth] {result.status} {request.method} {request.url.path}"
        + (f" reason={result.reason}" if result.reason else "")
        + (" userId不一致" if mismatch else "")
    )
    return await call_next(request)

# 銘柄マスタ（起動時にJ-Quantsから取得してメモリに保持）
stocks_master = []


# ── 各routerに変数を注入 ──
import routers.stock as stock_router
import routers.market as market_router
import routers.youtube as youtube_router
import routers.ai as ai_router
import routers.user as user_router
import routers.stats as stats_router
import routers.notices as notices_router

stock_router.stocks_master   = stocks_master
stock_router.JQUANTS_API_KEY = JQUANTS_API_KEY
market_router.openai_client  = openai_client
youtube_router.YOUTUBE_API_KEY = YOUTUBE_API_KEY
ai_router.openai_client        = openai_client

# ── routerを登録 ──
app.include_router(stock_router.router)
app.include_router(market_router.router)
app.include_router(youtube_router.router)
app.include_router(ai_router.router)
app.include_router(user_router.router)
app.include_router(stats_router.router)
app.include_router(notices_router.router)


# ===================================================
# 起動時処理
# ===================================================
def fetch_stocks_master() -> bool:
    """
    J-Quantsから全上場銘柄マスタを取得して stocks_master に入れる。成功したら True

    起動時に1回呼ぶほか、検索・銘柄名APIでマスタが空のときに routers/stock.py から呼ばれる。
    以前は起動時の1回だけだったので、そこで失敗する（J-Quantsの一時的な障害・タイムアウト）と、
    Lambdaのコンテナが入れ替わるまで日本株の検索・銘柄名が全部空になっていた。
    """
    try:
        res = requests.get(
            "https://api.jquants.com/v2/equities/master",
            headers={"x-api-key": JQUANTS_API_KEY},
            timeout=JQUANTS_TIMEOUT,
        )
        if res.status_code != 200:
            print(f"銘柄マスタ取得エラー: HTTP {res.status_code} {res.text[:200]}")
            return False
        loaded = res.json().get("data", [])
        if not loaded:
            print("銘柄マスタ取得エラー: 0件")
            return False
        # routers/stock.py と同じリストを共有しているので、作り直さずに中身を入れ替える
        stocks_master[:] = loaded
        print(f"銘柄マスタ取得完了: {len(stocks_master)}件")
        return True
    except Exception as e:
        print(f"銘柄マスタ取得エラー: {e}")
        return False


stock_router.reload_stocks_master = fetch_stocks_master


@app.on_event("startup")
async def load_stocks_master():
    """起動時に銘柄マスタを取得してメモリに保持"""
    fetch_stocks_master()


@app.get("/health")
def health_check():
    results = {}
    # yfinanceチェック
    try:
        t = yf.Ticker("^N225")
        hist = t.history(period="1d")
        results["yfinance"] = "ok" if not hist.empty else "error"
    except:
        results["yfinance"] = "error"
    # J-Quantsチェック
    try:
        results["jquants"] = "ok" if len(stocks_master) > 0 else "error"
    except:
        results["jquants"] = "error"
    return results


def sanitize_for_json(obj):
    if isinstance(obj, dict):
        return {k: sanitize_for_json(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [sanitize_for_json(v) for v in obj]
    elif isinstance(obj, float) and (math.isnan(obj) or math.isinf(obj)):
        return None
    return obj




class NanSafeJSONResponse(JSONResponse):
    def render(self, content) -> bytes:
        return json.dumps(
            sanitize_for_json(content),
            ensure_ascii=False,
        ).encode("utf-8")

app.router.default_response_class = NanSafeJSONResponse