# ===================================================
# 日本時間（JST）の現在時刻
#
# Lambda はタイムゾーンが UTC なので、datetime.now() / date.today() は
# 日本時間より9時間遅れる。日本時間の 0:00〜8:59 は「前日」になってしまい、
# 決算までの残り日数・「直近の予定」の今日・予測の答え合わせ日がずれる。
#
# 日付・時刻が必要な箇所は、必ずこのモジュールの関数を使うこと。
#
# ・日本はサマータイムが無いので、固定の +9時間 で十分
#   （zoneinfo は Lambda のベースイメージに tzdata が無いと失敗するため使わない）
# ・now_jst() はタイムゾーン情報なし（naive）で返す。
#   DynamoDB に保存済みの日時文字列（naive）とそのまま比較できるようにするため
# ===================================================

from datetime import date, datetime, timedelta, timezone

JST = timezone(timedelta(hours=9), "JST")


def now_jst() -> datetime:
    """日本時間の現在日時（タイムゾーン情報なし）"""
    return datetime.now(JST).replace(tzinfo=None)


def today_jst() -> date:
    """日本時間の今日の日付"""
    return datetime.now(JST).date()
