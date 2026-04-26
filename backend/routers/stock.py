import math
import datetime
import requests
import yfinance as yf
from fastapi import APIRouter
from services.cache import stock_cache_table, cache_get, cache_set


# main.pyから注入される変数
stocks_master = []
JQUANTS_API_KEY = ""
router = APIRouter()

# ===================================================
# ユーティリティ関数
# ===================================================
# NaN値をNoneに変換（JSONシリアライズエラー防止）
def clean_value(v):
    if isinstance(v, float) and math.isnan(v):
        return None
    return v


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
@router.get("/stock/name")
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
@router.get("/stock/price")
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