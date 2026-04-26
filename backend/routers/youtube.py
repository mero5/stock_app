import os
import json
from fastapi import APIRouter, Request
from googleapiclient.discovery import build
import google.generativeai as genai
from services.cache import cache_get, cache_set, market_cache_table

router = APIRouter()
YOUTUBE_API_KEY = ""
gemini_model = None


@router.get("/channels/search")
def search_channels(q: str):
    try:
        youtube = build("youtube", "v3", developerKey=YOUTUBE_API_KEY)
        res = youtube.search().list(
            q=q, part="snippet", type="channel", maxResults=10
        ).execute()
        results = []
        for item in res.get("items", []):
            results.append({
                "channel_id": item["id"]["channelId"],
                "name":        item["snippet"]["title"],
                "description": item["snippet"]["description"][:100],
                "thumbnail":   item["snippet"]["thumbnails"]["default"]["url"],
            })
        return results
    except Exception as e:
        print(f"チャンネル検索エラー: {e}")
        return []


@router.post("/summarize")
async def summarize_video(request: Request):
    body      = await request.json()
    video_url = body.get("url", "")
    cache_key = f"summary_{video_url.replace('https://www.youtube.com/watch?v=', '')}"
    cached    = cache_get(market_cache_table, {'cache_key': cache_key})
    if cached:
        print(f"要約キャッシュヒット: {cache_key}")
        return cached

    title      = body.get("title", "")
    url        = body.get("url", "")
    transcript = body.get("transcript", "")

    prompt = f"""
以下のYouTube動画を分析して、必ずJSON形式のみで返してください。前置きや説明文は不要です。

動画タイトル: {title}
動画URL: {url}
動画説明文: {transcript}

以下のJSON形式で回答してください：
{{
"summary": "以下の項目で箇条書きにして記述（日本語）。各項目は「・」で始めること。\n・全体の結論\n・相場観・市場の見方\n・注目銘柄・セクター\n・根拠・理由\n・視聴者へのアドバイス",
"nikkei_outlook": "bullish" か "bearish" か "neutral" か "not_mentioned" のいずれか,
"nikkei_reason": "日経平均についての根拠（not_mentionedの場合は空文字）",
"us_market_outlook": "bullish" か "bearish" か "neutral" か "not_mentioned" のいずれか,
"sentiment": "very_bullish" か "bullish" か "neutral" か "bearish" か "very_bearish" のいずれか,
"topics": ["話題1", "話題2", "話題3"],
"recommended_action": "buy" か "sell" か "hold" か "watch" か "not_mentioned" のいずれか,
"key_stocks": ["言及された銘柄名1", "銘柄名2"],
"confidence": 1から5の整数
}}
"""

    try:
        model    = genai.GenerativeModel("gemini-2.5-flash")
        response = model.generate_content(
            [{"role": "user", "parts": [{"text": prompt}]}]
        )
        raw    = response.text.strip().replace("```json", "").replace("```", "").strip()
        parsed = json.loads(raw)
        cache_set(market_cache_table, {'cache_key': cache_key}, parsed, ttl_minutes=10080)
        return parsed
    except Exception as e:
        return {
            "summary": "要約できませんでした",
            "nikkei_outlook": "not_mentioned",
            "nikkei_reason": "",
            "us_market_outlook": "not_mentioned",
            "sentiment": "neutral",
            "topics": [],
            "recommended_action": "not_mentioned",
            "key_stocks": [],
            "confidence": 0,
            "error": str(e)
        }


@router.get("/summaries")
def get_summaries(channel_ids: str):
    return []


@router.get("/channels/{channel_id}/videos")
def get_channel_videos(channel_id: str, max_results: int = 10):
    try:
        youtube = build("youtube", "v3", developerKey=YOUTUBE_API_KEY)
        res = youtube.search().list(
            channelId=channel_id, part="snippet",
            order="date", maxResults=max_results, type="video",
        ).execute()
        videos = []
        for item in res.get("items", []):
            videos.append({
                "video_id":     item["id"]["videoId"],
                "title":        item["snippet"]["title"],
                "published_at": item["snippet"]["publishedAt"],
                "thumbnail":    item["snippet"]["thumbnails"]["medium"]["url"],
                "description":  item["snippet"]["description"],
            })
        return {"videos": videos}
    except Exception as e:
        return {"error": str(e), "videos": []}