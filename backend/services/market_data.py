# ===================================================
# yfinance のデータの後始末
#
# yfinance は日本株（.T）で、最新の営業日を「値が空（NaN）の行」で返すことがある。
# 例：2026-10-10（土）に 7203.T を取ると、10/09 の行の Open/High/Low/Close が NaN で
#     Volume だけ入っている。
# その行をそのまま「最新」として使うと、株価・前日比・RSI・セクター騰落などが
# すべて null になる（ホーム画面で日本株の株価が全部表示されない等）。
#
# history() / download() の結果は、必ずここの関数を通してから使うこと。
# ===================================================


def drop_empty_rows(hist):
    """終値（Close）が空の行を取り除く。DataFrame が空・None ならそのまま返す"""
    if hist is None or getattr(hist, "empty", True) or "Close" not in hist:
        return hist
    return hist.dropna(subset=["Close"])


def first_earnings_date(calendar):
    """
    yfinance の Ticker.calendar から、最初の決算発表日を "YYYY-MM-DD" で返す。無ければ None

    yfinance 0.2.3x 以降、calendar は DataFrame ではなく dict
    （例：{"Earnings Date": [date(2026, 10, 30), ...], ...}）を返す。
    以前は DataFrame 前提で `cal.empty` を呼んでいたため AttributeError になり、
    それを握りつぶしていたので、米国株の決算日がスケジュールにもAI分析にも出ていなかった。
    古い形（DataFrame）が来ても動くよう、両方に対応する。
    """
    if calendar is None:
        return None
    if isinstance(calendar, dict):
        dates = calendar.get("Earnings Date") or []
    else:
        if getattr(calendar, "empty", True):
            return None
        column = calendar.get("Earnings Date")
        dates = list(column) if column is not None else []
    if not dates:
        return None
    first = dates[0]
    # pandas.Timestamp / datetime は .date() で日付だけにする。date はそのまま文字列にする
    if hasattr(first, "hour") and hasattr(first, "date"):
        first = first.date()
    return str(first)[:10]


def dividend_yield_pct(info: dict):
    """
    yfinance の info から配当利回りを「%」で返す（例：3.44 は 3.44%）。分からなければ None

    yfinance の dividendYield は、0.2.5x 以降の版で単位が「割合（0.0344）」から「%（3.44）」に変わった。
    以前は割合のつもりで ×100 していたため、トヨタが「344%」になっていた（K-46）。
    版によって単位が変わる値には頼らず、年間配当額（dividendRate）÷ 株価で計算する。
    年間配当額が無いときだけ dividendYield（今の版の「%」）を使う。
    """
    info = info or {}
    rate = info.get("dividendRate")
    price = info.get("currentPrice") or info.get("regularMarketPrice") or info.get("previousClose")
    try:
        if rate is not None and price:
            return round(float(rate) / float(price) * 100, 2)
        if info.get("dividendYield") is not None:
            return round(float(info["dividendYield"]), 2)
    except (TypeError, ValueError, ZeroDivisionError) as e:
        print(f"配当利回りの計算エラー: {e}")
    return None


def week52_range(info: dict, highs=None, lows=None):
    """
    52週（約1年）の高値・安値を (高値, 安値) で返す。分からなければ (None, None)

    以前は画面・APIで手元にある期間（3か月・6か月）の高値・安値を「52週」として出していた（K-50）。
    yfinance の info にある本当の52週の値（fiftyTwoWeekHigh / fiftyTwoWeekLow）を優先し、
    無いときだけ渡された高値・安値の一覧から求める。
    """
    info = info or {}
    high = info.get("fiftyTwoWeekHigh")
    low = info.get("fiftyTwoWeekLow")
    if high is None and highs:
        high = max(highs)
    if low is None and lows:
        low = min(lows)
    return (round(float(high), 2) if high is not None else None,
            round(float(low), 2) if low is not None else None)
