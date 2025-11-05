# Wattowa - TV Guide Recommender API

A semantic search service for TV guide content that uses vector embeddings to find related shows and programs based on similarity in titles and descriptions.

## Purpose

This service provides a recommendation API that finds semantically similar TV content using vector search. It processes TV guide data (titles, descriptions, genres, cast) and uses machine learning embeddings to enable similarity-based recommendations, allowing users to discover related content based on semantic meaning rather than just keyword matching.

## Architecture

The system consists of two main components orchestrated via Docker Compose:

- **Qdrant Vector Database**: Stores embeddings and metadata for TV guide content, enabling fast similarity search
- **FastAPI Service**: Provides REST API endpoints for:
  - Finding related content by content ID
  - Ingesting new content (single items or bulk)
  - Health checks

The API uses sentence transformers to generate embeddings from TV content. The default model (`paraphrase-multilingual-mpnet-base-v2`) supports multilingual content, making it suitable for international TV guides.

## Prerequisites

- Docker and Docker Compose
- `curl` and `jq` (for testing and data ingestion)

## Getting Started

### 1. Configuration

**First, copy the example environment file to create your `.env` file:**

```bash
cp env.example .env
```

This is required before starting the services. Run `./check_env.sh` to verify your system meets all requirements and that `.env` exists.

Edit `.env` to customize:
- `QDRANT_PORT`: Port for Qdrant (default: 6333)
- `API_PORT`: Port for the API service (default: 8000)
- `MODEL_NAME`: Sentence transformer model (default supports multilingual)
- `COLLECTION_NAME`: Qdrant collection name (default: tvguide)
- `SIMILARITY`: Similarity metric - `cosine` or `dot` (default: cosine)

### 2. Verify Environment

Verify your system meets all requirements and that `.env` is configured:

```bash
./check_env.sh
```

### 3. Start the Services

Build and start all services:

```bash
./build_up.sh
```

This will:
- Start Qdrant vector database
- Build and start the FastAPI service
- Automatically create the Qdrant collection on first startup
- Download the embedding model (first run may take time)

### 4. Ingest Data

Once the services are running, ingest your TV guide data:

```bash
./ingest.sh
```

This sends data from `data/epg.json` to the `/bulk_ingest` endpoint. The data should be in the following format:

```json
[
  {
    "guid": "tt0944947_s1e1",
    "title": "Winter Is Coming",
    "description": "Eddard Stark is summoned to King's Landing...",
    "startTime": 1303027200,
    "channelId": 1
  }
]
```

### 5. Query the API

Find related content:

```bash
curl "http://localhost:8000/related/tt0944947_s1e1?k=10"
```

Optional parameters:
- `k`: Number of results to return (default: 10)
- `same_channel`: Filter to same channel (default: false)

Example response:
```json
[
  {
    "content_id": "tt0944947_s1e2",
    "score": 0.92,
    "title": "The Kingsroad",
    "start_time": "2011-04-24T01:00:00Z",
    "channel": "HBO"
  }
]
```

## Operations

### Stop Services

Stop all running containers:

```bash
./down.sh
```

This stops the containers but preserves data volumes.

### Clean Data

Delete the Qdrant collection (removes all ingested data):

```bash
./clean.sh
```

**Note**: This only deletes the collection data. To remove all volumes (including Qdrant storage), first stop services with `./down.sh`, then manually run `docker compose down -v`.

### Investigate & Debug

**View service status:**
```bash
./ps.sh
```

**View logs:**
```bash
./logs.sh
```

This shows logs from all services. To view logs for a specific service only, use `docker compose logs -f api` or `docker compose logs -f qdrant`.

**Check API health:**
```bash
curl http://localhost:8000/health
```

**Inspect Qdrant directly:**
```bash
curl http://localhost:6333/collections
```

## API Endpoints

### `GET /health`
Health check endpoint.

**Response:**
```json
{"status": "ok"}
```

### `GET /related/{content_id}`
Find related content by content ID.

**Parameters:**
- `content_id` (path): The GUID/content ID to find related items for
- `k` (query, default: 10): Number of results to return
- `same_channel` (query, optional): Filter results to same channel

**Example:**

```bash
curl -X 'GET' 'http://localhost:8000/related/eeec34be-0a92-46f1-a63f-c7424d11ed81?k=10'
```

### `POST /upsert`
Add or update a single content item.

**Request Body:**
```json
[
  {
    "content_id": "4bce0ab1-1f95-4e7e-8cc1-54b6a254922f",
    "score": 0.93430996,
    "title": "SvampBob Fyrkant",
    "start_time": "2025-11-05T22:15:00+00:00",
    "channel": "32618"
  },
  {
    "content_id": "b4ba0d14-2f86-463e-85cd-0bd1cee0fa30",
    "score": 0.92883784,
    "title": "SvampBob Fyrkant",
    "start_time": "2025-11-05T13:15:00+00:00",
    "channel": "32618"
  },
  {
    "content_id": "b41fdf0f-68a7-4939-ace3-840555c71dcf",
    "score": 0.92879844,
    "title": "SvampBob Fyrkant",
    "start_time": "2025-11-04T01:40:00+00:00",
    "channel": "32618"
  },
  {
    "content_id": "4bfb32db-bbc5-4303-ac02-b506b9ea9c31",
    "score": 0.9249022,
    "title": "SvampBob Fyrkant",
    "start_time": "2025-11-05T08:00:00+00:00",
    "channel": "32618"
  },
  {
    "content_id": "9599fccf-8c40-4db0-85af-3347c56217ee",
    "score": 0.9104362,
    "title": "SvampBob Fyrkant",
    "start_time": "2025-11-06T13:35:00+00:00",
    "channel": "32618"
  },
  {
    "content_id": "a5cf932f-478a-4dba-b300-ba93f385b38d",
    "score": 0.90917873,
    "title": "SvampBob Fyrkant",
    "start_time": "2025-11-05T20:10:00+00:00",
    "channel": "32618"
  },
  {
    "content_id": "77d025e2-0c1d-4e2c-a7d5-eb716d6766c9",
    "score": 0.90917873,
    "title": "SvampBob Fyrkant",
    "start_time": "2025-11-05T04:20:00+00:00",
    "channel": "32618"
  },
  {
    "content_id": "6b8e5977-d2d2-413b-97da-d4aa340d3ea9",
    "score": 0.90772015,
    "title": "SvampBob Fyrkant",
    "start_time": "2025-11-06T08:25:00+00:00",
    "channel": "32618"
  },
  {
    "content_id": "62d9d12b-19f4-4950-9e56-447511b28f57",
    "score": 0.8950625,
    "title": "SvampBob Fyrkant",
    "start_time": "2025-11-04T08:25:00+00:00",
    "channel": "32618"
  },
  {
    "content_id": "615e73fa-1f32-4d04-af8a-da3c0ebb7da6",
    "score": 0.8950266,
    "title": "SvampBob Fyrkant",
    "start_time": "2025-11-05T16:15:00+00:00",
    "channel": "32618"
  }
]
```

### `POST /bulk_ingest`

Bulk ingest multiple content items (batched for efficiency).

**Request Body:** Array of items (see data format above)

**Example:**

```bash
curl -X POST http://localhost:8000/bulk_ingest \
  -H "Content-Type: application/json" \
  --data-binary @data/epg.json
```

For initial test data use:

```bash
./ingest.sh
```


## Data Format

EPG data should be provided as a JSON array. Each item requires:
- `guid`: Unique identifier (used as content_id)
- `title`: Content title (required)
- `description`: Optional description
- `startTime`: Unix timestamp (optional)
- `channelId`: Channel identifier (optional)

The service generates embeddings from the combined title and description text.
