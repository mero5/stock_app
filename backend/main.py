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
"summary": "動画の内容を2〜3文で要約",
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
            "description": video["snippet"]["description"],
            "thumbnail": video["snippet"]["thumbnails"]["default"]["url"],
            "url": f"https://www.youtube.com/watch?v={video['id']['videoId']}",
        }
    except Exception as e:
        print(f"最新動画取得エラー: {e}")
        return {"error": str(e)}

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
def get_sector_trends():
    """
    日本・米国の主要セクターETFの騰落を取得して返す
    """
    import datetime

    # 日本セクターETF（東証ETF）
    jp_sectors = {
        "銀行":     "1615.T",
        "電気機器": "1617.T",
        "自動車":   "1622.T",
        "不動産":   "1621.T",
        "食品":     "1619.T",
        "医薬品":   "1620.T",
        "情報通信": "1618.T",
        "素材":     "1623.T",
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
            hist = ticker.history(period="6d")
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