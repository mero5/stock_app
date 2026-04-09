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

            # 決算発表日
            earnings_date = None
            try:
                cal = ticker.calendar
                if cal is not None and not cal.empty:
                    ed = cal.get("Earnings Date")
                    if ed is not None and len(ed) > 0:
                        earnings_date = str(ed.iloc[0].date()) if hasattr(ed.iloc[0], 'date') else str(ed.iloc[0])
            except Exception:
                pass

            # 配当関連
            ex_dividend = None
            dividend_date = None
            try:
                ex_div = info.get("exDividendDate")
                if ex_div:
                    import datetime
                    ex_dividend = str(datetime.datetime.fromtimestamp(ex_div).date())
                div_date = info.get("lastDividendDate") or info.get("nextDividendDate")
                if div_date:
                    dividend_date = str(datetime.datetime.fromtimestamp(div_date).date())
            except Exception:
                pass

            if earnings_date:
                result.append({
                    "code": code,
                    "name": name,
                    "date": earnings_date,
                    "type": "earnings",
                    "label": f"{name} 決算発表",
                    "color": "red",
                })
            if ex_dividend:
                result.append({
                    "code": code,
                    "name": name,
                    "date": ex_dividend,
                    "type": "ex_dividend",
                    "label": f"{name} 配当落ち日",
                    "color": "blue",
                })
            if dividend_date and dividend_date != ex_dividend:
                result.append({
                    "code": code,
                    "name": name,
                    "date": dividend_date,
                    "type": "dividend",
                    "label": f"{name} 配当支払日",
                    "color": "green",
                })

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
