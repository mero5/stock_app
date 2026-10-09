# ===================================================
# 銘柄コードの判定・変換（services/stock_code.py）
#
# 2024年から東証は英字入りのコード（285A キオクシア など）を使っている。
# 以前は isdigit() で判定していたため、英字入りの日本株を米国株として扱っていた。
# ===================================================

import pytest

from services.stock_code import is_jp_code, to_jquants_code, to_yf_ticker


@pytest.mark.parametrize("code", ["7203", "72030", "285A", "285A0", "130A", "130A0", "9984"])
def test_jp_codes(code):
    assert is_jp_code(code)


@pytest.mark.parametrize("code", ["AAPL", "MSFT", "BRK-B", "^N225", "7203.T", "", "720", "720300", "285a"])
def test_not_jp_codes(code):
    assert not is_jp_code(code)


@pytest.mark.parametrize(
    "code, expected",
    [
        ("7203", "7203.T"),
        ("72030", "7203.T"),
        ("285A", "285A.T"),
        ("285A0", "285A.T"),
        ("AAPL", "AAPL"),
        ("^N225", "^N225"),
    ],
)
def test_to_yf_ticker(code, expected):
    assert to_yf_ticker(code) == expected


def test_to_jquants_code():
    assert to_jquants_code("7203") == "72030"
    assert to_jquants_code("72030") == "72030"
    assert to_jquants_code("285A") == "285A0"


def test_search_finds_alphanumeric_code(monkeypatch):
    # 「285a」と小文字で打っても、英字入りのコードを前方一致で探せる
    import routers.stock as stock

    master = [
        {"Code": "285A0", "CoName": "キオクシアホールディングス"},
        {"Code": "72030", "CoName": "トヨタ自動車"},
    ]
    monkeypatch.setattr(stock, "stocks_master", master)
    assert stock.search("285a") == [
        {"code": "285A0", "name": "キオクシアホールディングス", "market": "JP"}
    ]
    assert stock.search("7203")[0]["code"] == "72030"
