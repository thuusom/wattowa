#!/bin/sh
curl -X POST http://localhost:8000/bulk_ingest -H Content-Type: application/json --data-binary @data/epg.json
