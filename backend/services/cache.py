import boto3
from decimal import Decimal
from datetime import datetime, timedelta


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
        if expires_at and datetime.fromisoformat(str(expires_at)) < datetime.now():
            return None  # TTL切れ
        return _from_decimal({k: v for k, v in item.items()
                               if k not in ('expires_at', 'updated_at')})
    except Exception as e:
        print(f"キャッシュ取得エラー: {e}")
        return None

def cache_set(table, key: dict, data: dict, ttl_minutes: int = 60):
    """DynamoDBにキャッシュ保存"""
    try:
        item = {
            **key,
            **data,
            'updated_at': datetime.now().isoformat(),
            'expires_at': (datetime.now() + timedelta(minutes=ttl_minutes)).isoformat(),
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