import functools
import logging
from collections.abc import Callable
from typing import Any, ParamSpec

import flask
from apiflask.exceptions import HTTPError

from src.adapters.oauth.login_gov.login_gov_jwt import (
    LoginClient,
    MobileLoginNotConfiguredError,
    get_final_logout_redirect_uri,
    get_final_redirect_uri,
)
from src.api import response
from src.api.route_utils import raise_flask_error

logger = logging.getLogger(__name__)

P = ParamSpec("P")
INTERNAL_ERROR = "internal error"


def get_app_security_scheme() -> dict[str, Any]:
    return {
        "ApiJwtAuth": {"type": "apiKey", "in": "header", "name": "X-SGG-Token"},
        "InternalApiJwtAuth": {"type": "apiKey", "in": "header", "name": "X-SGG-Internal-Token"},
        "ApiUserKeyAuth": {"type": "apiKey", "in": "header", "name": "X-API-Key"},
    }


def set_request_login_client(login_client: LoginClient | None) -> None:
    """Remember which client started the login flow for the rest of this request"""
    if flask.has_app_context():
        flask.g.login_client = login_client


def get_request_login_client() -> LoginClient | None:
    if not flask.has_app_context():
        return None
    return flask.g.get("login_client", None)


def _login_error_redirect(
    message: str | None, login_piv_required_error: str | None = None
) -> flask.Response:
    try:
        redirect_uri = get_final_redirect_uri(
            "error",
            error_description=message,
            login_piv_required_error=login_piv_required_error,
            login_client=get_request_login_client(),
        )
    except MobileLoginNotConfiguredError:
        # Never fall back to the web destination for a mobile client
        logger.warning("Login flow failed for a mobile client without a mobile destination")
        raise_flask_error(400, "Mobile login is not configured")

    return response.redirect_response(redirect_uri)


def with_login_redirect_error_handler() -> Callable[..., Callable[P, flask.Response]]:
    """Wrapper function to handle catching errors and redirecting

    Because several of our login functions don't have standard 2xx returns
    and instead redirect the user, we also redirect in the case of errors
    so that they stay on the frontend, but we pass errors along.

    The error redirect goes to the destination of the client that started the flow
    (see set_request_login_client). Errors raised before that client is known, such as
    an unknown or invalid state on the callback, go to the web destination.
    If the client is a mobile client without a configured destination, a 400 is
    returned instead of a redirect.

    Usage::

        @with_login_redirect_error_handler()
        def foo(...):
            logger.info("hello")

            if condition:
                raise_flask_error(...) # this will get caught and a redirect will occur

            return ...

    """

    def decorator(f: Callable[P, flask.Response]) -> Callable[P, flask.Response]:
        @functools.wraps(f)
        def wrapper(*args: P.args, **kwargs: P.kwargs) -> flask.Response:
            try:
                return f(*args, **kwargs)
            except MobileLoginNotConfiguredError:
                logger.warning("Login flow started by a mobile client without a mobile destination")
                raise_flask_error(400, "Mobile login is not configured")
            except HTTPError as e:
                # HTTPError is what raise_flask_error raises
                # and should encompass our "expected" errors
                # that aren't a concern, as long as it isn't a 5xx
                message = e.message
                logger.info("Login flow failed: %s", message)

                # But we still don't expect 5xx errors
                if e.status_code >= 500:
                    message = INTERNAL_ERROR
                    logger.exception(
                        "Unexpected error occurred in login flow via raise_flask_error",
                        extra={"error.message": e.message},
                    )

                return _login_error_redirect(
                    message,
                    login_piv_required_error=e.extra_data.get("login_piv_required_error", None),
                )
            except Exception:
                # Any other exception, we'll just use a generic error message to be safe
                # but this means an unexpected error occurred and we should log an error
                logger.exception("Unexpected error occurred in login flow")
                return _login_error_redirect(INTERNAL_ERROR)

        return wrapper

    return decorator


def with_logout_redirect_error_handler() -> Callable[..., Callable[P, flask.Response]]:
    """Wrapper function to handle catching errors and redirecting for our logout redirect endpoints

    Because our logout functions don't have standard 2xx returns
    and instead redirect the user, we also redirect in the case of errors
    so that they stay on the frontend, but we pass errors along.

    Usage::

        @with_logout_redirect_error_handler()
        def foo(...):
            logger.info("hello")

            if condition:
                raise_flask_error(...) # this will get caught and a redirect will occur

            return ...

    """

    def decorator(f: Callable[P, flask.Response]) -> Callable[P, flask.Response]:
        @functools.wraps(f)
        def wrapper(*args: P.args, **kwargs: P.kwargs) -> flask.Response:
            try:
                return f(*args, **kwargs)
            except HTTPError as e:
                # HTTPError is what raise_flask_error raises
                # and should encompass our "expected" errors
                # that aren't a concern, as long as it isn't a 5xx
                message = e.message
                logger.info("Logout flow failed: %s", message)

                # But we still don't expect 5xx errors
                if e.status_code >= 500:
                    message = INTERNAL_ERROR
                    logger.exception(
                        "Unexpected error occurred in logout flow via raise_flask_error",
                        extra={"error.message": e.message},
                    )

                return response.redirect_response(
                    get_final_logout_redirect_uri(
                        "error",
                        error_description=message,
                    )
                )
            except Exception:
                # Any other exception, we'll just use a generic error message to be safe
                # but this means an unexpected error occurred and we should log an error
                logger.exception("Unexpected error occurred in logout flow")
                return response.redirect_response(
                    get_final_logout_redirect_uri("error", error_description=INTERNAL_ERROR)
                )

        return wrapper

    return decorator
