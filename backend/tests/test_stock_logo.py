# ===================================================
# 銘柄の画像の URL（services/stock_logo.py）
# ===================================================

import pytest

from services import stock_logo as sl


class StoringTable:
    def __init__(self):
        self.item = None

    def put_item(self, Item):
        self.item = Item

    def get_item(self, Key):
        return {"Item": self.item} if self.item else {}


@pytest.mark.parametrize("website, expected", [
    ("https://global.toyota", "global.toyota"),   # 2026-10-10 に yfinance で取った値
    ("https://www.apple.com", "apple.com"),
    ("https://www.mufg.jp/", "mufg.jp"),
    ("www.example.co.jp", "example.co.jp"),
    ("", None),
    (None, None),
])
def test_website_domain(website, expected):
    assert sl.website_domain(website) == expected


def _fake_ticker(monkeypatch, website, calls):
    class FakeTicker:
        def __init__(self, code):
            calls.append(code)
            self.info = {"website": website} if website is not None else {}

    monkeypatch.setattr(sl.yf, "Ticker", FakeTicker)


def test_logo_url_and_cache(monkeypatch):
    calls = []
    _fake_ticker(monkeypatch, "https://global.toyota", calls)
    table = StoringTable()

    url = sl.get_logo_url("72030", table)
    assert url == "https://www.google.com/s2/favicons?domain=global.toyota&sz=128"
    assert calls == ["7203.T"]  # yfinance 用のコードで聞く

    # 2回目は保存した Web サイトを使い、yfinance を呼ばない
    assert sl.get_logo_url("72030", table) == url
    assert calls == ["7203.T"]


def test_no_website_returns_none_and_is_cached(monkeypatch):
    calls = []
    _fake_ticker(monkeypatch, None, calls)
    table = StoringTable()
    assert sl.get_logo_url("285A0", table) is None
    assert sl.get_logo_url("285A0", table) is None
    assert calls == ["285A.T"]  # 無かったことも保存する


def test_error_returns_none(monkeypatch):
    class Broken:
        def __init__(self, code):
            raise RuntimeError("yfinance error")

    monkeypatch.setattr(sl.yf, "Ticker", Broken)
    table = StoringTable()
    assert sl.get_logo_url("AAPL", table) is None
    assert table.item is None  # 失敗は保存しない
