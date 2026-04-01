from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import yfinance as yf
import requests
import os

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

JQUANTS_API_KEY = "tvRUlGQXJCWhFYhH1VAUakkU_AVqolQsA8yk-WZu3pA"

# 起動時に銘柄マスタを取得してメモリに保持
stocks_master = []

@app.on_event("startup")
async def load_stocks_master():
    global stocks_master
    try:
        res = requests.get(
            "https://api.jquants.com/v1/listed/info",
            headers={"Authorization": f"Bearer {JQUANTS_API_KEY}"}
        )
        data = res.json()
        stocks_master = data.get("info", [])
        print(f"銘柄マスタ取得完了: {len(stocks_master)}件")
    except Exception as e:
        print(f"銘柄マスタ取得エラー: {e}")

@app.get("/search")
def search(q: str):
    if not q:
        return []

    results = []

    # 日本語 → J-Quantsマスタから検索
    if any("\u3040" <= c <= "\u9fff" for c in q):
        for s in stocks_master:
            name = s.get("CompanyName", "")
            code = s.get("Code", "")
            if q in name:
                results.append({
                    "code": code,
                    "name": name,
                    "market": "JP"
                })
        return results[:20]

    # 数字 → 日本株コード検索
    if q.isdigit():
        ticker = yf.Ticker(f"{q}.T")
        info = ticker.info
        name = info.get("longName") or info.get("shortName")
        if name:
            results.append({"code": q, "name": name, "market": "JP"})
        return results

    # 英語 → yfinanceで米国株検索
    try:
        s = yf.Search(q, max_results=15, enable_fuzzy_query=True)
        for r in s.quotes:
            symbol = r.get("symbol", "")
            name = r.get("longname") or r.get("shortname") or ""
            if not name or "." in symbol:
                continue
            results.append({"code": symbol, "name": name, "market": "US"})
    except Exception as e:
        print(f"US検索エラー: {e}")

    return results