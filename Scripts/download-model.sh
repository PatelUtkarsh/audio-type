#!/bin/bash
#
# Download whisper.cpp model
#

set -e

MODEL=${1:-base.en}
MODELS_DIR="$HOME/Library/Application Support/AudioType/models"

# Create models directory
mkdir -p "$MODELS_DIR"

WHISPER_MODELS_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
MODEL_FILE="ggml-${MODEL}.bin"
DESTINATION="$MODELS_DIR/$MODEL_FILE"

# Check if model already exists
if [ -f "$DESTINATION" ]; then
    echo "Model already exists: $DESTINATION"
    echo "Delete it first if you want to re-download."
    exit 0
fi

echo "Downloading $MODEL_FILE..."
echo "From: $WHISPER_MODELS_URL/$MODEL_FILE"
echo "To: $DESTINATION"
echo ""

# Download with progress
curl -L "${WHISPER_MODELS_URL}/${MODEL_FILE}" \
    -o "$DESTINATION" \
    --progress-bar

# Verify download
if [ -f "$DESTINATION" ]; then
    SIZE=$(du -h "$DESTINATION" | cut -f1)
    echo ""
    echo "Download complete!"
    echo "Model: $MODEL_FILE"
    echo "Size: $SIZE"
    echo "Location: $DESTINATION"
else
    echo "Error: Download failed"
    exit 1
fi
