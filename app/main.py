# ─────────────────────────────────────────────────────────────────────────────
# app/main.py (FastAPI service)
# ─────────────────────────────────────────────────────────────────────────────

import asyncio
import os
from typing import List, Optional

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from qdrant_client import QdrantClient
from qdrant_client.http.models import Distance, VectorParams, Filter, FieldCondition, MatchValue
from sentence_transformers import SentenceTransformer

COLLECTION_NAME = os.getenv("COLLECTION_NAME", "tvguide")
QDRANT_HOST = os.getenv("QDRANT_HOST", "localhost")
QDRANT_PORT = int(os.getenv("QDRANT_PORT", "6333"))
MODEL_NAME = os.getenv("MODEL_NAME", "sentence-transformers/paraphrase-multilingual-mpnet-base-v2")
SIMILARITY = os.getenv("SIMILARITY", "cosine").lower()

app = FastAPI(title="TV Guide Recommender API")

# Lazily initialized singletons
_model: Optional[SentenceTransformer] = None
_client: Optional[QdrantClient] = None


def get_model() -> SentenceTransformer:
    global _model
    if _model is None:
        _model = SentenceTransformer(MODEL_NAME)
    return _model


def get_client() -> QdrantClient:
    global _client
    if _client is None:
        _client = QdrantClient(
            host=QDRANT_HOST,
            port=QDRANT_PORT,
            timeout=30.0,            # request timeout
            prefer_grpc=False        # leave HTTP unless you want gRPC
        )
    return _client


def ensure_collection():
    client = get_client()
    model = get_model()
    dim = model.get_sentence_embedding_dimension()
    distance = Distance.COSINE if SIMILARITY == "cosine" else Distance.DOT
    existing = [c.name for c in client.get_collections().collections]
    if COLLECTION_NAME not in existing:
        client.create_collection(
            collection_name=COLLECTION_NAME,
            vectors_config=VectorParams(size=dim, distance=distance),
        )


@app.on_event("startup")
async def _startup():
    print(f"[startup] Loading model: {MODEL_NAME}")
    ensure_collection()
    print(f"[startup] Model loaded. dim={get_model().get_sentence_embedding_dimension()}")

class RelatedResponse(BaseModel):
    content_id: str
    score: float
    title: Optional[str] = None
    start_time: Optional[str] = None
    channel: Optional[str] = None


@app.get("/health")
async def health():
    return JSONResponse({"status": "ok"})


@app.get("/related/{content_id}", response_model=List[RelatedResponse])
async def related(content_id: str, k: int = 10, same_channel: Optional[bool] = None):
    client = get_client()

    # 1) fetch the anchor vector
    points = client.retrieve(
        collection_name=COLLECTION_NAME,
        ids=[content_id],
        with_vectors=True,
        with_payload=True,
    )
    if not points or points[0].vector is None:
        raise HTTPException(status_code=404, detail="content_id not found or has no vector")

    anchor_vec = points[0].vector

    # 2) optional filter
    q_filter = None
    if same_channel is True and points[0].payload and "channel" in points[0].payload:
        q_filter = Filter( 
            must=[FieldCondition(key="channel", match=MatchValue(value=points[0].payload["channel"]))]
        )

    # 3) search
    search_res = client.search(
        collection_name=COLLECTION_NAME,
        query_vector=anchor_vec,
        limit=max(k + 1, 2),
        with_payload=True,
        score_threshold=None,
        query_filter=q_filter,
    )

    out = []
    for p in search_res:
        pid = str(p.id)
        if pid == content_id:
            continue
        payload = p.payload or {}
        channel_val = payload.get("channel")
        # Convert channel to string if it's stored as an integer (for backward compatibility)
        if channel_val is not None and not isinstance(channel_val, str):
            channel_val = str(channel_val)
        out.append(
            RelatedResponse(
                content_id=pid,
                score=float(p.score),
                title=payload.get("title"),
                start_time=payload.get("start_time"),
                channel=channel_val,
            )
        )
        if len(out) >= k:
            break
    return out


class UpsertItem(BaseModel):
    content_id: str
    title: str
    description: Optional[str] = None
    genres: Optional[List[str]] = None
    cast: Optional[List[str]] = None
    channel: Optional[str] = None
    start_time: Optional[str] = None


@app.post("/upsert")
async def upsert(item: UpsertItem):
    client = get_client()
    model = get_model()
    text = build_signature(item.title, item.description, None, None)
    
    # Run encoding in a thread pool to avoid blocking the event loop
    vec = await asyncio.to_thread(model.encode, text)
    vec = vec.tolist()

    # Run Qdrant upsert in a thread pool as well
    await asyncio.to_thread(
        client.upsert,
        collection_name=COLLECTION_NAME,
        points=[
            {
                "id": item.content_id,
                "vector": vec,
                "payload": {
                    "title": item.title,
                    "description": item.description,
                    "channel": item.channel,
                    "start_time": item.start_time,
                },
            }
        ],
        wait=False
    )
    return JSONResponse({"status": "ok"})


class BulkIngestItem(BaseModel):
    guid: str
    title: str
    description: Optional[str] = None
    startTime: Optional[int] = None
    channelId: Optional[int] = None

BATCH_SIZE = 500

@app.post("/bulk_ingest")
async def bulk_ingest(items: List[BulkIngestItem]):
    from datetime import datetime, timezone
    client = get_client()
    model = get_model()

    print(f"[bulk_ingest] received {len(items)} items")

    total = len(items)
    index = 0

    def encode_batch(batch_items):
        """Encode a batch of items in a separate thread to avoid blocking the event loop."""
        points = []
        for it in batch_items:
            cid = it.guid
            text = build_signature(it.title, it.description, None, None)
            vec = model.encode(text).tolist()

            iso_time = None
            if it.startTime:
                iso_time = datetime.fromtimestamp(it.startTime, tz=timezone.utc).isoformat()

            points.append({
                "id": cid,
                "vector": vec,
                "payload": {
                    "title": it.title,
                    "description": it.description,
                    "channel": str(it.channelId) if it.channelId is not None else None,
                    "start_time": iso_time,
                }
            })
        return points

    while index < total:
        batch = items[index:index+BATCH_SIZE]
        print(f"[bulk_ingest] batching {index}-{index+len(batch)-1}")

        # Run encoding in a thread pool to avoid blocking the event loop
        points = await asyncio.to_thread(encode_batch, batch)

        print(f"[bulk_ingest] upserting batch of {len(points)}")
        # Run Qdrant upsert in a thread pool as well
        await asyncio.to_thread(client.upsert, collection_name=COLLECTION_NAME, points=points)
        index += len(batch)
        
        # Yield control to allow other requests to be processed
        await asyncio.sleep(0)

    print("[bulk_ingest] DONE")
    return JSONResponse({"status": "ok", "count": total})

def build_signature(title: str, description, genres, cast):
    parts = [title or ""]
    if description:
        parts.append(description)
    return " \n".join(parts)
