# ===================================================
# 投資プロファイルの取得（routers/user.get_user_profile）
#
# アプリは "exists": False を見て「未登録＝初回設定に進む」と判断する。
# 以前は DynamoDB のエラーでも "exists": False を返していたため、
# 登録済みのユーザーが初回設定に進み、既定値で上書き保存しうる状態だった（課題 K-36）。
# ===================================================

import asyncio

import routers.user as user


def _get(user_id="u1"):
    return asyncio.run(user.get_user_profile(user_id))


def test_未登録ならexists_falseを返す(monkeypatch, fake_table):
    monkeypatch.setattr(user, "user_profile_table", fake_table(item=None))
    assert _get() == {"exists": False}


def test_登録済みならexists_trueと既定値の補完(monkeypatch, fake_table):
    monkeypatch.setattr(user, "user_profile_table", fake_table(item={"userId": "u1", "risk_level": "高"}))
    result = _get()
    assert result["exists"] is True
    assert result["risk_level"] == "高"
    assert "priority_short" in result
    assert "period_short_max_days" in result


class _BrokenTable:
    def get_item(self, Key):
        raise RuntimeError("DynamoDB throttled")


def test_DynamoDBのエラーは未登録扱いにしない(monkeypatch):
    monkeypatch.setattr(user, "user_profile_table", _BrokenTable())
    result = _get()
    assert "error" in result
    assert "exists" not in result
