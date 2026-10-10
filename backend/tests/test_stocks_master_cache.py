# ===================================================
# 銘柄マスタの DynamoDB 保存と J-Quants のページ送り（services/stocks_master.py）
#
# 以前は Lambda の起動のたびに J-Quants から取り直していて、同時に何台も起動すると
# 一部の台で失敗し、銘柄名がコードのまま・/health が J-Quants エラーになっていた。
# ===================================================

from datetime import datetime, timedelta

from services import cache
from services import stocks_master as sm


class FakeResponse:
    def __init__(self, body, status_code=200):
        self._body = body
        self.status_code = status_code
        self.text = str(body)

    def json(self):
        return self._body


class StoringTable:
    """put_item したものを get_item で返す DynamoDB の偽物"""

    def __init__(self):
        self.item = None

    def put_item(self, Item):
        self.item = Item

    def get_item(self, Key):
        return {"Item": self.item} if self.item else {}


MASTER = [
    {"Code": "72030", "CoName": "トヨタ自動車", "Sector17": "6"},
    {"Code": "285A0", "CoName": "キオクシアホールディングス", "Sector17": "9"},
]


def test_cache_round_trip_keeps_only_code_and_name():
    table = StoringTable()
    sm.save_stocks_master_cache(sm._slim(MASTER), table)
    assert table.item["count"] == 2
    assert isinstance(table.item["data_gz"], bytes)  # 圧縮して1件に入れる
    assert sm.load_stocks_master_cache(table) == [
        {"Code": "72030", "CoName": "トヨタ自動車"},
        {"Code": "285A0", "CoName": "キオクシアホールディングス"},
    ]


def test_cache_reads_boto3_binary():
    # DynamoDB から読むと bytes ではなく Binary 型（.value に bytes）で返る
    class Binary:
        def __init__(self, value):
            self.value = value

    table = StoringTable()
    sm.save_stocks_master_cache(sm._slim(MASTER), table)
    table.item["data_gz"] = Binary(table.item["data_gz"])
    assert len(sm.load_stocks_master_cache(table)) == 2


def test_expired_cache_is_ignored(monkeypatch):
    table = StoringTable()
    sm.save_stocks_master_cache(sm._slim(MASTER), table)
    later = datetime.fromisoformat(table.item["expires_at"]) + timedelta(minutes=1)
    monkeypatch.setattr(cache, "now_jst", lambda: later)
    assert sm.load_stocks_master_cache(table) == []


def test_broken_cache_returns_empty():
    table = StoringTable()
    table.item = {"cache_key": "stocks_master_v1", "data_gz": b"not gzip"}
    assert sm.load_stocks_master_cache(table) == []


def test_fetch_follows_pagination():
    calls = []

    def fake_get(url, headers, params, timeout):
        calls.append(dict(params))
        if not params:
            return FakeResponse({"data": MASTER[:1], "pagination_key": "next"})
        return FakeResponse({"data": MASTER[1:]})

    result = sm.fetch_stocks_master_from_jquants("key", http_get=fake_get)
    assert calls == [{}, {"pagination_key": "next"}]
    assert [s["Code"] for s in result] == ["72030", "285A0"]


def test_fetch_returns_empty_on_http_error():
    def fake_get(url, headers, params, timeout):
        return FakeResponse({"message": "Too Many Requests"}, status_code=429)

    assert sm.fetch_stocks_master_from_jquants("key", http_get=fake_get) == []


def test_fetch_returns_empty_on_exception():
    def fake_get(url, headers, params, timeout):
        raise TimeoutError("timeout")

    assert sm.fetch_stocks_master_from_jquants("key", http_get=fake_get) == []


def test_prepare_uses_cache_without_calling_jquants(monkeypatch):
    monkeypatch.setattr(sm, "load_stocks_master_cache", lambda: sm._slim(MASTER))
    monkeypatch.setattr(sm, "fetch_stocks_master_from_jquants",
                        lambda key: (_ for _ in ()).throw(AssertionError("J-Quants を呼んだ")))
    loaded, source = sm.prepare_stocks_master("key")
    assert source == "cache"
    assert len(loaded) == 2


def test_prepare_fetches_and_saves_when_no_cache(monkeypatch):
    saved = []
    monkeypatch.setattr(sm, "load_stocks_master_cache", lambda: [])
    monkeypatch.setattr(sm, "acquire_fetch_lock", lambda: True)
    monkeypatch.setattr(sm, "fetch_stocks_master_from_jquants", lambda key: sm._slim(MASTER))
    monkeypatch.setattr(sm, "save_stocks_master_cache", lambda master: saved.append(master))
    loaded, source = sm.prepare_stocks_master("key")
    assert source == "jquants"
    assert saved == [loaded]


def test_prepare_does_not_save_when_fetch_fails(monkeypatch):
    saved = []
    monkeypatch.setattr(sm, "load_stocks_master_cache", lambda: [])
    monkeypatch.setattr(sm, "acquire_fetch_lock", lambda: True)
    monkeypatch.setattr(sm, "fetch_stocks_master_from_jquants", lambda key: [])
    monkeypatch.setattr(sm, "save_stocks_master_cache", lambda master: saved.append(master))
    assert sm.prepare_stocks_master("key") == ([], "")
    assert saved == []


# ---------------------------------------------------
# 2026-10-10 デプロイ後の J-Quants 回数制限（HTTP 429）対策
# ---------------------------------------------------
def test_slim_removes_duplicate_codes_keeping_latest_date():
    # J-Quants は同じ銘柄を日付違いで何行も返す（22,210行 → 約4,400銘柄）
    rows = [
        {"Date": "2026-07-17", "Code": "72030", "CoName": "トヨタ自動車（旧）"},
        {"Date": "2026-07-18", "Code": "72030", "CoName": "トヨタ自動車"},
        {"Date": "2026-07-18", "Code": "67580", "CoName": "ソニーグループ"},
        {"Date": "2026-07-16", "Code": "72030", "CoName": "トヨタ自動車（もっと旧）"},
    ]
    assert sm._slim(rows) == [
        {"Code": "72030", "CoName": "トヨタ自動車"},
        {"Code": "67580", "CoName": "ソニーグループ"},
    ]


class LockTable:
    """条件付き書き込み（attribute_not_exists OR lock_until < :now）を再現する DynamoDB の偽物"""

    def __init__(self):
        self.item = None

    def put_item(self, Item, ConditionExpression=None, ExpressionAttributeValues=None):
        now = ExpressionAttributeValues[":now"]
        if self.item is not None and self.item["lock_until"] >= now:
            raise RuntimeError("ConditionalCheckFailedException")
        self.item = Item


def test_fetch_lock_only_one_container_at_a_time():
    table = LockTable()
    assert sm.acquire_fetch_lock(table, now=1000) is True
    assert sm.acquire_fetch_lock(table, now=1001) is False      # ほかのコンテナは取りに行かない
    assert sm.acquire_fetch_lock(table, now=1000 + sm.STOCKS_MASTER_LOCK_SEC + 1) is True  # 期限が切れたら取れる


def test_prepare_does_not_fetch_without_lock(monkeypatch):
    monkeypatch.setattr(sm, "load_stocks_master_cache", lambda: [])
    monkeypatch.setattr(sm, "acquire_fetch_lock", lambda: False)
    monkeypatch.setattr(sm, "fetch_stocks_master_from_jquants",
                        lambda key: (_ for _ in ()).throw(AssertionError("J-Quants を呼んだ")))
    assert sm.prepare_stocks_master("key") == ([], "")


def test_prepare_on_startup_never_calls_jquants(monkeypatch):
    # 起動時（allow_fetch=False）は DynamoDB を読むだけ。Lambda の起動の時間切れを防ぐ
    monkeypatch.setattr(sm, "load_stocks_master_cache", lambda: [])
    monkeypatch.setattr(sm, "acquire_fetch_lock",
                        lambda: (_ for _ in ()).throw(AssertionError("札を取りに行った")))
    assert sm.prepare_stocks_master("key", allow_fetch=False) == ([], "")
