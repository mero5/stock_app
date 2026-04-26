import yfinance as yf
import pandas as pd
import numpy as np
import json
from datetime import datetime, date
from services.cache import (
    cache_get, cache_set,
    market_cache_table, stock_cache_table
)


# ===================================================
# データ取得ユーティリティ
# ===================================================
def safe_float(val, digits=2):
    """安全にfloatに変換。失敗したらNoneを返す"""
    try:
        return round(float(val), digits)
    except:
        return None


def get_latest_price(ticker_code: str):
    """直近終値を取得"""
    try:
        t = yf.Ticker(ticker_code)
        hist = t.history(period="3d")
        if not hist.empty:
            return round(float(hist["Close"].iloc[-1]), 2)
    except:
        pass
    return None


def get_trend_label(ticker_code: str, period: str = "5d") -> str:
    """
    指定期間のトレンドをラベルで返す
    例：「上昇トレンド（+2.3%）」
    """
    try:
        t = yf.Ticker(ticker_code)
        hist = t.history(period=period)
        if len(hist) >= 2:
            pct = (
                float(hist["Close"].iloc[-1]) - float(hist["Close"].iloc[0])
            ) / float(hist["Close"].iloc[0]) * 100
            if pct > 1:
                return f"上昇トレンド（+{pct:.1f}%）"
            elif pct < -1:
                return f"下落トレンド（{pct:.1f}%）"
            else:
                return f"横ばい（{pct:.1f}%）"
    except:
        pass
    return None


def get_macro_data() -> dict:
    """
    マクロ指標を一括取得（DynamoDBに15分キャッシュ）
    """
    # キャッシュ確認
    cached = cache_get(market_cache_table, {'cache_key': 'macro'})
    if cached:
        print("マクロ: キャッシュヒット")
        return cached

    print("マクロ: yfinanceから取得")
    macro = {
        "vix":          get_latest_price("^VIX"),
        "us10y":        get_latest_price("^TNX"),
        "us2y":         get_latest_price("^IRX"),
        "usd_jpy":      get_latest_price("USDJPY=X"),
        "dxy":          get_latest_price("DX-Y.NYB"),
        "oil_price":    get_latest_price("CL=F"),
        "gold_price":   get_latest_price("GC=F"),
        "nikkei_trend": get_trend_label("^N225"),
        "sp500_trend":  get_trend_label("^GSPC"),
    }

    # 金利差（逆イールド判定）
    if macro["us2y"] and macro["us10y"]:
        macro["yield_spread"] = round(macro["us10y"] - macro["us2y"], 3)
    else:
        macro["yield_spread"] = None

    # 15分キャッシュ
    cache_set(market_cache_table, {'cache_key': 'macro'}, macro, ttl_minutes=15)
    return macro


def get_nikkei225_breadth() -> dict:
    """
    日経225の騰落レシオ・上昇下落銘柄数を計算（DynamoDBに8時間キャッシュ）
    """
    # キャッシュ確認
    cached = cache_get(market_cache_table, {'cache_key': 'breadth'})
    if cached:
        print("騰落レシオ: キャッシュヒット")
        return cached

    print("騰落レシオ: yfinanceから計算（30銘柄）")
    # 日経225構成銘柄（主要30銘柄で簡易計算）
    nikkei_sample = [
        "7203.T", "6758.T", "9984.T", "8306.T", "6861.T",
        "9432.T", "7974.T", "6367.T", "4063.T", "8316.T",
        "6501.T", "6702.T", "7267.T", "4543.T", "9433.T",
        "8035.T", "6752.T", "2914.T", "4452.T", "7751.T",
        "6954.T", "4519.T", "9022.T", "8411.T", "5108.T",
        "6503.T", "7733.T", "4568.T", "6971.T", "9020.T",
    ]
    try:
        data = yf.download(nikkei_sample, period="3d", progress=False)
        close = data["Close"]
        change = close.pct_change().iloc[-1]
        advancers = int((change > 0).sum())
        decliners = int((change < 0).sum())
        ratio = round(advancers / decliners, 2) if decliners > 0 else None
        result = {
            "advancers": advancers,
            "decliners": decliners,
            "advance_decline_ratio": ratio,
        }
        # 8時間キャッシュ（翌営業日まで有効）
        cache_set(market_cache_table, {'cache_key': 'breadth'}, result, ttl_minutes=480)
        return result
    except:
        return {
            "advancers": None,
            "decliners": None,
            "advance_decline_ratio": None,
        }


def get_technical_data(ticker_code: str) -> dict:
    """
    テクニカル指標を計算して返す（DynamoDBに4時間キャッシュ）
    """
    # キャッシュ確認
    cached = cache_get(stock_cache_table, {'code': ticker_code, 'cache_type': 'technical'})
    if cached:
        print(f"テクニカル {ticker_code}: キャッシュヒット")
        return cached

    print(f"テクニカル {ticker_code}: yfinanceから計算")
    try:
        t = yf.Ticker(ticker_code)
        hist = t.history(period="6mo")
        if len(hist) < 30:
            return {}

        close = hist["Close"]
        volume = hist["Volume"]

        # 移動平均
        ma5  = safe_float(close.rolling(5).mean().iloc[-1])
        ma25 = safe_float(close.rolling(25).mean().iloc[-1])
        ma75 = safe_float(close.rolling(75).mean().iloc[-1]) if len(close) >= 75 else None

        # RSI
        delta = close.diff()
        gain  = delta.clip(lower=0).rolling(14).mean()
        loss  = (-delta.clip(upper=0)).rolling(14).mean()
        rs    = gain / loss
        rsi   = safe_float(100 - (100 / (1 + rs.iloc[-1])))

        # MACD
        ema12      = close.ewm(span=12).mean()
        ema26      = close.ewm(span=26).mean()
        macd_line  = ema12 - ema26
        signal     = macd_line.ewm(span=9).mean()
        macd_hist  = macd_line - signal
        macd_val   = safe_float(macd_line.iloc[-1])
        macd_sig   = safe_float(signal.iloc[-1])
        macd_h     = safe_float(macd_hist.iloc[-1])

        # ボリンジャーバンド
        ma20      = close.rolling(20).mean()
        std20     = close.rolling(20).std()
        bb_upper  = safe_float((ma20 + 2 * std20).iloc[-1])
        bb_mid    = safe_float(ma20.iloc[-1])
        bb_lower  = safe_float((ma20 - 2 * std20).iloc[-1])

        # ATR
        high  = hist["High"]
        low   = hist["Low"]
        tr    = pd.concat([
            high - low,
            (high - close.shift()).abs(),
            (low  - close.shift()).abs(),
        ], axis=1).max(axis=1)
        atr   = safe_float(tr.rolling(14).mean().iloc[-1])

        # 出来高移動平均比
        vol_ma20   = volume.rolling(20).mean()
        vol_ratio  = safe_float(volume.iloc[-1] / vol_ma20.iloc[-1])

        # OBV
        obv = (np.sign(close.diff()) * volume).fillna(0).cumsum()
        obv_val = safe_float(obv.iloc[-1])

        # ストキャスティクス
        low14  = low.rolling(14).min()
        high14 = high.rolling(14).max()
        stoch_k = safe_float(((close - low14) / (high14 - low14) * 100).iloc[-1])

        # ADX（簡易計算）
        plus_dm  = high.diff().clip(lower=0)
        minus_dm = (-low.diff()).clip(lower=0)
        tr_adx   = tr.rolling(14).mean()
        plus_di  = safe_float((plus_dm.rolling(14).mean()  / tr_adx * 100).iloc[-1])
        minus_di = safe_float((minus_dm.rolling(14).mean() / tr_adx * 100).iloc[-1])
        if plus_di and minus_di:
            dx  = abs(plus_di - minus_di) / (plus_di + minus_di) * 100
            adx = safe_float(dx)
        else:
            adx = None

        # 52週レンジ位置
        week52_high = safe_float(close.tail(252).max())
        week52_low  = safe_float(close.tail(252).min())
        current     = safe_float(close.iloc[-1])
        if week52_high and week52_low and (week52_high - week52_low) > 0:
            range_position = safe_float(
                (current - week52_low) / (week52_high - week52_low) * 100
            )
        else:
            range_position = None

        # モメンタム
        momentum_1m  = safe_float((close.iloc[-1] / close.iloc[-21] - 1) * 100) if len(close) >= 21  else None
        momentum_3m  = safe_float((close.iloc[-1] / close.iloc[-63] - 1) * 100) if len(close) >= 63  else None
        momentum_6m  = safe_float((close.iloc[-1] / close.iloc[-126] - 1) * 100) if len(close) >= 126 else None

        result = {
            "price":          current,
            "ma5":            ma5,
            "ma25":           ma25,
            "ma75":           ma75,
            "rsi":            rsi,
            "macd":           macd_val,
            "macd_signal":    macd_sig,
            "macd_hist":      macd_h,
            "bb_upper":       bb_upper,
            "bb_mid":         bb_mid,
            "bb_lower":       bb_lower,
            "atr":            atr,
            "volume_ratio":   vol_ratio,
            "obv":            obv_val,
            "stoch_k":        stoch_k,
            "adx":            adx,
            "week52_high":    week52_high,
            "week52_low":     week52_low,
            "range_position": range_position,
            "momentum_1m":    momentum_1m,
            "momentum_3m":    momentum_3m,
            "momentum_6m":    momentum_6m,
        }
        # 4時間キャッシュ
        cache_set(stock_cache_table,
                  {'code': ticker_code, 'cache_type': 'technical'},
                  result, ttl_minutes=240)
        return result
    except Exception as e:
        print(f"テクニカル計算エラー: {e}")
        return {}


def get_fundamental_data(ticker_code: str) -> dict:
    """
    ファンダメンタル指標を取得（DynamoDBに24時間キャッシュ）
    """
    # キャッシュ確認
    cached = cache_get(stock_cache_table, {'code': ticker_code, 'cache_type': 'fundamental'})
    if cached:
        print(f"ファンダ {ticker_code}: キャッシュヒット")
        return cached

    print(f"ファンダ {ticker_code}: yfinanceから取得")
    try:
        t    = yf.Ticker(ticker_code)
        info = t.info
        result = {
            "per":              safe_float(info.get("trailingPE")),
            "pbr":              safe_float(info.get("priceToBook")),
            "roe":              safe_float(info.get("returnOnEquity",  0) * 100) if info.get("returnOnEquity")    else None,
            "roa":              safe_float(info.get("returnOnAssets",  0) * 100) if info.get("returnOnAssets")    else None,
            "revenue_growth":   safe_float(info.get("revenueGrowth",  0) * 100) if info.get("revenueGrowth")     else None,
            "eps_growth":       safe_float(info.get("earningsGrowth", 0) * 100) if info.get("earningsGrowth")    else None,
            "operating_margin": safe_float(info.get("operatingMargins",0) * 100) if info.get("operatingMargins") else None,
            "debt_ratio":       safe_float(info.get("debtToEquity")),
            "equity_ratio":     safe_float(info.get("bookValue")),
            "dividend_yield":   safe_float(info.get("dividendYield", 0) * 100) if info.get("dividendYield")      else None,
            "fcf":              info.get("freeCashflow"),
            "target_price":     safe_float(info.get("targetMeanPrice")),
            "analyst_rating":   info.get("recommendationKey"),
            "sector":           info.get("sector"),
            "industry":         info.get("industry"),
        }

        # 年次トレンドデータ（長期診断用）
        try:
            fin = t.financials
            if 'Total Revenue' in fin.index:
                rev = fin.loc['Total Revenue'].sort_index()
                result["revenue_trend"] = {
                    str(k.year): round(float(v) / 1e8, 1)
                    for k, v in rev.items()
                }
            if 'Operating Income' in fin.index:
                op = fin.loc['Operating Income'].sort_index()
                result["op_income_trend"] = {
                    str(k.year): round(float(v) / 1e8, 1)
                    for k, v in op.items()
                }
        except Exception as e:
            print(f"年次トレンド取得エラー: {e}")

        # 24時間キャッシュ（ファンダは変化が少ない）
        cache_set(stock_cache_table,
                  {'code': ticker_code, 'cache_type': 'fundamental'},
                  result, ttl_minutes=1440)
        return result
    except Exception as e:
        print(f"ファンダ取得エラー: {e}")
        return {}


def get_earnings_alert(earnings_date_str: str, period: str) -> dict:
    """
    決算アラートレベルを判定
    period: "短期" / "中期" / "長期"
    """
    if not earnings_date_str or earnings_date_str == "なし":
        return {
            "exists":  False,
            "date":    None,
            "level":   "safe",
            "message": None,
        }

    try:
        from datetime import datetime, date
        earnings_date = datetime.strptime(earnings_date_str, "%Y-%m-%d").date()
        today         = date.today()
        days_to       = (earnings_date - today).days

        if days_to < 0:
            return {
                "exists":  False,
                "date":    None,
                "level":   "safe",
                "message": None,
            }

        # 期間別の閾値
        if period == "短期":
            danger_days  = 7
            caution_days = 14
        elif period == "中期":
            danger_days  = 14
            caution_days = 30
        else:
            # 長期は決算アラート不要
            return {
                "exists":  False,
                "date":    None,
                "level":   "safe",
                "message": None,
            }

        if days_to <= danger_days:
            level   = "danger"
            message = f"{earnings_date_str}（{days_to}日後）に決算発表があります。急騰・急落リスクが高いため慎重に判断してください。"
        elif days_to <= caution_days:
            level   = "caution"
            message = f"{earnings_date_str}（{days_to}日後）に決算発表があります。決算内容次第でトレンドが変わる可能性があります。"
        else:
            level   = "safe"
            message = f"{earnings_date_str}（{days_to}日後）に決算予定があります。"

        return {
            "exists":  True,
            "date":    earnings_date_str,
            "days_to": days_to,
            "level":   level,
            "message": message,
        }
    except:
        return {
            "exists":  False,
            "date":    None,
            "level":   "safe",
            "message": None,
        }


# ===================================================
# プロンプト生成
# ===================================================

def fmt(val, suffix="", null_str="データなし"):
    """値をフォーマット。Noneならnull_strを返す"""
    if val is None:
        return null_str
    return f"{val}{suffix}"


def build_short_prompt(name, code, tech, fund, macro, breadth,
                       earnings_alert, news_summary, score, user_profile,
                       sector="不明", industry="不明") -> str:
    return f"""
あなたは日本株の短期スイングトレード専門アナリストです。
以下のデータを元に{name}（{code}）が1〜2週間で「上昇・様子見・下落」のどれになるかを確率ベースで判断してください。

【前提】
- すべての判断には具体的な数値を引用した理由を付ける（3文以上）
- 確率の合計は必ず100にすること
- リスク許容度が低い場合は様子見寄りに補正すること
- JSONのみ出力（前置き・説明文禁止）

【最重要ルール】
- RSI・MACDなど単一指標で結論を出してはいけない
- 「今の相場で資金が入る銘柄か」を最優先に判断する
- セクター強度と資金流入を必ず評価する
- 個別ではなく相対評価（強い/普通/弱い）で判断する

【優先順位】
1. セクター資金フロー（最重要）
2. 地合い（指数・VIX）
3. 短期トレンド（MA・出来高）
4. テクニカル（RSI・MACD）
5. ファンダメンタル（補助）

【推定ルール（データが無い場合）】
- セクター強度：ニュース、指数トレンド、マクロ（原油・金利・為替）から推定し、必ず「strong/neutral/weak」で評価する
- 資金流入：出来高の増減（データがあれば）、なければ直近の値動きの強弱とニュースから「inflow/neutral/outflow」で推定する
- トレンド：MA25を基準に「uptrend/downtrend/sideways」で必ず判定する
- 推定した場合は、必ず「推定」と明記すること

【禁止】
- RSIやMACDのみで結論を出す
- データが無いのに断定する（必ず推定と書く）

【必須分析】
- セクターに資金が入っているか
- 需給（強い銘柄か弱い銘柄か）
- 短期トレンドが継続しているか

【ユーザープロファイル】
- リスク許容度：{user_profile.get('risk_level', '中')}
- 分析スタイル：{user_profile.get('analysis_style', 'バランス型')}

【テクニカル】
- 現在株価：{fmt(tech.get('price'), '円')}
- RSI(14)：{fmt(tech.get('rsi'))}
  ※70以上=買われすぎ・反落リスク／50〜70=上昇継続／30〜50=弱含み／30以下=売られすぎ・反発期待
- MACD：{fmt(tech.get('macd'))} / シグナル：{fmt(tech.get('macd_signal'))} / ヒストグラム：{fmt(tech.get('macd_hist'))}
  ※MACDがシグナルを上回る=上昇シグナル／ヒストグラム拡大=トレンド強化
- ボリンジャー：上{fmt(tech.get('bb_upper'), '円')} 中{fmt(tech.get('bb_mid'), '円')} 下{fmt(tech.get('bb_lower'), '円')}
  ※上限付近=反落リスク／下限付近=反発期待
- MA5：{fmt(tech.get('ma5'), '円')} / MA25：{fmt(tech.get('ma25'), '円')}
  ※MA5がMA25を上回る=ゴールデンクロス／下回る=デッドクロス
- ストキャス(K)：{fmt(tech.get('stoch_k'))}
  ※80以上=買われすぎ／20以下=売られすぎ
- OBV：{fmt(tech.get('obv'))}
  ※上昇トレンドなら出来高が伴っているか確認
- ATR：{fmt(tech.get('atr'), '円')}
  ※ボラティリティの目安
- 出来高移動平均比：{fmt(tech.get('volume_ratio'), '倍')}
  ※1.5倍以上=注目度高い／0.5倍以下=閑散
- 52週レンジ位置：{fmt(tech.get('range_position'), '%')}
  ※0%=52週安値／100%=52週高値／30%以下=底値圏／70%以上=高値圏

【需給】
- 信用倍率：{fmt(macro.get('margin_ratio'), '倍')}
  ※倍率高い=将来の売り圧力
- 空売り比率：{fmt(macro.get('short_ratio'), '%')}
  ※高い=弱気筋が多い

【市場内部】
- 騰落レシオ：{fmt(breadth.get('advance_decline_ratio'))}
  ※120以上=過熱感／70以下=売られすぎ
- 上昇銘柄数：{fmt(breadth.get('advancers'))} / 下落銘柄数：{fmt(breadth.get('decliners'))}

【セクター情報】
- セクター：{sector}
- 業種：{industry}

【ファンダ（参考）】
- PER：{fmt(fund.get('per'), '倍')} / PBR：{fmt(fund.get('pbr'), '倍')}
- ROE：{fmt(fund.get('roe'), '%')}
- 売上成長率：{fmt(fund.get('revenue_growth'), '%')}

【市場環境】
- 日経平均トレンド：{fmt(macro.get('nikkei_trend'))}
- VIX：{fmt(macro.get('vix'))}
  ※20以下=安定／20〜30=やや不安定／30以上=恐怖状態
- 米10年債：{fmt(macro.get('us10y'), '%')}
  ※金利上昇=グロース株逆風
- ドル円：{fmt(macro.get('usd_jpy'), '円')}
  ※円安=輸出株有利／円高=輸入株有利
- S&P500トレンド：{fmt(macro.get('sp500_trend'))}

【マクロ指標】
- DXY（ドル指数）：{fmt(macro.get('dxy'))}
- 原油：{fmt(macro.get('oil_price'), 'ドル')}
- 金：{fmt(macro.get('gold_price'), 'ドル')}
  ※金上昇=リスクオフの指標

【決算アラート】
- 決算日：{fmt(earnings_alert.get('date'))}
- 残り日数：{fmt(earnings_alert.get('days_to'), '日')}
- アラートレベル：{earnings_alert.get('level', 'safe')}
  ※danger=7日以内（急騰・急落リスク大）／caution=14日以内（注意）／safe=当面なし
  ※リスク許容度が低い場合はdanger・cautionで様子見を強く推奨

【ニュース】
{news_summary}

【参考スコア】
- 総合スコア：{fmt(score, '点')}
  ※スコアは参考情報として扱い再計算・変更はしない

以下のJSON形式のみで回答（他のテキスト禁止）：
{{
  "verdict": {{ "value": "up/sideways/down", "reason": "3〜5文で数値を引用して具体的に" }},
  "probability": {{
    "up":       {{ "value": 上昇確率(整数0〜100), "reason": "3文以上で具体的に" }},
    "sideways": {{ "value": 横ばい確率(整数0〜100), "reason": "3文以上で具体的に" }},
    "down":     {{ "value": 下落確率(整数0〜100), "reason": "3文以上で具体的に" }}
  }},
  "confidence": {{ "value": "high/medium/low", "reason": "2〜3文で" }},
  "earnings_alert": {{
    "exists":  {str(earnings_alert.get('exists', False)).lower()},
    "date":    {json.dumps(earnings_alert.get('date'), ensure_ascii=False)},
    "level":   "{earnings_alert.get('level', 'safe')}",
    "message": {json.dumps(earnings_alert.get('message'), ensure_ascii=False)}
  }},
  "macro_analysis": {{
    "risk_mode":            {{ "value": "risk_on/risk_off/neutral", "reason": "VIX・米株から3文で" }},
    "usd_jpy_impact":       {{ "value": "positive/negative/neutral", "reason": "2〜3文で" }},
    "interest_rate_impact": {{ "value": "positive/negative/neutral", "reason": "2〜3文で" }}
  }},
  "supply_demand": {{
    "bias": {{ "value": "bullish/bearish/neutral", "reason": "信用倍率・空売り比率から2〜3文で" }}
  }},
  "price_strategy": {{
    "entry":       {{ "value": "具体的な価格帯（例：2450〜2500円）", "reason": "3〜4文で" }},
    "stop_loss":   {{ "value": 損切り価格(数値), "reason": "3〜4文で" }},
    "take_profit": {{ "value": 利確価格(数値), "reason": "3〜4文で" }}
  }},
  "positive_points": ["上昇根拠1（指標名と数値を含め2文以上）", "上昇根拠2", "上昇根拠3"],
  "negative_points": ["下落リスク1（指標名と数値を含め2文以上）", "下落リスク2", "下落リスク3"],
  "summary": "5〜8文で具体的な数値を交えた総合サマリー"
}}
""".strip()


def build_medium_prompt(name, code, tech, fund, macro, breadth,
                        earnings_alert, news_summary, score, user_profile,
                        sector="不明", industry="不明") -> str:
    return f"""
あなたは日本株の中期投資（1〜3ヶ月）専門アナリストです。
以下のデータを元に{name}（{code}）が1〜3ヶ月で「上昇・様子見・下落」のどれになるかを確率ベースで判断してください。

【前提】
- 短期ノイズより中期トレンドを優先
- すべての判断には具体的な数値を引用した理由を付ける（3文以上）
- 確率の合計は必ず100にすること
- JSONのみ出力（前置き・説明文禁止）

【最重要ルール】
- RSI・MACDなど単一指標で結論を出してはいけない
- 「今の相場で資金が入る銘柄か」を最優先に判断する
- セクター強度と資金流入を必ず評価する
- 個別ではなく相対評価（強い/普通/弱い）で判断する

【優先順位】
1. セクター強度（最重要）
2. 資金流入/流出（テーマ性）
3. マクロ環境（為替・金利・原油）
4. トレンド（MA25）
5. ファンダメンタル（成長・割安）
6. テクニカル（補助）

【推定ルール（データが無い場合）】
- セクター強度：ニュース、指数トレンド、マクロ（原油・金利・為替）から推定し、必ず「strong/neutral/weak」で評価する
- 資金流入：出来高の増減（データがあれば）、なければ直近の値動きの強弱とニュースから「inflow/neutral/outflow」で推定する
- トレンド：MA25を基準に「uptrend/downtrend/sideways」で必ず判定する
- 推定した場合は、必ず「推定」と明記すること

【禁止】
- RSIやMACDのみで結論を出す
- データが無いのに断定する（必ず推定と書く）

【必須分析】
- この銘柄のセクターは強いか（強い/普通/弱い）
- 市場資金は流入しているか
- 相場テーマに合っているか
- トレンドは継続か崩れか

【ユーザープロファイル】
- リスク許容度：{user_profile.get('risk_level', '中')}
- 分析スタイル：{user_profile.get('analysis_style', 'バランス型')}

【テクニカル（トレンド重視）】
- 現在株価：{fmt(tech.get('price'), '円')}
- MA25：{fmt(tech.get('ma25'), '円')} / MA75：{fmt(tech.get('ma75'), '円')}
  ※MA25がMA75を上回る=中期上昇トレンド
- MACD：{fmt(tech.get('macd'))} / シグナル：{fmt(tech.get('macd_signal'))} / ヒストグラム：{fmt(tech.get('macd_hist'))}
- ADX：{fmt(tech.get('adx'))}
  ※25以上=トレンド強い／25以下=方向感なし
- OBV：{fmt(tech.get('obv'))}
- 出来高移動平均比：{fmt(tech.get('volume_ratio'), '倍')}
- 52週レンジ位置：{fmt(tech.get('range_position'), '%')}
- モメンタム（1ヶ月）：{fmt(tech.get('momentum_1m'), '%')}
- モメンタム（3ヶ月）：{fmt(tech.get('momentum_3m'), '%')}

【需給】
- 信用倍率：{fmt(macro.get('margin_ratio'), '倍')}
- 空売り比率：{fmt(macro.get('short_ratio'), '%')}

【市場内部】
- 騰落レシオ：{fmt(breadth.get('advance_decline_ratio'))}
- 上昇銘柄数：{fmt(breadth.get('advancers'))} / 下落銘柄数：{fmt(breadth.get('decliners'))}

【セクター情報】
- セクター：{sector}
- 業種：{industry}

【ファンダメンタル】
- PER：{fmt(fund.get('per'), '倍')}
  ※業種平均より低い=割安
- PBR：{fmt(fund.get('pbr'), '倍')}
  ※1倍割れ=資産的に割安
- ROE：{fmt(fund.get('roe'), '%')}
  ※10%以上=資本効率良好
- ROA：{fmt(fund.get('roa'), '%')}
- 売上成長率：{fmt(fund.get('revenue_growth'), '%')}
- EPS成長率：{fmt(fund.get('eps_growth'), '%')}
- 営業利益率：{fmt(fund.get('operating_margin'), '%')}
- 配当利回り：{fmt(fund.get('dividend_yield'), '%')}

【市場環境】
- 日経平均トレンド：{fmt(macro.get('nikkei_trend'))}
- VIX：{fmt(macro.get('vix'))}
- 米10年債：{fmt(macro.get('us10y'), '%')}
- 米2年債：{fmt(macro.get('us2y'), '%')}
- 金利差（10年-2年）：{fmt(macro.get('yield_spread'), '%')}
  ※マイナス=逆イールド・景気後退シグナル
- ドル円：{fmt(macro.get('usd_jpy'), '円')}
- DXY：{fmt(macro.get('dxy'))}
- S&P500トレンド：{fmt(macro.get('sp500_trend'))}

【マクロ指標】
- 原油：{fmt(macro.get('oil_price'), 'ドル')}
- 金：{fmt(macro.get('gold_price'), 'ドル')}

【決算アラート】
- 決算日：{fmt(earnings_alert.get('date'))}
- 残り日数：{fmt(earnings_alert.get('days_to'), '日')}
- アラートレベル：{earnings_alert.get('level', 'safe')}
  ※danger=14日以内／caution=1ヶ月以内／safe=当面なし

【ニュース】
{news_summary}

【参考スコア】
- 総合スコア：{fmt(score, '点')}

以下のJSON形式のみで回答（他のテキスト禁止）：
{{
  "verdict": {{ "value": "up/sideways/down", "reason": "3〜5文で数値を引用して具体的に" }},
  "probability": {{
    "up":       {{ "value": 上昇確率(整数0〜100), "reason": "3文以上で具体的に" }},
    "sideways": {{ "value": 横ばい確率(整数0〜100), "reason": "3文以上で具体的に" }},
    "down":     {{ "value": 下落確率(整数0〜100), "reason": "3文以上で具体的に" }}
  }},
  "confidence": {{ "value": "high/medium/low", "reason": "2〜3文で" }},
  "earnings_alert": {{
    "exists":  {str(earnings_alert.get('exists', False)).lower()},
    "date":    {json.dumps(earnings_alert.get('date'), ensure_ascii=False)},
    "level":   "{earnings_alert.get('level', 'safe')}",
    "message": {json.dumps(earnings_alert.get('message'), ensure_ascii=False)}
  }},
  "trend_analysis": {{
    "strength": {{ "value": "strong/weak/neutral", "reason": "MA・ADX・モメンタムから3文で" }}
  }},
  "fundamental_analysis": {{
    "growth":    {{ "value": "high/medium/low",          "reason": "売上・EPS成長率から3文で" }},
    "valuation": {{ "value": "undervalued/fair/overvalued", "reason": "PER・PBRから3文で" }}
  }},
  "macro_analysis": {{
    "risk_mode":            {{ "value": "risk_on/risk_off/neutral", "reason": "3文で" }},
    "usd_jpy_impact":       {{ "value": "positive/negative/neutral", "reason": "2〜3文で" }},
    "interest_rate_impact": {{ "value": "positive/negative/neutral", "reason": "金利差も含め3文で" }}
  }},
  "price_outlook": {{
    "range": {{ "value": "3ヶ月の想定値幅（例：2200〜2800円）", "reason": "3〜4文で" }}
  }},
  "positive_points": ["上昇根拠1（指標名と数値を含め2文以上）", "上昇根拠2", "上昇根拠3"],
  "negative_points": ["下落リスク1（指標名と数値を含め2文以上）", "下落リスク2", "下落リスク3"],
  "summary": "5〜8文で具体的な数値を交えた総合サマリー"
}}
""".strip()


def build_long_prompt(name, code, tech, fund, macro,
                      news_summary, score, user_profile,
                      sector="不明", industry="不明") -> str:
    return f"""
あなたは日本株の長期投資（1年以上）専門アナリストです。
以下のデータを元に{name}（{code}）が長期で「上昇・様子見・下落」のどれになるかを確率ベースで判断してください。

【前提】
- 企業の成長性・収益性・財務健全性とマクロ環境を最優先
- すべての判断には具体的な数値を引用した理由を付ける（3文以上）
- 確率の合計は必ず100にすること
- JSONのみ出力（前置き・説明文禁止）

【最重要ルール】
- RSI・MACDなど単一指標で結論を出してはいけない
- 「今の相場で資金が入る銘柄か」を最優先に判断する
- セクター強度と資金流入を必ず評価する
- 個別ではなく相対評価（強い/普通/弱い）で判断する

【優先順位】
1. ファンダメンタル（最重要）
2. 成長性（売上・ROE）
3. マクロ環境（金利・為替）
4. セクター構造（市場テーマ）
5. バリュエーション（PER・PBR）
6. テクニカル（参考程度）

【推定ルール（データが無い場合）】
- セクター強度：ニュース、指数トレンド、マクロ（原油・金利・為替）から推定し、必ず「strong/neutral/weak」で評価する
- 資金流入：出来高の増減（データがあれば）、なければ直近の値動きの強弱とニュースから「inflow/neutral/outflow」で推定する
- トレンド：MA25を基準に「uptrend/downtrend/sideways」で必ず判定する
- 推定した場合は、必ず「推定」と明記すること

【禁止】
- RSIやMACDのみで結論を出す
- データが無いのに断定する（必ず推定と書く）

【必須分析】
- 長期成長できる企業か
- セクターが今後伸びるか
- 金利環境が追い風か逆風か

【ユーザープロファイル】
- リスク許容度：{user_profile.get('risk_level', '中')}
- 分析スタイル：{user_profile.get('analysis_style', 'バランス型')}

【ファンダメンタル（最重要）】
- PER：{fmt(fund.get('per'), '倍')}
  ※業種平均より低い=割安
- PBR：{fmt(fund.get('pbr'), '倍')}
  ※1倍割れ=資産的に割安
- ROE：{fmt(fund.get('roe'), '%')}
  ※10%以上=資本効率良好／5%以下=低効率
- ROA：{fmt(fund.get('roa'), '%')}
  ※5%以上=資産効率良好
- 売上成長率：{fmt(fund.get('revenue_growth'), '%')}
  ※プラス継続=成長トレンド
- EPS成長率：{fmt(fund.get('eps_growth'), '%')}
- 営業利益率：{fmt(fund.get('operating_margin'), '%')}
- 負債比率：{fmt(fund.get('debt_ratio'))}
  ※低いほど財務健全
- 配当利回り：{fmt(fund.get('dividend_yield'), '%')}
- FCF：{fmt(fund.get('fcf'))}
  ※プラス=キャッシュ創出力あり
- アナリスト目標株価：{fmt(fund.get('target_price'), '円')}
- アナリスト評価：{fmt(fund.get('analyst_rating'))}

【セクター情報】
- セクター：{sector}
- 業種：{industry}

【テクニカル（参考）】
- 現在株価：{fmt(tech.get('price'), '円')}
- MA75：{fmt(tech.get('ma75'), '円')}
- 52週レンジ位置：{fmt(tech.get('range_position'), '%')}
- モメンタム（3ヶ月）：{fmt(tech.get('momentum_3m'), '%')}
- モメンタム（6ヶ月）：{fmt(tech.get('momentum_6m'), '%')}
- ADX：{fmt(tech.get('adx'))}

【マクロ・市場環境】
- 日経平均トレンド：{fmt(macro.get('nikkei_trend'))}
- VIX：{fmt(macro.get('vix'))}
- 米10年債：{fmt(macro.get('us10y'), '%')}
- 米2年債：{fmt(macro.get('us2y'), '%')}
- 金利差（10年-2年）：{fmt(macro.get('yield_spread'), '%')}
  ※マイナス=逆イールド・景気後退シグナル
- ドル円：{fmt(macro.get('usd_jpy'), '円')}
- DXY：{fmt(macro.get('dxy'))}
- 原油：{fmt(macro.get('oil_price'), 'ドル')}
- 金：{fmt(macro.get('gold_price'), 'ドル')}
- S&P500トレンド：{fmt(macro.get('sp500_trend'))}

【ニュース】
{news_summary}

【参考スコア】
- 総合スコア：{fmt(score, '点')}

以下のJSON形式のみで回答（他のテキスト禁止）：
{{
  "verdict": {{ "value": "up/sideways/down", "reason": "3〜5文で数値を引用して具体的に" }},
  "probability": {{
    "up":       {{ "value": 上昇確率(整数0〜100), "reason": "3文以上で具体的に" }},
    "sideways": {{ "value": 横ばい確率(整数0〜100), "reason": "3文以上で具体的に" }},
    "down":     {{ "value": 下落確率(整数0〜100), "reason": "3文以上で具体的に" }}
  }},
  "confidence": {{ "value": "high/medium/low", "reason": "2〜3文で" }},
  "fundamental_analysis": {{
    "growth":       {{ "value": "high/medium/low", "reason": "売上・EPS成長率から3文で" }},
    "profitability":{{ "value": "high/medium/low", "reason": "ROE・営業利益率から3文で" }},
    "financial_health": {{ "value": "strong/neutral/weak", "reason": "負債比率・FCFから3文で" }},
    "valuation":    {{ "value": "undervalued/fair/overvalued", "reason": "PER・PBRから3文で" }}
  }},
  "macro_analysis": {{
    "risk_mode":            {{ "value": "risk_on/risk_off/neutral", "reason": "3文で" }},
    "interest_rate_impact": {{ "value": "positive/negative/neutral", "reason": "金利差も含め3文で" }},
    "usd_jpy_impact":       {{ "value": "positive/negative/neutral", "reason": "2〜3文で" }}
  }},
  "price_outlook": {{
    "target_trend": {{ "value": "uptrend/sideways/downtrend", "reason": "長期的な方向性を3〜4文で" }}
  }},
  "long_term_risk": {{ "value": "high/medium/low", "reason": "長期リスクを3文で" }},
  "positive_points": ["上昇根拠1（指標名と数値を含め2文以上）", "上昇根拠2", "上昇根拠3"],
  "negative_points": ["下落リスク1（指標名と数値を含め2文以上）", "下落リスク2", "下落リスク3"],
  "summary": "5〜8文で長期投資家向けの具体的な総合サマリー"
}}
""".strip()