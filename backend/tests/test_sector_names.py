# ===================================================
# セクターETFの名前と、銘柄のセクター → セクターETF の対応表の食い違いを検出する
#
# 以前は日本のセクターETF 17本中15本の名前がずれていて（1617「食品」を「電気機器」など）、
# マーケット画面と AI に渡すセクターの動きが間違っていた（K-45）。
# ===================================================

from routers.market import JP_SECTOR_ETFS, US_SECTOR_ETFS
from services.technical import INDUSTRY_KEYWORD_TO_JP, SECTOR_EN_TO_JP, SECTOR_EN_TO_US

# JPX「銘柄一覧（ETF）日本株（業種別）」https://www.jpx.co.jp/equities/products/etfs/issues/01-03.html
# 2026-10-10 にブラウザで確認した、NEXT FUNDS TOPIX-17 シリーズのコードと連動指数「TOPIX-17 ○○」
JPX_TOPIX17 = {
    "1617.T": "食品", "1618.T": "エネルギー資源", "1619.T": "建設・資材", "1620.T": "素材・化学",
    "1621.T": "医薬品", "1622.T": "自動車・輸送機", "1623.T": "鉄鋼・非鉄", "1624.T": "機械",
    "1625.T": "電機・精密", "1626.T": "情報通信・サービスその他", "1627.T": "電力・ガス",
    "1628.T": "運輸・物流", "1629.T": "商社・卸売", "1630.T": "小売", "1631.T": "銀行",
    "1632.T": "金融（除く銀行）", "1633.T": "不動産",
}


def test_jp_sector_names_match_jpx():
    assert {code: name for name, code in JP_SECTOR_ETFS.items()} == JPX_TOPIX17


def test_jp_mapping_targets_exist():
    names = set(JP_SECTOR_ETFS)
    targets = set(SECTOR_EN_TO_JP.values()) | {name for _, name in INDUSTRY_KEYWORD_TO_JP}
    assert targets <= names, targets - names


def test_us_mapping_targets_exist():
    assert set(SECTOR_EN_TO_US.values()) <= set(US_SECTOR_ETFS)
