# ===================================================
# OpenAI に渡す「出力の上限」「考える量」の組み立て
#
# GPT-5系と GPT-4o系でパラメータの決まりが違うので、
# 呼び出し側で分岐を書かずに済むよう、ここにまとめる。
#   ・GPT-5系は max_tokens を受け付けない（400エラーになる）
#     → max_completion_tokens を使う（GPT-4o系もこれを受け付けるので両方そろえる）
#   ・GPT-5系は思考トークンも上限に数えられる → 回答の分に思考の分を足す
#   ・reasoning_effort は GPT-5系だけ。GPT-4o系に渡すとエラーになる
# ===================================================

from config.ai_models import OPENAI_REASONING_EFFORT, OPENAI_REASONING_TOKEN_BUDGET


def is_reasoning_model(model: str) -> bool:
    """考えてから答えるモデル（GPT-5系）か"""
    return model.startswith("gpt-5")


def openai_limit_params(model: str, answer_tokens: int) -> dict:
    """
    chat.completions.create() に足すパラメータを返す。

    [answer_tokens] 回答（JSON・文章）に使ってよいトークン数。
                    GPT-5系では、これに思考の分を足した値が上限になる。
    """
    if not is_reasoning_model(model):
        return {"max_completion_tokens": answer_tokens}
    return {
        "max_completion_tokens": answer_tokens + OPENAI_REASONING_TOKEN_BUDGET,
        "reasoning_effort":      OPENAI_REASONING_EFFORT,
    }
