# ===================================================
# OpenAI に渡すパラメータの組み立て（services/openai_params.py）
#
# 考えるモデル（GPT-5系・GPT-6系）と GPT-4o系で決まりが違う。間違えると本番で
# 400 エラーになったり、思考で上限を使い切って答えが空になったりするので、ここで確かめる。
# ===================================================

from config.ai_models import OPENAI_REASONING_TOKEN_BUDGET
from services.openai_params import is_reasoning_model, openai_limit_params


def test_is_reasoning_model():
    assert is_reasoning_model("gpt-6-luna")
    assert is_reasoning_model("gpt-5-mini")
    assert not is_reasoning_model("gpt-4o")
    assert not is_reasoning_model("gpt-4o-mini")


def test_reasoning_model_adds_budget():
    """思考の分を足さないと、市況コメント（300）は考えるだけで上限を使い切る"""
    assert openai_limit_params("gpt-6-luna", 300, "low") == {
        "max_completion_tokens": 300 + OPENAI_REASONING_TOKEN_BUDGET,
        "reasoning_effort":      "low",
    }


def test_effort_none_needs_no_budget():
    """考えない（none）ときは思考の分を足さない"""
    assert openai_limit_params("gpt-6-luna", 500, "none") == {
        "max_completion_tokens": 500,
        "reasoning_effort":      "none",
    }


def test_gpt4o_ignores_effort():
    assert openai_limit_params("gpt-4o-mini", 3000, "low") == {"max_completion_tokens": 3000}
