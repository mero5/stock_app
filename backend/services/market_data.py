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
