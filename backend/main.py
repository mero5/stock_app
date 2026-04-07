# ===================================================
# 株アプリ バックエンドAPI (FastAPI)
# ===================================================

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import yfinance as yf
import requests
import math
from googleapiclient.discovery import build
from youtube_transcript_api import YouTubeTranscriptApi
from openai import OpenAI
import google.generativeai as genai
from dotenv import load_dotenv
import os

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
# ユーティリティ関数
# ===================================================

# NaN値をNoneに変換（JSONシリアライズエラー防止）
def clean_value(v):
    if isinstance(v, float) and math.isnan(v):
        return None
    return v

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
        stocks_master = data.get("data", [])
        print(f"銘柄マスタ取得完了: {len(stocks_master)}件")
    except Exception as e:
        print(f"銘柄マスタ取得エラー: {e}")

# ===================================================
# 銘柄検索API
# ===================================================

@app.get("/search")
def search(q: str):
    """
    銘柄検索エンドポイント
    - 日本語入力 → J-Quantsマスタから部分一致検索
    - 数字入力   → J-Quantsマスタからコード前方一致検索
    - 英語入力   → yfinanceで米国株検索
    """
    if not q:
        return []
    results = []

    # 日本語 → J-Quantsマスタから検索
    if any("\u3040" <= c <= "\u9fff" for c in q):
        for s in stocks_master:
            name = s.get("CoName", "")
            code = s.get("Code", "")
            if q in name:
                results.append({"code": code, "name": name, "market": "JP"})
        return results[:20]

    # 数字 → J-Quantsマスタからコード検索
    if q.isdigit():
        for s in stocks_master:
            code = s.get("Code", "")
            if code.startswith(q):
                results.append({"code": code, "name": s.get("CoName", code), "market": "JP"})
        return results[:20]

    # 英語 → yfinanceで米国株検索
    try:
        s = yf.Search(q, max_results=15, enable_fuzzy_query=True)
        for r in s.quotes:
            symbol = r.get("symbol", "")
            name = r.get("longname") or r.get("shortname") or ""
            if not name or "." in symbol:
                continue
            results.append({"code": symbol, "name": name, "market": "US"})
    except Exception as e:
        print(f"US検索エラー: {e}")
    return results

# ===================================================
# 銘柄名取得API
# ===================================================

@app.get("/stock/name")
def get_stock_name(code: str):
    """
    銘柄コードから銘柄名を取得
    - 日本株(数字コード) → J-Quantsマスタから検索（4桁→5桁変換）
    - 米国株(英字コード) → yfinanceから取得
    """
    if code.isdigit():
        # 4桁の場合は末尾に0を付けて5桁でJ-Quantsマスタ検索
        search_code = code + "0" if len(code) == 4 else code
        for s in stocks_master:
            if s.get("Code") == search_code:
                return {"code": code, "name": s.get("CoName", code)}
        return {"code": code, "name": code}
    try:
        ticker = yf.Ticker(code)
        info = ticker.info
        name = info.get("longName") or info.get("shortName") or code
        return {"code": code, "name": name}
    except Exception as e:
        print(f"銘柄名取得エラー: {e}")
        return {"code": code, "name": code}

# ===================================================
# 株価詳細API（チャート・RSI・PER・PBR含む）
# ===================================================

@app.get("/stock/detail")
def get_stock_detail(code: str):
    """
    銘柄の詳細情報を取得
    - ローソク足データ（3ヶ月分）
    - 移動平均（MA5・MA25）
    - RSI（14日）
    - 現在株価・前日比
    - PER・PBR・時価総額
    日本株は5桁コードの末尾0を除いてyfinanceに渡す
    """
    try:
        if code.isdigit():
            # 5桁→4桁に変換してyfinanceに渡す（例: 72030 → 7203.T）
            yf_code = code[:-1] if len(code) == 5 else code
            ticker = yf.Ticker(f"{yf_code}.T")
        else:
            ticker = yf.Ticker(code)

        info = ticker.info

        # 3ヶ月分の株価履歴を取得
        hist = ticker.history(period="3mo")

        # ローソク足データを整形
        candles = []
        for date, row in hist.iterrows():
            candles.append({
                "date": str(date.date()),
                "open": round(float(row["Open"]), 2),
                "high": round(float(row["High"]), 2),
                "low": round(float(row["Low"]), 2),
                "close": round(float(row["Close"]), 2),
                "volume": int(row["Volume"]),
            })

        # 移動平均を計算（MA5・MA25）
        closes = [c["close"] for c in candles]
        for i, candle in enumerate(candles):
            candle["ma5"] = round(sum(closes[max(0,i-4):i+1]) / min(i+1, 5), 2)
            candle["ma25"] = round(sum(closes[max(0,i-24):i+1]) / min(i+1, 25), 2)

        # RSI計算（14日間）
        def calc_rsi(closes, period=14):
            if len(closes) < period + 1:
                return [None] * len(closes)
            rsi_list = [None] * period
            gains, losses = [], []
            for i in range(1, period + 1):
                diff = closes[i] - closes[i-1]
                gains.append(max(diff, 0))
                losses.append(max(-diff, 0))
            avg_gain = sum(gains) / period
            avg_loss = sum(losses) / period
            for i in range(period, len(closes)):
                diff = closes[i] - closes[i-1]
                gain = max(diff, 0)
                loss = max(-diff, 0)
                avg_gain = (avg_gain * (period-1) + gain) / period
                avg_loss = (avg_loss * (period-1) + loss) / period
                rs = avg_gain / avg_loss if avg_loss != 0 else 100
                rsi_list.append(round(100 - (100 / (1 + rs)), 2))
            return rsi_list

        rsi_list = calc_rsi(closes)
        for i, candle in enumerate(candles):
            candle["rsi"] = rsi_list[i]

        # 現在株価（取得できない場合は最新終値を使用）
        price = info.get("currentPrice") or info.get("regularMarketPrice") or info.get("previousClose")
        if price is None and not hist.empty:
            price = float(hist["Close"].iloc[-1])

        # 前日比を計算
        prev_close = info.get("previousClose")
        if price and prev_close:
            change = round(price - prev_close, 2)
            change_pct = round((change / prev_close) * 100, 2)
        elif not hist.empty and len(hist) >= 2:
            prev_close = float(hist["Close"].iloc[-2])
            current = float(hist["Close"].iloc[-1])
            change = round(current - prev_close, 2)
            change_pct = round((change / prev_close) * 100, 2)
        else:
            change = None
            change_pct = None

        return {
            "code": code,
            "name": info.get("longName") or info.get("shortName") or code,
            "price": clean_value(price),
            "change": clean_value(change),
            "change_pct": clean_value(change_pct),
            "currency": info.get("currency", "JPY"),
            "per": clean_value(info.get("trailingPE")),
            "pbr": clean_value(info.get("priceToBook")),
            "market_cap": clean_value(info.get("marketCap")),
            "candles": [
                {k: clean_value(v) for k, v in c.items()}
                for c in candles
            ],
        }
    except Exception as e:
        print(f"詳細取得エラー: {e}")
        return {"error": str(e)}

# ===================================================
# 株価・前日比取得API（ホーム画面用・軽量版）
# ===================================================

@app.get("/stock/price")
def get_stock_price(code: str):
    """
    株価と前日比のみを取得（ホーム画面の一覧表示用）
    詳細APIより軽量で高速
    """
    try:
        if code.isdigit():
            yf_code = code[:-1] if len(code) == 5 else code
            ticker = yf.Ticker(f"{yf_code}.T")
        else:
            ticker = yf.Ticker(code)

        info = ticker.info
        price = (
            info.get("currentPrice") or
            info.get("regularMarketPrice") or
            info.get("previousClose")
        )
        prev_close = info.get("previousClose")

        if price and prev_close:
            change = round(price - prev_close, 2)
            change_pct = round((change / prev_close) * 100, 2)
        else:
            # 履歴から計算
            hist = ticker.history(period="5d")
            if not hist.empty:
                if price is None:
                    price = float(hist["Close"].iloc[-1])
                if len(hist) >= 2:
                    prev = float(hist["Close"].iloc[-2])
                    change = round(price - prev, 2)
                    change_pct = round((change / prev) * 100, 2)
                else:
                    change = None
                    change_pct = None
            else:
                change = None
                change_pct = None

        return {
            "code": code,
            "price": price,
            "change": change,
            "change_pct": change_pct,
        }
    except Exception as e:
        print(f"株価取得エラー: {e}")
        return {"code": code, "price": None, "change": None, "change_pct": None}

# ===================================================
# YouTubeチャンネル検索API
# ===================================================

@app.get("/channels/search")
def search_channels(q: str):
    """
    YouTubeチャンネルを検索
    YouTube Data APIを使用して最大10件返す
    """
    try:
        res = youtube.search().list(
            q=q,
            part="snippet",
            type="channel",
            maxResults=10
        ).execute()

        results = []
        for item in res.get("items", []):
            results.append({
                "channel_id": item["id"]["channelId"],
                "name": item["snippet"]["title"],
                "description": item["snippet"]["description"][:100],
                "thumbnail": item["snippet"]["thumbnails"]["default"]["url"],
            })
        return results
    except Exception as e:
        print(f"チャンネル検索エラー: {e}")
        return []

# ===================================================
# YouTubeチャンネル最新動画要約API
# ===================================================
@app.post("/summarize")
def summarize(data: dict):
    """
    YouTubeのURLをGeminiに渡して動画内容を直接要約
    GeminiはYouTubeのURLを直接理解できるので字幕取得不要
    """
    try:
        title = data.get("title", "")
        url = data.get("url", "")
        transcript = data.get("transcript", "")

        # URLがある場合はGeminiにYouTubeURLを直接渡す
        if url:
            response = gemini_model.generate_content([
                f"以下のYouTube動画「{title}」を見て、株式投資に役立つ情報を日本語で箇条書き5つ以内で要約してください。\n{url}"
            ])
            return {"summary": response.text}

        # URLがない場合は説明文や字幕テキストで要約
        if transcript:
            if len(transcript) > 8000:
                transcript = transcript[:8000]
            response = gemini_model.generate_content(
                f"以下の動画「{title}」の内容を株式投資に役立つ情報として日本語で箇条書き5つ以内で要約してください。\n\n{transcript}"
            )
            return {"summary": response.text}

        return {"error": "URLまたはテキストが必要です"}

    except Exception as e:
        print(f"要約エラー: {e}")
        return {"error": str(e)}


# ===================================================
# 複数チャンネルの要約一覧API
# ===================================================

@app.get("/summaries")
def get_summaries(channel_ids: str):
    """
    複数チャンネルの最新動画要約を一括取得
    channel_ids: カンマ区切りのチャンネルID
    例: /summaries?channel_ids=UCxxx,UCyyy,UCzzz
    """
    ids = channel_ids.split(",")
    results = []
    for channel_id in ids:
        summary = get_channel_summary(channel_id.strip())
        results.append(summary)
    return results



@app.get("/channels/{channel_id}/latest_video")
def get_latest_video(channel_id: str):
    """
    チャンネルの最新動画のIDとタイトルだけ返す（字幕はFlutter側で取得）
    """
    try:
        res = youtube.search().list(
            channelId=channel_id,
            part="snippet",
            order="date",
            maxResults=1,
            type="video"
        ).execute()

        items = res.get("items", [])
        if not items:
            return {"error": "動画が見つかりません"}

        video = items[0]
        return {
            "video_id": video["id"]["videoId"],
            "title": video["snippet"]["title"],
            "published_at": video["snippet"]["publishedAt"],
            "thumbnail": video["snippet"]["thumbnails"]["default"]["url"],
            "url": f"https://www.youtube.com/watch?v={video['id']['videoId']}",
        }
    except Exception as e:
        print(f"最新動画取得エラー: {e}")
        return {"error": str(e)}
