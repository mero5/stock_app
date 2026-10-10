# ===================================================
# 銘柄マスタ（J-Quants の全上場銘柄の一覧）の取得と、DynamoDB への保存
#
# 以前は Lambda のコンテナが起動するたびに J-Quants から全銘柄（約4,400件）を取り直していた。
# ホームのウォッチリストは銘柄ごとに同時に問い合わせるので、コンテナが何台も同時に起動し、
# J-Quants への同時アクセスで一部の台だけ取得に失敗 → その台では銘柄名がコードのまま・
# /health が「J-Quants に接続できません」になっていた（2026-10-10 本番で再現）。
#
# そこで、取れたマスタを DynamoDB（market_cache）に1日保存し、起動時はまずそこから読む。
# J-Quants に取りに行くのは、保存が無い・期限切れのときだけになる。
#
# 保存する中身：使っているのは Code と CoName だけなので、その2つに絞って
# gzip で圧縮して1件に入れる（DynamoDB は1件 400KB まで。全項目のままだと超える）。
# ===================================================

import gzip
import json
import time

import requests

from config.timeouts import JQUANTS_TIMEOUT
from services.cache import cache_get, cache_set, market_cache_table

JQUANTS_MASTER_URL = "https://api.jquants.com/v2/equities/master"

# 中身の形を変えたら版を上げる（CODING_RULES 5章）
STOCKS_MASTER_CACHE_KEY = {"cache_key": "stocks_master_v1"}

# 上場・廃止は1日単位でしか変わらないので1日
STOCKS_MASTER_CACHE_TTL_MINUTES = 24 * 60

# ページ送りが終わらないとき（APIの不具合）に無限に回らないための上限
JQUANTS_MAX_PAGES = 20

# J-Quants に取りに行くのは、全コンテナで同時に1つだけにする（DynamoDB を「取得中」の札にする）。
# 2026-10-10 のデプロイ直後、起動したコンテナが一斉に J-Quants を呼んで無料プランの「1分5回」を超え（HTTP 429）、
# 1度も取れないまま全コンテナが取り直しを続けていた。札を取れたコンテナだけが取りに行き、
# 失敗したら札の期限まで（＝回数制限が戻るまで）どのコンテナも取りに行かない
STOCKS_MASTER_LOCK_KEY = {"cache_key": "stocks_master_lock"}
STOCKS_MASTER_LOCK_SEC = 120


def _slim(master: list) -> list:
    """
    使う項目（Code・CoName）だけに絞り、銘柄コードの重複を除く

    J-Quants の一覧は同じ銘柄が日付違いで何行も返ることがある（2026-10-10 に 22,210 行。上場銘柄は約4,400）。
    重複したままだと保存が DynamoDB の1件 400KB を超えうるので、銘柄ごとに一番新しい日付（Date）の行だけ残す
    """
    latest = {}
    for s in master:
        code = s.get("Code")
        if not code:
            continue
        if code not in latest or str(s.get("Date", "")) >= str(latest[code].get("Date", "")):
            latest[code] = s
    return [{"Code": code, "CoName": s.get("CoName", "")} for code, s in latest.items()]


def _compress(master: list) -> bytes:
    rows = [[s["Code"], s["CoName"]] for s in master]
    return gzip.compress(json.dumps(rows, ensure_ascii=False).encode("utf-8"))


def _decompress(raw) -> list:
    # DynamoDB から読むと bytes ではなく boto3 の Binary 型で返る
    data = getattr(raw, "value", raw)
    rows = json.loads(gzip.decompress(bytes(data)).decode("utf-8"))
    return [{"Code": code, "CoName": name} for code, name in rows]


def load_stocks_master_cache(table=None) -> list:
    """DynamoDB に保存してある銘柄マスタを返す。無い・期限切れ・壊れている場合は []"""
    table = table or market_cache_table
    cached = cache_get(table, STOCKS_MASTER_CACHE_KEY)
    if not cached or "data_gz" not in cached:
        return []
    try:
        return _decompress(cached["data_gz"])
    except Exception as e:
        print(f"銘柄マスタのキャッシュ読み込みエラー: {e}")
        return []


def save_stocks_master_cache(master: list, table=None) -> None:
    """銘柄マスタを DynamoDB に1日保存する（失敗してもログに出すだけ）"""
    table = table or market_cache_table
    try:
        data = {"data_gz": _compress(master), "count": len(master)}
    except Exception as e:
        print(f"銘柄マスタのキャッシュ保存エラー: {e}")
        return
    cache_set(table, STOCKS_MASTER_CACHE_KEY, data, ttl_minutes=STOCKS_MASTER_CACHE_TTL_MINUTES)


def fetch_stocks_master_from_jquants(api_key: str, http_get=requests.get) -> list:
    """
    J-Quants から全上場銘柄を取得して、Code・CoName だけのリストで返す。失敗したら []

    レスポンスが大きいと pagination_key 付きで分割して返ってくるので、最後のページまで読む。
    （以前は1ページ目しか読んでいなかった）
    """
    loaded = []
    params = {}
    for _ in range(JQUANTS_MAX_PAGES):
        try:
            res = http_get(
                JQUANTS_MASTER_URL,
                headers={"x-api-key": api_key},
                params=params,
                timeout=JQUANTS_TIMEOUT,
            )
        except Exception as e:
            print(f"銘柄マスタ取得エラー: {e}")
            return []
        if res.status_code != 200:
            print(f"銘柄マスタ取得エラー: HTTP {res.status_code} {res.text[:200]}")
            return []
        body = res.json()
        loaded.extend(body.get("data", []))
        next_key = body.get("pagination_key")
        if not next_key:
            break
        params = {"pagination_key": next_key}
    else:
        print(f"銘柄マスタ取得エラー: {JQUANTS_MAX_PAGES}ページを超えたので打ち切り")

    if not loaded:
        print("銘柄マスタ取得エラー: 0件")
    return _slim(loaded)


def acquire_fetch_lock(table=None, now=None) -> bool:
    """
    「J-Quants から取得中」の札を取る。取れたら True（このコンテナだけが取りに行ってよい）

    DynamoDB の条件付き書き込みで、札が無いか期限切れのときだけ書ける。
    札は STOCKS_MASTER_LOCK_SEC 秒で切れるので、取得に失敗しても次の人が取り直せる
    """
    table = table or market_cache_table
    now = int(now if now is not None else time.time())
    try:
        table.put_item(
            Item={**STOCKS_MASTER_LOCK_KEY, "lock_until": now + STOCKS_MASTER_LOCK_SEC,
                  "ttl": now + STOCKS_MASTER_LOCK_SEC + 3600},
            ConditionExpression="attribute_not_exists(cache_key) OR lock_until < :now",
            ExpressionAttributeValues={":now": now},
        )
        return True
    except Exception as e:
        # 条件に合わない（ほかのコンテナが取得中・回数制限の待ち）か、DynamoDB のエラー
        print(f"銘柄マスタ：取得中の札を取れなかった（ほかのコンテナが取得中など）: {type(e).__name__}")
        return False


def prepare_stocks_master(api_key: str, allow_fetch: bool = True) -> tuple[list, str]:
    """
    銘柄マスタを用意する。(銘柄リスト, 取得元) を返す。取得元は "cache" / "jquants" / ""（失敗）

    1. DynamoDB に保存があればそれを使う（J-Quants にアクセスしない）
    2. 無ければ、「取得中」の札を取れたときだけ J-Quants から取り、取れたら DynamoDB に保存する

    [allow_fetch] False なら 1 だけ（起動時用。Lambda の起動は約10秒で打ち切られるので、
                  起動中に J-Quants を待たない。2026-10-10 に起動の時間切れ（INIT timeout）が出ていた）
    """
    cached = load_stocks_master_cache()
    if cached:
        return cached, "cache"
    if not allow_fetch or not acquire_fetch_lock():
        return [], ""
    loaded = fetch_stocks_master_from_jquants(api_key)
    if not loaded:
        return [], ""
    save_stocks_master_cache(loaded)
    return loaded, "jquants"
