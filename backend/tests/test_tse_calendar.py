# ===================================================
# 東証の営業日と権利落ち日（services/tse_calendar.py）
#
# 以前は土日だけ見て数えていて、祝日・年末の休場で権利落ち日がずれていた。
# ===================================================

import datetime

import exchange_calendars as xcals
import pandas as pd
import pytest

from routers.market import get_market_events
from services.tse_calendar import is_tse_business_day, month_end_rights_dates

D = datetime.date


@pytest.mark.parametrize("year, month, last_with_rights, ex_rights, record", [
    # 12/31 は休場。以前は 12/30 を権利落ち日にしていた
    (2026, 12, D(2026, 12, 28), D(2026, 12, 29), D(2026, 12, 30)),
    # 4/29（昭和の日）は休場。以前は祝日の 4/29 を権利落ち日にしていた
    (2027, 4, D(2027, 4, 27), D(2027, 4, 28), D(2027, 4, 30)),
    # 月末が土日
    (2026, 10, D(2026, 10, 28), D(2026, 10, 29), D(2026, 10, 30)),
    (2026, 11, D(2026, 11, 26), D(2026, 11, 27), D(2026, 11, 30)),
    (2027, 3, D(2027, 3, 29), D(2027, 3, 30), D(2027, 3, 31)),
    # 2027-09：9/20 敬老の日・9/23 秋分の日を挟んでも月末側は影響なし
    (2027, 9, D(2027, 9, 28), D(2027, 9, 29), D(2027, 9, 30)),
])
def test_month_end_rights_dates(year, month, last_with_rights, ex_rights, record):
    assert month_end_rights_dates(year, month) == {
        "last_with_rights": last_with_rights, "ex_rights": ex_rights, "record": record,
    }


def test_year_end_and_new_year_are_closed():
    assert not is_tse_business_day(D(2026, 12, 31))  # 木曜だが休場
    assert is_tse_business_day(D(2027, 1, 4))  # 1/4（月）は大発会
    assert not is_tse_business_day(D(2027, 1, 1))
    assert not is_tse_business_day(D(2027, 1, 2))
    assert not is_tse_business_day(D(2027, 1, 3))


def test_matches_exchange_calendars_xtks():
    # exchange_calendars の東証カレンダーと、計算できる範囲の全月で一致することを確かめる
    xtks = xcals.get_calendar("XTKS")
    sessions = {s.date() for s in xtks.sessions}
    start = xtks.first_session.date().replace(day=1) + pd.offsets.MonthBegin(1)
    end = xtks.last_session.date().replace(day=1) - pd.offsets.MonthBegin(1)
    for month_start in pd.date_range(start, end, freq="MS"):
        y, m = month_start.year, month_start.month
        month_sessions = sorted(d for d in sessions if d.year == y and d.month == m)
        got = month_end_rights_dates(y, m)
        assert got["record"] == month_sessions[-1], (y, m)
        assert got["ex_rights"] == month_sessions[-2], (y, m)
        assert got["last_with_rights"] == month_sessions[-3], (y, m)


def test_market_events_has_exact_ex_rights_without_estimate_label():
    rights = [e for e in get_market_events(2026, 12) if e["type"] == "rights"]
    assert rights == [{"date": "2026-12-29", "label": "権利落ち日", "type": "rights", "color": "indigo"}]


# JPX「営業時間・休業日一覧」（https://www.jpx.co.jp/corporate/about-jpx/calendar/index.html 2026-02-06 更新）
# に載っている休業日のうち平日のもの。2026-10-10 にブラウザで確認して書き写した
JPX_WEEKDAY_HOLIDAYS = {
    2026: ["01-01", "01-02", "01-12", "02-11", "02-23", "03-20", "04-29", "05-04", "05-05",
           "05-06", "07-20", "08-11", "09-21", "09-22", "09-23", "10-12", "11-03", "11-23", "12-31"],
    2027: ["01-01", "01-11", "02-11", "02-23", "03-22", "04-29", "05-03", "05-04", "05-05",
           "07-19", "08-11", "09-20", "09-23", "10-11", "11-03", "11-23", "12-31"],
}


@pytest.mark.parametrize("year", sorted(JPX_WEEKDAY_HOLIDAYS))
def test_matches_jpx_official_holidays(year):
    holidays = {D.fromisoformat(f"{year}-{md}") for md in JPX_WEEKDAY_HOLIDAYS[year]}
    d = D(year, 1, 1)
    while d.year == year:
        if d.weekday() < 5:
            assert is_tse_business_day(d) == (d not in holidays), d
        d += datetime.timedelta(days=1)
