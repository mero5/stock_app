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
from googleapiclient.discovery import build

# ===================================================
# APIキー設定
# ===================================================
load_dotenv()

JQUANTS_API_KEY = os.getenv("JQUANTS_API_KEY")
YOUTUBE_API_KEY = os.getenv("YOUTUBE_API_KEY")
GEMINI_API_KEY  = os.getenv("GEMINI_API_KEY")
OPENAI_API_KEY  = os.getenv("OPENAI_API_KEY")

# YouTube・OpenAIクライアント初期化
youtube = build("youtube", "v3", developerKey=YOUTUBE_API_KEY)
openai_client = OpenAI(api_key=OPENAI_API_KEY)
genai.configure(api_key=GEMINI_API_KEY)
gemini_model = genai.GenerativeModel("gemini-2.5-flash")


# ===================================================
# FastAPIアプリ初期化
# ===================================================
app = FastAPI()

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

stock_router.stocks_master   = stocks_master
stock_router.JQUANTS_API_KEY = JQUANTS_API_KEY
market_router.openai_client  = openai_client
youtube_router.YOUTUBE_API_KEY = YOUTUBE_API_KEY
youtube_router.gemini_model    = gemini_model
ai_router.openai_client        = openai_client
ai_router.gemini_model         = gemini_model

# ── routerを登録 ──
app.include_router(stock_router.router)
app.include_router(market_router.router)
app.include_router(youtube_router.router)
app.include_router(ai_router.router)
app.include_router(user_router.router)


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
            headers={"x-api-key": JQUANTS_API_KEY}
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