"""One error shape for the whole API: {"error": code, "message": sentence, ...}."""
import logging

from django.http import Http404
from rest_framework import exceptions, status
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_exception_handler

log = logging.getLogger(__name__)


class APIError(Exception):
    """Raise anywhere under a view to produce a handled, app-readable error."""

    def __init__(self, code: str, message: str, http_status: int = 400, **extra):
        super().__init__(message)
        self.code = code
        self.message = message
        self.http_status = http_status
        self.extra = extra

    def response(self) -> Response:
        return Response({"error": self.code, "message": self.message, **self.extra}, status=self.http_status)


def exception_handler(exc, context):
    if isinstance(exc, APIError):
        return exc.response()
    if isinstance(exc, Http404):
        return Response({"error": "not_found", "message": "That item doesn't exist."}, status=404)

    response = drf_exception_handler(exc, context)
    if response is None:
        log.exception("Unhandled error in %s", context.get("view"))
        return Response(
            {"error": "server_error", "message": "Something went wrong on our side. Please try again."},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )

    if isinstance(exc, exceptions.ValidationError):
        response.data = {
            "error": "validation_error",
            "message": "Some of the details need fixing.",
            "fields": response.data,
        }
    elif isinstance(exc, (exceptions.NotAuthenticated, exceptions.AuthenticationFailed)):
        response.status_code = 401
        response.data = {"error": "not_authenticated", "message": "Please reopen the app and try again."}
    elif isinstance(exc, exceptions.Throttled):
        response.data = {"error": "throttled", "message": "Too many requests. Please wait a moment."}
    elif isinstance(exc, exceptions.NotFound):
        response.data = {"error": "not_found", "message": "That item doesn't exist."}
    elif isinstance(exc, exceptions.ParseError):
        response.data = {"error": "validation_error", "message": "The request body wasn't valid JSON."}
    else:
        detail = response.data.get("detail") if isinstance(response.data, dict) else None
        response.data = {"error": "request_error", "message": str(detail or "The request couldn't be processed.")}
    return response
