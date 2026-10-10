# ===================================================
# AI予測の成績API
#
# 「AI分析はどれくらい当たっているのか」を返す。
# プロンプトを改良したときに、良くなったのか悪くなったのかを
# 数字で確認するための土台。
# ===================================================

from fastapi import APIRouter, Request

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
def list_predictions(request: Request, limit: int = 30, code: str = "", userId: str = ""):
    """
    直近の予測履歴を返す。

    [code]   指定するとその銘柄の履歴だけを返す
    [userId] その人の予測だけを返す（/stats/accuracy と同じ）。
             userId を送らない古いアプリ（ビルド22以前）でも他人の予測が出ないよう、
             ログインのトークン（#30 でアプリが付けている）が本物ならその持ち主で絞る
    """
    user_id = userId or _token_user_id(request)
    return {
        "threshold_pct": VERDICT_THRESHOLD_PCT,
        "predictions": get_recent_predictions(limit=limit, code=code, user_id=user_id),
    }


def _token_user_id(request: Request) -> str:
    """確かめたトークンの持ち主（main.py のミドルウェアが request.state.auth に入れる）。無ければ空文字"""
    auth = getattr(request.state, "auth", None)
    if auth is not None and auth.status == "valid" and auth.user_id:
        return auth.user_id
    return ""
