# ===================================================
# Cognito のアクセストークンを確かめる
#
# 設定と段階的な導入の考え方は config/auth.py を参照。
# 使い方：verify_request_token(request.headers.get("authorization"))
#   → AuthResult(status, user_id, reason)
#      status："none"（トークンなし）/ "valid"（本物）/ "invalid"（偽物・期限切れ・形式違い）
#      user_id：本物のときだけ Cognito の sub（アプリの userId と同じ値）
# ===================================================

from dataclasses import dataclass

import jwt

from config.auth import (
    COGNITO_APP_CLIENT_ID,
    COGNITO_ISSUER,
    COGNITO_JWKS_URL,
    JWKS_TIMEOUT_SEC,
)


@dataclass(frozen=True)
class AuthResult:
    status: str
    user_id: str | None = None
    reason: str = ""


# 公開鍵はコンテナが生きている間キャッシュする（毎回 Cognito に取りに行かない）
_jwks_client = None


def _get_jwks_client():
    global _jwks_client
    if _jwks_client is None:
        _jwks_client = jwt.PyJWKClient(COGNITO_JWKS_URL, timeout=JWKS_TIMEOUT_SEC)
    return _jwks_client


def verify_access_token(token: str) -> dict:
    """
    Cognito のアクセストークンを確かめて、中身（claims）を返す。正しくなければ例外

    確かめること：署名（Cognito の公開鍵）・有効期限・発行元（iss）・
    アクセストークンであること（token_use）・このアプリのクライアントID（client_id）。
    アクセストークンには aud が無いので、client_id で確かめる。
    """
    signing_key = _get_jwks_client().get_signing_key_from_jwt(token)
    claims = jwt.decode(
        token,
        signing_key.key,
        algorithms=["RS256"],
        issuer=COGNITO_ISSUER,
        options={"verify_aud": False, "require": ["exp", "iss", "sub"]},
    )
    if claims.get("token_use") != "access":
        raise jwt.InvalidTokenError("アクセストークンではない")
    if claims.get("client_id") != COGNITO_APP_CLIENT_ID:
        raise jwt.InvalidTokenError("このアプリのトークンではない")
    return claims


def verify_request_token(authorization: str | None) -> AuthResult:
    """Authorization ヘッダーの値（"Bearer xxx"）を確かめる。例外は投げない"""
    if not authorization:
        return AuthResult("none")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        return AuthResult("invalid", reason="Bearer 形式ではない")
    try:
        claims = verify_access_token(token.strip())
        return AuthResult("valid", user_id=claims["sub"])
    except jwt.ExpiredSignatureError:
        return AuthResult("invalid", reason="期限切れ")
    except Exception as e:
        return AuthResult("invalid", reason=f"{type(e).__name__}: {e}")
