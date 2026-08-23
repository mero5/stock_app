# ===================================================
# AI予測の成績API
#
# 「AI分析はどれくらい当たっているのか」を返す。
# プロンプトを改良したときに、良くなったのか悪くなったのかを
# 数字で確認するための土台。
# ===================================================

from fastapi import APIRouter

from services.predictions import (
    evaluate_pending, get_accuracy_stats, get_recent_predictions,
    VERDICT_THRESHOLD_PCT,
)

router = APIRouter()


@router.get("/stats/accuracy")
def get_accuracy(userId: str = "", evaluate: bool = True):
    """
    AI予測の的中率を返す。

    定期実行の仕組みは持たず、この画面を開いたときに
    判定期限が来た予測をまとめて答え合わせしてから集計する。
    過去の株価は後からでも取得できるので、これで問題ない。

    [evaluate] Falseにすると答え合わせをせず集計だけ返す（表示を速くしたい場合）
    """
    evaluated = {"evaluated": 0, "skipped": 0}
    if evaluate:
        evaluated = evaluate_pending()

    stats = get_accuracy_stats(userId)
    stats["just_evaluated"] = evaluated
    return stats


@router.post("/stats/evaluate")
def run_evaluation(limit: int = 100):
    """答え合わせだけを手動で実行する（動作確認・運用用）"""
    return evaluate_pending(limit)


@router.get("/stats/predictions")
def list_predictions(limit: int = 30, code: str = ""):
    """
    直近の予測履歴を返す。

    [code] 指定するとその銘柄の履歴だけを返す
    """
    return {
        "threshold_pct": VERDICT_THRESHOLD_PCT,
        "predictions": get_recent_predictions(limit=limit, code=code),
    }
