# ===================================================
# 市場が開いている時間かどうか（株価アラートの判定で使う）
#
# 閉まっている時間は株価が動かないので、yfinance を呼ばずに飛ばす。
# EventBridge Scheduler は5分おきに一日中起こすので、ここで市場ごとに絞る。
#
# ・日本株：東証の営業日（services/tse_calendar.py。祝日・年末年始は休み）の取引時間
# ・米国株：平日の取引時間（ニューヨーク時間）。夏時間（3月第2日曜〜11月第1日曜）は自分で計算する
#   （zoneinfo は Lambda のベースイメージに tzdata が無いと失敗するため使わない。services/clock.py と同じ理由）
#   米国の祝日は見ていない。休みの日は株価が動かないので、前の日の終値のまま判定されるだけ
# ===================================================

from datetime import date, datetime, timedelta, timezone

from config.price_alerts import JP_SESSIONS, SESSION_GRACE_MINUTES, US_SESSIONS
from services.clock import JST
from services.stock_code import is_jp_code
from services.tse_calendar import is_tse_business_day

_US_STANDARD = timezone(timedelta(hours=-5), "EST")
_US_DAYLIGHT = timezone(timedelta(hours=-4), "EDT")


def _nth_sunday(year: int, month: int, n: int) -> date:
    """その月の第n日曜日"""
    first = date(year, month, 1)
    first_sunday = first + timedelta(days=(6 - first.weekday()) % 7)
    return first_sunday + timedelta(weeks=n - 1)


def us_eastern(now_utc: datetime) -> datetime:
    """UTC の日時を、ニューヨーク時間（夏時間を考えた時刻）にする"""
    year = now_utc.year
    # 夏時間は 3月第2日曜 2:00（EST）〜 11月第1日曜 2:00（EDT）。UTC ではそれぞれ 7:00 と 6:00
    dst_start = datetime.combine(_nth_sunday(year, 3, 2), datetime.min.time(), timezone.utc) + timedelta(hours=7)
    dst_end = datetime.combine(_nth_sunday(year, 11, 1), datetime.min.time(), timezone.utc) + timedelta(hours=6)
    tz = _US_DAYLIGHT if dst_start <= now_utc < dst_end else _US_STANDARD
    return now_utc.astimezone(tz)


def _in_sessions(local: datetime, sessions) -> bool:
    """local（その市場の時刻）が、どれかの取引時間（終わりに余裕を足す）に入っていれば True"""
    minutes = local.hour * 60 + local.minute
    for (sh, sm), (eh, em) in sessions:
        if sh * 60 + sm <= minutes < eh * 60 + em + SESSION_GRACE_MINUTES:
            return True
    return False


def market_date(code: str, now_utc: datetime) -> str:
    """
    その銘柄の市場での今日の日付（"2026-10-12"）。アラートの「1日1回まで」を数えるのに使う

    米国株の取引時間は日本時間の夜〜朝にまたがるので、日本の日付で数えると1回の取引で2回通知してしまう
    """
    local = now_utc.astimezone(JST) if is_jp_code(code) else us_eastern(now_utc)
    return local.date().isoformat()


def is_market_open(code: str, now_utc: datetime) -> bool:
    """
    その銘柄の市場が開いている時間なら True

    [now_utc] タイムゾーン付きの UTC の日時（datetime.now(timezone.utc)）
    """
    if is_jp_code(code):
        local = now_utc.astimezone(JST)
        return is_tse_business_day(local.date()) and _in_sessions(local, JP_SESSIONS)
    local = us_eastern(now_utc)
    return local.weekday() < 5 and _in_sessions(local, US_SESSIONS)
