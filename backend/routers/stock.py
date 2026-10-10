import math
import time
import datetime
import requests
import yfinance as yf
from fastapi import APIRouter
from services.cache import stock_cache_table, cache_get, cache_set
from config.timeouts import JQUANTS_TIMEOUT
from services.clock import JST
from services.market_data import drop_empty_rows, first_earnings_date, week52_range
from services.stock_code import is_jp_code, to_yf_ticker, to_jquants_code


# main.pyから注入される変数
stocks_master = []
JQUANTS_API_KEY = ""
reload_stocks_master = None  # 銘柄マスタを取り直す関数（main.fetch_stocks_master）

# 銘柄マスタが空のとき、取り直しを試す最短の間隔（秒）。
# J-Quantsが落ちている間に、検索のたびに呼びに行かないようにする
STOCKS_MASTER_RETRY_SEC = 60
_last_master_retry = 0.0
router = APIRouter()

# ===================================================
# ユーティリティ関数
# ===================================================
# NaN値をNoneに変換（JSONシリアライズエラー防止）
def clean_value(v):
    if isinstance(v, float) and math.isnan(v):
        return None
    return v


def ensure_stocks_master():
    """
    銘柄マスタが空なら取り直す（起動時の取得に失敗していた場合の復旧用）

    STOCKS_MASTER_RETRY_SEC に1回までしか試さない。
    """
    global _last_master_retry
    if stocks_master or reload_stocks_master is None:
        return
    now = time.monotonic()
    if _last_master_retry and now - _last_master_retry < STOCKS_MASTER_RETRY_SEC:
        return
    _last_master_retry = now
    reload_stocks_master()


# ===================================================
# 銘柄検索API
# ===================================================
@router.get("/search")
def search(q: str):
    """
    銘柄検索エンドポイント
    - 日本語入力 → J-Quantsマスタから部分一致検索
    - 数字入力   → J-Quantsマスタからコード前方一致検索
    - 英語入力   → yfinanceで米国株検索
    """
    if not q:
        return []
    ensure_stocks_master()
    results = []

    # 日本語 → J-Quantsマスタから検索
    if any("\u3040" <= c <= "\u9fff" for c in q):
        for s in stocks_master:
            name = s.get("CoName", "")
            code = s.get("Code", "")
            if q in name:
                results.append({"code": code, "name": name, "market": "JP"})
        return results[:20]

    # 数字で始まる → J-Quantsマスタからコード検索（285A のような英字入りのコードも含む）
    if q[0].isdigit() and q.isalnum():
        prefix = q.upper()
        for s in stocks_master:
            code = s.get("Code", "")
            if code.startswith(prefix):
                results.append({"code": code, "name": s.get("CoName", code), "market": "JP"})
        # 数字だけなら日本株のコードとして終わり。
        # 「3M」のように英字を含むものは、日本株で見つからなければ米国株も探す
        if results or q.isdigit():
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
@router.get("/stock/name")
def get_stock_name(code: str):
    """
    銘柄コードから銘柄名を取得
    - 日本株(数字コード) → J-Quantsマスタから検索（4桁→5桁変換）
    - 米国株(英字コード) → yfinanceから取得
    """
    if is_jp_code(code):
        ensure_stocks_master()
        # 4桁の場合は末尾に0を付けて5桁でJ-Quantsマスタ検索
        search_code = to_jquants_code(code)
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
@router.get("/stock/detail")
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
        # 5桁→4桁に変換してyfinanceに渡す（例: 72030 → 7203.T、285A0 → 285A.T）
        ticker = yf.Ticker(to_yf_ticker(code))

        info = ticker.info

        # 3ヶ月分の株価履歴を取得
        hist = drop_empty_rows(ticker.history(period="3mo"))

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
        
        week52 = week52_range(info, [c["high"] for c in candles], [c["low"] for c in candles])

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
            # 本当の52週の高値・安値（詳細画面の「52週価格帯」用）。
            # 以前の画面は3か月分のローソク足から計算していた（K-50）
            "week52_high": clean_value(week52[0]),
            "week52_low": clean_value(week52[1]),
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
@router.get("/stock/price")
def get_stock_price(code: str):
    """
    株価と前日比のみを取得（ホーム画面の一覧表示用）
    詳細APIより軽量で高速
    """
    try:
        ticker = yf.Ticker(to_yf_ticker(code))

        # 最新日が空の行で返ることがあるので、余裕を持って5日分取ってから空の行を除く
        hist = drop_empty_rows(ticker.history(period="5d"))
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
# 銘柄イベント取得API
# ===================================================
@router.get("/stock/events")
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
            ticker = yf.Ticker(to_yf_ticker(code))

            info = ticker.info
            name = info.get("longName") or info.get("shortName") or code

            # 決算発表日（日本株はJ-Quantsから取得）
            if is_jp_code(code):
                try:
                    res = requests.get(
                        "https://api.jquants.com/v2/fins/announcement",
                        headers={"x-api-key": JQUANTS_API_KEY},
                        params={"code": to_jquants_code(code)},
                        timeout=JQUANTS_TIMEOUT,
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
                    earnings_date = first_earnings_date(ticker.calendar)
                    if earnings_date:
                        result.append({
                            "code": code,
                            "name": name,
                            "date": earnings_date,
                            "type": "earnings",
                            "label": f"{name} 決算発表",
                            "color": "red",
                        })
                except Exception as e:
                    print(f"米国株の決算日取得エラー {code}: {e}")

            # 配当関連（yfinance）
            try:
                ex_div = info.get("exDividendDate")
                if ex_div:
                    ex_dividend = str(datetime.datetime.fromtimestamp(ex_div, tz=JST).date())
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