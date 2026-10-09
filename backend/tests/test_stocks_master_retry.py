# ===================================================
# 銘柄マスタの取り直し（routers/stock.ensure_stocks_master）
#
# 起動時に J-Quants から取れなかったとき、以前はコンテナが入れ替わるまで
# 日本株の検索・銘柄名が空のままだった。空なら取り直す（ただし60秒に1回まで）。
# ===================================================

import pytest

import routers.stock as stock


@pytest.fixture
def master(monkeypatch):
    """stocks_master を空にし、取り直し関数を偽物に差し替える"""
    data = []
    calls = []

    def fake_reload():
        calls.append(1)
        data[:] = [{"Code": "72030", "CoName": "トヨタ自動車"}]
        return True

    monkeypatch.setattr(stock, "stocks_master", data)
    monkeypatch.setattr(stock, "reload_stocks_master", fake_reload)
    monkeypatch.setattr(stock, "_last_master_retry", 0.0)
    return data, calls


def test_empty_master_is_reloaded_on_search(master):
    data, calls = master
    result = stock.search("トヨタ")
    assert calls == [1]
    assert result == [{"code": "72030", "name": "トヨタ自動車", "market": "JP"}]


def test_name_api_reloads_empty_master(master):
    data, calls = master
    assert stock.get_stock_name("7203") == {"code": "7203", "name": "トヨタ自動車"}
    assert calls == [1]


def test_loaded_master_is_not_reloaded(master):
    data, calls = master
    data.append({"Code": "67580", "CoName": "ソニーグループ"})
    stock.search("ソニー")
    assert calls == []


def test_retry_is_throttled(monkeypatch):
    # 取り直しに失敗し続けても、60秒以内は呼びに行かない
    calls = []
    monkeypatch.setattr(stock, "stocks_master", [])
    monkeypatch.setattr(stock, "reload_stocks_master", lambda: calls.append(1) or False)
    monkeypatch.setattr(stock, "_last_master_retry", 0.0)
    clock = {"now": 1000.0}
    monkeypatch.setattr(stock.time, "monotonic", lambda: clock["now"])

    stock.ensure_stocks_master()
    clock["now"] += 30
    stock.ensure_stocks_master()
    assert calls == [1]

    clock["now"] += stock.STOCKS_MASTER_RETRY_SEC
    stock.ensure_stocks_master()
    assert calls == [1, 1]
