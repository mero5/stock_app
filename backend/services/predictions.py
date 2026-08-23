# ===================================================
# AI予測の記録と答え合わせ
#
# AI分析の結果を保存しておき、期間が過ぎたら実際の株価と
# 突き合わせて「当たったか」を判定する。
#
# なぜ必要か：
#   プロンプトを改良しても、的中率を測っていなければ
#   良くなったのか悪くなったのか分からない。
#   ここが無いと、以降の精度改善は当てずっぽうになる。
#
# 判定の仕組み（遅延評価）：
#   定期実行の仕組みは持たず、成績を見るタイミングで
#   期限が来た予測をまとめて判定する。
#   過去の株価は後からでも取得できるので、これで十分。
# ===================================================

import math
from datetime import datetime, timedelta, date

import yfinance as yf
from boto3.dynamodb.conditions import Attr

from services.cache import predictions_table, _to_decimal, _from_decimal


# 「上昇」「下落」と判定する変化率のしきい値（%）
#
# ±3%を超えたら上昇/下落、それ以内は様子見とする。
# 小さすぎるとノイズを拾い、大きすぎると何も当たらなくなる。
# 実際の売買判断に近い水準としてこの値にしている。
VERDICT_THRESHOLD_PCT = 3.0

# 判定に使う期間の日数（プロファイル未設定時のデフォルト）
DEFAULT_HORIZON_DAYS = {"短期": 14, "中期": 90, "長期": 180}


def _to_float(value, default=None):
    """DecimalやNoneを安全にfloatへ変換する"""
    try:
        if value is None:
            return default
        f = float(value)
        if math.isnan(f) or math.isinf(f):
            return default
        return f
    except (TypeError, ValueError):
        return default


def classify_change(change_pct) -> str:
    """変化率から実際の結果（up / sideways / down）を決める"""
    pct = _to_float(change_pct)
    if pct is None:
        return "sideways"
    if pct > VERDICT_THRESHOLD_PCT:
        return "up"
    if pct < -VERDICT_THRESHOLD_PCT:
        return "down"
    return "sideways"


def resolve_horizon_days(period: str, period_days=None) -> int:
    """
    予測の答え合わせをする日数を決める。

    ユーザーが設定画面で期間の日数を変えている場合はそれに合わせる。
    """
    default = DEFAULT_HORIZON_DAYS.get(period, 90)
    if not isinstance(period_days, dict):
        return default
    try:
        if period == "短期":
            return int(period_days.get("short_max") or default)
        if period == "中期":
            return int(period_days.get("medium_max") or default)
    except (TypeError, ValueError):
        pass
    return default


# ===================================================
# 保存
# ===================================================
def save_prediction(*, code, ticker_code, name, period, result,
                    price, horizon_days, prompt_version,
                    checks=None, user_profile=None, user_id=None,
                    usage=None) -> bool:
    """
    AI分析の結果を1件保存する。

    分析APIのレスポンスを遅らせたくないので、
    失敗しても例外は投げずFalseを返すだけにしている。
    """
    try:
        price = _to_float(price)
        if price is None or price <= 0:
            # 判定に使う基準価格が取れないと答え合わせできないので保存しない
            print(f"予測記録スキップ（価格なし）: {code}")
            return False

        verdict = (result.get("verdict") or {}).get("value")
        if verdict not in ("up", "sideways", "down"):
            print(f"予測記録スキップ（判定が不正）: {code} / {verdict}")
            return False

        prob = result.get("probability") or {}

        def prob_of(key):
            node = prob.get(key)
            if isinstance(node, dict):
                return _to_float(node.get("value"), 0.0)
            return _to_float(node, 0.0)

        now = datetime.now()
        item = {
            "code":          str(code),
            "predicted_at":  now.isoformat(),
            "ticker_code":   str(ticker_code or ""),
            "name":          str(name or ""),
            "period":        str(period or ""),
            "user_id":       str(user_id or ""),

            # 予測内容
            "verdict":       verdict,
            "prob_up":       prob_of("up"),
            "prob_sideways": prob_of("sideways"),
            "prob_down":     prob_of("down"),
            "confidence":    (result.get("confidence") or {}).get("value") or "",

            # 判定に必要な情報
            "price_at_prediction": price,
            "horizon_days":        int(horizon_days),
            "evaluate_at":         str((now + timedelta(days=int(horizon_days))).date()),
            "threshold_pct":       VERDICT_THRESHOLD_PCT,

            # 改良の前後を比較するための情報
            "prompt_version": str(prompt_version),
            "checks":         checks or {},
            "user_profile":   user_profile or {},
            "usage":          usage or {},

            "status": "pending",
        }
        predictions_table.put_item(Item=_to_decimal(item))
        print(f"予測を記録: {code} {period} {verdict} → {item['evaluate_at']}に判定")
        return True
    except Exception as e:
        print(f"予測記録エラー: {type(e).__name__}: {e}")
        return False


# ===================================================
# 答え合わせ
# ===================================================
def _close_on_or_before(ticker_code: str, target: date):
    """
    指定日（またはその直前の営業日）の終値を返す。

    土日祝はデータが無いので、その場合は手前の営業日を使う。
    """
    try:
        t = yf.Ticker(ticker_code)
        # 前後に余裕を持って取得してから対象日以前の最後の行を取る
        start = target - timedelta(days=10)
        end   = target + timedelta(days=2)
        hist = t.history(start=str(start), end=str(end))
        if hist.empty:
            return None
        hist = hist[hist.index.date <= target]
        if hist.empty:
            return None
        return float(hist["Close"].iloc[-1])
    except Exception as e:
        print(f"判定用株価取得エラー {ticker_code}: {e}")
        return None


def evaluate_pending(limit: int = 100) -> dict:
    """
    判定期限が来た予測をまとめて答え合わせする。

    成績画面を開いたタイミングで呼ばれる（遅延評価）。
    定期実行の仕組みが要らないので構成がシンプルになる。
    """
    today = date.today()
    evaluated = 0
    skipped = 0

    try:
        res = predictions_table.scan(
            FilterExpression=Attr("status").eq("pending")
            & Attr("evaluate_at").lte(str(today)),
            Limit=limit,
        )
        items = res.get("Items", [])
    except Exception as e:
        print(f"判定対象の取得エラー: {e}")
        return {"evaluated": 0, "skipped": 0, "error": str(e)}

    for item in items:
        try:
            ticker = item.get("ticker_code") or item.get("code")
            target = date.fromisoformat(str(item["evaluate_at"]))
            close = _close_on_or_before(str(ticker), target)
            if close is None:
                skipped += 1
                continue

            base = _to_float(item.get("price_at_prediction"))
            if not base:
                skipped += 1
                continue

            change_pct = (close - base) / base * 100
            actual = classify_change(change_pct)
            predicted = str(item.get("verdict"))

            predictions_table.update_item(
                Key={
                    "code":         item["code"],
                    "predicted_at": item["predicted_at"],
                },
                UpdateExpression=(
                    "SET #s = :s, price_at_evaluation = :p, "
                    "actual_change_pct = :c, actual_verdict = :a, "
                    "is_correct = :ok, evaluated_at = :t"
                ),
                ExpressionAttributeNames={"#s": "status"},
                ExpressionAttributeValues=_to_decimal({
                    ":s":  "evaluated",
                    ":p":  round(close, 2),
                    ":c":  round(change_pct, 2),
                    ":a":  actual,
                    ":ok": predicted == actual,
                    ":t":  datetime.now().isoformat(),
                }),
            )
            evaluated += 1
        except Exception as e:
            print(f"判定エラー {item.get('code')}: {type(e).__name__}: {e}")
            skipped += 1

    if evaluated or skipped:
        print(f"答え合わせ: 判定{evaluated}件 / 保留{skipped}件")
    return {"evaluated": evaluated, "skipped": skipped}


# ===================================================
# 集計
# ===================================================
def _empty_stats():
    return {"total": 0, "correct": 0, "accuracy": None}


def _accuracy(correct: int, total: int):
    return round(correct / total * 100, 1) if total else None


def get_accuracy_stats(user_id: str = "") -> dict:
    """
    的中率とキャリブレーションを集計して返す。

    ・全体／期間別／判定別／確信度別の的中率
    ・プロンプトのバージョン別の的中率（改良の効果を見るため）
    ・キャリブレーション（「上昇70%」と言った時に本当に7割上がったか）
    ・累計のトークン使用量
    """
    try:
        items = []
        kwargs = {}
        while True:
            res = predictions_table.scan(**kwargs)
            items.extend(res.get("Items", []))
            if "LastEvaluatedKey" not in res:
                break
            kwargs["ExclusiveStartKey"] = res["LastEvaluatedKey"]
    except Exception as e:
        print(f"成績集計エラー: {e}")
        return {"error": str(e)}

    items = [_from_decimal(i) for i in items]
    if user_id:
        items = [i for i in items if not i.get("user_id") or i.get("user_id") == user_id]

    done = [i for i in items if i.get("status") == "evaluated"]
    pending = [i for i in items if i.get("status") != "evaluated"]

    def bucket(key_fn):
        out = {}
        for i in done:
            k = str(key_fn(i) or "不明")
            b = out.setdefault(k, _empty_stats())
            b["total"] += 1
            if i.get("is_correct"):
                b["correct"] += 1
        for b in out.values():
            b["accuracy"] = _accuracy(b["correct"], b["total"])
        return out

    # キャリブレーション
    # 「上昇◯%」と言った予測を確率帯ごとに束ね、実際の上昇率と比べる
    calibration = []
    for lo in range(0, 100, 20):
        hi = lo + 20
        group = [
            i for i in done
            if lo <= _to_float(i.get("prob_up"), 0) < hi
        ]
        if not group:
            continue
        actual_up = sum(1 for i in group if i.get("actual_verdict") == "up")
        calibration.append({
            "range":       f"{lo}〜{hi}%",
            "said_avg":    round(
                sum(_to_float(i.get("prob_up"), 0) for i in group) / len(group), 1
            ),
            "actual_pct":  round(actual_up / len(group) * 100, 1),
            "count":       len(group),
        })

    total_in = sum(_to_float((i.get("usage") or {}).get("prompt_tokens"), 0) for i in items)
    total_out = sum(_to_float((i.get("usage") or {}).get("completion_tokens"), 0) for i in items)

    return {
        "threshold_pct":  VERDICT_THRESHOLD_PCT,
        "total":          len(items),
        "evaluated":      len(done),
        "pending":        len(pending),
        "accuracy":       _accuracy(sum(1 for i in done if i.get("is_correct")), len(done)),
        "by_period":      bucket(lambda i: i.get("period")),
        "by_verdict":     bucket(lambda i: i.get("verdict")),
        "by_confidence":  bucket(lambda i: i.get("confidence")),
        "by_prompt_version": bucket(lambda i: i.get("prompt_version")),
        "calibration":    calibration,
        "tokens": {
            "prompt":     int(total_in),
            "completion": int(total_out),
        },
        # 判定待ちのうち、次に判定される日
        "next_evaluate_at": min(
            (str(i.get("evaluate_at")) for i in pending if i.get("evaluate_at")),
            default=None,
        ),
    }


def get_recent_predictions(limit: int = 30, code: str = "") -> list:
    """直近の予測を新しい順に返す（成績画面の履歴表示用）"""
    try:
        if code:
            from boto3.dynamodb.conditions import Key
            res = predictions_table.query(
                KeyConditionExpression=Key("code").eq(str(code)),
                ScanIndexForward=False,
                Limit=limit,
            )
            items = res.get("Items", [])
        else:
            res = predictions_table.scan()
            items = res.get("Items", [])
            items.sort(key=lambda i: str(i.get("predicted_at", "")), reverse=True)
            items = items[:limit]

        out = []
        for i in (_from_decimal(x) for x in items):
            out.append({
                "code":          i.get("code"),
                "name":          i.get("name"),
                "period":        i.get("period"),
                "predicted_at":  i.get("predicted_at"),
                "evaluate_at":   i.get("evaluate_at"),
                "verdict":       i.get("verdict"),
                "confidence":    i.get("confidence"),
                "prob_up":       _to_float(i.get("prob_up")),
                "prob_sideways": _to_float(i.get("prob_sideways")),
                "prob_down":     _to_float(i.get("prob_down")),
                "status":        i.get("status"),
                "actual_verdict":    i.get("actual_verdict"),
                "actual_change_pct": _to_float(i.get("actual_change_pct")),
                "is_correct":        i.get("is_correct"),
            })
        return out
    except Exception as e:
        print(f"予測履歴取得エラー: {e}")
        return []
