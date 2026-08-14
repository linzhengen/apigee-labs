"""Pub/Sub triggered Cloud Run function that records Apigee usage logs in BigQuery.

Apigee の vertexai-proxy が ServiceCallout で Pub/Sub にパブリッシュした
メッセージ (Base64 エンコードされた JSON) を受け取り、BigQuery に書き込む。

環境変数:
    BQ_DATASET  BigQuery データセット ID (必須)
    BQ_TABLE    BigQuery テーブル ID (必須)
    BQ_PROJECT  BigQuery プロジェクト ID (省略時は実行プロジェクト)
"""

import base64
import binascii
import json
import logging
import os
from datetime import datetime, timezone
from typing import Any

import functions_framework
from google.cloud import bigquery

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

BQ_DATASET = os.environ["BQ_DATASET"]
BQ_TABLE = os.environ["BQ_TABLE"]

_client = bigquery.Client()
TABLE_ID = f"{os.environ.get('BQ_PROJECT', _client.project)}.{BQ_DATASET}.{BQ_TABLE}"


def _as_int(value: Any) -> int | None:
    """Coerce a value to int, returning None when it is not numeric."""
    if value is None or isinstance(value, bool):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _as_text(value: Any) -> str | None:
    """Return a BigQuery STRING value, JSON-encoding non-string payloads."""
    if value is None:
        return None
    if isinstance(value, str):
        return value
    return json.dumps(value, ensure_ascii=False)


def _to_row(payload: dict[str, Any], published_at: str | None) -> dict[str, Any]:
    usage = payload.get("usage_metadata") or {}
    request = payload.get("request") or {}
    response = payload.get("response") or {}

    return {
        "transaction_id": _as_text(payload.get("transaction_id")),
        "timestamp": _as_text(payload.get("timestamp")) or published_at,
        "user_id": _as_text(payload.get("user_id")),
        "model": _as_text(payload.get("model")),
        "action": _as_text(payload.get("action")),
        "region": _as_text(payload.get("region")),
        "api_proxy": _as_text(payload.get("api_proxy")),
        "api_proxy_revision": _as_text(payload.get("api_proxy_revision")),
        "environment": _as_text(payload.get("environment")),
        "status_code": _as_int(payload.get("status_code")),
        "latency_ms": _as_int(payload.get("latency_ms")),
        "prompt_token_count": _as_int(usage.get("prompt_token_count")),
        "candidates_token_count": _as_int(usage.get("candidates_token_count")),
        "total_token_count": _as_int(usage.get("total_token_count")),
        "request_payload": _as_text(request.get("prompt")),
        "response_payload": _as_text(response.get("generated_text")),
        "ingested_at": datetime.now(timezone.utc).isoformat(),
    }


@functions_framework.cloud_event
def handle_usage_log(cloud_event) -> None:
    """Decode one Pub/Sub message and stream it into BigQuery.

    パース不能なメッセージは ack して破棄する (再試行しても成功しないため)。
    BigQuery への書き込み失敗は例外を送出し、Pub/Sub の再配信に委ねる。
    """
    message = (cloud_event.data or {}).get("message") or {}
    message_id = message.get("messageId")
    data = message.get("data")

    if not data:
        logger.warning("Skipping message %s: no data field", message_id)
        return

    try:
        payload = json.loads(base64.b64decode(data).decode("utf-8"))
    except (binascii.Error, ValueError, UnicodeDecodeError):
        logger.exception("Skipping message %s: undecodable payload", message_id)
        return

    if not isinstance(payload, dict):
        logger.warning("Skipping message %s: payload is not a JSON object", message_id)
        return

    row = _to_row(payload, message.get("publishTime"))

    errors = _client.insert_rows_json(
        TABLE_ID,
        [row],
        # 同じ Pub/Sub メッセージが再配信されても行が重複しないようにする
        row_ids=[message_id] if message_id else None,
    )
    if errors:
        raise RuntimeError(f"BigQuery insert failed for message {message_id}: {errors}")

    logger.info(
        "Recorded usage log: transaction_id=%s user=%s model=%s total_tokens=%s",
        row["transaction_id"],
        row["user_id"],
        row["model"],
        row["total_token_count"],
    )
