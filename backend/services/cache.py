import time
import boto3
from decimal import Decimal
from datetime import datetime, timedelta
from services.clock import now_jst


def _to_decimal(obj):
    """float → Decimal変換（DynamoDB保存用）"""
    if isinstance(obj, float):
        return Decimal(str(obj))
    if isinstance(obj, dict):
        return {k: _to_decimal(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_to_decimal(i) for i in obj]
    return obj

def _from_decimal(obj):
    """Decimal → float変換（レスポンス用）"""
    if isinstance(obj, Decimal):
        return float(obj)
    if isinstance(obj, dict):
        return {k: _from_decimal(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_from_decimal(i) for i in obj]
    return obj

def cache_get(table, key: dict) -> dict | None:
    """DynamoDBキャッシュ取得。期限切れ・未存在はNoneを返す"""
    try:
        res  = table.get_item(Key=key)
        item = res.get('Item')
        if not item:
            return None
        expires_at = item.get('expires_at')
        if expires_at and datetime.fromisoformat(str(expires_at)) < now_jst():
            return None  # TTL切れ
        return _from_decimal({k: v for k, v in item.items()
                               if k not in ('expires_at', 'updated_at', 'ttl')})
    except Exception as e:
        print(f"キャッシュ取得エラー: {e}")
        return None

# DynamoDBのTTL（期限切れ項目の自動削除）用の猶予
# 期限切れの判定は cache_get が expires_at で行うので、
# 自動削除はそれより1日遅らせて、判定より先に消えないようにする
TTL_GRACE_SECONDS = 24 * 60 * 60


def cache_set(table, key: dict, data: dict, ttl_minutes: int = 60):
    """
    DynamoDBにキャッシュ保存

    ttl 属性（UNIX時刻の秒）も書く。テーブルのTTL設定で
    「ttl」属性を有効にすると、期限切れの項目をDynamoDBが自動で削除する。
    （以前は期限切れの項目が消えずに溜まり続けていた）
    UNIX時刻はタイムゾーンに依存しないので time.time() を使う。
    """
    try:
        item = {
            **key,
            **data,
            'updated_at': now_jst().isoformat(),
            'expires_at': (now_jst() + timedelta(minutes=ttl_minutes)).isoformat(),
            'ttl': int(time.time()) + ttl_minutes * 60 + TTL_GRACE_SECONDS,
        }
        table.put_item(Item=_to_decimal(item))
    except Exception as e:
        print(f"キャッシュ保存エラー: {e}")


# ===================================================
# DynamoDBキャッシュ
# ===================================================

dynamodb = boto3.resource('dynamodb', region_name='ap-northeast-1')
market_cache_table = dynamodb.Table('market_cache')
stock_cache_table  = dynamodb.Table('stock_cache')
user_profile_table = dynamodb.Table('user_profiles')

# AI予測の記録テーブル（的中率の測定用。キャッシュではないのでTTLなし）
predictions_table  = dynamodb.Table('ai_predictions')