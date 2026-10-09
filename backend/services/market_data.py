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
