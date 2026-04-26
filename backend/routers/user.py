from fastapi import APIRouter, Request
from datetime import datetime
from services.cache import user_profile_table, _from_decimal

router = APIRouter()


@router.get("/user/profile")
async def get_user_profile(userId: str):
    try:
        res = user_profile_table.get_item(Key={'userId': userId})
        item = res.get('Item')
        if not item:
            return {"exists": False}
        return {"exists": True, **_from_decimal(item)}
    except Exception as e:
        return {"error": str(e), "exists": False}


@router.post("/user/profile")
async def save_user_profile(request: Request):
    try:
        body = await request.json()
        user_id = body.get("userId")
        if not user_id:
            return {"error": "userIdが必要です"}
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
            "updated_at":       datetime.now().isoformat(),
        }
        user_profile_table.put_item(Item=item)
        return {"success": True}
    except Exception as e:
        return {"error": str(e), "success": False}