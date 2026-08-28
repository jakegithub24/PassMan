import uuid
from datetime import timedelta
import pytest
from fastapi import HTTPException

from core.jwt import (
    create_access_token,
    create_refresh_token,
    create_token_pair,
    decode_jwt_token,
    validate_token_type,
)
from models.schemas import ClientPlatform


def test_access_token_creation_and_claims():
    user_id = uuid.uuid4()
    token = create_access_token(user_id=user_id, client_type=ClientPlatform.ANDROID)
    
    payload = decode_jwt_token(token)
    assert payload["sub"] == str(user_id)
    assert payload["type"] == "access"
    assert payload["client_type"] == "android"
    assert "jti" not in payload
    # 10 minutes lifespan = 600 seconds
    assert payload["exp"] - payload["iat"] == 600

    validated = validate_token_type(payload, "access")
    assert validated.sub == str(user_id)
    assert validated.type == "access"


def test_refresh_token_lifespans_android_vs_web():
    user_id = uuid.uuid4()
    
    # 1. Android: 10 days = 864,000 seconds
    token_android, exp_android, jti_android = create_refresh_token(
        user_id=user_id,
        client_type=ClientPlatform.ANDROID,
    )
    payload_android = decode_jwt_token(token_android)
    assert payload_android["type"] == "refresh"
    assert payload_android["jti"] == jti_android
    assert payload_android["exp"] - payload_android["iat"] == 10 * 86400

    # 2. Web: 8 hours = 28,800 seconds
    token_web, exp_web, jti_web = create_refresh_token(
        user_id=user_id,
        client_type=ClientPlatform.WEB,
    )
    payload_web = decode_jwt_token(token_web)
    assert payload_web["type"] == "refresh"
    assert payload_web["jti"] == jti_web
    assert payload_web["exp"] - payload_web["iat"] == 8 * 3600


def test_token_pair_creation():
    user_id = uuid.uuid4()
    pair, refresh_exp, refresh_jti = create_token_pair(user_id=user_id, client_type=ClientPlatform.ANDROID)
    
    assert pair.token_type == "bearer"
    assert pair.expires_in == 600
    
    acc_payload = decode_jwt_token(pair.access_token)
    ref_payload = decode_jwt_token(pair.refresh_token)
    
    assert acc_payload["type"] == "access"
    assert ref_payload["type"] == "refresh"


def test_token_confusion_rejection():
    user_id = uuid.uuid4()
    access_token = create_access_token(user_id=user_id)
    refresh_token, _, _ = create_refresh_token(user_id=user_id)

    acc_payload = decode_jwt_token(access_token)
    ref_payload = decode_jwt_token(refresh_token)

    # Attempting to use access token as refresh token must fail
    with pytest.raises(HTTPException) as exc_info:
        validate_token_type(acc_payload, expected_type="refresh")
    assert exc_info.value.status_code == 401
    assert "Invalid token type" in exc_info.value.detail

    # Attempting to use refresh token as access token must fail
    with pytest.raises(HTTPException) as exc_info:
        validate_token_type(ref_payload, expected_type="access")
    assert exc_info.value.status_code == 401
    assert "Invalid token type" in exc_info.value.detail


def test_expired_token_rejection():
    user_id = uuid.uuid4()
    # Create token that expired 5 minutes ago
    expired_token = create_access_token(
        user_id=user_id,
        expires_delta=timedelta(minutes=-5),
    )

    with pytest.raises(HTTPException) as exc_info:
        decode_jwt_token(expired_token)
    assert exc_info.value.status_code == 401
    assert "expired" in exc_info.value.detail.lower()


def test_tampered_token_rejection():
    user_id = uuid.uuid4()
    token = create_access_token(user_id=user_id)
    tampered_token = token[:-5] + "XXXXX"

    with pytest.raises(HTTPException) as exc_info:
        decode_jwt_token(tampered_token)
    assert exc_info.value.status_code == 401
    assert "invalid" in exc_info.value.detail.lower()
