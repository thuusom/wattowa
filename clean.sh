#!/bin/sh
@echo clean qdrant
curl -X DELETE "http://localhost:6333/collections/tvguide"
