"""Tests for the login flow when it is started by the iOS app (client=ios)"""

import logging
import urllib
import uuid

import alembic.command as command
import pytest

import src.auth.login_gov_jwt_auth as login_gov_jwt_auth
from src.adapters.oauth.login_gov.login_gov_jwt import (
    LOGIN_GOV_PIV_REQUIRED,
    LoginClient,
    MobileLoginNotConfiguredError,
    get_final_redirect_uri,
)
from src.adapters.oauth.oauth_client_models import OauthTokenResponse
from src.auth.api_jwt_auth import parse_jwt_for_user
from src.db.migrations.run import alembic_cfg
from src.db.models.user_models import LoginGovState
from tests.lib.auth_test_utils import create_jwt
from tests.src.db.models.factories import (
    AgencyFactory,
    AgencyUserFactory,
    LinkExternalUserFactory,
    LoginGovStateFactory,
)

MOBILE_DESTINATION = "simplergrants://auth/callback"
WEB_RESULT_PATH = "/v1/users/login/result"


@pytest.fixture
def mobile_destination(monkeypatch):
    monkeypatch.setattr(
        login_gov_jwt_auth.get_config(), "login_mobile_final_destination", MOBILE_DESTINATION
    )


@pytest.fixture
def no_mobile_destination(monkeypatch):
    monkeypatch.setattr(login_gov_jwt_auth.get_config(), "login_mobile_final_destination", None)


def _get_state(db_session, state_id: str) -> LoginGovState | None:
    db_session.expire_all()
    return (
        db_session.query(LoginGovState)
        .filter(LoginGovState.login_gov_state_id == state_id)
        .one_or_none()
    )


def _run_login_flow(client, login_query: str) -> tuple:
    """Run the login flow one redirect at a time.

    The mobile destination is a custom URL scheme, which the test client can't follow.
    """
    login_resp = client.get(f"/v1/users/login{login_query}")
    assert login_resp.status_code == 302

    authorize_resp = client.get(login_resp.headers["Location"])
    assert authorize_resp.status_code == 302

    callback_resp = client.get(authorize_resp.headers["Location"])
    assert callback_resp.status_code == 302

    return login_resp, callback_resp


def _parse_location(resp) -> tuple[str, dict]:
    location = resp.headers["Location"]
    destination, _, query = location.partition("?")
    return destination, {k: v[0] for k, v in urllib.parse.parse_qs(query).items()}


def _add_token_response(mock_oauth_client, private_rsa_key, nonce, user_id, **kwargs) -> str:
    code = str(uuid.uuid4())
    id_token = create_jwt(user_id=user_id, nonce=nonce, private_key=private_rsa_key, **kwargs)
    mock_oauth_client.add_token_response(
        code,
        OauthTokenResponse(
            id_token=id_token, access_token="fake_token", token_type="Bearer", expires_in=300
        ),
    )
    return code


##########################################
# Web flow is unchanged
##########################################


@pytest.mark.parametrize("login_query,expected_login_client", [("", None), ("?client=web", "web")])
def test_web_login_flow_unchanged(
    client, db_session, mobile_destination, login_query, expected_login_client
):
    login_resp = client.get(f"/v1/users/login{login_query}")
    assert login_resp.status_code == 302

    login_params = urllib.parse.parse_qs(
        urllib.parse.urlparse(login_resp.headers["Location"]).query
    )
    assert login_params["acr_values"][0] == login_gov_jwt_auth.get_config().acr_value
    state = _get_state(db_session, login_params["state"][0])
    assert state is not None
    assert state.login_client == expected_login_client

    authorize_resp = client.get(login_resp.headers["Location"])
    callback_resp = client.get(authorize_resp.headers["Location"])
    assert callback_resp.status_code == 302

    destination, params = _parse_location(callback_resp)
    assert destination == f"http://localhost:8080{WEB_RESULT_PATH}"
    assert list(params.keys()) == ["message", "token", "is_user_new"]
    assert params["message"] == "success"


def test_web_login_error_still_goes_to_web_destination(client, enable_factory_create):
    login_gov_state = LoginGovStateFactory.create()

    resp = client.get(
        f"/v1/users/login/callback?state={login_gov_state.login_gov_state_id}&code=xyz456"
    )

    assert resp.status_code == 302
    destination, params = _parse_location(resp)
    assert destination == f"http://localhost:8080{WEB_RESULT_PATH}"
    assert params == {"message": "error", "error_description": "internal error"}


##########################################
# iOS flow
##########################################


def test_ios_login_flow_success_302(client, db_session, mobile_destination):
    login_resp, callback_resp = _run_login_flow(client, "?client=ios")

    # The state recorded the client, and was consumed by the callback
    state_id = urllib.parse.parse_qs(urllib.parse.urlparse(login_resp.headers["Location"]).query)[
        "state"
    ][0]
    assert _get_state(db_session, state_id) is None

    assert callback_resp.headers["Location"].startswith(
        f"{MOBILE_DESTINATION}?message=success&token="
    )
    destination, params = _parse_location(callback_resp)
    assert destination == MOBILE_DESTINATION
    assert list(params.keys()) == ["message", "token", "is_user_new"]
    assert params["is_user_new"] == "1"

    user_token_session = parse_jwt_for_user(params["token"], db_session)
    assert user_token_session.is_valid is True


def test_ios_login_persists_client_on_state(client, db_session, mobile_destination):
    resp = client.get("/v1/users/login?client=ios")

    assert resp.status_code == 302
    state_id = urllib.parse.parse_qs(urllib.parse.urlparse(resp.headers["Location"]).query)[
        "state"
    ][0]
    state = _get_state(db_session, state_id)
    assert state is not None
    assert state.login_client == LoginClient.IOS


def test_ios_login_flow_piv_required_302(client, mobile_destination):
    login_resp, callback_resp = _run_login_flow(client, "?client=ios&piv_required=true")

    login_params = urllib.parse.parse_qs(
        urllib.parse.urlparse(login_resp.headers["Location"]).query
    )
    assert (
        login_params["acr_values"][0]
        == login_gov_jwt_auth.get_config().acr_value + " " + LOGIN_GOV_PIV_REQUIRED
    )

    destination, params = _parse_location(callback_resp)
    assert destination == MOBILE_DESTINATION
    assert params["message"] == "success"


def test_ios_error_in_token_after_state_resolved_302(
    client, db_session, enable_factory_create, mobile_destination
):
    login_gov_state = LoginGovStateFactory.create(login_client=LoginClient.IOS)

    resp = client.get(
        f"/v1/users/login/callback?state={login_gov_state.login_gov_state_id}&code=xyz456"
    )

    assert resp.status_code == 302
    destination, params = _parse_location(resp)
    assert destination == MOBILE_DESTINATION
    assert params == {"message": "error", "error_description": "internal error"}
    assert _get_state(db_session, login_gov_state.login_gov_state_id) is None


def test_ios_piv_required_error_after_state_resolved_302(
    client,
    enable_factory_create,
    mock_oauth_client,
    private_rsa_key,
    monkeypatch,
    mobile_destination,
):
    monkeypatch.setattr(login_gov_jwt_auth.get_config(), "is_piv_required", True)

    login_gov_state = LoginGovStateFactory.create(login_client=LoginClient.IOS)
    login_gov_id = str(uuid.uuid4())
    external_user = LinkExternalUserFactory.create(external_user_id=login_gov_id)
    AgencyUserFactory.create(user=external_user.user, agency=AgencyFactory.create())
    code = _add_token_response(
        mock_oauth_client,
        private_rsa_key,
        str(login_gov_state.nonce),
        login_gov_id,
        x509_presented=False,
    )

    resp = client.get(
        f"/v1/users/login/callback?state={login_gov_state.login_gov_state_id}&code={code}"
    )

    assert resp.status_code == 302
    destination, params = _parse_location(resp)
    assert destination == MOBILE_DESTINATION
    assert params == {
        "message": "error",
        "error_description": "Agency users must authenticate using a PIV/CAC card",
        "login_piv_required_error": "true",
    }


def test_ios_access_denied_from_login_gov_302(
    client, db_session, enable_factory_create, mobile_destination
):
    """A user cancelling at login.gov is sent back to the app, not the website"""
    login_gov_state = LoginGovStateFactory.create(login_client=LoginClient.IOS)

    resp = client.get(
        f"/v1/users/login/callback?state={login_gov_state.login_gov_state_id}"
        "&error=access_denied&error_description=cancelled"
    )

    assert resp.status_code == 302
    destination, params = _parse_location(resp)
    assert destination == MOBILE_DESTINATION
    assert params == {"message": "error", "error_description": "User declined to login"}


def test_unknown_state_goes_to_web_destination(client, mobile_destination):
    """Before the state is resolved we can't know the client, so errors go to the web destination"""
    resp = client.get(f"/v1/users/login/callback?state={uuid.uuid4()}&code=abc123")

    assert resp.status_code == 302
    destination, params = _parse_location(resp)
    assert destination == f"http://localhost:8080{WEB_RESULT_PATH}"
    assert params == {"message": "error", "error_description": "OAuth state not found"}


def test_ios_login_without_mobile_destination_400(client, db_session, no_mobile_destination):
    state_count = db_session.query(LoginGovState).count()

    resp = client.get("/v1/users/login?client=ios")

    assert resp.status_code == 400
    assert "Location" not in resp.headers
    assert resp.get_json()["message"] == "Mobile login is not configured"
    assert db_session.query(LoginGovState).count() == state_count


def test_ios_callback_without_mobile_destination_400(
    client, enable_factory_create, no_mobile_destination
):
    """If the config is removed mid-flow, never fall back to the web destination"""
    login_gov_state = LoginGovStateFactory.create(login_client=LoginClient.IOS)

    resp = client.get(
        f"/v1/users/login/callback?state={login_gov_state.login_gov_state_id}&code=xyz456"
    )

    assert resp.status_code == 400
    assert "Location" not in resp.headers


@pytest.mark.parametrize("login_query", ["?client=android", "?client=https://evil.example"])
def test_unknown_client_422(client, login_query):
    resp = client.get(f"/v1/users/login{login_query}")

    assert resp.status_code == 422
    assert "Location" not in resp.headers
    assert resp.get_json()["data"]["query"]["client"][0]["key"] == "invalid_choice"


def test_login_ignores_redirect_url_in_request(client, mobile_destination):
    """Destinations only come from config, never from the request"""
    _, callback_resp = _run_login_flow(
        client, "?client=ios&redirect_uri=https://evil.example&final_destination=x"
    )

    destination, _ = _parse_location(callback_resp)
    assert destination == MOBILE_DESTINATION


##########################################
# get_final_redirect_uri
##########################################


def test_get_final_redirect_uri_by_client(login_gov_config):
    login_gov_config.login_mobile_final_destination = MOBILE_DESTINATION

    assert (
        get_final_redirect_uri("success", token="abc", config=login_gov_config)
        == "http://localhost:3000/final?message=success&token=abc"
    )
    assert (
        get_final_redirect_uri(
            "success", token="abc", config=login_gov_config, login_client=LoginClient.WEB
        )
        == "http://localhost:3000/final?message=success&token=abc"
    )
    assert (
        get_final_redirect_uri(
            "success",
            token="abc",
            is_user_new=False,
            config=login_gov_config,
            login_client=LoginClient.IOS,
        )
        == "simplergrants://auth/callback?message=success&token=abc&is_user_new=0"
    )


def test_get_final_redirect_uri_ios_not_configured(login_gov_config):
    login_gov_config.login_mobile_final_destination = None

    with pytest.raises(MobileLoginNotConfiguredError):
        get_final_redirect_uri("success", config=login_gov_config, login_client=LoginClient.IOS)


##########################################
# Migration
##########################################


def test_login_client_migration_sql(caplog, capsys):
    caplog.set_level(logging.INFO)
    command.upgrade(alembic_cfg, "0c0638b3010e:8d2f4c6a1b3e", sql=True)

    assert "ALTER TABLE api.login_gov_state ADD COLUMN login_client TEXT" in capsys.readouterr().out
