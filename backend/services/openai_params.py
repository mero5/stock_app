# ===================================================
# OpenAI に渡す「出力の上限」「考える量」の組み立て
#
# 考えるモデル（GPT-5系・GPT-6系）と GPT-4o系でパラメータの決まりが違うので、
# 呼び出し側で分岐を書かずに済むよう、ここにまとめる。
#   ・考えるモデルは max_tokens を受け付けない（400エラーになる）
#     → max_completion_tokens を使う（GPT-4o系もこれを受け付けるので両方そろえる）
#   ・思考トークンも上限に数えられる → 回答の分に思考の分を足す（考えない none のときは不要）
#   ・reasoning_effort は考えるモデルだけ。GPT-4o系に渡すとエラーになる
# ===================================================

from config.ai_models import OPENAI_REASONING_TOKEN_BUDGET

# 考えるモデルの名前の頭
_REASONING_MODEL_PREFIXES = ("gpt-5", "gpt-6")


def is_reasoning_model(model: str) -> bool:
    """考えてから答えるモデル（GPT-5系・GPT-6系）か"""
    return model.startswith(_REASONING_MODEL_PREFIXES)


def openai_limit_params(model: str, answer_tokens: int, effort: str) -> dict:
    """
    chat.completions.create() に足すパラメータを返す。

    [answer_tokens] 回答（JSON・文章）に使ってよいトークン数。
                    考えるモデルでは、これに思考の分を足した値が上限になる。
    [effort]        考える量（none / low / medium …）。GPT-4o系では無視する。
    """
    if not is_reasoning_model(model):
        return {"max_completion_tokens": answer_tokens}
    budget = 0 if effort == "none" else OPENAI_REASONING_TOKEN_BUDGET
    return {
        "max_completion_tokens": answer_tokens + budget,
        "reasoning_effort":      effort,
    }
