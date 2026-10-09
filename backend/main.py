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
@app.on_event("startup")
async def load_stocks_master():
    """J-Quantsから全上場銘柄マスタを取得してメモリに保持"""
    global stocks_master
    try:
        res = requests.get(
            "https://api.jquants.com/v2/equities/master",
            headers={"x-api-key": JQUANTS_API_KEY},
            timeout=JQUANTS_TIMEOUT,
        )
        data = res.json()
        loaded = data.get("data", [])
        stocks_master.extend(loaded)
        # routerに反映
        stock_router.stocks_master = stocks_master
        stock_router.JQUANTS_API_KEY = JQUANTS_API_KEY
        print(f"銘柄マスタ取得完了: {len(stocks_master)}件")
    except Exception as e:
        print(f"銘柄マスタ取得エラー: {e}")


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