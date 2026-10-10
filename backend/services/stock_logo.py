# ===================================================
# 銘柄の画像（ロゴ代わりのアイコン）の URL
#
# 公式のロゴを無料で取れる API は日本株に対応していないので、
# yfinance の info にある会社の Web サイト（例：https://global.toyota）から、
# Google のファビコン（サイトのアイコン）配信の URL を作る。
#   例：https://www.google.com/s2/favicons?domain=global.toyota&sz=128 → トヨタの「T」のアイコン
# 画像そのものはアプリが直接読み込む（バックエンドは URL を返すだけ）。
# Web サイトが分からない銘柄は None（アプリは銘柄名の頭文字を丸く出す）。
#
# yfinance の info は1銘柄1秒ほどかかるので、Web サイトは DynamoDB に30日保存する
# （会社の Web サイトはめったに変わらない）。
# ===================================================

from urllib.parse import urlparse

import yfinance as yf

from services.cache import cache_get, cache_set, stock_cache_table
from services.stock_code import to_yf_ticker

FAVICON_URL = "https://www.google.com/s2/favicons?domain={domain}&sz=128"

# 中身の形を変えたら版を上げる
PROFILE_CACHE_TYPE = "profile_v1"
PROFILE_CACHE_TTL_MINUTES = 30 * 24 * 60


def website_domain(website) -> str | None:
    """Web サイトの URL からドメインを取り出す（"https://www.apple.com/" → "apple.com"）"""
    if not website or not isinstance(website, str):
        return None
    parsed = urlparse(website if "://" in website else f"https://{website}")
    domain = (parsed.netloc or "").lower().split(":")[0]
    if domain.startswith("www."):
        domain = domain[4:]
    return domain or None


def _website(ticker_code: str, table) -> str:
    """銘柄の Web サイト（無ければ ""）。30日保存する"""
    key = {"code": ticker_code, "cache_type": PROFILE_CACHE_TYPE}
    cached = cache_get(table, key)
    if cached is not None and "website" in cached:
        return cached["website"] or ""
    website = yf.Ticker(ticker_code).info.get("website") or ""
    # 無かったことも保存する（毎回 yfinance に聞きに行かないため）
    cache_set(table, key, {"website": website}, ttl_minutes=PROFILE_CACHE_TTL_MINUTES)
    return website


def get_logo_url(code: str, table=None) -> str | None:
    """銘柄の画像の URL。分からなければ None（失敗しても例外を投げない）"""
    try:
        domain = website_domain(_website(to_yf_ticker(code), table or stock_cache_table))
    except Exception as e:
        print(f"銘柄の画像の取得エラー {code}: {e}")
        return None
    return FAVICON_URL.format(domain=domain) if domain else None
