# ===================================================
# 日本株の決算発表予定日（J-Quants の /v2/fins/earnings-date）
#
# 以前は /v2/fins/announcement を呼んでいたが、これは V1 の名前（/v1/fins/announcement）で、
# V2 には存在しない（V2 の対応先は /v2/equities/earnings-calendar・/v2/fins/earnings-date）。
# エラーにならずに空のまま進んでいたので、日本株の決算日がスケジュールにも AI 分析にも
# 一度も出ていなかった（K-47。2026-10-10 本番で 72030・67580・83060 を確認）。
#
# /v2/fins/earnings-date?code= は、その銘柄の「予定日の公表・変更の履歴」を返す。
#   https://jpx-jquants.com/ja/spec/fin-earnings-date
#   項目：PubDate（公表日）・SchDate（予定日。未定なら ""）・FQName（1Q/2Q/3Q/FY）・FYE（決算期末）
# 予定日が変わると、上書きではなく新しい PubDate の行が増える。
# なので「決算期末・決算区分ごとに最後に公表された行」だけを見て、今日以降の予定日を返す。
#
# J-Quants は無料プランだと1分5回までなので、銘柄ごとの結果を DynamoDB に12時間保存する。
# ===================================================

import requests

from config.timeouts import JQUANTS_TIMEOUT
from services.cache import cache_get, cache_set, stock_cache_table

JQUANTS_EARNINGS_DATE_URL = "https://api.jquants.com/v2/fins/earnings-date"

# 中身の形を変えたら版を上げる
JP_EARNINGS_CACHE_TYPE = "jp_earnings_v1"
JP_EARNINGS_CACHE_TTL_MINUTES = 12 * 60

# ページ送りが終わらないとき（APIの不具合）に無限に回らないための上限
JQUANTS_MAX_PAGES = 10


def _fetch_records(code5: str, api_key: str, http_get) -> list | None:
    """earnings-date の行を全ページ読んで返す。失敗したら None（「無い」と区別するため）"""
    records = []
    params = {"code": code5}
    for _ in range(JQUANTS_MAX_PAGES):
        try:
            res = http_get(
                JQUANTS_EARNINGS_DATE_URL,
                headers={"x-api-key": api_key},
                params=params,
                timeout=JQUANTS_TIMEOUT,
            )
        except Exception as e:
            print(f"J-Quants決算予定日の取得エラー {code5}: {e}")
            return None
        if res.status_code != 200:
            print(f"J-Quants決算予定日の取得エラー {code5}: HTTP {res.status_code} {res.text[:200]}")
            return None
        body = res.json()
        records.extend(body.get("data", []))
        next_key = body.get("pagination_key")
        if not next_key:
            return records
        params = {"code": code5, "pagination_key": next_key}
    print(f"J-Quants決算予定日の取得エラー {code5}: {JQUANTS_MAX_PAGES}ページを超えたので打ち切り")
    return records


def upcoming_dates(records: list, today_str: str, limit: int = 2) -> list:
    """
    公表履歴から、今日以降の決算発表予定日を古い順に最大 limit 件返す（"YYYY-MM-DD"）

    決算期末（FYE）・決算区分（FQName）ごとに、最後に公表された行だけを使う。
    最後の行の SchDate が ""（未定に変わった）なら、その決算の予定日は出さない。
    """
    latest = {}
    for r in records:
        key = (r.get("FYE", ""), r.get("FQName", ""))
        if key not in latest or str(r.get("PubDate", "")) > str(latest[key].get("PubDate", "")):
            latest[key] = r
    dates = sorted({
        str(r.get("SchDate"))[:10]
        for r in latest.values()
        if r.get("SchDate") and str(r.get("SchDate"))[:10] >= today_str
    })
    return dates[:limit]


def get_jp_earnings_dates(code5: str, api_key: str, today_str: str,
                          http_get=requests.get, table=None) -> list:
    """
    日本株の今日以降の決算発表予定日を返す（最大2件）。取れなければ []

    結果は12時間保存する（取得に失敗したときは保存しない＝次のリクエストでまた取りに行く）。
    """
    table = table or stock_cache_table
    key = {"code": code5, "cache_type": JP_EARNINGS_CACHE_TYPE}
    cached = cache_get(table, key)
    if cached and isinstance(cached.get("records"), list):
        return upcoming_dates(cached["records"], today_str)

    records = _fetch_records(code5, api_key, http_get)
    if records is None:
        return []
    # 予定日の判定に使う項目だけ保存する
    slim = [
        {k: r.get(k, "") for k in ("PubDate", "SchDate", "FQName", "FYE")}
        for r in records
    ]
    cache_set(table, key, {"records": slim}, ttl_minutes=JP_EARNINGS_CACHE_TTL_MINUTES)
    return upcoming_dates(slim, today_str)
