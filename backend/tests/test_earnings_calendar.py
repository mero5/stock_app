# ===================================================
# 米国株の決算発表日（services/market_data.first_earnings_date）
#
# yfinance の Ticker.calendar は、新しい版では dict を返す。
# 以前は DataFrame 前提で書いていたため、米国株の決算日が一度も出ていなかった。
# ===================================================

from datetime import date, datetime

import pandas as pd

from services.market_data import first_earnings_date


def test_dict_with_dates_returns_first_date():
    # yfinance 0.2.3x 以降の形
    cal = {"Earnings Date": [date(2026, 10, 30), date(2026, 11, 3)], "Dividend Date": date(2026, 11, 13)}
    assert first_earnings_date(cal) == "2026-10-30"


def test_dict_with_datetime_returns_date_only():
    cal = {"Earnings Date": [datetime(2026, 10, 30, 20, 0)]}
    assert first_earnings_date(cal) == "2026-10-30"


def test_dict_without_earnings_returns_none():
    # ETF などは決算日が無い
    assert first_earnings_date({}) is None
    assert first_earnings_date({"Earnings Date": []}) is None
    assert first_earnings_date(None) is None


def test_old_dataframe_format_still_works():
    # 古い yfinance の形（DataFrame）
    cal = pd.DataFrame({"Earnings Date": [pd.Timestamp("2026-10-30"), pd.Timestamp("2026-11-03")]})
    assert first_earnings_date(cal) == "2026-10-30"
    assert first_earnings_date(pd.DataFrame()) is None
