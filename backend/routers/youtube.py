import json
from fastapi import APIRouter, Request
from googleapiclient.discovery import build
import google.generativeai as genai
from config.timeouts import GEMINI_TIMEOUT_SEC
from services.cache import cache_get, cache_set, market_cache_table

router = APIRouter()
YOUTUBE_API_KEY = ""


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
            [{"role": "user", "parts": [{"text": prompt}]}],
            request_options={"timeout": GEMINI_TIMEOUT_SEC},
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



def _uploads_playlist_id(youtube, channel_id: str) -> str:
    """
    チャンネルの「アップロード動画」プレイリストIDを返す。

    channels.list（1ユニット）で取得する。取れなかった場合は、
    チャンネルID「UCxxxx」の先頭を「UU」に変えたもの（YouTubeの決まった形式）を使う。
    """
    try:
        res = youtube.channels().list(id=channel_id, part="contentDetails").execute()
        items = res.get("items", [])
        if items:
            return items[0]["contentDetails"]["relatedPlaylists"]["uploads"]
    except Exception as e:
        print(f"アップロードプレイリスト取得エラー: {e}")
    return "UU" + channel_id[2:] if channel_id.startswith("UC") else channel_id


@router.get("/channels/{channel_id}/videos")
def get_channel_videos(channel_id: str, max_results: int = 10):
    """
    チャンネルの最新動画を返す。

    以前は search.list（1回100ユニット）を使っていたため、
    YouTube Data API の無料枠（1日10,000ユニット）を約100回で使い切っていた。
    アップロード動画のプレイリストを playlistItems.list（1ユニット）で読む方式に変更し、
    1回あたり2ユニット（channels.list + playlistItems.list）で済むようにした。
    """
    try:
        youtube = build("youtube", "v3", developerKey=YOUTUBE_API_KEY)
        playlist_id = _uploads_playlist_id(youtube, channel_id)
        res = youtube.playlistItems().list(
            playlistId=playlist_id, part="snippet",
            maxResults=max(1, min(int(max_results), 50)),
        ).execute()
        videos = []
        for item in res.get("items", []):
            snippet = item.get("snippet", {})
            video_id = (snippet.get("resourceId") or {}).get("videoId")
            thumbs = snippet.get("thumbnails") or {}
            # 非公開・削除済みの動画はサムネイルが無いので除外する
            thumb = (thumbs.get("medium") or thumbs.get("default") or {}).get("url")
            if not video_id or not thumb:
                continue
            videos.append({
                "video_id":     video_id,
                "title":        snippet.get("title", ""),
                "published_at": snippet.get("publishedAt", ""),
                "thumbnail":    thumb,
                "description":  snippet.get("description", ""),
            })
        # プレイリストは基本的に新しい順だが、念のため投稿日時で並べ直す
        videos.sort(key=lambda v: v["published_at"], reverse=True)
        return {"videos": videos}
    except Exception as e:
        return {"error": str(e), "videos": []}