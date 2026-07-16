import base64
import json
import logging
import re

LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)
SAFE_TEXT = re.compile(r"^[A-Za-z0-9._:-]{1,128}$")
EVENT_KINDS = {"browser_error", "api_error", "web_vital"}


def response(status):
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json", "cache-control": "no-store"},
        "body": "{}",
    }


def handler(request, _context):
    try:
        encoded = request.get("body") or ""
        if request.get("isBase64Encoded"):
            encoded = base64.b64decode(encoded).decode("utf-8")
        if len(encoded.encode("utf-8")) > 4096:
            return response(413)
        envelope = json.loads(encoded)
        event = envelope.get("event") or {}
        if envelope.get("schemaVersion") != 1 or event.get("kind") not in EVENT_KINDS:
            return response(400)
        required = ("eventId", "occurredAt", "environment", "release")
        if any(not SAFE_TEXT.fullmatch(str(envelope.get(field, ""))) for field in required):
            return response(400)
        safe_event = {"kind": event["kind"]}
        for field in ("errorType", "method", "code", "correlationId", "metric"):
            value = event.get(field)
            if value is not None and SAFE_TEXT.fullmatch(str(value)):
                safe_event[field] = value
        for field in ("status", "value"):
            value = event.get(field)
            if isinstance(value, (int, float)):
                safe_event[field] = value
        LOGGER.info(json.dumps({
            "message": "ui browser telemetry",
            "schemaVersion": 1,
            "eventId": envelope["eventId"],
            "occurredAt": envelope["occurredAt"],
            "environment": envelope["environment"],
            "release": envelope["release"],
            "event": safe_event,
        }, separators=(",", ":")))
        return response(202)
    except (ValueError, TypeError, UnicodeDecodeError):
        return response(400)
