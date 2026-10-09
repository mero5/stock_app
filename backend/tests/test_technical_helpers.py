# ===================================================
# AI分析用の補助関数（services/technical.py）
#
# 株価を取りに行く関数（get_technical_data 等）は外部APIに依存するので対象外。
# ここでは「入力を渡すと結果が決まる」計算・変換の関数だけをテストする。
# ===================================================

from datetime import date

import pytest

from services import clock
from services import technical as t


# ---------------------------------------------------
# safe_float / sanitize：NaN・inf を None にする
# ---------------------------------------------------
@pytest.mark.parametrize("val, expected", [
    (1.234, 1.23),
    ("2.5", 2.5),
    (float("nan"), None),
    (float("inf"), None),
    (None, None),
    ("abc", None),
])
def test_safe_float(val, expected):
    assert t.safe_float(val) == expected


def test_sanitize_nested():
    data = {"a": float("nan"), "b": [1.0, float("-inf"), {"c": 2}]}
    assert t.sanitize(data) == {"a": None, "b": [1.0, None, {"c": 2}]}


# ---------------------------------------------------
# 優先順位
# ---------------------------------------------------
def test_normalize_priority_uses_default_when_empty():
    assert t.normalize_priority(None, "短期") == t.DEFAULT_PRIORITY["短期"]
    assert t.normalize_priority("壊れた値", "長期") == t.DEFAULT_PRIORITY["長期"]


def test_normalize_priority_drops_unknown_and_fills_missing():
    result = t.normalize_priority(["news", "存在しない項目", "macro"], "中期")
    assert result[:2] == ["news", "macro"]
    assert "存在しない項目" not in result
    assert sorted(result) == sorted(t.PRIORITY_ITEMS)  # 9項目すべてがちょうど1回ずつ


def test_build_priority_section_marks_first():
    text = t.build_priority_section(["fundamental", "macro"])
    lines = text.splitlines()
    assert lines[0].startswith("1. ファンダメンタル（最重要）：")
    assert lines[1].startswith("2. マクロ環境：")


# ---------------------------------------------------
# 分析オプション（チェックボックス）
# ---------------------------------------------------
def test_normalize_checks():
    assert t.normalize_checks(None) == t.DEFAULT_CHECKS
    checks = t.normalize_checks({"macro": True, "technical": "yes", "unknown": True})
    assert checks["macro"] is True
    assert checks["technical"] is True   # bool 以外は無視してデフォルトのまま
    assert "unknown" not in checks


def test_filter_priority_by_checks():
    priority = ["technical", "trend", "fundamental", "macro"]
    assert t.filter_priority_by_checks(priority, {"technical": False}) == ["fundamental", "macro"]
    # 全部OFFでも空にはしない
    all_off = {k: False for k in t.DEFAULT_CHECKS}
    assert t.filter_priority_by_checks(priority, all_off) == priority


# ---------------------------------------------------
# 期間の日数・ラベル
# ---------------------------------------------------
def test_resolve_period_days():
    assert t.resolve_period_days() == {"short_max": 14, "medium_max": 90}
    assert t.resolve_period_days({"short_max": "7", "medium_max": "abc"}) == {"short_max": 7, "medium_max": 90}


@pytest.mark.parametrize("period, expected", [
    ("短期", "14日以内"),
    ("中期", "15〜90日"),
    ("長期", "90日超"),
])
def test_get_period_label(period, expected):
    assert t.get_period_label(period) == expected


def test_get_period_label_follows_settings():
    assert t.get_period_label("中期", {"short_max": 7, "medium_max": 60}) == "8〜60日"


# ---------------------------------------------------
# 決算アラート（今日の日付を固定してテストする）
# ---------------------------------------------------
@pytest.fixture
def today(monkeypatch):
    monkeypatch.setattr(clock, "today_jst", lambda: date(2026, 10, 10))


@pytest.mark.parametrize("earnings, period, level", [
    ("2026-10-15", "短期", "danger"),    # 5日後：短期は7日以内が danger
    ("2026-10-22", "短期", "caution"),   # 12日後：14日以内は caution
    ("2026-11-30", "短期", "safe"),
    ("2026-10-20", "中期", "danger"),    # 10日後：中期は14日以内が danger
    ("2026-12-01", "中期", "caution"),   # 52日後：90日以内は caution
    ("2026-12-01", "長期", "danger"),    # 長期は90日以内が danger
])
def test_get_earnings_alert_levels(today, earnings, period, level):
    alert = t.get_earnings_alert(earnings, period)
    assert alert["exists"] is True
    assert alert["level"] == level


@pytest.mark.parametrize("earnings", [None, "", "なし", "2026-10-01", "日付じゃない"])
def test_get_earnings_alert_no_alert(today, earnings):
    alert = t.get_earnings_alert(earnings, "短期")
    assert alert["exists"] is False
    assert alert["level"] == "safe"


def test_get_earnings_alert_uses_jst_today(today):
    assert t.get_earnings_alert("2026-10-10", "短期")["days_to"] == 0


# ---------------------------------------------------
# セクター名の突合（英語のセクター → 日本語のセクターETF名）
# ---------------------------------------------------
@pytest.mark.parametrize("sector, industry, is_jp, expected", [
    ("Consumer Cyclical", "Auto Manufacturers", True, "自動車"),   # 日本株は industry 優先
    ("Technology", "", True, "電気機器"),
    ("Technology", "Semiconductors", False, "テクノロジー"),       # 米国株は sector のみ
    ("Utilities", "", True, None),                                  # 対応ETFなし
    ("", "", True, None),
    ("自動車", "", True, "自動車"),                                 # すでに日本語
])
def test_resolve_sector_name(sector, industry, is_jp, expected):
    assert t.resolve_sector_name(sector, industry, is_jp) == expected


def test_resolve_sector_trend():
    sector_data = {
        "jp": [{"name": "自動車", "change_pct": 1.234, "trend_5d": -0.4}],
        "us": [{"name": "テクノロジー", "change_pct": -0.5, "trend_5d": 2}],
    }
    assert t.resolve_sector_trend("Consumer Cyclical", "Auto Parts", sector_data, "7203.T") \
        == "自動車 +1.23%（5日:-0.40%）"
    assert t.resolve_sector_trend("Technology", "", sector_data, "AAPL") \
        == "テクノロジー -0.50%（5日:+2.00%）"
    assert t.resolve_sector_trend("Real Estate", "", sector_data, "8801.T") == "不明"
    assert t.resolve_sector_trend("Technology", "", None, "AAPL") == "不明"
