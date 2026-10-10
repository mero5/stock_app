# ===================================================
# 日本株の決算発表予定日（services/jp_earnings.py）
#
# 以前は V2 に存在しない /v2/fins/announcement を呼んでいて、
# 日本株の決算日が一度も出ていなかった（K-47）。
# ===================================================

from services import jp_earnings as je


class FakeResponse:
    def __init__(self, body, status_code=200):
        self._body = body
        self.status_code = status_code
        self.text = str(body)

    def json(self):
        return self._body


class StoringTable:
    def __init__(self):
        self.item = None

    def put_item(self, Item):
        self.item = Item

    def get_item(self, Key):
        return {"Item": self.item} if self.item else {}


# 公式ドキュメントのレスポンスの形（https://jpx-jquants.com/ja/spec/fin-earnings-date）
RECORDS = [
    # 2Q：最初は 10/30 と公表 → 11/05 に変更（新しい PubDate の行が増える）
    {"PubDate": "2026-09-01", "SchDate": "2026-10-30", "FQName": "2Q", "FYE": "0331", "Code": "72030"},
    {"PubDate": "2026-09-20", "SchDate": "2026-11-05", "FQName": "2Q", "FYE": "0331", "Code": "72030"},
    # 3Q：公表後に「未定」（SchDate が ""）に変更 → 出さない
    {"PubDate": "2026-09-01", "SchDate": "2027-02-05", "FQName": "3Q", "FYE": "0331", "Code": "72030"},
    {"PubDate": "2026-09-25", "SchDate": "", "FQName": "3Q", "FYE": "0331", "Code": "72030"},
    # 1Q：もう終わった
    {"PubDate": "2026-06-01", "SchDate": "2026-08-01", "FQName": "1Q", "FYE": "0331", "Code": "72030"},
    # FY
    {"PubDate": "2026-09-01", "SchDate": "2027-05-08", "FQName": "FY", "FYE": "0331", "Code": "72030"},
]


def test_upcoming_dates_uses_latest_record_per_quarter():
    assert je.upcoming_dates(RECORDS, "2026-10-10") == ["2026-11-05", "2027-05-08"]


def test_upcoming_dates_limit_and_today_included():
    assert je.upcoming_dates(RECORDS, "2026-11-05", limit=1) == ["2026-11-05"]


def test_fetch_follows_pagination_and_caches():
    calls = []

    def fake_get(url, headers, params, timeout):
        calls.append(dict(params))
        if "pagination_key" not in params:
            return FakeResponse({"data": RECORDS[:3], "pagination_key": "next"})
        return FakeResponse({"data": RECORDS[3:]})

    table = StoringTable()
    assert je.get_jp_earnings_dates("72030", "key", "2026-10-10", http_get=fake_get, table=table) \
        == ["2026-11-05", "2027-05-08"]
    assert calls == [{"code": "72030"}, {"code": "72030", "pagination_key": "next"}]
    assert je.JQUANTS_EARNINGS_DATE_URL.endswith("/v2/fins/earnings-date")

    # 2回目は保存したものを使い、J-Quants を呼ばない（無料プランは1分5回まで）
    def must_not_call(*a, **k):
        raise AssertionError("J-Quants を呼んだ")

    assert je.get_jp_earnings_dates("72030", "key", "2026-10-10", http_get=must_not_call, table=table) \
        == ["2026-11-05", "2027-05-08"]


def test_http_error_returns_empty_and_does_not_cache():
    def fake_get(url, headers, params, timeout):
        return FakeResponse({"message": "Too Many Requests"}, status_code=429)

    table = StoringTable()
    assert je.get_jp_earnings_dates("72030", "key", "2026-10-10", http_get=fake_get, table=table) == []
    assert table.item is None  # 失敗は保存しない（次のリクエストで取り直す）


def test_no_records_is_cached_as_empty():
    def fake_get(url, headers, params, timeout):
        return FakeResponse({"data": []})

    table = StoringTable()
    assert je.get_jp_earnings_dates("13010", "key", "2026-10-10", http_get=fake_get, table=table) == []
    assert table.item["records"] == []


def test_stock_events_returns_jp_earnings(monkeypatch):
    import routers.stock as stock

    class FakeTicker:
        def __init__(self, symbol):
            self.info = {"longName": "トヨタ自動車"}

    monkeypatch.setattr(stock.yf, "Ticker", FakeTicker)
    monkeypatch.setattr(stock, "today_jst", lambda: __import__("datetime").date(2026, 10, 10))
    got = {}

    def fake_dates(code5, api_key, today_str):
        got["args"] = (code5, today_str)
        return ["2026-11-05"]

    monkeypatch.setattr(stock, "get_jp_earnings_dates", fake_dates)
    events = stock.get_stock_events("7203")
    assert got["args"] == ("72030", "2026-10-10")  # J-Quants は5桁コード
    assert {"code": "7203", "name": "トヨタ自動車", "date": "2026-11-05", "type": "earnings",
            "label": "トヨタ自動車 決算発表", "color": "red"} in events

