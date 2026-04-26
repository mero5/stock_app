import datetime
import yfinance as yf
import ephem
import jpholiday
import exchange_calendars as xcals
from fastapi import APIRouter, Request
from services.technical import get_nikkei225_breadth


router = APIRouter()
openai_client = None

# ===================================================
# マーケットイベント取得API
# ===================================================
@router.get("/market/events")
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
@router.get("/nikkei/monthly")
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
# セクタートレンドAPI
# ===================================================
@router.get("/market/sectors")
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


@router.get("/market/breadth")
def get_market_breadth():
    """騰落レシオをDynamoDBにキャッシュして返す（毎日更新）"""
    # 今は get_nikkei225_breadth() で計算
    # 将来的にDynamoDBから取得
    return get_nikkei225_breadth()


@router.post("/market/sector_comment")
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
            model="gpt-4o",
            messages=[
                {"role": "system", "content": "あなたは株式市場のアナリストです。簡潔に日本語で答えてください。"},
                {"role": "user", "content": prompt}
            ],
            max_tokens=300,
        )
        return {"comment": res.choices[0].message.content.strip()}
    except Exception as e:
        return {"comment": "解説を取得できませんでした。"}