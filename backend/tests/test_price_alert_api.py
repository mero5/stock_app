# ===================================================
# 株価アラート・プッシュ通知の API（routers/price_alerts.py）と FCM の送信（services/push.py）
#
# ログインの確認（main.verify_request_token）・DynamoDB・FCM は偽物に差し替える。
# ===================================================

import os

import pytest
from fastapi.testclient import TestClient

# main.py は import した瞬間に OpenAI のクライアントを作り、鍵が無いとエラーになる（通信はしない）
os.environ.setdefault("OPENAI_API_KEY", "testing")

import main  # noqa: E402
import routers.price_alerts as router  # noqa: E402
from services import push  # noqa: E402
from services import price_alerts as pa  # noqa: E402
from services.auth import AuthResult  # noqa: E402
from tests.test_price_alerts import MemoryTable  # noqa: E402

AUTH = {"Authorization": "Bearer ok"}


@pytest.fixture
def client(monkeypatch):
    # "Bearer ok" だけを本物のトークンとして扱う
    monkeypatch.setattr(
        main, "verify_request_token",
        lambda h: AuthResult("valid", user_id="u1") if h == "Bearer ok" else AuthResult("none"),
    )
    monkeypatch.setattr(pa, "price_alerts_table", MemoryTable())
    return TestClient(main.app)


def test_requires_login(client):
    assert client.get("/alerts").status_code == 401
    assert client.post("/alerts", json={}).status_code == 401
    assert client.post("/push/token", json={"token": "t"}).status_code == 401
    assert client.post("/push/test").status_code == 401


def test_create_list_update_delete(client):
    res = client.post("/alerts", headers=AUTH, json={
        "code": "7203", "name": "トヨタ", "condition": "price_above", "target": 3000, "repeat": "once",
        # userId を送っても使わない（トークンの持ち主を使う）
        "userId": "someone-else",
    }).json()
    alert_id = res["alert"]["alert_id"]
    assert res["alert"]["userId"] == "u1"

    alerts = client.get("/alerts", headers=AUTH).json()["alerts"]
    assert [a["alert_id"] for a in alerts] == [alert_id]
    assert alerts[0]["target"] == 3000.0

    assert client.post("/alerts/update", headers=AUTH, json={"alert_id": alert_id, "enabled": False}).json() == {"success": True}
    assert client.get("/alerts", headers=AUTH).json()["alerts"][0]["enabled"] is False
    assert "error" in client.post("/alerts/update", headers=AUTH, json={"alert_id": "nothing", "enabled": True}).json()

    assert client.post("/alerts/delete", headers=AUTH, json={"alert_id": alert_id}).json() == {"success": True}
    assert client.get("/alerts", headers=AUTH).json()["alerts"] == []


def test_create_rejects_bad_input_and_limit(client):
    assert "error" in client.post("/alerts", headers=AUTH, json={"code": "7203", "condition": "x", "target": 1}).json()
    body = {"code": "7203", "condition": "price_above", "target": 1}
    for _ in range(pa.MAX_ALERTS_PER_USER):
        assert "alert" in client.post("/alerts", headers=AUTH, json=body).json()
    assert "10件まで" in client.post("/alerts", headers=AUTH, json=body).json()["error"]


def test_push_token_and_test_notification(client, monkeypatch):
    saved, sent_to = [], []
    monkeypatch.setattr(push, "save_token", lambda user, token, platform: saved.append((user, token, platform)))
    assert client.post("/push/token", headers=AUTH, json={"token": "fcm-1", "platform": "ios"}).json() == {"success": True}
    assert saved == [("u1", "fcm-1", "ios")]

    monkeypatch.setattr(push, "send_to_user", lambda user, title, body, data: sent_to.append(user) or 1)
    assert client.post("/push/test", headers=AUTH).json() == {"success": True, "sent": 1}
    assert sent_to == ["u1"]

    monkeypatch.setattr(push, "send_to_user", lambda *a: 0)
    assert "端末がありません" in client.post("/push/test", headers=AUTH).json()["error"]


# ===================================================
# FCM の送信
# ===================================================
class FakeResponse:
    def __init__(self, status_code, body=None):
        self.status_code = status_code
        self._body = body or {}
        self.ok = 200 <= status_code < 300
        self.text = str(body)

    def json(self):
        return self._body


def _unregistered():
    return FakeResponse(404, {"error": {"details": [{"errorCode": "UNREGISTERED"}]}})


def test_send_to_user_deletes_dead_tokens(monkeypatch):
    responses = {"good": FakeResponse(200), "dead": _unregistered(), "busy": FakeResponse(503)}
    deleted = []
    monkeypatch.setattr(push, "FCM_PROJECT_ID", "test-project")
    monkeypatch.setattr(push, "_access_token", lambda: "google-token")
    monkeypatch.setattr(push, "get_tokens", lambda user: ["good", "dead", "busy"])
    monkeypatch.setattr(push, "delete_token", lambda user, token: deleted.append(token))
    monkeypatch.setattr(push.requests, "post",
                        lambda url, headers, json, timeout: responses[json["message"]["token"]])

    assert push.send_to_user("u1", "タイトル", "本文", {"code": "7203"}) == 1
    assert deleted == ["dead"]  # 一時的な失敗（503）のトークンは消さない


def test_build_message_sends_data_as_strings():
    message = push.build_message("t", "タイトル", "本文", {"code": "7203", "n": 1})["message"]
    assert message["token"] == "t"
    assert message["data"] == {"code": "7203", "n": "1"}
    assert message["apns"]["payload"]["aps"]["sound"] == "default"


def test_dead_token_error_only_for_unregistered():
    assert push.is_dead_token_error(_unregistered()) is True
    assert push.is_dead_token_error(FakeResponse(400, {"error": {"details": [{"errorCode": "INVALID_ARGUMENT"}]}})) is False
    assert push.is_dead_token_error(FakeResponse(500)) is False
