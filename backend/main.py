# ===================================================
# 株アプリ バックエンドAPI (FastAPI)
# ===================================================

from fastapi import FastAPI, Request
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
import json
import pandas as pd
import numpy as np
import asyncio
from concurrent.futures import ThreadPoolExecutor
import boto3
from decimal import Decimal
from datetime import datetime, timedelta

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
# DynamoDBキャッシュ
# ===================================================

dynamodb = boto3.resource('dynamodb', region_name='ap-northeast-1')
market_cache_table = dynamodb.Table('market_cache')
stock_cache_table  = dynamodb.Table('stock_cache')

def _to_decimal(obj):
    """float → Decimal変換（DynamoDB保存用）"""
    if isinstance(obj, float):
        return Decimal(str(obj))
    if isinstance(obj, dict):
        return {k: _to_decimal(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_to_decimal(i) for i in obj]
    return obj

def _from_decimal(obj):
    """Decimal → float変換（レスポンス用）"""
    if isinstance(obj, Decimal):
        return float(obj)
    if isinstance(obj, dict):
        return {k: _from_decimal(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_from_decimal(i) for i in obj]
    return obj

def cache_get(table, key: dict) -> dict | None:
    """DynamoDBキャッシュ取得。期限切れ・未存在はNoneを返す"""
    try:
        res  = table.get_item(Key=key)
        item = res.get('Item')
        if not item:
            return None
        expires_at = item.get('expires_at')
        if expires_at and datetime.fromisoformat(str(expires_at)) < datetime.now():
            return None  # TTL切れ
        return _from_decimal({k: v for k, v in item.items()
                               if k not in ('expires_at', 'updated_at')})
    except Exception as e:
        print(f"キャッシュ取得エラー: {e}")
        return None

def cache_set(table, key: dict, data: dict, ttl_minutes: int = 60):
    """DynamoDBにキャッシュ保存"""
    try:
        item = {
            **key,
            **data,
            'updated_at': datetime.now().isoformat(),
            'expires_at': (datetime.now() + timedelta(minutes=ttl_minutes)).isoformat(),
        }
        table.put_item(Item=_to_decimal(item))
    except Exception as e:
        print(f"キャッシュ保存エラー: {e}")

user_profile_table = dynamodb.Table('user_profiles')

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

        # ボリンジャーバンド計算（20日）
        for i, candle in enumerate(candles):
            if i >= 19:
                window = closes[i-19:i+1]
                mean = sum(window) / 20
                std = (sum((x - mean) ** 2 for x in window) / 20) ** 0.5
                candle["bb_upper"] = round(mean + 2 * std, 2)
                candle["bb_middle"] = round(mean, 2)
                candle["bb_lower"] = round(mean - 2 * std, 2)
            else:
                candle["bb_upper"] = None
                candle["bb_middle"] = None
                candle["bb_lower"] = None

        # MACD計算
        def ema_series(data, period):
            result = [None] * (period - 1)
            k = 2 / (period + 1)
            val = sum(data[:period]) / period
            result.append(round(val, 2))
            for v in data[period:]:
                val = v * k + val * (1 - k)
                result.append(round(val, 2))
            return result

        ema12_series = ema_series(closes, 12)
        ema26_series = ema_series(closes, 26)
        for i, candle in enumerate(candles):
            e12 = ema12_series[i]
            e26 = ema26_series[i]
            if e12 is not None and e26 is not None:
                candle["macd"] = round(e12 - e26, 2)
            else:
                candle["macd"] = None

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
        
        # ニュース取得
        try:
            news_raw = ticker.news or []
            news = []
            for n in news_raw[:5]:
                content = n.get("content", {})
                if not isinstance(content, dict):
                    continue
                title = content.get("title", "")
                if title:
                    news.append({"title": title})
        except:
            news = []

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
            "dividend_yield": clean_value(info.get("dividendYield")),
            "roe": clean_value(info.get("returnOnEquity")),
            "roa": clean_value(info.get("returnOnAssets")),
            "revenue_growth": clean_value(info.get("revenueGrowth")),
            "debt_to_equity": clean_value(info.get("debtToEquity")),
            "news": news,
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

        hist = ticker.history(period="2d")
        if not hist.empty:
            price = round(float(hist["Close"].iloc[-1]), 2)
            if len(hist) >= 2:
                prev = round(float(hist["Close"].iloc[-2]), 2)
                change = round(price - prev, 2)
                change_pct = round((change / prev) * 100, 2)
            else:
                change = None
                change_pct = None
        else:
            info = ticker.info
            price = info.get("currentPrice") or info.get("previousClose")
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
async def summarize_video(request: Request):
    body = await request.json()
    video_url = body.get("url", "")
    
    # URLをキーにしてキャッシュ確認（7日間）
    cache_key = f"summary_{video_url.replace('https://www.youtube.com/watch?v=', '')}"
    cached = cache_get(market_cache_table, {'cache_key': cache_key})
    if cached:
        print(f"要約キャッシュヒット: {cache_key}")
        return cached
    
    title = body.get("title", "")
    url = body.get("url", "")
    transcript = body.get("transcript", "")

    prompt = f"""
以下のYouTube動画を分析して、必ずJSON形式のみで返してください。前置きや説明文は不要です。

動画タイトル: {title}
動画URL: {url}
動画説明文: {transcript}

以下のJSON形式で回答してください：
{{
"summary": "以下の項目で箇条書きにして記述（日本語）。各項目は「・」で始めること。\n・全体の結論\n・相場観・市場の見方\n・注目銘柄・セクター\n・根拠・理由\n・視聴者へのアドバイス",
"nikkei_outlook": "bullish" か "bearish" か "neutral" か "not_mentioned" のいずれか,
"nikkei_reason": "日経平均についての根拠（not_mentionedの場合は空文字）",
"us_market_outlook": "bullish" か "bearish" か "neutral" か "not_mentioned" のいずれか,
"sentiment": "very_bullish" か "bullish" か "neutral" か "bearish" か "very_bearish" のいずれか,
"topics": ["話題1", "話題2", "話題3"],
"recommended_action": "buy" か "sell" か "hold" か "watch" か "not_mentioned" のいずれか,
"key_stocks": ["言及された銘柄名1", "銘柄名2"],
"confidence": 1から5の整数
}}
"""

    try:
        model = genai.GenerativeModel("gemini-2.5-flash")
        response = model.generate_content(
            [{"role": "user", "parts": [{"text": prompt}]}]
        )
        raw = response.text.strip()
        raw = raw.replace("```json", "").replace("```", "").strip()
        parsed = json.loads(raw)
        return parsed

        # 7日間キャッシュ保存
        cache_set(market_cache_table, {'cache_key': cache_key}, parsed, ttl_minutes=10080)
        return parsed

    except Exception as e:
        return {
            "summary": "要約できませんでした",
            "nikkei_outlook": "not_mentioned",
            "nikkei_reason": "",
            "us_market_outlook": "not_mentioned",
            "sentiment": "neutral",
            "topics": [],
            "recommended_action": "not_mentioned",
            "key_stocks": [],
            "confidence": 0,
            "error": str(e)
        }


# ===================================================
# 複数チャンネルの要約一覧API
# ===================================================

@app.get("/summaries")
def get_summaries(channel_ids: str):
    return []



@app.get("/channels/{channel_id}/videos")
def get_channel_videos(channel_id: str, max_results: int = 10):
    """チャンネルの最新動画一覧を取得"""
    try:
        youtube = build("youtube", "v3", developerKey=os.getenv("YOUTUBE_API_KEY"))
        res = youtube.search().list(
            channelId=channel_id,
            part="snippet",
            order="date",
            maxResults=max_results,
            type="video",
        ).execute()

        videos = []
        for item in res.get("items", []):
            videos.append({
                "video_id":     item["id"]["videoId"],
                "title":        item["snippet"]["title"],
                "published_at": item["snippet"]["publishedAt"],
                "thumbnail":    item["snippet"]["thumbnails"]["medium"]["url"],
                "description":  item["snippet"]["description"],
            })
        return {"videos": videos}
    except Exception as e:
        return {"error": str(e), "videos": []}

# ===================================================
# 銘柄イベント取得API
# ===================================================

@app.get("/stock/events")
def get_stock_events(codes: str):
    """
    ウォッチリスト銘柄のイベント（決算・配当）を取得
    codes: カンマ区切りの銘柄コード
    """
    import datetime
    result = []

    for code in codes.split(","):
        code = code.strip()
        if not code:
            continue
        try:
            if code.isdigit():
                yf_code = code[:-1] if len(code) == 5 else code
                ticker = yf.Ticker(f"{yf_code}.T")
            else:
                ticker = yf.Ticker(code)

            info = ticker.info
            name = info.get("longName") or info.get("shortName") or code

            # 決算発表日（日本株はJ-Quantsから取得）
            if code.isdigit():
                try:
                    res = requests.get(
                        "https://api.jquants.com/v2/fins/announcement",
                        headers={"x-api-key": JQUANTS_API_KEY},
                        params={"code": (code[:-1] if len(code) == 5 else code) + "0"}
                    )
                    data = res.json()
                    announcements = data.get("announcement", [])
                    for ann in announcements[:2]:
                        date_str = ann.get("AnnouncementDate", "")
                        if date_str:
                            result.append({
                                "code": code,
                                "name": name,
                                "date": date_str[:10],
                                "type": "earnings",
                                "label": f"{name} 決算発表",
                                "color": "red",
                            })
                except Exception as e:
                    print(f"J-Quants決算取得エラー: {e}")
            else:
                # 米国株はyfinanceから
                try:
                    cal = ticker.calendar
                    if cal is not None and not cal.empty:
                        ed = cal.get("Earnings Date")
                        if ed is not None and len(ed) > 0:
                            earnings_date = str(ed.iloc[0].date()) if hasattr(ed.iloc[0], 'date') else str(ed.iloc[0])
                            result.append({
                                "code": code,
                                "name": name,
                                "date": earnings_date,
                                "type": "earnings",
                                "label": f"{name} 決算発表",
                                "color": "red",
                            })
                except Exception:
                    pass

            # 配当関連（yfinance）
            try:
                ex_div = info.get("exDividendDate")
                if ex_div:
                    ex_dividend = str(datetime.datetime.fromtimestamp(ex_div).date())
                    result.append({
                        "code": code,
                        "name": name,
                        "date": ex_dividend,
                        "type": "ex_dividend",
                        "label": f"{name} 配当落ち日",
                        "color": "blue",
                    })
            except Exception:
                pass

        except Exception as e:
            print(f"イベント取得エラー {code}: {e}")

    return result

# ===================================================
# AI分析API（テクニカル・ファンダ・ニュース）
# ===================================================

@app.get("/stock/ai_analysis")
async def get_ai_analysis(code: str):
    try:
        if code.isdigit():
            yf_code = code[:-1] if len(code) == 5 else code
            ticker = yf.Ticker(f"{yf_code}.T")
        else:
            ticker = yf.Ticker(code)

        info = ticker.info
        hist = ticker.history(period="3mo")
        raw_news = ticker.news[:5] if ticker.news else []

        # ── ニュース整形 ──
        news_items = []
        for n in raw_news:
            content = n.get("content", {})
            if not isinstance(content, dict):
                continue
            title = content.get("title", "")
            summary = content.get("summary", "")
            provider = ""
            pub_date = ""
            provider_info = content.get("provider", {})
            if isinstance(provider_info, dict):
                provider = provider_info.get("displayName", "")
            pub_date = content.get("pubDate", "")
            if title:
                news_items.append({
                    "title": title,
                    "summary": summary,
                    "provider": provider,
                    "pub_date": pub_date,
                })

        # ── ChatGPTでニュースタイトルと要約を日本語翻訳 ──
        if news_items:
            try:
                titles_en = [n['title'] for n in news_items]
                summaries_en = [n['summary'] for n in news_items]

                # タイトル翻訳
                title_res = openai_client.chat.completions.create(
                    model="gpt-4o-mini",
                    messages=[
                        {
                            "role": "system",
                            "content": "株式ニュースのタイトルを日本語に翻訳してください。JSON配列のみ返してください。例：[\"翻訳1\", \"翻訳2\"]"
                        },
                        {
                            "role": "user",
                            "content": str(titles_en)
                        }
                    ],
                    max_tokens=500,
                )
                raw_titles = title_res.choices[0].message.content.strip()
                raw_titles = raw_titles.replace("```json", "").replace("```", "").strip()
                titles_ja = json.loads(raw_titles)
                for i, n in enumerate(news_items):
                    if i < len(titles_ja):
                        n['title'] = titles_ja[i]

                # 要約翻訳
                summary_res = openai_client.chat.completions.create(
                    model="gpt-4o-mini",
                    messages=[
                        {
                            "role": "system",
                            "content": "株式ニュースの要約文を日本語に翻訳してください。JSON配列のみ返してください。空文字はそのまま空文字で返してください。例：[\"翻訳1\", \"翻訳2\"]"
                        },
                        {
                            "role": "user",
                            "content": str(summaries_en)
                        }
                    ],
                    max_tokens=1000,
                )
                raw_summaries = summary_res.choices[0].message.content.strip()
                raw_summaries = raw_summaries.replace("```json", "").replace("```", "").strip()
                summaries_ja = json.loads(raw_summaries)
                for i, n in enumerate(news_items):
                    if i < len(summaries_ja):
                        n['summary'] = summaries_ja[i]

            except Exception as e:
                print(f"翻訳エラー: {e}")


        # ── テクニカル計算 ──
        closes = hist["Close"].tolist() if not hist.empty else []
        highs  = hist["High"].tolist()  if not hist.empty else []
        lows   = hist["Low"].tolist()   if not hist.empty else []

        current_price = closes[-1] if closes else None
        ma5  = round(sum(closes[-5:])  / min(len(closes), 5),  2) if closes else None
        ma25 = round(sum(closes[-25:]) / min(len(closes), 25), 2) if closes else None

        def ema(data, period):
            if len(data) < period:
                return None
            k = 2 / (period + 1)
            val = sum(data[:period]) / period
            for v in data[period:]:
                val = v * k + val * (1 - k)
            return round(val, 2)

        ema12 = ema(closes, 12)
        ema26 = ema(closes, 26)
        macd  = round(ema12 - ema26, 2) if ema12 and ema26 else None

        rsi = None
        if len(closes) >= 15:
            period = 14
            gains, losses = [], []
            for i in range(1, period + 1):
                diff = closes[-period - 1 + i] - closes[-period - 2 + i]
                gains.append(max(diff, 0))
                losses.append(max(-diff, 0))
            avg_gain = sum(gains) / period
            avg_loss = sum(losses) / period
            if avg_loss != 0:
                rsi = round(100 - (100 / (1 + avg_gain / avg_loss)), 1)
            else:
                rsi = 100.0

        high52 = round(max(highs), 2) if highs else None
        low52  = round(min(lows),  2) if lows  else None

        per            = clean_value(info.get("trailingPE"))
        pbr            = clean_value(info.get("priceToBook"))
        market_cap     = clean_value(info.get("marketCap"))
        dividend_yield = clean_value(info.get("dividendYield"))
        roe            = clean_value(info.get("returnOnEquity"))
        revenue_growth = clean_value(info.get("revenueGrowth"))
        name           = info.get("longName") or info.get("shortName") or code

        news_text = "\n".join([
            f"・{n['title']}（{n['provider']}）"
            for n in news_items if n['title']
        ]) or "ニュースなし"

        prompt = f"""
以下の株式データを分析して、必ずJSON形式のみで返してください。前置きや説明文は不要です。

銘柄名: {name}
現在株価: {current_price}
MA5: {ma5} / MA25: {ma25}
RSI(14): {rsi}
MACD: {macd}
52週高値: {high52} / 52週安値: {low52}
PER: {per} / PBR: {pbr}
時価総額: {market_cap}
配当利回り: {dividend_yield}
ROE: {roe}
売上成長率: {revenue_growth}

最近のニュース:
{news_text}

以下のJSON形式で回答してください：
{{
  "overall_score": 1〜100の整数（総合投資スコア）,
  "overall_judgment": "buy" か "sell" か "hold" か "watch" のいずれか,
  "overall_reason": "総合判断の理由を2〜3文で（日本語）",
  "news_summary": "ニュース全体の要約を2〜3文で（日本語）",
  "news_sentiment": "positive" か "negative" か "neutral" のいずれか,
  "news_sentiment_reason": "ニュースのセンチメント判断理由（日本語）",
  "risks": ["リスク1（日本語）", "リスク2（日本語）"],
  "opportunities": ["機会1（日本語）", "機会2（日本語）"]
}}
"""

        model = genai.GenerativeModel("gemini-2.5-flash")
        response = model.generate_content(
            [{"role": "user", "parts": [{"text": prompt}]}]
        )
        raw = response.text.strip()
        raw = raw.replace("```json", "").replace("```", "").strip()
        analysis = json.loads(raw)

        return {
            "code": code,
            "name": name,
            "price": current_price,
            "ma5": ma5,
            "ma25": ma25,
            "rsi": rsi,
            "macd": macd,
            "high52": high52,
            "low52": low52,
            "per": per,
            "pbr": pbr,
            "market_cap": market_cap,
            "dividend_yield": dividend_yield,
            "roe": roe,
            "revenue_growth": revenue_growth,
            "news": news_items,
            "analysis": analysis,
        }

    except Exception as e:
        print(f"AI分析エラー: {e}")
        return {"error": str(e)}


# ===================================================
# マーケットイベント取得API
# ===================================================

@app.get("/market/events")
def get_market_events(year: int, month: int):
    """
    指定年月のマーケットイベントを取得
    - 日本の祝日（jpholiday）
    - 米国市場休場日（exchange-calendars）
    - 満月・新月（ephem）
    - SQ・メジャーSQ（計算）
    - 権利落ち日（計算）
    - FOMC・日銀（固定データ）
    - 米雇用統計（毎月第1金曜）
    """
    import datetime
    import ephem
    import jpholiday
    import exchange_calendars as xcals

    results = []

    # ── 日本の祝日（jpholiday） ──
    first = datetime.date(year, month, 1)
    last_day = (datetime.date(year, month + 1, 1) - datetime.timedelta(days=1)) if month < 12 else datetime.date(year, 12, 31)
    d = first
    while d <= last_day:
        if jpholiday.is_holiday(d):
            name = jpholiday.is_holiday_name(d)
            results.append({
                "date": str(d),
                "label": f"🇯🇵 {name}",
                "type": "holiday_jp",
                "color": "pink",
            })
        d += datetime.timedelta(days=1)

    # ── 米国市場休場日（exchange-calendars） ──
    try:
        xnys = xcals.get_calendar("XNYS")
        month_start = f"{year}-{str(month).zfill(2)}-01"
        month_end = str(last_day)
        sessions = xnys.sessions_in_range(month_start, month_end)
        all_weekdays = []
        d = first
        while d <= last_day:
            if d.weekday() < 5:  # 月〜金
                all_weekdays.append(str(d))
            d += datetime.timedelta(days=1)
        session_strs = [str(s.date()) for s in sessions]
        for wd in all_weekdays:
            if wd not in session_strs:
                results.append({
                    "date": wd,
                    "label": "🇺🇸 米国市場休場",
                    "type": "holiday_us",
                    "color": "blueGrey",
                })
    except Exception as e:
        print(f"米国休場日取得エラー: {e}")

    # ── 満月・新月（ephem） ──
    try:
        d = first
        while d <= last_day:
            dt = datetime.datetime(d.year, d.month, d.day)
            # 新月チェック
            prev_new = ephem.previous_new_moon(dt)
            next_new = ephem.next_new_moon(dt)
            prev_new_date = ephem.Date(prev_new).datetime().date()
            next_new_date = ephem.Date(next_new).datetime().date()
            if prev_new_date == d or next_new_date == d:
                results.append({
                    "date": str(d),
                    "label": "🌑 新月",
                    "type": "new_moon",
                    "color": "grey",
                })
            # 満月チェック
            prev_full = ephem.previous_full_moon(dt)
            next_full = ephem.next_full_moon(dt)
            prev_full_date = ephem.Date(prev_full).datetime().date()
            next_full_date = ephem.Date(next_full).datetime().date()
            if prev_full_date == d or next_full_date == d:
                results.append({
                    "date": str(d),
                    "label": "🌕 満月",
                    "type": "full_moon",
                    "color": "amber",
                })
            d += datetime.timedelta(days=1)
    except Exception as e:
        print(f"月齢取得エラー: {e}")

    # ── SQ・メジャーSQ（第2金曜） ──
    fri_count = 0
    d = first
    while d <= last_day:
        if d.weekday() == 4:  # 金曜
            fri_count += 1
            if fri_count == 2:
                is_major = month in [3, 6, 9, 12]
                results.append({
                    "date": str(d),
                    "label": "メジャーSQ" if is_major else "SQ",
                    "type": "major_sq" if is_major else "sq",
                    "color": "deepOrange" if is_major else "orange",
                })
                break
        d += datetime.timedelta(days=1)

    # ── 米雇用統計（第1金曜） ──
    d = first
    while d <= last_day:
        if d.weekday() == 4:  # 金曜
            results.append({
                "date": str(d),
                "label": "🇺🇸 米雇用統計",
                "type": "jobs",
                "color": "teal",
            })
            break
        d += datetime.timedelta(days=1)

    # ── 権利落ち日（月末から2営業日前） ──
    biz_count = 0
    d = last_day
    while biz_count < 2:
        if d.weekday() < 5:
            biz_count += 1
            if biz_count < 2:
                d -= datetime.timedelta(days=1)
        else:
            d -= datetime.timedelta(days=1)
    results.append({
        "date": str(d),
        "label": "権利落ち日（目安）",
        "type": "rights",
        "color": "indigo",
    })

    # ── FOMC（固定データ・年1回更新） ──
    fomc = {
        "2025-01-29", "2025-03-19", "2025-05-07", "2025-06-18",
        "2025-07-30", "2025-09-17", "2025-10-29", "2025-12-10",
        "2026-01-28", "2026-03-18", "2026-04-29", "2026-06-17",
        "2026-07-29", "2026-09-16", "2026-10-28", "2026-12-09",
    }
    prefix = f"{year}-{str(month).zfill(2)}"
    for date_str in fomc:
        if date_str.startswith(prefix):
            results.append({
                "date": date_str,
                "label": "FOMC 結果発表",
                "type": "fomc",
                "color": "purple",
            })

    # ── 日銀金融政策決定会合（固定データ・年1回更新） ──
    boj = {
        "2025-01-24", "2025-03-19", "2025-05-01", "2025-06-17",
        "2025-07-31", "2025-09-19", "2025-10-29", "2025-12-19",
        "2026-01-23", "2026-03-19", "2026-04-28", "2026-06-16",
        "2026-07-30", "2026-09-17", "2026-10-28", "2026-12-18",
    }
    for date_str in boj:
        if date_str.startswith(prefix):
            results.append({
                "date": date_str,
                "label": "日銀 政策金利発表",
                "type": "boj",
                "color": "brown",
            })

    return results

# ===================================================
# 日経平均月次データAPI
# ===================================================

@app.get("/nikkei/monthly")
def get_nikkei_monthly(year: int, month: int):
    """
    指定年月の日経平均の日次騰落データを返す
    """
    import datetime
    try:
        ticker = yf.Ticker("^N225")
        # 前月末も含めて取得（前日比計算のため）
        start = datetime.date(year, month, 1) - datetime.timedelta(days=5)
        end   = datetime.date(year, month + 1, 1) if month < 12 \
                else datetime.date(year + 1, 1, 1)
        hist  = ticker.history(start=str(start), end=str(end))

        result = {}
        prev_close = None
        for date, row in hist.iterrows():
            close = round(float(row["Close"]), 2)
            date_str = str(date.date())
            if prev_close is not None and date_str.startswith(
                f"{year}-{str(month).zfill(2)}"
            ):
                change     = round(close - prev_close, 2)
                change_pct = round((change / prev_close) * 100, 2)
                result[date_str] = {
                    "close":      close,
                    "change":     change,
                    "change_pct": change_pct,
                }
            prev_close = close

        return result
    except Exception as e:
        print(f"日経平均取得エラー: {e}")
        return {}

# ===================================================
# AI相談API
# ===================================================

@app.post("/stock/consult")
async def stock_consult(request: Request):
    """
    チェックボックスで選択した条件をもとにChatGPTに相談
    """
    body = await request.json()
    code            = body.get("code", "")
    name            = body.get("name", "")
    direction       = body.get("direction", "")       # 買い / 売り
    trade_type      = body.get("trade_type", "")      # 現物 / 信用
    period          = body.get("period", "")          # 短期 / 中期 / 長期
    extra_questions = body.get("extra_questions", []) # 追加質問リスト

    # 株価データ
    price      = body.get("price")
    rsi        = body.get("rsi")
    macd       = body.get("macd")
    ma5        = body.get("ma5")
    ma25       = body.get("ma25")
    per        = body.get("per")
    pbr        = body.get("pbr")
    roe        = body.get("roe")
    high52     = body.get("high52")
    low52      = body.get("low52")

    extra_text = ""
    if "損切りライン" in extra_questions:
        extra_text += "\n・損切りラインの目安はどこか？"
    if "ファンダメンタル" in extra_questions:
        extra_text += "\n・ファンダメンタル的な評価はどうか？"
    if "リスク" in extra_questions:
        extra_text += "\n・主なリスクは何か？"
    if "他銘柄比較" in extra_questions:
        extra_text += "\n・同業他社と比べて優位性はあるか？"

    prompt = f"""
あなたは株式投資の専門アドバイザーです。以下の条件と株価データをもとに、具体的なアドバイスをしてください。

【銘柄】{name}（{code}）
【相談内容】{direction}・{trade_type}・{period}の場合、この銘柄はどうか？{extra_text}

【株価データ】
現在株価: {price}円
MA5: {ma5} / MA25: {ma25}
RSI: {rsi}
MACD: {macd}
52週高値: {high52} / 52週安値: {low52}
PER: {per}倍 / PBR: {pbr}倍 / ROE: {roe}

以下の形式で日本語で回答してください：
{{
  "judgment": "適切" か "要注意" か "不適切" のいずれか,
  "judgment_reason": "判断理由を2〜3文で",
  "advice": "具体的なアドバイスを3〜5文で",
  "caution": "注意点を2〜3文で",
  "stop_loss": "損切りラインの目安（損切りラインの質問がある場合のみ、ない場合は空文字）",
  "fundamental_comment": "ファンダメンタルコメント（ファンダ質問がある場合のみ、ない場合は空文字）"
}}
"""

    try:
        res = openai_client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "あなたは日本株・米国株に詳しい投資アドバイザーです。必ずJSON形式のみで返してください。"},
                {"role": "user",   "content": prompt}
            ],
            max_tokens=1000,
        )
        raw = res.choices[0].message.content.strip()
        raw = raw.replace("```json", "").replace("```", "").strip()
        return json.loads(raw)
    except Exception as e:
        return {"error": str(e)}


# ===================================================
# セクタートレンドAPI
# ===================================================

@app.get("/market/sectors")
def get_sector_trends(period: str = "5d"):
    """
    日本・米国の主要セクターETFの騰落を取得して返す
    """
    import datetime

    # 日本セクターETF（東証ETF）
    jp_sectors = {
        "銀行":       "1615.T",
        "電気機器":   "1617.T",
        "自動車":     "1622.T",
        "不動産":     "1621.T",
        "食品":       "1619.T",
        "医薬品":     "1620.T",
        "情報通信":   "1618.T",
        "素材":       "1623.T",
        "鉄鋼・非鉄": "1629.T",
        "化学":       "1624.T",
        "機械":       "1625.T",
        "小売":       "1626.T",
        "サービス":   "1627.T",
        "海運・空運": "1628.T",
        "鉱業":       "1630.T",
        "建設":       "1631.T",
        "水産・農林": "1633.T",
    }

    # 米国セクターETF（SPDR）
    us_sectors = {
        "テクノロジー":   "XLK",
        "ヘルスケア":     "XLV",
        "金融":           "XLF",
        "エネルギー":     "XLE",
        "一般消費財":     "XLY",
        "生活必需品":     "XLP",
        "公益":           "XLU",
        "不動産(US)":     "XLRE",
        "素材(US)":       "XLB",
        "通信":           "XLC",
        "資本財":         "XLI",
        "AI/半導体":      "SOXX",
    }

    result = {"jp": [], "us": []}

    for name, ticker_code in {**jp_sectors, **us_sectors}.items():
        try:
            ticker = yf.Ticker(ticker_code)
            hist = ticker.history(period="1mo" if period == "1mo" else "6d")
            if len(hist) < 2:
                continue
            prev  = float(hist["Close"].iloc[-2])
            close = float(hist["Close"].iloc[-1])
            change     = round(close - prev, 2)
            change_pct = round((change / prev) * 100, 2)

            # 5日トレンド
            trend_5d = round(
                (close - float(hist["Close"].iloc[0])) / float(hist["Close"].iloc[0]) * 100, 2
            ) if len(hist) >= 5 else change_pct

            item = {
                "name":       name,
                "ticker":     ticker_code,
                "change_pct": change_pct,
                "trend_5d":   trend_5d,
                "trend": round(
                    (close - float(hist["Close"].iloc[0])) / float(hist["Close"].iloc[0]) * 100, 2
                ) if len(hist) >= 2 else change_pct,
            }

            if ticker_code in us_sectors.values():
                result["us"].append(item)
            else:
                result["jp"].append(item)
        except Exception as e:
            print(f"セクター取得エラー {ticker_code}: {e}")

    # 騰落率でソート
    result["jp"].sort(key=lambda x: x["change_pct"], reverse=True)
    result["us"].sort(key=lambda x: x["change_pct"], reverse=True)

    return result


# ===================================================
# AI診断API
# ===================================================
# ===================================================
# データ取得ユーティリティ
# ===================================================

def safe_float(val, digits=2):
    """安全にfloatに変換。失敗したらNoneを返す"""
    try:
        return round(float(val), digits)
    except:
        return None


def get_latest_price(ticker_code: str):
    """直近終値を取得"""
    try:
        t = yf.Ticker(ticker_code)
        hist = t.history(period="3d")
        if not hist.empty:
            return round(float(hist["Close"].iloc[-1]), 2)
    except:
        pass
    return None


def get_trend_label(ticker_code: str, period: str = "5d") -> str:
    """
    指定期間のトレンドをラベルで返す
    例：「上昇トレンド（+2.3%）」
    """
    try:
        t = yf.Ticker(ticker_code)
        hist = t.history(period=period)
        if len(hist) >= 2:
            pct = (
                float(hist["Close"].iloc[-1]) - float(hist["Close"].iloc[0])
            ) / float(hist["Close"].iloc[0]) * 100
            if pct > 1:
                return f"上昇トレンド（+{pct:.1f}%）"
            elif pct < -1:
                return f"下落トレンド（{pct:.1f}%）"
            else:
                return f"横ばい（{pct:.1f}%）"
    except:
        pass
    return None


def get_macro_data() -> dict:
    """
    マクロ指標を一括取得（DynamoDBに15分キャッシュ）
    """
    # キャッシュ確認
    cached = cache_get(market_cache_table, {'cache_key': 'macro'})
    if cached:
        print("マクロ: キャッシュヒット")
        return cached

    print("マクロ: yfinanceから取得")
    macro = {
        "vix":          get_latest_price("^VIX"),
        "us10y":        get_latest_price("^TNX"),
        "us2y":         get_latest_price("^IRX"),
        "usd_jpy":      get_latest_price("USDJPY=X"),
        "dxy":          get_latest_price("DX-Y.NYB"),
        "oil_price":    get_latest_price("CL=F"),
        "gold_price":   get_latest_price("GC=F"),
        "nikkei_trend": get_trend_label("^N225"),
        "sp500_trend":  get_trend_label("^GSPC"),
    }

    # 金利差（逆イールド判定）
    if macro["us2y"] and macro["us10y"]:
        macro["yield_spread"] = round(macro["us10y"] - macro["us2y"], 3)
    else:
        macro["yield_spread"] = None

    # 15分キャッシュ
    cache_set(market_cache_table, {'cache_key': 'macro'}, macro, ttl_minutes=15)
    return macro


def get_nikkei225_breadth() -> dict:
    """
    日経225の騰落レシオ・上昇下落銘柄数を計算（DynamoDBに8時間キャッシュ）
    """
    # キャッシュ確認
    cached = cache_get(market_cache_table, {'cache_key': 'breadth'})
    if cached:
        print("騰落レシオ: キャッシュヒット")
        return cached

    print("騰落レシオ: yfinanceから計算（30銘柄）")
    # 日経225構成銘柄（主要30銘柄で簡易計算）
    nikkei_sample = [
        "7203.T", "6758.T", "9984.T", "8306.T", "6861.T",
        "9432.T", "7974.T", "6367.T", "4063.T", "8316.T",
        "6501.T", "6702.T", "7267.T", "4543.T", "9433.T",
        "8035.T", "6752.T", "2914.T", "4452.T", "7751.T",
        "6954.T", "4519.T", "9022.T", "8411.T", "5108.T",
        "6503.T", "7733.T", "4568.T", "6971.T", "9020.T",
    ]
    try:
        data = yf.download(nikkei_sample, period="3d", progress=False)
        close = data["Close"]
        change = close.pct_change().iloc[-1]
        advancers = int((change > 0).sum())
        decliners = int((change < 0).sum())
        ratio = round(advancers / decliners, 2) if decliners > 0 else None
        result = {
            "advancers": advancers,
            "decliners": decliners,
            "advance_decline_ratio": ratio,
        }
        # 8時間キャッシュ（翌営業日まで有効）
        cache_set(market_cache_table, {'cache_key': 'breadth'}, result, ttl_minutes=480)
        return result
    except:
        return {
            "advancers": None,
            "decliners": None,
            "advance_decline_ratio": None,
        }


def get_technical_data(ticker_code: str) -> dict:
    """
    テクニカル指標を計算して返す（DynamoDBに4時間キャッシュ）
    """
    # キャッシュ確認
    cached = cache_get(stock_cache_table, {'code': ticker_code, 'cache_type': 'technical'})
    if cached:
        print(f"テクニカル {ticker_code}: キャッシュヒット")
        return cached

    print(f"テクニカル {ticker_code}: yfinanceから計算")
    try:
        t = yf.Ticker(ticker_code)
        hist = t.history(period="6mo")
        if len(hist) < 30:
            return {}

        close = hist["Close"]
        volume = hist["Volume"]

        # 移動平均
        ma5  = safe_float(close.rolling(5).mean().iloc[-1])
        ma25 = safe_float(close.rolling(25).mean().iloc[-1])
        ma75 = safe_float(close.rolling(75).mean().iloc[-1]) if len(close) >= 75 else None

        # RSI
        delta = close.diff()
        gain  = delta.clip(lower=0).rolling(14).mean()
        loss  = (-delta.clip(upper=0)).rolling(14).mean()
        rs    = gain / loss
        rsi   = safe_float(100 - (100 / (1 + rs.iloc[-1])))

        # MACD
        ema12      = close.ewm(span=12).mean()
        ema26      = close.ewm(span=26).mean()
        macd_line  = ema12 - ema26
        signal     = macd_line.ewm(span=9).mean()
        macd_hist  = macd_line - signal
        macd_val   = safe_float(macd_line.iloc[-1])
        macd_sig   = safe_float(signal.iloc[-1])
        macd_h     = safe_float(macd_hist.iloc[-1])

        # ボリンジャーバンド
        ma20      = close.rolling(20).mean()
        std20     = close.rolling(20).std()
        bb_upper  = safe_float((ma20 + 2 * std20).iloc[-1])
        bb_mid    = safe_float(ma20.iloc[-1])
        bb_lower  = safe_float((ma20 - 2 * std20).iloc[-1])

        # ATR
        high  = hist["High"]
        low   = hist["Low"]
        tr    = pd.concat([
            high - low,
            (high - close.shift()).abs(),
            (low  - close.shift()).abs(),
        ], axis=1).max(axis=1)
        atr   = safe_float(tr.rolling(14).mean().iloc[-1])

        # 出来高移動平均比
        vol_ma20   = volume.rolling(20).mean()
        vol_ratio  = safe_float(volume.iloc[-1] / vol_ma20.iloc[-1])

        # OBV
        obv = (np.sign(close.diff()) * volume).fillna(0).cumsum()
        obv_val = safe_float(obv.iloc[-1])

        # ストキャスティクス
        low14  = low.rolling(14).min()
        high14 = high.rolling(14).max()
        stoch_k = safe_float(((close - low14) / (high14 - low14) * 100).iloc[-1])

        # ADX（簡易計算）
        plus_dm  = high.diff().clip(lower=0)
        minus_dm = (-low.diff()).clip(lower=0)
        tr_adx   = tr.rolling(14).mean()
        plus_di  = safe_float((plus_dm.rolling(14).mean()  / tr_adx * 100).iloc[-1])
        minus_di = safe_float((minus_dm.rolling(14).mean() / tr_adx * 100).iloc[-1])
        if plus_di and minus_di:
            dx  = abs(plus_di - minus_di) / (plus_di + minus_di) * 100
            adx = safe_float(dx)
        else:
            adx = None

        # 52週レンジ位置
        week52_high = safe_float(close.tail(252).max())
        week52_low  = safe_float(close.tail(252).min())
        current     = safe_float(close.iloc[-1])
        if week52_high and week52_low and (week52_high - week52_low) > 0:
            range_position = safe_float(
                (current - week52_low) / (week52_high - week52_low) * 100
            )
        else:
            range_position = None

        # モメンタム
        momentum_1m  = safe_float((close.iloc[-1] / close.iloc[-21] - 1) * 100) if len(close) >= 21  else None
        momentum_3m  = safe_float((close.iloc[-1] / close.iloc[-63] - 1) * 100) if len(close) >= 63  else None
        momentum_6m  = safe_float((close.iloc[-1] / close.iloc[-126] - 1) * 100) if len(close) >= 126 else None

        result = {
            "price":          current,
            "ma5":            ma5,
            "ma25":           ma25,
            "ma75":           ma75,
            "rsi":            rsi,
            "macd":           macd_val,
            "macd_signal":    macd_sig,
            "macd_hist":      macd_h,
            "bb_upper":       bb_upper,
            "bb_mid":         bb_mid,
            "bb_lower":       bb_lower,
            "atr":            atr,
            "volume_ratio":   vol_ratio,
            "obv":            obv_val,
            "stoch_k":        stoch_k,
            "adx":            adx,
            "week52_high":    week52_high,
            "week52_low":     week52_low,
            "range_position": range_position,
            "momentum_1m":    momentum_1m,
            "momentum_3m":    momentum_3m,
            "momentum_6m":    momentum_6m,
        }
        # 4時間キャッシュ
        cache_set(stock_cache_table,
                  {'code': ticker_code, 'cache_type': 'technical'},
                  result, ttl_minutes=240)
        return result
    except Exception as e:
        print(f"テクニカル計算エラー: {e}")
        return {}


def get_fundamental_data(ticker_code: str) -> dict:
    """
    ファンダメンタル指標を取得（DynamoDBに24時間キャッシュ）
    """
    # キャッシュ確認
    cached = cache_get(stock_cache_table, {'code': ticker_code, 'cache_type': 'fundamental'})
    if cached:
        print(f"ファンダ {ticker_code}: キャッシュヒット")
        return cached

    print(f"ファンダ {ticker_code}: yfinanceから取得")
    try:
        t    = yf.Ticker(ticker_code)
        info = t.info
        result = {
            "per":             safe_float(info.get("trailingPE")),
            "pbr":             safe_float(info.get("priceToBook")),
            "roe":             safe_float(info.get("returnOnEquity",  0) * 100) if info.get("returnOnEquity")  else None,
            "roa":             safe_float(info.get("returnOnAssets",  0) * 100) if info.get("returnOnAssets")  else None,
            "revenue_growth":  safe_float(info.get("revenueGrowth",  0) * 100) if info.get("revenueGrowth")   else None,
            "eps_growth":      safe_float(info.get("earningsGrowth", 0) * 100) if info.get("earningsGrowth")  else None,
            "operating_margin":safe_float(info.get("operatingMargins",0) * 100) if info.get("operatingMargins") else None,
            "debt_ratio":      safe_float(info.get("debtToEquity")),
            "equity_ratio":    safe_float(info.get("bookValue")),
            "dividend_yield":  safe_float(info.get("dividendYield", 0) * 100) if info.get("dividendYield") else None,
            "fcf":             info.get("freeCashflow"),
            "target_price":    safe_float(info.get("targetMeanPrice")),
            "analyst_rating":  info.get("recommendationKey"),
        }
        # 24時間キャッシュ（ファンダは変化が少ない）
        cache_set(stock_cache_table,
                  {'code': ticker_code, 'cache_type': 'fundamental'},
                  result, ttl_minutes=1440)
        return result
    except Exception as e:
        print(f"ファンダ取得エラー: {e}")
        return {}


def get_earnings_alert(earnings_date_str: str, period: str) -> dict:
    """
    決算アラートレベルを判定
    period: "短期" / "中期" / "長期"
    """
    if not earnings_date_str or earnings_date_str == "なし":
        return {
            "exists":  False,
            "date":    None,
            "level":   "safe",
            "message": None,
        }

    try:
        from datetime import datetime, date
        earnings_date = datetime.strptime(earnings_date_str, "%Y-%m-%d").date()
        today         = date.today()
        days_to       = (earnings_date - today).days

        if days_to < 0:
            return {
                "exists":  False,
                "date":    None,
                "level":   "safe",
                "message": None,
            }

        # 期間別の閾値
        if period == "短期":
            danger_days  = 7
            caution_days = 14
        elif period == "中期":
            danger_days  = 14
            caution_days = 30
        else:
            # 長期は決算アラート不要
            return {
                "exists":  False,
                "date":    None,
                "level":   "safe",
                "message": None,
            }

        if days_to <= danger_days:
            level   = "danger"
            message = f"{earnings_date_str}（{days_to}日後）に決算発表があります。急騰・急落リスクが高いため慎重に判断してください。"
        elif days_to <= caution_days:
            level   = "caution"
            message = f"{earnings_date_str}（{days_to}日後）に決算発表があります。決算内容次第でトレンドが変わる可能性があります。"
        else:
            level   = "safe"
            message = f"{earnings_date_str}（{days_to}日後）に決算予定があります。"

        return {
            "exists":  True,
            "date":    earnings_date_str,
            "days_to": days_to,
            "level":   level,
            "message": message,
        }
    except:
        return {
            "exists":  False,
            "date":    None,
            "level":   "safe",
            "message": None,
        }


# ===================================================
# プロンプト生成
# ===================================================

def fmt(val, suffix="", null_str="データなし"):
    """値をフォーマット。Noneならnull_strを返す"""
    if val is None:
        return null_str
    return f"{val}{suffix}"


def build_short_prompt(name, code, tech, fund, macro, breadth,
                       earnings_alert, news_summary, score, user_profile) -> str:
    return f"""
あなたは日本株の短期スイングトレード専門アナリストです。
以下のデータを元に{name}（{code}）が1〜2週間で「上昇・様子見・下落」のどれになるかを確率ベースで判断してください。

【前提】
- テクニカル・需給・市場環境・マクロを最優先
- ファンダは参考程度
- すべての判断には具体的な数値を引用した理由を付ける（3文以上）
- 確率の合計は必ず100にすること
- リスク許容度が低い場合は様子見寄りに補正すること
- JSONのみ出力（前置き・説明文禁止）

【ユーザープロファイル】
- リスク許容度：{user_profile.get('risk_level', '中')}
- 分析スタイル：{user_profile.get('analysis_style', 'バランス型')}

【テクニカル】
- 現在株価：{fmt(tech.get('price'), '円')}
- RSI(14)：{fmt(tech.get('rsi'))}
  ※70以上=買われすぎ・反落リスク／50〜70=上昇継続／30〜50=弱含み／30以下=売られすぎ・反発期待
- MACD：{fmt(tech.get('macd'))} / シグナル：{fmt(tech.get('macd_signal'))} / ヒストグラム：{fmt(tech.get('macd_hist'))}
  ※MACDがシグナルを上回る=上昇シグナル／ヒストグラム拡大=トレンド強化
- ボリンジャー：上{fmt(tech.get('bb_upper'), '円')} 中{fmt(tech.get('bb_mid'), '円')} 下{fmt(tech.get('bb_lower'), '円')}
  ※上限付近=反落リスク／下限付近=反発期待
- MA5：{fmt(tech.get('ma5'), '円')} / MA25：{fmt(tech.get('ma25'), '円')}
  ※MA5がMA25を上回る=ゴールデンクロス／下回る=デッドクロス
- ストキャス(K)：{fmt(tech.get('stoch_k'))}
  ※80以上=買われすぎ／20以下=売られすぎ
- OBV：{fmt(tech.get('obv'))}
  ※上昇トレンドなら出来高が伴っているか確認
- ATR：{fmt(tech.get('atr'), '円')}
  ※ボラティリティの目安
- 出来高移動平均比：{fmt(tech.get('volume_ratio'), '倍')}
  ※1.5倍以上=注目度高い／0.5倍以下=閑散
- 52週レンジ位置：{fmt(tech.get('range_position'), '%')}
  ※0%=52週安値／100%=52週高値／30%以下=底値圏／70%以上=高値圏

【需給】
- 信用倍率：{fmt(macro.get('margin_ratio'), '倍')}
  ※倍率高い=将来の売り圧力
- 空売り比率：{fmt(macro.get('short_ratio'), '%')}
  ※高い=弱気筋が多い

【市場内部】
- 騰落レシオ：{fmt(breadth.get('advance_decline_ratio'))}
  ※120以上=過熱感／70以下=売られすぎ
- 上昇銘柄数：{fmt(breadth.get('advancers'))} / 下落銘柄数：{fmt(breadth.get('decliners'))}

【ファンダ（参考）】
- PER：{fmt(fund.get('per'), '倍')} / PBR：{fmt(fund.get('pbr'), '倍')}
- ROE：{fmt(fund.get('roe'), '%')}
- 売上成長率：{fmt(fund.get('revenue_growth'), '%')}

【市場環境】
- 日経平均トレンド：{fmt(macro.get('nikkei_trend'))}
- VIX：{fmt(macro.get('vix'))}
  ※20以下=安定／20〜30=やや不安定／30以上=恐怖状態
- 米10年債：{fmt(macro.get('us10y'), '%')}
  ※金利上昇=グロース株逆風
- ドル円：{fmt(macro.get('usd_jpy'), '円')}
  ※円安=輸出株有利／円高=輸入株有利
- S&P500トレンド：{fmt(macro.get('sp500_trend'))}

【マクロ指標】
- DXY（ドル指数）：{fmt(macro.get('dxy'))}
- 原油：{fmt(macro.get('oil_price'), 'ドル')}
- 金：{fmt(macro.get('gold_price'), 'ドル')}
  ※金上昇=リスクオフの指標

【決算アラート】
- 決算日：{fmt(earnings_alert.get('date'))}
- 残り日数：{fmt(earnings_alert.get('days_to'), '日')}
- アラートレベル：{earnings_alert.get('level', 'safe')}
  ※danger=7日以内（急騰・急落リスク大）／caution=14日以内（注意）／safe=当面なし
  ※リスク許容度が低い場合はdanger・cautionで様子見を強く推奨

【ニュース】
{news_summary}

【参考スコア】
- 総合スコア：{fmt(score, '点')}
  ※スコアは参考情報として扱い再計算・変更はしない

以下のJSON形式のみで回答（他のテキスト禁止）：
{{
  "verdict": {{ "value": "up/sideways/down", "reason": "3〜5文で数値を引用して具体的に" }},
  "probability": {{
    "up":       {{ "value": 上昇確率(整数0〜100), "reason": "3文以上で具体的に" }},
    "sideways": {{ "value": 横ばい確率(整数0〜100), "reason": "3文以上で具体的に" }},
    "down":     {{ "value": 下落確率(整数0〜100), "reason": "3文以上で具体的に" }}
  }},
  "confidence": {{ "value": "high/medium/low", "reason": "2〜3文で" }},
  "earnings_alert": {{
    "exists":  {str(earnings_alert.get('exists', False)).lower()},
    "date":    {json.dumps(earnings_alert.get('date'), ensure_ascii=False)},
    "level":   "{earnings_alert.get('level', 'safe')}",
    "message": {json.dumps(earnings_alert.get('message'), ensure_ascii=False)}
  }},
  "macro_analysis": {{
    "risk_mode":            {{ "value": "risk_on/risk_off/neutral", "reason": "VIX・米株から3文で" }},
    "usd_jpy_impact":       {{ "value": "positive/negative/neutral", "reason": "2〜3文で" }},
    "interest_rate_impact": {{ "value": "positive/negative/neutral", "reason": "2〜3文で" }}
  }},
  "supply_demand": {{
    "bias": {{ "value": "bullish/bearish/neutral", "reason": "信用倍率・空売り比率から2〜3文で" }}
  }},
  "price_strategy": {{
    "entry":       {{ "value": "具体的な価格帯（例：2450〜2500円）", "reason": "3〜4文で" }},
    "stop_loss":   {{ "value": 損切り価格(数値), "reason": "3〜4文で" }},
    "take_profit": {{ "value": 利確価格(数値), "reason": "3〜4文で" }}
  }},
  "positive_points": ["上昇根拠1（指標名と数値を含め2文以上）", "上昇根拠2", "上昇根拠3"],
  "negative_points": ["下落リスク1（指標名と数値を含め2文以上）", "下落リスク2", "下落リスク3"],
  "summary": "5〜8文で具体的な数値を交えた総合サマリー"
}}
""".strip()


def build_medium_prompt(name, code, tech, fund, macro, breadth,
                        earnings_alert, news_summary, score, user_profile) -> str:
    return f"""
あなたは日本株の中期投資（1〜3ヶ月）専門アナリストです。
以下のデータを元に{name}（{code}）が1〜3ヶ月で「上昇・様子見・下落」のどれになるかを確率ベースで判断してください。

【前提】
- テクニカルのトレンド継続性とファンダ・マクロを同等に重視
- 短期ノイズより中期トレンドを優先
- すべての判断には具体的な数値を引用した理由を付ける（3文以上）
- 確率の合計は必ず100にすること
- JSONのみ出力（前置き・説明文禁止）

【ユーザープロファイル】
- リスク許容度：{user_profile.get('risk_level', '中')}
- 分析スタイル：{user_profile.get('analysis_style', 'バランス型')}

【テクニカル（トレンド重視）】
- 現在株価：{fmt(tech.get('price'), '円')}
- MA25：{fmt(tech.get('ma25'), '円')} / MA75：{fmt(tech.get('ma75'), '円')}
  ※MA25がMA75を上回る=中期上昇トレンド
- MACD：{fmt(tech.get('macd'))} / シグナル：{fmt(tech.get('macd_signal'))} / ヒストグラム：{fmt(tech.get('macd_hist'))}
- ADX：{fmt(tech.get('adx'))}
  ※25以上=トレンド強い／25以下=方向感なし
- OBV：{fmt(tech.get('obv'))}
- 出来高移動平均比：{fmt(tech.get('volume_ratio'), '倍')}
- 52週レンジ位置：{fmt(tech.get('range_position'), '%')}
- モメンタム（1ヶ月）：{fmt(tech.get('momentum_1m'), '%')}
- モメンタム（3ヶ月）：{fmt(tech.get('momentum_3m'), '%')}

【需給】
- 信用倍率：{fmt(macro.get('margin_ratio'), '倍')}
- 空売り比率：{fmt(macro.get('short_ratio'), '%')}

【市場内部】
- 騰落レシオ：{fmt(breadth.get('advance_decline_ratio'))}
- 上昇銘柄数：{fmt(breadth.get('advancers'))} / 下落銘柄数：{fmt(breadth.get('decliners'))}

【ファンダメンタル】
- PER：{fmt(fund.get('per'), '倍')}
  ※業種平均より低い=割安
- PBR：{fmt(fund.get('pbr'), '倍')}
  ※1倍割れ=資産的に割安
- ROE：{fmt(fund.get('roe'), '%')}
  ※10%以上=資本効率良好
- ROA：{fmt(fund.get('roa'), '%')}
- 売上成長率：{fmt(fund.get('revenue_growth'), '%')}
- EPS成長率：{fmt(fund.get('eps_growth'), '%')}
- 営業利益率：{fmt(fund.get('operating_margin'), '%')}
- 配当利回り：{fmt(fund.get('dividend_yield'), '%')}

【市場環境】
- 日経平均トレンド：{fmt(macro.get('nikkei_trend'))}
- VIX：{fmt(macro.get('vix'))}
- 米10年債：{fmt(macro.get('us10y'), '%')}
- 米2年債：{fmt(macro.get('us2y'), '%')}
- 金利差（10年-2年）：{fmt(macro.get('yield_spread'), '%')}
  ※マイナス=逆イールド・景気後退シグナル
- ドル円：{fmt(macro.get('usd_jpy'), '円')}
- DXY：{fmt(macro.get('dxy'))}
- S&P500トレンド：{fmt(macro.get('sp500_trend'))}

【マクロ指標】
- 原油：{fmt(macro.get('oil_price'), 'ドル')}
- 金：{fmt(macro.get('gold_price'), 'ドル')}

【決算アラート】
- 決算日：{fmt(earnings_alert.get('date'))}
- 残り日数：{fmt(earnings_alert.get('days_to'), '日')}
- アラートレベル：{earnings_alert.get('level', 'safe')}
  ※danger=14日以内／caution=1ヶ月以内／safe=当面なし

【ニュース】
{news_summary}

【参考スコア】
- 総合スコア：{fmt(score, '点')}

以下のJSON形式のみで回答（他のテキスト禁止）：
{{
  "verdict": {{ "value": "up/sideways/down", "reason": "3〜5文で数値を引用して具体的に" }},
  "probability": {{
    "up":       {{ "value": 上昇確率(整数0〜100), "reason": "3文以上で具体的に" }},
    "sideways": {{ "value": 横ばい確率(整数0〜100), "reason": "3文以上で具体的に" }},
    "down":     {{ "value": 下落確率(整数0〜100), "reason": "3文以上で具体的に" }}
  }},
  "confidence": {{ "value": "high/medium/low", "reason": "2〜3文で" }},
  "earnings_alert": {{
    "exists":  {str(earnings_alert.get('exists', False)).lower()},
    "date":    {json.dumps(earnings_alert.get('date'), ensure_ascii=False)},
    "level":   "{earnings_alert.get('level', 'safe')}",
    "message": {json.dumps(earnings_alert.get('message'), ensure_ascii=False)}
  }},
  "trend_analysis": {{
    "strength": {{ "value": "strong/weak/neutral", "reason": "MA・ADX・モメンタムから3文で" }}
  }},
  "fundamental_analysis": {{
    "growth":    {{ "value": "high/medium/low",          "reason": "売上・EPS成長率から3文で" }},
    "valuation": {{ "value": "undervalued/fair/overvalued", "reason": "PER・PBRから3文で" }}
  }},
  "macro_analysis": {{
    "risk_mode":            {{ "value": "risk_on/risk_off/neutral", "reason": "3文で" }},
    "usd_jpy_impact":       {{ "value": "positive/negative/neutral", "reason": "2〜3文で" }},
    "interest_rate_impact": {{ "value": "positive/negative/neutral", "reason": "金利差も含め3文で" }}
  }},
  "price_outlook": {{
    "range": {{ "value": "3ヶ月の想定値幅（例：2200〜2800円）", "reason": "3〜4文で" }}
  }},
  "positive_points": ["上昇根拠1（指標名と数値を含め2文以上）", "上昇根拠2", "上昇根拠3"],
  "negative_points": ["下落リスク1（指標名と数値を含め2文以上）", "下落リスク2", "下落リスク3"],
  "summary": "5〜8文で具体的な数値を交えた総合サマリー"
}}
""".strip()


def build_long_prompt(name, code, tech, fund, macro,
                      news_summary, score, user_profile) -> str:
    return f"""
あなたは日本株の長期投資（1年以上）専門アナリストです。
以下のデータを元に{name}（{code}）が長期で「上昇・様子見・下落」のどれになるかを確率ベースで判断してください。

【前提】
- 企業の成長性・収益性・財務健全性とマクロ環境を最優先
- 短期ノイズは無視・テクニカルは参考程度
- すべての判断には具体的な数値を引用した理由を付ける（3文以上）
- 確率の合計は必ず100にすること
- JSONのみ出力（前置き・説明文禁止）

【ユーザープロファイル】
- リスク許容度：{user_profile.get('risk_level', '中')}
- 分析スタイル：{user_profile.get('analysis_style', 'バランス型')}

【ファンダメンタル（最重要）】
- PER：{fmt(fund.get('per'), '倍')}
  ※業種平均より低い=割安
- PBR：{fmt(fund.get('pbr'), '倍')}
  ※1倍割れ=資産的に割安
- ROE：{fmt(fund.get('roe'), '%')}
  ※10%以上=資本効率良好／5%以下=低効率
- ROA：{fmt(fund.get('roa'), '%')}
  ※5%以上=資産効率良好
- 売上成長率：{fmt(fund.get('revenue_growth'), '%')}
  ※プラス継続=成長トレンド
- EPS成長率：{fmt(fund.get('eps_growth'), '%')}
- 営業利益率：{fmt(fund.get('operating_margin'), '%')}
- 負債比率：{fmt(fund.get('debt_ratio'))}
  ※低いほど財務健全
- 配当利回り：{fmt(fund.get('dividend_yield'), '%')}
- FCF：{fmt(fund.get('fcf'))}
  ※プラス=キャッシュ創出力あり
- アナリスト目標株価：{fmt(fund.get('target_price'), '円')}
- アナリスト評価：{fmt(fund.get('analyst_rating'))}

【テクニカル（参考）】
- 現在株価：{fmt(tech.get('price'), '円')}
- MA75：{fmt(tech.get('ma75'), '円')}
- 52週レンジ位置：{fmt(tech.get('range_position'), '%')}
- モメンタム（3ヶ月）：{fmt(tech.get('momentum_3m'), '%')}
- モメンタム（6ヶ月）：{fmt(tech.get('momentum_6m'), '%')}
- ADX：{fmt(tech.get('adx'))}

【マクロ・市場環境】
- 日経平均トレンド：{fmt(macro.get('nikkei_trend'))}
- VIX：{fmt(macro.get('vix'))}
- 米10年債：{fmt(macro.get('us10y'), '%')}
- 米2年債：{fmt(macro.get('us2y'), '%')}
- 金利差（10年-2年）：{fmt(macro.get('yield_spread'), '%')}
  ※マイナス=逆イールド・景気後退シグナル
- ドル円：{fmt(macro.get('usd_jpy'), '円')}
- DXY：{fmt(macro.get('dxy'))}
- 原油：{fmt(macro.get('oil_price'), 'ドル')}
- 金：{fmt(macro.get('gold_price'), 'ドル')}
- S&P500トレンド：{fmt(macro.get('sp500_trend'))}

【ニュース】
{news_summary}

【参考スコア】
- 総合スコア：{fmt(score, '点')}

以下のJSON形式のみで回答（他のテキスト禁止）：
{{
  "verdict": {{ "value": "up/sideways/down", "reason": "3〜5文で数値を引用して具体的に" }},
  "probability": {{
    "up":       {{ "value": 上昇確率(整数0〜100), "reason": "3文以上で具体的に" }},
    "sideways": {{ "value": 横ばい確率(整数0〜100), "reason": "3文以上で具体的に" }},
    "down":     {{ "value": 下落確率(整数0〜100), "reason": "3文以上で具体的に" }}
  }},
  "confidence": {{ "value": "high/medium/low", "reason": "2〜3文で" }},
  "fundamental_analysis": {{
    "growth":       {{ "value": "high/medium/low", "reason": "売上・EPS成長率から3文で" }},
    "profitability":{{ "value": "high/medium/low", "reason": "ROE・営業利益率から3文で" }},
    "financial_health": {{ "value": "strong/neutral/weak", "reason": "負債比率・FCFから3文で" }},
    "valuation":    {{ "value": "undervalued/fair/overvalued", "reason": "PER・PBRから3文で" }}
  }},
  "macro_analysis": {{
    "risk_mode":            {{ "value": "risk_on/risk_off/neutral", "reason": "3文で" }},
    "interest_rate_impact": {{ "value": "positive/negative/neutral", "reason": "金利差も含め3文で" }},
    "usd_jpy_impact":       {{ "value": "positive/negative/neutral", "reason": "2〜3文で" }}
  }},
  "price_outlook": {{
    "target_trend": {{ "value": "uptrend/sideways/downtrend", "reason": "長期的な方向性を3〜4文で" }}
  }},
  "long_term_risk": {{ "value": "high/medium/low", "reason": "長期リスクを3文で" }},
  "positive_points": ["上昇根拠1（指標名と数値を含め2文以上）", "上昇根拠2", "上昇根拠3"],
  "negative_points": ["下落リスク1（指標名と数値を含め2文以上）", "下落リスク2", "下落リスク3"],
  "summary": "5〜8文で長期投資家向けの具体的な総合サマリー"
}}
""".strip()


# ===================================================
# メインエンドポイント（swing_analysis 置き換え）
# ===================================================

@app.post("/stock/swing_analysis")
async def swing_analysis(request: Request):
    """
    AI診断（短期・中期・長期）
    - tech/fund/macro/breadth を ThreadPoolExecutor で並列取得
    - DynamoDBキャッシュ対応済み
    - エラーメッセージを日本語化
    """
    body = await request.json()

    # 基本情報
    code   = body.get("code", "")
    name   = body.get("name", "")
    period = body.get("period", "短期")  # 短期 / 中期 / 長期

    # ユーザープロファイル
    user_profile = {
        "risk_level":     body.get("risk_level", "中"),
        "analysis_style": body.get("analysis_style", "バランス型"),
    }

    # ニュース
    news_list = body.get("news", [])
    news_summary = "\n".join([
        f"・{n.get('title', '')}"
        for n in news_list[:5] if n.get("title")
    ]) or "なし"

    # 決算日
    earnings_date_str    = body.get("earnings_date", "")
    dividend_record_date = body.get("dividend_record_date", "")
    score                = body.get("score")

    # ticker_code 正規化
    ticker_code = body.get("ticker_code") or (
        f"{code}.T" if len(code) == 4 and code.isdigit() else code
    )

    # ── データ取得（4関数を並列実行）──
    loop = asyncio.get_event_loop()
    with ThreadPoolExecutor(max_workers=4) as executor:
        tech_f    = loop.run_in_executor(executor, get_technical_data,   ticker_code)
        fund_f    = loop.run_in_executor(executor, get_fundamental_data, ticker_code)
        macro_f   = loop.run_in_executor(executor, get_macro_data)
        breadth_f = loop.run_in_executor(executor, get_nikkei225_breadth)
        tech, fund, macro, breadth = await asyncio.gather(
            tech_f, fund_f, macro_f, breadth_f
        )

    # 信用残・空売り（フロントから渡すか、後でバッチ化）
    macro["margin_ratio"] = body.get("margin_ratio")
    macro["short_ratio"]  = body.get("short_ratio")

    # 決算アラート判定
    earnings_alert = get_earnings_alert(earnings_date_str, period)

    # ── プロンプト選択 ──
    if period == "短期":
        prompt = build_short_prompt(
            name, code, tech, fund, macro, breadth,
            earnings_alert, news_summary, score, user_profile
        )
    elif period == "中期":
        prompt = build_medium_prompt(
            name, code, tech, fund, macro, breadth,
            earnings_alert, news_summary, score, user_profile
        )
    else:
        prompt = build_long_prompt(
            name, code, tech, fund, macro,
            news_summary, score, user_profile
        )

    # ── AI呼び出し ──
    raw = ""
    try:
        res = openai_client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {
                    "role": "system",
                    "content": "あなたは日本株専門アナリストです。必ずJSON形式のみで返してください。理由は具体的かつ詳細に記述してください。"
                },
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            max_tokens=2500,
        )
        raw    = res.choices[0].message.content.strip()
        raw    = raw.replace("```json", "").replace("```", "").strip()
        result = json.loads(raw)
        result["_period"]       = period
        result["_ticker"]       = ticker_code
        result["_prompt"]       = prompt
        result["_tech_data"]    = tech
        result["_fund_data"]    = fund
        result["_macro_data"]   = macro
        result["_breadth_data"] = breadth
        return result

    except json.JSONDecodeError as e:
        return {
            "error": "AI分析結果の解析に失敗しました。もう一度お試しください。",
            "error_detail": f"JSONパースエラー: {str(e)}",
            "error_type": "parse_error",
            "raw": raw,
        }
    except Exception as e:
        err_str = str(e).lower()
        if "rate limit" in err_str or "ratelimit" in err_str:
            msg = "AI分析の利用制限に達しました。しばらく待ってからもう一度お試しください。"
            etype = "rate_limit"
        elif "timeout" in err_str:
            msg = "AI分析がタイムアウトしました。サーバーが混雑しています。時間をおいて再度お試しください。"
            etype = "timeout"
        elif "connection" in err_str or "network" in err_str:
            msg = "AIサーバーに接続できませんでした。ネットワーク状況を確認してください。"
            etype = "connection"
        elif "yfinance" in err_str or "download" in err_str:
            msg = "株価データの取得に失敗しました。銘柄コードを確認してください。"
            etype = "data_fetch"
        elif "dynamodb" in err_str or "no region" in err_str:
            msg = "データベースへの接続に失敗しました。管理者にお問い合わせください。"
            etype = "database"
        else:
            msg = "予期せぬエラーが発生しました。しばらく待ってからもう一度お試しください。"
            etype = "unknown"
        return {
            "error": msg,
            "error_type": etype,
            "error_detail": str(e),
        }


@app.get("/market/breadth")
def get_market_breadth():
    """騰落レシオをDynamoDBにキャッシュして返す（毎日更新）"""
    # 今は get_nikkei225_breadth() で計算
    # 将来的にDynamoDBから取得
    return get_nikkei225_breadth()


@app.post("/market/sector_comment")
async def sector_comment(request: Request):
    body = await request.json()
    jp = body.get("jp", [])
    us = body.get("us", [])

    jp_text = "\n".join([f"{s['name']}: {s['change_pct']:+.2f}%" for s in jp])
    us_text = "\n".join([f"{s['name']}: {s['change_pct']:+.2f}%" for s in us])

    prompt = f"""
以下は本日の日本株・米国株のセクター騰落率です。
これを見て今の相場環境を2〜3文で日本語で解説してください。
どのセクターが強く・弱く、それが何を意味するか（リスクオン/オフ、金利動向など）を簡潔に説明してください。

【日本株セクター】
{jp_text}

【米国株セクター】
{us_text}
"""
    try:
        res = openai_client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "あなたは株式市場のアナリストです。簡潔に日本語で答えてください。"},
                {"role": "user", "content": prompt}
            ],
            max_tokens=300,
        )
        return {"comment": res.choices[0].message.content.strip()}
    except Exception as e:
        return {"comment": "解説を取得できませんでした。"}


@app.get("/user/profile")
async def get_user_profile(userId: str):
    """ユーザープロファイル取得"""
    try:
        res = user_profile_table.get_item(Key={'userId': userId})
        item = res.get('Item')
        if not item:
            return {"exists": False}
        return {"exists": True, **_from_decimal(item)}
    except Exception as e:
        return {"error": str(e), "exists": False}


@app.post("/user/profile")
async def save_user_profile(request: Request):
    """ユーザープロファイル保存"""
    try:
        body = await request.json()
        user_id = body.get("userId")
        if not user_id:
            return {"error": "userIdが必要です"}
        item = {
            "userId":          user_id,
            "investment_style": body.get("investment_style", "中期"),
            "trade_type":       body.get("trade_type", "現物のみ"),
            "short_selling":    body.get("short_selling", "しない"),
            "analysis_style":   body.get("analysis_style", "バランス型"),
            "risk_level":       body.get("risk_level", "中"),
            "experience":       body.get("experience", "中級"),
            "market":           body.get("market", "両方"),
            "concentration":    body.get("concentration", "分散派"),
            "updated_at":       datetime.now().isoformat(),
        }
        user_profile_table.put_item(Item=item)
        return {"success": True}
    except Exception as e:
        return {"error": str(e), "success": False}


@app.post("/portfolio/diagnosis")
async def portfolio_diagnosis(request: Request):
    body = await request.json()
    user_profile = body.get("user_profile", {})
    holdings = body.get("holdings", [])
    period = body.get("period", "中期")

    # マクロ取得（キャッシュ対応済み）
    macro = get_macro_data()

    # 各銘柄の株価・テクニカル取得
    enriched = []
    for h in holdings:
        ticker_code = h.get("ticker_code", "")
        try:
            tech = get_technical_data(ticker_code)
            current_price = tech.get("price")

            # 損益率計算
            cost_price = h.get("cost_price")
            shares = h.get("shares")
            position = h.get("position", "買い")
            profit_loss_pct = None
            profit_loss_yen = None
            if cost_price and current_price:
                if position == "買い":
                    profit_loss_pct = round(
                        (current_price - cost_price) / cost_price * 100, 2)
                else:  # 空売り
                    profit_loss_pct = round(
                        (cost_price - current_price) / cost_price * 100, 2)
                if shares:
                    profit_loss_yen = round(
                        (current_price - cost_price) * shares *
                        (1 if position == "買い" else -1), 0)

            enriched.append({
                **h,
                "current_price": current_price,
                "profit_loss_pct": profit_loss_pct,
                "profit_loss_yen": profit_loss_yen,
                "rsi": tech.get("rsi"),
                "macd": tech.get("macd"),
                "ma5": tech.get("ma5"),
                "ma25": tech.get("ma25"),
            })
        except Exception as e:
            enriched.append({**h, "current_price": None, "error": str(e)})

    # プロンプト組み立て
    holdings_blocks = ""
    for h in enriched:
        cost_str = f"{h.get('cost_price')}円" if h.get('cost_price') else "未入力"
        shares_str = f"{h.get('shares')}株" if h.get('shares') else "未入力"
        pl_str = f"{h.get('profit_loss_pct')}%" if h.get('profit_loss_pct') is not None else "不明"
        pl_yen = f"（{h.get('profit_loss_yen'):+,.0f}円）" if h.get('profit_loss_yen') is not None else ""
        holdings_blocks += f"""
=== {h.get('name')}（{h.get('code')}） ===
取引種別：{h.get('trade_type', '現物')}　ポジション：{h.get('position', '買い')}
現在株価：{h.get('current_price')}円　取得単価：{cost_str}　保有株数：{shares_str}
損益率：{pl_str}{pl_yen}
RSI(14)：{h.get('rsi')}　MACD：{h.get('macd')}　MA5：{h.get('ma5')}円　MA25：{h.get('ma25')}円
"""

    prompt = f"""
あなたは株式投資の専門アナリストです。
以下のポートフォリオを詳細に診断してください。
各銘柄について「継続保有・買い増し・利確・損切り」のいずれかを確率ベースで判断し、
具体的な数値を引用した理由を記述してください。
確率（継続保有・買い増し・利確・損切り）の合計は必ず100にすること。
JSONのみ出力（前置き・説明文禁止）。

【ユーザープロファイル】
- 投資スタイル：{user_profile.get('investment_style', '中期')}
- リスク許容度：{user_profile.get('risk_level', '中')}
- 取引種別：{user_profile.get('trade_type', '現物のみ')}
- 分析スタイル：{user_profile.get('analysis_style', 'バランス型')}
- 投資経験：{user_profile.get('experience', '中級')}

【市場環境】
- 日経平均トレンド：{macro.get('nikkei_trend')}
- VIX：{macro.get('vix')}（20以下=安定／30以上=恐怖状態）
- ドル円：{macro.get('usd_jpy')}円
- 米10年債：{macro.get('us10y')}%
- S&P500トレンド：{macro.get('sp500_trend')}
- 金利差(10Y-2Y)：{macro.get('yield_spread')}

【保有銘柄】
{holdings_blocks}

【診断期間】
- 対象期間：{period}
  ※短期（数日〜2週間）はテクニカル・需給重視
  ※中期（1〜3ヶ月）はテクニカル＋ファンダ＋マクロのバランス
  ※長期（6ヶ月以上）はファンダメンタル・バリュエーション重視

【診断指示】
{period}の観点で各銘柄を診断してください。：
- verdict：継続保有 / 買い増し / 利確推奨 / 損切り推奨
- probability：継続保有・買い増し・利確・損切りの確率（合計100）
- confidence：high / medium / low
- price_strategy：利確目安価格・損切り目安価格・根拠
- positive_points：保有継続・買い増しの根拠（3点、指標名と数値を含め2文以上）
- negative_points：リスク・売却根拠（3点、指標名と数値を含め2文以上）
- macro_impact：市場環境がこの銘柄に与える影響
- summary：5〜8文の詳細サマリー（数値引用必須）

空売りポジションは上昇が損失になることを考慮。
信用取引は追証リスクも考慮。
リスク許容度が低い場合は損切り推奨寄りに補正。

必ずJSONのみで返してください：
{{
  "market_environment": {{
    "summary": "市場環境の総合コメント（3〜4文）",
    "risk_mode": "risk_on / risk_off / neutral",
    "risk_mode_reason": "VIX・米株・ドル円から3文で"
  }},
  "holdings": [
    {{
      "code": "",
      "name": "",
      "current_price": 0,
      "profit_loss_pct": 0,
      "verdict": "継続保有 / 買い増し / 利確推奨 / 損切り推奨",
      "probability": {{
        "hold":     {{"value": 継続保有確率(整数), "reason": "2〜3文で具体的に"}},
        "add":      {{"value": 買い増し確率(整数), "reason": "2〜3文で具体的に"}},
        "take_profit": {{"value": 利確確率(整数), "reason": "2〜3文で具体的に"}},
        "cut_loss": {{"value": 損切り確率(整数), "reason": "2〜3文で具体的に"}}
      }},
      "confidence": {{"value": "high/medium/low", "reason": "2文で"}},
      "price_strategy": {{
        "take_profit": {{"value": 0, "reason": "3〜4文で根拠を説明"}},
        "stop_loss":   {{"value": 0, "reason": "3〜4文で根拠を説明"}}
      }},
      "macro_impact": {{"value": "positive/negative/neutral", "reason": "この銘柄への市場環境の影響を2〜3文で"}},
      "positive_points": ["根拠1（指標名と数値を含め2文以上）", "根拠2", "根拠3"],
      "negative_points": ["リスク1（指標名と数値を含め2文以上）", "リスク2", "リスク3"],
      "summary": "5〜8文の詳細サマリー（RSI・MACD・損益率などの数値を引用）"
    }}
  ],
  "portfolio_analysis": {{
    "sector_balance": "セクターバランスの詳細コメント（3〜4文）",
    "concentration_risk": "集中リスクの詳細コメント（3〜4文）",
    "overall_comment": "ポートフォリオ全体の総評（5〜8文、ユーザープロファイルを考慮）"
  }}
}}
"""

    try:
        res = openai_client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "あなたは株式投資の専門アナリストです。必ずJSON形式のみで返してください。"},
                {"role": "user", "content": prompt}
            ],
            max_tokens=3000,
        )
        raw = res.choices[0].message.content.strip()
        raw = raw.replace("```json", "").replace("```", "").strip()
        result = json.loads(raw)
        result["_prompt"] = prompt
        result["_holdings_data"] = enriched
        return result
    except json.JSONDecodeError as e:
        return {"error": "AI分析結果の解析に失敗しました。もう一度お試しください。"}
    except Exception as e:
        return {"error": f"診断に失敗しました：{str(e)}"}