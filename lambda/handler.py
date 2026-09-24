import base64
import json
import os
import random
import time
from pathlib import Path

import psycopg2
import redis

DB_HOST = os.environ["DB_HOST"]
DB_PORT = int(os.environ.get("DB_PORT", 5432))
DB_NAME = os.environ["DB_NAME"]
DB_USER = os.environ["DB_USER"]
DB_PASSWORD = os.environ["DB_PASSWORD"]

REDIS_HOST = os.environ.get("REDIS_HOST")
REDIS_PORT = int(os.environ.get("REDIS_PORT", 6379))
CACHE_TTL_SECONDS = int(os.environ.get("CACHE_TTL_SECONDS", 60))

SEED_SQL_PATH = Path(__file__).parent / "seed.sql"
MAX_ITEM_ID = 200

# Reused across warm invocations of the same container - avoids reconnecting
# to Postgres/Redis (and re-seeding) on every request.
_db_conn = None
_redis_client = None
_seeded = False


def _get_db():
    global _db_conn
    if _db_conn is None or _db_conn.closed:
        _db_conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            connect_timeout=5,
        )
        _db_conn.autocommit = True
    return _db_conn


def _get_redis():
    global _redis_client
    if _redis_client is None:
        _redis_client = redis.Redis(
            host=REDIS_HOST,
            port=REDIS_PORT,
            socket_timeout=2,
            socket_connect_timeout=2,
            decode_responses=True,
        )
    return _redis_client


def _ensure_seeded():
    """Runs sql/seed.sql (bundled alongside this file) against RDS.

    Idempotent: the table uses CREATE TABLE IF NOT EXISTS and inserts use
    ON CONFLICT (id) DO NOTHING, so re-running it is always safe.
    """
    global _seeded
    if _seeded:
        return
    conn = _get_db()
    with conn.cursor() as cur:
        cur.execute(
            "SELECT EXISTS (SELECT FROM information_schema.tables "
            "WHERE table_name = 'items')"
        )
        (table_exists,) = cur.fetchone()
        if table_exists:
            cur.execute("SELECT COUNT(*) FROM items")
            (count,) = cur.fetchone()
            if count > 0:
                _seeded = True
                return
        # psycopg2 sends a plain (no-params) execute() over the simple query
        # protocol, which lets Postgres run the whole semicolon-separated
        # script (CREATE TABLE + ~200 INSERTs) in one round trip.
        cur.execute(SEED_SQL_PATH.read_text())
    _seeded = True


def _query_item(item_id):
    conn = _get_db()
    with conn.cursor() as cur:
        cur.execute(
            "SELECT id, name, description, price FROM items WHERE id = %s",
            (item_id,),
        )
        row = cur.fetchone()
    if row is None:
        return None
    return {"id": row[0], "name": row[1], "description": row[2], "price": float(row[3])}


def _parse_item_id(event):
    body = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        try:
            body = base64.b64decode(body).decode()
        except Exception:
            body = "{}"
    try:
        data = json.loads(body)
    except (TypeError, ValueError):
        data = {}
    try:
        return int(data.get("id", random.randint(1, MAX_ITEM_ID)))
    except (TypeError, ValueError):
        return random.randint(1, MAX_ITEM_ID)


def _response(status_code, payload):
    return {
        "statusCode": status_code,
        "statusDescription": f"{status_code} {'OK' if status_code == 200 else 'ERROR'}",
        "isBase64Encoded": False,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(payload),
    }


def _handle_cached(event):
    """Cache-aside (lazy loading): check Redis first, fall back to Postgres
    on miss and populate the cache with a TTL."""
    start = time.perf_counter()
    item_id = _parse_item_id(event)
    r = _get_redis()
    cache_key = f"item:{item_id}"

    cached_value = r.get(cache_key)
    if cached_value is not None:
        elapsed_ms = (time.perf_counter() - start) * 1000
        return _response(
            200,
            {"source": "cache", "item": json.loads(cached_value), "latency_ms": round(elapsed_ms, 2)},
        )

    _ensure_seeded()
    item = _query_item(item_id)
    if item is None:
        return _response(404, {"error": f"item {item_id} not found"})

    r.setex(cache_key, CACHE_TTL_SECONDS, json.dumps(item))
    elapsed_ms = (time.perf_counter() - start) * 1000
    return _response(
        200,
        {"source": "database", "item": item, "latency_ms": round(elapsed_ms, 2)},
    )


def _handle_nocache(event):
    """Always reads straight from Postgres - no cache involved."""
    start = time.perf_counter()
    item_id = _parse_item_id(event)
    _ensure_seeded()
    item = _query_item(item_id)
    if item is None:
        return _response(404, {"error": f"item {item_id} not found"})
    elapsed_ms = (time.perf_counter() - start) * 1000
    return _response(
        200,
        {"source": "database", "item": item, "latency_ms": round(elapsed_ms, 2)},
    )


def _handle_seed(_event):
    """Invoked once by Terraform right after deploy so data exists immediately."""
    _ensure_seeded()
    conn = _get_db()
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM items")
        (count,) = cur.fetchone()
    return _response(200, {"status": "seeded", "item_count": count})


def handler(event, context):
    """Single Lambda entry point serving both demo endpoints - routes on the
    ALB request path so one function backs /cached and /nocache."""
    path = (event.get("path") or "").rstrip("/")

    try:
        if path.endswith("/cached"):
            return _handle_cached(event)
        if path.endswith("/nocache"):
            return _handle_nocache(event)
        if path.endswith("/seed"):
            return _handle_seed(event)
        # ALB health checks (and anything unrecognized) get a cheap 200
        # without touching Postgres/Redis, so target health doesn't depend
        # on the database being warmed up yet.
        return _response(200, {"status": "healthy"})
    except Exception as exc:  # surfaced to the caller and CloudWatch Logs
        return _response(500, {"error": str(exc)})
