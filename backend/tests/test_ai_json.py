# ===================================================
# AIの返事の受け取り方（routers/ai.py）
#
# 本物の OpenAI は呼ばない。FakeOpenAI（決まった返事を返す偽物）に差し替えて、
# 「AIがこう返してきたら、アプリはこう処理する」だけを確かめる。→ AI代は0円
# ===================================================

import json
from types import SimpleNamespace

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from config.ai_models import (
    OPENAI_ANALYSIS_MODEL, OPENAI_LIGHT_MODEL,
    OPENAI_REASONING_EFFORT, OPENAI_REASONING_TOKEN_BUDGET,
)
from routers import ai


class FakeOpenAI:
    """openai_client.chat.completions.create(...) の偽物"""

    def __init__(self, content, finish_reason="stop"):
        self.content = content
        self.finish_reason = finish_reason
        self.calls = []
        self.chat = SimpleNamespace(completions=SimpleNamespace(create=self._create))

    def _create(self, **kwargs):
        self.calls.append(kwargs)
        return SimpleNamespace(
            choices=[SimpleNamespace(
                finish_reason=self.finish_reason,
                message=SimpleNamespace(content=self.content),
            )],
            usage=SimpleNamespace(prompt_tokens=100, completion_tokens=50),
            model="gpt-4o-mini",
        )


@pytest.fixture
def use_fake_ai(monkeypatch):
    def _use(content, finish_reason="stop"):
        fake = FakeOpenAI(content, finish_reason)
        monkeypatch.setattr(ai, "openai_client", fake)
        return fake
    return _use


# ---------------------------------------------------
# call_openai_json
# ---------------------------------------------------
def test_call_openai_json_parses_json(use_fake_ai):
    fake = use_fake_ai('{"verdict": "up"}')

    result, usage = ai.call_openai_json("prompt", system="sys", model="gpt-4o-mini")

    assert result == {"verdict": "up"}
    assert usage == {"prompt_tokens": 100, "completion_tokens": 50, "model": "gpt-4o-mini"}
    # JSONモードで呼んでいる（JSON以外を返させない）
    assert fake.calls[0]["response_format"] == {"type": "json_object"}


def test_call_openai_json_strips_code_fence(use_fake_ai):
    use_fake_ai('```json\n{"a": 1}\n```')
    result, _ = ai.call_openai_json("p", system="s")
    assert result == {"a": 1}


def test_call_openai_json_detects_truncation(use_fake_ai):
    use_fake_ai('{"a": ', finish_reason="length")
    with pytest.raises(ValueError, match="max_tokens"):
        ai.call_openai_json("p", system="s")


def test_call_openai_json_uses_gpt5_params_by_default(use_fake_ai):
    """既定（分析用）は GPT-5系。max_tokens は送らず、思考の分を足した上限と考える量を送る"""
    fake = use_fake_ai('{"a": 1}')
    ai.call_openai_json("p", system="s", max_tokens=4000)

    call = fake.calls[0]
    assert call["model"] == OPENAI_ANALYSIS_MODEL
    assert call["model"].startswith("gpt-5")
    # GPT-5系に max_tokens を送ると 400 エラーになる
    assert "max_tokens" not in call
    assert call["max_completion_tokens"] == 4000 + OPENAI_REASONING_TOKEN_BUDGET
    assert call["reasoning_effort"] == OPENAI_REASONING_EFFORT


def test_call_openai_json_light_model_has_no_reasoning(use_fake_ai):
    """gpt-4o-mini（相談）には reasoning_effort を送らない（送るとエラーになる）"""
    fake = use_fake_ai('{"a": 1}')
    ai.call_openai_json("p", system="s", max_tokens=3000, model=OPENAI_LIGHT_MODEL)

    call = fake.calls[0]
    assert "max_tokens" not in call
    assert "reasoning_effort" not in call
    assert call["max_completion_tokens"] == 3000


def test_call_openai_json_raises_on_broken_json(use_fake_ai):
    use_fake_ai("はい、分析します。{")
    with pytest.raises(json.JSONDecodeError):
        ai.call_openai_json("p", system="s")


# ---------------------------------------------------
# classify_error：例外 → ユーザー向けメッセージ
# ---------------------------------------------------
@pytest.mark.parametrize("message, error_type", [
    ("AIの回答が長すぎて途中で切れました（max_tokens超過）", "truncated"),
    ("Rate limit reached", "rate_limit"),
    ("Request timed out", "timeout"),
    ("Connection refused", "connection"),
    ("No data found for this date range", "data_fetch"),
    ("Unable to locate credentials", "database"),
    ("something else", "unknown"),
])
def test_classify_error(message, error_type):
    res = ai.classify_error(RuntimeError(message))
    assert res["error_type"] == error_type
    assert res["error"]  # 日本語メッセージが入っている
    assert message in res["error_detail"]


# ---------------------------------------------------
# /stock/consult（AI相談）
# 再発防止：PR #13（AIが壊れたJSONを返すと「予期せぬエラー」になっていた）
# ---------------------------------------------------
@pytest.fixture
def client():
    app = FastAPI()
    app.include_router(ai.router)
    return TestClient(app)


CONSULT_BODY = {
    "code": "7203", "name": "トヨタ", "direction": "買い", "trade_type": "現物",
    "period": "短期", "extra_questions": ["損切りライン"], "price": 2500,
}


def test_consult_returns_ai_json(client, use_fake_ai):
    answer = {"judgment": "適切", "judgment_reason": "r", "advice": "a", "caution": "c",
              "stop_loss": "2300円", "fundamental_comment": ""}
    fake = use_fake_ai(json.dumps(answer, ensure_ascii=False))

    res = client.post("/stock/consult", json=CONSULT_BODY)

    assert res.status_code == 200
    assert res.json() == answer
    prompt = fake.calls[0]["messages"][1]["content"]
    assert "トヨタ（7203）" in prompt
    assert "損切りライン" in prompt


def test_consult_handles_broken_json(client, use_fake_ai):
    use_fake_ai("申し訳ありません、")

    res = client.post("/stock/consult", json=CONSULT_BODY)

    assert res.status_code == 200
    assert res.json()["error_type"] == "parse_error"


def test_consult_handles_truncation(client, use_fake_ai):
    use_fake_ai('{"judgment": ', finish_reason="length")

    res = client.post("/stock/consult", json=CONSULT_BODY)

    assert res.json()["error_type"] == "truncated"
