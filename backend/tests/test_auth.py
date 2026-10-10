# ===================================================
# Cognito のアクセストークン確認（services/auth.py）
#
# 本物の Cognito にはつながない。テストの中で RSA の鍵を作り、
# 本物と同じ形のトークンを自分で発行して確かめる。
# ===================================================

import time

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from config.auth import COGNITO_APP_CLIENT_ID, COGNITO_ISSUER
from services import auth

USER_ID = "11111111-2222-3333-4444-555555555555"


@pytest.fixture(scope="module")
def keys():
    private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    other = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    return private, other


@pytest.fixture(autouse=True)
def fake_jwks(monkeypatch, keys):
    """Cognito の公開鍵の取得を、テスト用の公開鍵を返す偽物に差し替える"""
    public = keys[0].public_key()

    class FakeKey:
        key = public

    class FakeClient:
        def get_signing_key_from_jwt(self, token):
            return FakeKey()

    monkeypatch.setattr(auth, "_get_jwks_client", lambda: FakeClient())


def make_token(private_key, **overrides):
    now = int(time.time())
    claims = {
        "sub": USER_ID,
        "iss": COGNITO_ISSUER,
        "token_use": "access",
        "client_id": COGNITO_APP_CLIENT_ID,
        "iat": now,
        "exp": now + 3600,
    }
    claims.update(overrides)
    return jwt.encode(claims, private_key, algorithm="RS256")


def test_valid_token(keys):
    result = auth.verify_request_token("Bearer " + make_token(keys[0]))
    assert result.status == "valid"
    assert result.user_id == USER_ID


def test_no_header():
    assert auth.verify_request_token(None).status == "none"
    assert auth.verify_request_token("").status == "none"


def test_not_bearer(keys):
    result = auth.verify_request_token("Basic abc")
    assert result.status == "invalid"
    assert result.user_id is None


@pytest.mark.parametrize(
    "overrides, reason_part",
    [
        ({"exp": int(time.time()) - 10}, "期限切れ"),
        ({"client_id": "other-app"}, ""),
        ({"token_use": "id"}, ""),
        ({"iss": "https://example.com/other-pool"}, ""),
    ],
)
def test_rejects_wrong_tokens(keys, overrides, reason_part):
    result = auth.verify_request_token("Bearer " + make_token(keys[0], **overrides))
    assert result.status == "invalid"
    assert result.user_id is None
    assert reason_part in result.reason


def test_rejects_token_signed_by_other_key(keys):
    # 偽物の鍵で作ったトークン（署名が合わない）
    result = auth.verify_request_token("Bearer " + make_token(keys[1]))
    assert result.status == "invalid"


def test_rejects_garbage():
    assert auth.verify_request_token("Bearer not-a-jwt").status == "invalid"
