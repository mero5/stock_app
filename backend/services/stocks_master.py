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


def _slim(master: list) -> list:
    """使う項目（Code・CoName）だけに絞る"""
    return [
        {"Code": s.get("Code", ""), "CoName": s.get("CoName", "")}
        for s in master
        if s.get("Code")
    ]


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


def prepare_stocks_master(api_key: str) -> tuple[list, str]:
    """
    銘柄マスタを用意する。(銘柄リスト, 取得元) を返す。取得元は "cache" / "jquants" / ""（失敗）

    1. DynamoDB に保存があればそれを使う（J-Quants にアクセスしない）
    2. 無ければ J-Quants から取り、取れたら DynamoDB に保存する
    """
    cached = load_stocks_master_cache()
    if cached:
        return cached, "cache"
    loaded = fetch_stocks_master_from_jquants(api_key)
    if not loaded:
        return [], ""
    save_stocks_master_cache(loaded)
    return loaded, "jquants"
