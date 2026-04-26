import json
import asyncio
from concurrent.futures import ThreadPoolExecutor
from fastapi import APIRouter, Request
from openai import OpenAI
from services.technical import (
    get_technical_data, get_fundamental_data,
    get_macro_data, get_nikkei225_breadth,
    get_earnings_alert, fmt,
    build_short_prompt, build_medium_prompt, build_long_prompt
)


router = APIRouter()
openai_client = None
gemini_model = None

def clean_value(v):
    import math
    if isinstance(v, float) and math.isnan(v):
        return None
    return v

# ===================================================
# AI分析API（テクニカル・ファンダ・ニュース）
# ===================================================
@router.get("/stock/ai_analysis")
async def get_ai_analysis(code: str):
    try:
        if code.isdigit():
            yf_code = code[:-1] if len(code) == 5 else code
            ticker = yf.Ticker(f"{yf_code}.T")
        else:
            ticker = yf.Ticker(code)

        info = ticker.info
        hist = ticker.history(period="3mo")
        raw_news = ticker.news[:5] if ticker.news else []

        # ── ニュース整形 ──
        news_items = []
        for n in raw_news:
            content = n.get("content", {})
            if not isinstance(content, dict):
                continue
            title = content.get("title", "")
            summary = content.get("summary", "")
            provider = ""
            pub_date = ""
            provider_info = content.get("provider", {})
            if isinstance(provider_info, dict):
                provider = provider_info.get("displayName", "")
            pub_date = content.get("pubDate", "")
            if title:
                news_items.append({
                    "title": title,
                    "summary": summary,
                    "provider": provider,
                    "pub_date": pub_date,
                })

        # ── ChatGPTでニュースタイトルと要約を日本語翻訳 ──
        if news_items:
            try:
                titles_en = [n['title'] for n in news_items]
                summaries_en = [n['summary'] for n in news_items]

                # タイトル翻訳
                title_res = openai_client.chat.completions.create(
                    model="gpt-4o-mini",
                    messages=[
                        {
                            "role": "system",
                            "content": "株式ニュースのタイトルを日本語に翻訳してください。JSON配列のみ返してください。例：[\"翻訳1\", \"翻訳2\"]"
                        },
                        {
                            "role": "user",
                            "content": str(titles_en)
                        }
                    ],
                    max_tokens=500,
                )
                raw_titles = title_res.choices[0].message.content.strip()
                raw_titles = raw_titles.replace("```json", "").replace("```", "").strip()
                titles_ja = json.loads(raw_titles)
                for i, n in enumerate(news_items):
                    if i < len(titles_ja):
                        n['title'] = titles_ja[i]

                # 要約翻訳
                summary_res = openai_client.chat.completions.create(
                    model="gpt-4o-mini",
                    messages=[
                        {
                            "role": "system",
                            "content": "株式ニュースの要約文を日本語に翻訳してください。JSON配列のみ返してください。空文字はそのまま空文字で返してください。例：[\"翻訳1\", \"翻訳2\"]"
                        },
                        {
                            "role": "user",
                            "content": str(summaries_en)
                        }
                    ],
                    max_tokens=1000,
                )
                raw_summaries = summary_res.choices[0].message.content.strip()
                raw_summaries = raw_summaries.replace("```json", "").replace("```", "").strip()
                summaries_ja = json.loads(raw_summaries)
                for i, n in enumerate(news_items):
                    if i < len(summaries_ja):
                        n['summary'] = summaries_ja[i]

            except Exception as e:
                print(f"翻訳エラー: {e}")


        # ── テクニカル計算 ──
        closes = hist["Close"].tolist() if not hist.empty else []
        highs  = hist["High"].tolist()  if not hist.empty else []
        lows   = hist["Low"].tolist()   if not hist.empty else []

        current_price = closes[-1] if closes else None
        ma5  = round(sum(closes[-5:])  / min(len(closes), 5),  2) if closes else None
        ma25 = round(sum(closes[-25:]) / min(len(closes), 25), 2) if closes else None

        def ema(data, period):
            if len(data) < period:
                return None
            k = 2 / (period + 1)
            val = sum(data[:period]) / period
            for v in data[period:]:
                val = v * k + val * (1 - k)
            return round(val, 2)

        ema12 = ema(closes, 12)
        ema26 = ema(closes, 26)
        macd  = round(ema12 - ema26, 2) if ema12 and ema26 else None

        rsi = None
        if len(closes) >= 15:
            period = 14
            gains, losses = [], []
            for i in range(1, period + 1):
                diff = closes[-period - 1 + i] - closes[-period - 2 + i]
                gains.append(max(diff, 0))
                losses.append(max(-diff, 0))
            avg_gain = sum(gains) / period
            avg_loss = sum(losses) / period
            if avg_loss != 0:
                rsi = round(100 - (100 / (1 + avg_gain / avg_loss)), 1)
            else:
                rsi = 100.0

        high52 = round(max(highs), 2) if highs else None
        low52  = round(min(lows),  2) if lows  else None

        per            = clean_value(info.get("trailingPE"))
        pbr            = clean_value(info.get("priceToBook"))
        market_cap     = clean_value(info.get("marketCap"))
        dividend_yield = clean_value(info.get("dividendYield"))
        roe            = clean_value(info.get("returnOnEquity"))
        revenue_growth = clean_value(info.get("revenueGrowth"))
        name           = info.get("longName") or info.get("shortName") or code

        news_text = "\n".join([
            f"・{n['title']}（{n['provider']}）"
            for n in news_items if n['title']
        ]) or "ニュースなし"

        prompt = f"""
以下の株式データを分析して、必ずJSON形式のみで返してください。前置きや説明文は不要です。

銘柄名: {name}
現在株価: {current_price}
MA5: {ma5} / MA25: {ma25}
RSI(14): {rsi}
MACD: {macd}
52週高値: {high52} / 52週安値: {low52}
PER: {per} / PBR: {pbr}
時価総額: {market_cap}
配当利回り: {dividend_yield}
ROE: {roe}
売上成長率: {revenue_growth}

最近のニュース:
{news_text}

以下のJSON形式で回答してください：
{{
  "overall_score": 1〜100の整数（総合投資スコア）,
  "overall_judgment": "buy" か "sell" か "hold" か "watch" のいずれか,
  "overall_reason": "総合判断の理由を2〜3文で（日本語）",
  "news_summary": "ニュース全体の要約を2〜3文で（日本語）",
  "news_sentiment": "positive" か "negative" か "neutral" のいずれか,
  "news_sentiment_reason": "ニュースのセンチメント判断理由（日本語）",
  "risks": ["リスク1（日本語）", "リスク2（日本語）"],
  "opportunities": ["機会1（日本語）", "機会2（日本語）"]
}}
"""

        model = genai.GenerativeModel("gemini-2.5-flash")
        response = model.generate_content(
            [{"role": "user", "parts": [{"text": prompt}]}]
        )
        raw = response.text.strip()
        raw = raw.replace("```json", "").replace("```", "").strip()
        analysis = json.loads(raw)

        return {
            "code": code,
            "name": name,
            "price": current_price,
            "ma5": ma5,
            "ma25": ma25,
            "rsi": rsi,
            "macd": macd,
            "high52": high52,
            "low52": low52,
            "per": per,
            "pbr": pbr,
            "market_cap": market_cap,
            "dividend_yield": dividend_yield,
            "roe": roe,
            "revenue_growth": revenue_growth,
            "news": news_items,
            "analysis": analysis,
        }

    except Exception as e:
        print(f"AI分析エラー: {e}")
        return {"error": str(e)}


# ===================================================
# AI相談API
# ===================================================
@router.post("/stock/consult")
async def stock_consult(request: Request):
    """
    チェックボックスで選択した条件をもとにChatGPTに相談
    """
    body = await request.json()
    code            = body.get("code", "")
    name            = body.get("name", "")
    direction       = body.get("direction", "")       # 買い / 売り
    trade_type      = body.get("trade_type", "")      # 現物 / 信用
    period          = body.get("period", "")          # 短期 / 中期 / 長期
    extra_questions = body.get("extra_questions", []) # 追加質問リスト

    # 株価データ
    price      = body.get("price")
    rsi        = body.get("rsi")
    macd       = body.get("macd")
    ma5        = body.get("ma5")
    ma25       = body.get("ma25")
    per        = body.get("per")
    pbr        = body.get("pbr")
    roe        = body.get("roe")
    high52     = body.get("high52")
    low52      = body.get("low52")

    extra_text = ""
    if "損切りライン" in extra_questions:
        extra_text += "\n・損切りラインの目安はどこか？"
    if "ファンダメンタル" in extra_questions:
        extra_text += "\n・ファンダメンタル的な評価はどうか？"
    if "リスク" in extra_questions:
        extra_text += "\n・主なリスクは何か？"
    if "他銘柄比較" in extra_questions:
        extra_text += "\n・同業他社と比べて優位性はあるか？"

    prompt = f"""
あなたは株式投資の専門アドバイザーです。以下の条件と株価データをもとに、具体的なアドバイスをしてください。

【銘柄】{name}（{code}）
【相談内容】{direction}・{trade_type}・{period}の場合、この銘柄はどうか？{extra_text}

【株価データ】
現在株価: {price}円
MA5: {ma5} / MA25: {ma25}
RSI: {rsi}
MACD: {macd}
52週高値: {high52} / 52週安値: {low52}
PER: {per}倍 / PBR: {pbr}倍 / ROE: {roe}

以下の形式で日本語で回答してください：
{{
  "judgment": "適切" か "要注意" か "不適切" のいずれか,
  "judgment_reason": "判断理由を2〜3文で",
  "advice": "具体的なアドバイスを3〜5文で",
  "caution": "注意点を2〜3文で",
  "stop_loss": "損切りラインの目安（損切りラインの質問がある場合のみ、ない場合は空文字）",
  "fundamental_comment": "ファンダメンタルコメント（ファンダ質問がある場合のみ、ない場合は空文字）"
}}
"""

    try:
        res = openai_client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "あなたは日本株・米国株に詳しい投資アドバイザーです。必ずJSON形式のみで返してください。"},
                {"role": "user",   "content": prompt}
            ],
            max_tokens=1000,
        )
        raw = res.choices[0].message.content.strip()
        raw = raw.replace("```json", "").replace("```", "").strip()
        return json.loads(raw)
    except Exception as e:
        return {"error": str(e)}


# ===================================================
# メインエンドポイント（swing_analysis 置き換え）
# ===================================================
@router.post("/stock/swing_analysis")
async def swing_analysis(request: Request):
    """
    AI診断（短期・中期・長期）
    - tech/fund/macro/breadth を ThreadPoolExecutor で並列取得
    - DynamoDBキャッシュ対応済み
    - エラーメッセージを日本語化
    """
    body = await request.json()

    # 基本情報
    code   = body.get("code", "")
    name   = body.get("name", "")
    period = body.get("period", "短期")  # 短期 / 中期 / 長期

    # ユーザープロファイル
    user_profile = {
        "risk_level":     body.get("risk_level", "中"),
        "analysis_style": body.get("analysis_style", "バランス型"),
    }

    sector_data = body.get("sector_data", {})
    jp_sectors  = sector_data.get("jp", [])
    us_sectors  = sector_data.get("us", [])

    # ニュース
    news_list = body.get("news", [])
    news_summary = "\n".join([
        f"・{n.get('title', '')}"
        for n in news_list[:5] if n.get("title")
    ]) or "なし"

    # 決算日
    earnings_date_str    = body.get("earnings_date", "")
    dividend_record_date = body.get("dividend_record_date", "")
    score                = body.get("score")

    # ticker_code 正規化
    ticker_code = body.get("ticker_code") or (
        f"{code}.T" if len(code) == 4 and code.isdigit() else code
    )

    # ── データ取得（4関数を並列実行）──
    loop = asyncio.get_event_loop()
    with ThreadPoolExecutor(max_workers=4) as executor:
        tech_f    = loop.run_in_executor(executor, get_technical_data,   ticker_code)
        fund_f    = loop.run_in_executor(executor, get_fundamental_data, ticker_code)
        macro_f   = loop.run_in_executor(executor, get_macro_data)
        breadth_f = loop.run_in_executor(executor, get_nikkei225_breadth)
        tech, fund, macro, breadth = await asyncio.gather(
            tech_f, fund_f, macro_f, breadth_f
        )
        sector_name  = fund.get("sector", "")
        sector_trend = "不明"
        for s in jp_sectors + us_sectors:
            if s.get("name") in sector_name or sector_name in s.get("name", ""):
                sector_trend = f"{s['change_pct']:+.2f}%（5日:{s['trend_5d']:+.2f}%）"
                break
        macro["sector_trend"] = sector_trend

    # 信用残・空売り（フロントから渡すか、後でバッチ化）
    macro["margin_ratio"] = body.get("margin_ratio")
    macro["short_ratio"]  = body.get("short_ratio")

    sector   = fund.get("sector")   or "不明"
    industry = fund.get("industry") or "不明"

    # 決算アラート判定
    earnings_alert = get_earnings_alert(earnings_date_str, period)

    # ── プロンプト選択 ──
    if period == "短期":
        prompt = build_short_prompt(
            name, code, tech, fund, macro, breadth,
            earnings_alert, news_summary, score, user_profile,
            sector, industry
        )
    elif period == "中期":
        prompt = build_medium_prompt(
            name, code, tech, fund, macro, breadth,
            earnings_alert, news_summary, score, user_profile,
            sector, industry
        )
    else:
        prompt = build_long_prompt(
            name, code, tech, fund, macro,
            news_summary, score, user_profile,
            sector, industry
        )

    # ── AI呼び出し ──
    raw = ""
    try:
        res = openai_client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {
                    "role": "system",
                    "content": "あなたは日本株専門アナリストです。必ずJSON形式のみで返してください。理由は具体的かつ詳細に記述してください。"
                },
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            max_tokens=2500,
        )
        raw    = res.choices[0].message.content.strip()
        raw    = raw.replace("```json", "").replace("```", "").strip()
        result = json.loads(raw)
        result["_period"]       = period
        result["_ticker"]       = ticker_code
        result["_prompt"]       = prompt
        result["_tech_data"]    = tech
        result["_fund_data"]    = fund
        result["_macro_data"]   = macro
        result["_breadth_data"] = breadth
        return result

    except json.JSONDecodeError as e:
        return {
            "error": "AI分析結果の解析に失敗しました。もう一度お試しください。",
            "error_detail": f"JSONパースエラー: {str(e)}",
            "error_type": "parse_error",
            "raw": raw,
        }
    except Exception as e:
        err_str = str(e).lower()
        if "rate limit" in err_str or "ratelimit" in err_str:
            msg = "AI分析の利用制限に達しました。しばらく待ってからもう一度お試しください。"
            etype = "rate_limit"
        elif "timeout" in err_str:
            msg = "AI分析がタイムアウトしました。サーバーが混雑しています。時間をおいて再度お試しください。"
            etype = "timeout"
        elif "connection" in err_str or "network" in err_str:
            msg = "AIサーバーに接続できませんでした。ネットワーク状況を確認してください。"
            etype = "connection"
        elif "yfinance" in err_str or "download" in err_str:
            msg = "株価データの取得に失敗しました。銘柄コードを確認してください。"
            etype = "data_fetch"
        elif "dynamodb" in err_str or "no region" in err_str:
            msg = "データベースへの接続に失敗しました。管理者にお問い合わせください。"
            etype = "database"
        else:
            msg = "予期せぬエラーが発生しました。しばらく待ってからもう一度お試しください。"
            etype = "unknown"
        return {
            "error": msg,
            "error_type": etype,
            "error_detail": str(e),
        }


@router.post("/portfolio/diagnosis")
async def portfolio_diagnosis(request: Request):
    body = await request.json()
    user_profile = body.get("user_profile", {})
    holdings = body.get("holdings", [])
    period = body.get("period", "中期")

    # マクロ取得（キャッシュ対応済み）
    macro = get_macro_data()

    # 各銘柄の株価・テクニカル取得
    enriched = []
    for h in holdings:
        ticker_code = h.get("ticker_code", "")
        try:
            tech = get_technical_data(ticker_code)
            fund = get_fundamental_data(ticker_code)
            current_price = tech.get("price")

            # 損益率計算
            cost_price = h.get("cost_price")
            shares = h.get("shares")
            position = h.get("position", "買い")
            profit_loss_pct = None
            profit_loss_yen = None
            if cost_price and current_price:
                if position == "買い":
                    profit_loss_pct = round(
                        (current_price - cost_price) / cost_price * 100, 2)
                else:  # 空売り
                    profit_loss_pct = round(
                        (cost_price - current_price) / cost_price * 100, 2)
                if shares:
                    profit_loss_yen = round(
                        (current_price - cost_price) * shares *
                        (1 if position == "買い" else -1), 0)

            enriched.append({
                **h,
                "current_price": current_price,
                "profit_loss_pct": profit_loss_pct,
                "profit_loss_yen": profit_loss_yen,
                "rsi": tech.get("rsi"),
                "macd": tech.get("macd"),
                "ma5": tech.get("ma5"),
                "ma25": tech.get("ma25"),
                "sector":           fund.get("sector")   or "不明",
                "industry":         fund.get("industry") or "不明",
                "per":              fund.get("per"),
                "pbr":              fund.get("pbr"),
                "roe":              fund.get("roe"),
                "revenue_growth":   fund.get("revenue_growth"),
                "operating_margin": fund.get("operating_margin"),
            })
        except Exception as e:
            enriched.append({**h, "current_price": None, "error": str(e)})

    # プロンプト組み立て
    # 期間別で銘柄ブロックを変える
    holdings_blocks = ""
    for h in enriched:
        cost_str   = f"{h.get('cost_price')}円" if h.get('cost_price') else "未入力"
        shares_str = f"{h.get('shares')}株"     if h.get('shares')     else "未入力"
        pl_str     = f"{h.get('profit_loss_pct')}%" if h.get('profit_loss_pct') is not None else "不明"
        pl_yen     = f"（{h.get('profit_loss_yen'):+,.0f}円）" if h.get('profit_loss_yen') is not None else ""

        if period == "長期":
            holdings_blocks += f"""
=== {h.get('name')}（{h.get('code')}） ===
セクター：{h.get('sector', '不明')} / 業種：{h.get('industry', '不明')}
取引種別：{h.get('trade_type', '現物')}　ポジション：{h.get('position', '買い')}
現在株価：{h.get('current_price')}円　取得単価：{cost_str}　保有株数：{shares_str}
損益率：{pl_str}{pl_yen}
PER：{h.get('per', '不明')}倍
PBR：{h.get('pbr', '不明')}倍
ROE：{h.get('roe', '不明')}%
売上成長率（直近12ヶ月YoY）：{h.get('revenue_growth', '不明')}%
売上高推移(億円)：{h.get('revenue_trend', {})}
営業利益率（直近12ヶ月TTM）：{h.get('operating_margin', '不明')}%
営業利益推移(億円)：{h.get('op_income_trend', {})}
"""
        else:
            holdings_blocks += f"""
=== {h.get('name')}（{h.get('code')}） ===
セクター：{h.get('sector', '不明')} / 業種：{h.get('industry', '不明')}
取引種別：{h.get('trade_type', '現物')}　ポジション：{h.get('position', '買い')}
現在株価：{h.get('current_price')}円　取得単価：{cost_str}　保有株数：{shares_str}
損益率：{pl_str}{pl_yen}
RSI(14)：{h.get('rsi') if period != '長期' else 'テクニカル非使用'}　MACD：{h.get('macd') if period != '長期' else '-'}　MA5：{h.get('ma5') if period != '長期' else '-'}円　MA25：{h.get('ma25') if period != '長期' else '-'}円
"""

    # ベースプロンプト
    prompt = f"""
あなたは株式投資の専門アナリストです。
以下のポートフォリオを詳細に診断してください。
確率（継続保有・買い増し・利確・損切り）の合計は必ず100にすること。
JSONのみ出力（前置き・説明文禁止）。

【データ補完ルール】
以下のデータが「不明」の場合、AIが推定・補完して判断に使用すること：
- セクター・業種が不明 → 銘柄名・コードからセクターを推定する
  例：6758（ソニー）→ 電気機器・エンタメ、7203（トヨタ）→ 自動車
- PER・PBR・ROEが不明 → 業種平均や一般的な水準から推定する
  例：自動車セクターの平均PERは10〜15倍程度
- 推定した場合は必ず「推定値」と明記すること
- 推定が困難な場合は「データ不足」と記載すること

【共通ルール】
- 各期間の「最重要ルール」に従うこと（共通ルールより優先）
- 損益率のみで損切り判断をしてはいけない
- 単一指標のみで結論を出してはいけない
- 必ず複数要素（セクター・マクロ・トレンド等）で総合判断する
- 個別ではなく相対評価（強い/普通/弱い）で判断する

【ユーザープロファイル】
- 投資スタイル：{user_profile.get('investment_style', '中期')}
- リスク許容度：{user_profile.get('risk_level', '中')}
- 取引種別：{user_profile.get('trade_type', '現物のみ')}
- 分析スタイル：{user_profile.get('analysis_style', 'バランス型')}
- 投資経験：{user_profile.get('experience', '中級')}

【取引種別ごとの評価基準】
・現物取引：損切り閾値やや緩め（-15%〜-20%）、長期保有も選択肢
・信用取引：追証リスク考慮、損切り厳しめ（-8%〜-10%）
・空売り：上昇が損失、損切りライン必須設定

【保有銘柄】
{holdings_blocks}
"""

    # 期間別プロンプト追加
    if period == "短期":
        prompt += f"""
【市場環境（短期重視）】
- 日経平均トレンド：{macro.get('nikkei_trend')}
- VIX：{macro.get('vix')}
- 騰落レシオ目安：相場の強弱を判断

【診断期間】短期（数日〜2週間）

【最重要ルール（短期特化）】
- 資金流入・需給を最優先
- セクターの強弱を必ず判定
- 出来高・値動きから資金流入を推定
- トレンドより「今強いか」を重視
- 損益は完全無視（バイアス排除）

【判断の優先順位】
1. 資金流入（最重要）
2. セクター強度
3. 需給（出来高・値動き）
4. 短期トレンド（MA5）
5. テクニカル（RSI・MACD）

【禁止】
- ファンダメンタルで判断
- 長期目線の説明
"""
    elif period == "中期":
        prompt += f"""
【市場環境】
- 日経平均トレンド：{macro.get('nikkei_trend')}
- VIX：{macro.get('vix')}（20以下=安定／30以上=恐怖状態）
- ドル円：{macro.get('usd_jpy')}円
- 米10年債：{macro.get('us10y')}%
- S&P500トレンド：{macro.get('sp500_trend')}
- 金利差(10Y-2Y)：{macro.get('yield_spread')}

【診断期間】中期（1〜3ヶ月）

【最重要ルール（中期）】
- セクターと資金流入を最優先
- トレンド（MA25）を重視
- マクロ（為替・金利）を必ず考慮
- テクニカルは補助

【判断の優先順位】
1. セクター強度（最重要）
2. 資金流入
3. マクロ（為替・金利）
4. トレンド（MA25）
5. テクニカル

【禁止】
- RSI単体判断
"""
    else:  # 長期
        prompt += f"""

【長期ファンダ評価ルール】
- 直近12ヶ月（TTM）の数値は参考とし、単独で結論を出してはいけない
- 業績の持続性（3年〜5年のトレンド）を最優先に評価する
- TTMが大きく悪化している場合は、一時的要因の可能性を必ず検討する
- 一時要因が不明な場合は「リスクあり」として評価する

【市場環境（長期・マクロのみ）】
- 日経平均トレンド：{macro.get('nikkei_trend')}
- 米10年債：{macro.get('us10y')}%（金利環境）
- ドル円：{macro.get('usd_jpy')}円
- 金利差(10Y-2Y)：{macro.get('yield_spread')}（景気後退シグナル）

【診断期間】長期（6ヶ月以上）

【最重要ルール（長期特化）】
- ファンダメンタルを最優先
- 成長性・収益性・競争優位を評価
- バリュエーションを必ず考慮
- マクロ環境（景気・金利）を重視
- テクニカルは使用禁止

【判断の優先順位】
1. 成長性（売上・利益）
2. 収益性（ROEなど）
3. バリュエーション（PER等）
4. セクター構造
5. マクロ環境

【禁止】
- RSI・MACDなどのテクニカル使用
- 短期値動きの言及
"""

    prompt += f"""
【診断指示】
{period}の観点で各銘柄を診断してください：
- verdict：継続保有 / 買い増し / 利確推奨 / 損切り推奨
- probability：継続保有・買い増し・利確・損切りの確率（合計100）
- confidence：high / medium / low
- price_strategy：利確目安価格・損切り目安価格・根拠
- positive_points：保有継続・買い増しの根拠
- negative_points：リスク・売却根拠
- macro_impact：市場環境がこの銘柄に与える影響
- summary：5〜8文の詳細サマリー（数値引用必須）

必ずJSONのみで返してください：
{{
  "market_environment": {{
    "summary": "市場環境の総合コメント（3〜4文）",
    "risk_mode": "risk_on / risk_off / neutral",
    "risk_mode_reason": "VIX・米株・ドル円から3文で"
  }},
  "holdings": [
    {{
      "code": "",
      "name": "",
      "current_price": 0,
      "profit_loss_pct": 0,
      "verdict": "継続保有 / 買い増し / 利確推奨 / 損切り推奨",
      "probability": {{
        "hold":        {{"value": 継続保有確率(整数), "reason": "2〜3文で具体的に"}},
        "add":         {{"value": 買い増し確率(整数), "reason": "2〜3文で具体的に"}},
        "take_profit": {{"value": 利確確率(整数),    "reason": "2〜3文で具体的に"}},
        "cut_loss":    {{"value": 損切り確率(整数),  "reason": "2〜3文で具体的に"}}
      }},
      "confidence": {{"value": "high/medium/low", "reason": "2文で"}},
      "price_strategy": {{
        "take_profit": {{"value": 0, "reason": "3〜4文で根拠を説明"}},
        "stop_loss":   {{"value": 0, "reason": "3〜4文で根拠を説明"}}
      }},
      "macro_impact": {{"value": "positive/negative/neutral", "reason": "この銘柄への市場環境の影響を2〜3文で"}},
      "positive_points": ["根拠1（指標名と数値を含め2文以上）", "根拠2", "根拠3"],
      "negative_points": ["リスク1（指標名と数値を含め2文以上）", "リスク2", "リスク3"],
      "summary": "5〜8文の詳細サマリー（数値引用必須）"
    }}
  ],
  "portfolio_analysis": {{
    "sector_balance": "セクターバランスの詳細コメント（3〜4文）",
    "concentration_risk": "集中リスクの詳細コメント（3〜4文）",
    "overall_comment": "ポートフォリオ全体の総評（5〜8文、{period}の観点で）"
  }}
}}
"""

    try:
        res = openai_client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": "あなたは株式投資の専門アナリストです。必ずJSON形式のみで返してください。"},
                {"role": "user", "content": prompt}
            ],
            max_tokens=3000,
        )
        raw = res.choices[0].message.content.strip()
        raw = raw.replace("```json", "").replace("```", "").strip()
        result = json.loads(raw)
        result["_prompt"] = prompt
        result["_holdings_data"] = enriched
        return result
    except json.JSONDecodeError as e:
        return {"error": "AI分析結果の解析に失敗しました。もう一度お試しください。"}
    except Exception as e:
        return {"error": f"診断に失敗しました：{str(e)}"}