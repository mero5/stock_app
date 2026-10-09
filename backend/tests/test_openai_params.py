# ===================================================
# OpenAI に渡すパラメータの組み立て（services/openai_params.py）
#
# GPT-5系と GPT-4o系で決まりが違う。間違えると本番で 400 エラーになったり、
# 思考で上限を使い切って答えが空になったりするので、ここで確かめる。
# ===================================================

from config.ai_models import OPENAI_REASONING_EFFORT, OPENAI_REASONING_TOKEN_BUDGET
from services.openai_params import is_reasoning_model, openai_limit_params


def test_is_reasoning_model():
    assert is_reasoning_model("gpt-5-mini")
    assert is_reasoning_model("gpt-5")
    assert not is_reasoning_model("gpt-4o")
    assert not is_reasoning_model("gpt-4o-mini")


def test_gpt5_adds_reasoning_budget():
    """思考の分を足さないと、市況コメント（300）は考えるだけで上限を使い切る"""
    params = openai_limit_params("gpt-5-mini", 300)
    assert params == {
        "max_completion_tokens": 300 + OPENAI_REASONING_TOKEN_BUDGET,
        "reasoning_effort":      OPENAI_REASONING_EFFORT,
    }


def test_gpt4o_uses_answer_tokens_only():
    assert openai_limit_params("gpt-4o-mini", 3000) == {"max_completion_tokens": 3000}
