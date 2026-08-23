from fastapi import APIRouter, Request
from datetime import datetime
from services.cache import user_profile_table, _from_decimal
from services.technical import DEFAULT_PRIORITY, DEFAULT_PERIOD_DAYS, normalize_priority

router = APIRouter()


@router.get("/user/profile")
async def get_user_profile(userId: str):
    try:
        res = user_profile_table.get_item(Key={'userId': userId})
        item = res.get('Item')
        if not item:
            return {"exists": False}
        data = _from_decimal(item)
        # 優先順位・期間設定が未保存（旧プロファイル）の場合はデフォルトを補完
        data.setdefault("priority_short",  DEFAULT_PRIORITY["短期"])
        data.setdefault("priority_medium", DEFAULT_PRIORITY["中期"])
        data.setdefault("priority_long",   DEFAULT_PRIORITY["長期"])
        data.setdefault("period_short_max_days",  DEFAULT_PERIOD_DAYS["short_max"])
        data.setdefault("period_medium_max_days", DEFAULT_PERIOD_DAYS["medium_max"])
        return {"exists": True, **data}
    except Exception as e:
        return {"error": str(e), "exists": False}


@router.post("/user/profile")
async def save_user_profile(request: Request):
    try:
        body = await request.json()
        user_id = body.get("userId")
        if not user_id:
            return {"error": "userIdが必要です"}

        def _period_days(key, default):
            v = body.get(key)
            try:
                return int(v) if v else default
            except (TypeError, ValueError):
                return default

        item = {
            "userId":           user_id,
            "investment_style": body.get("investment_style", "中期"),
            "trade_type":       body.get("trade_type", "現物のみ"),
            "short_selling":    body.get("short_selling", "しない"),
            "analysis_style":   body.get("analysis_style", "バランス型"),
            "risk_level":       body.get("risk_level", "中"),
            "experience":       body.get("experience", "中級"),
            "market":           body.get("market", "両方"),
            "concentration":    body.get("concentration", "分散派"),
            "priority_short":   normalize_priority(body.get("priority_short"),  "短期"),
            "priority_medium":  normalize_priority(body.get("priority_medium"), "中期"),
            "priority_long":    normalize_priority(body.get("priority_long"),   "長期"),
            "period_short_max_days":  _period_days("period_short_max_days",  DEFAULT_PERIOD_DAYS["short_max"]),
            "period_medium_max_days": _period_days("period_medium_max_days", DEFAULT_PERIOD_DAYS["medium_max"]),
            "updated_at":       datetime.now().isoformat(),
        }
        user_profile_table.put_item(Item=item)
        return {"success": True}
    except Exception as e:
        return {"error": str(e), "success": False}
