# ===================================================
# 配当利回り（services/market_data.dividend_yield_pct）
#
# yfinance の dividendYield は版によって単位が「割合」と「%」で変わり、
# 以前は ×100 していたのでトヨタが「344%」になっていた（K-46）。
# ===================================================

import pytest

import routers.stock as stock
from services.market_data import dividend_yield_pct


@pytest.mark.parametrize("info, expected", [
    # 2026-10-10 に yfinance 1.7.0 で取った実際の値
    ({"dividendRate": 100.0, "currentPrice": 2910.5, "dividendYield": 3.44}, 3.44),   # トヨタ
    ({"dividendRate": 1.08, "currentPrice": 336.64, "dividendYield": 0.32}, 0.32),    # Apple
    # 年間配当額が無いときは dividendYield（今の版は %）を使う
    ({"dividendRate": None, "currentPrice": 17505.0, "dividendYield": 0.0}, 0.0),     # 無配
    # 株価が currentPrice に無いときは regularMarketPrice・previousClose
    ({"dividendRate": 96.0, "regularMarketPrice": 3462.0}, 2.77),
    ({"dividendRate": 96.0, "previousClose": 3462.0}, 2.77),
    # 何も無い
    ({}, None),
    (None, None),
])
def test_dividend_yield_pct(info, expected):
    assert dividend_yield_pct(info) == expected


def test_detail_api_returns_ratio_for_app():
    # アプリ（detail_screen）は割合を ×100 して表示するので、詳細APIは割合で返す
    assert stock._pct_to_ratio(3.44) == 0.0344
    assert stock._pct_to_ratio(None) is None
