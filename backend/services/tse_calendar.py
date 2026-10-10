# ===================================================
# 東証の営業日と、毎月の権利落ち日の計算
#
# 以前は routers/market.py で「月末から2営業日前」を土日だけ見て数えていて、
# 祝日や年末の休場（12/31）を営業日として数えていた。
# 例：2026年12月は 12/31 を営業日と数えて、本当の権利落ち日（12/29）より1日遅い 12/30 を出していた。
#     2027年4月は祝日の 4/29 を権利落ち日として出していた。
#
# 東証の休業日（JPX の取引所規則で決まっている）：
#   土日・国民の祝日と振替休日（jpholiday）・12/31〜1/3
# 権利確定日を月末の最終営業日とすると（月末が決算・権利確定の会社の場合）：
#   権利付最終日 ＝ 権利確定日の2営業日前（この日の終わりまでに買えば権利がもらえる）
#   権利落ち日   ＝ 権利確定日の1営業日前（受渡しが T+2 になった 2019-07 以降の決まり）
#
# exchange_calendars の東証カレンダー（XTKS）は「今日から約1年先」までしか計算できないので、
# 何年先でも計算できるよう、休業日の決まりから直接計算する。
# ===================================================

import datetime

import jpholiday


def is_tse_business_day(d: datetime.date) -> bool:
    """東証が開いている日なら True"""
    if d.weekday() >= 5:
        return False
    if (d.month == 12 and d.day == 31) or (d.month == 1 and d.day <= 3):
        return False
    return not jpholiday.is_holiday(d)


def _last_business_day_of_month(year: int, month: int) -> datetime.date:
    next_month = datetime.date(year + month // 12, month % 12 + 1, 1)
    d = next_month - datetime.timedelta(days=1)
    while not is_tse_business_day(d):
        d -= datetime.timedelta(days=1)
    return d


def _previous_business_day(d: datetime.date) -> datetime.date:
    d -= datetime.timedelta(days=1)
    while not is_tse_business_day(d):
        d -= datetime.timedelta(days=1)
    return d


def month_end_rights_dates(year: int, month: int) -> dict:
    """
    月末が権利確定日の銘柄の、その月の権利の日程を返す

    戻り値: {"last_with_rights": 権利付最終日, "ex_rights": 権利落ち日, "record": 権利確定日}（date）
    """
    record = _last_business_day_of_month(year, month)
    ex_rights = _previous_business_day(record)
    last_with_rights = _previous_business_day(ex_rights)
    return {"last_with_rights": last_with_rights, "ex_rights": ex_rights, "record": record}
