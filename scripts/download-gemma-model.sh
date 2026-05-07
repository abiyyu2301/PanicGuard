#!/bin/bash
# download-gemma-model.sh
# Downloads or converts a Gemma 4 2B model to .litertlm format for LiteRT-LM.
#
# Option A (recommended): Download a pre-converted .litertlm model from HuggingFace.
# Option B: Convert an existing GGUF using Bazel (requires Bazel 7+).
#
# Usage:
#   Option A (pre-converted):  ./scripts/download-gemma-model.sh
#   Option B (from GGUF):       ./scripts/download-gemma-model.sh --convert /path/to/model.gguf
#
# Recommended quant: gemma-4-E2B-it-Q4_K_M.gguf (3.11 GB)
#   From: https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF

set -euo pipefail

DEST_DIR="Detection/Gemma"

# --------------------------------------------------
# Option A: Download pre-converted model (fastest)
# --------------------------------------------------
download_preconverted() {
    mkdir -p "$DEST_DIR"

    # Check for huggingface-cli
    if command -v huggingface-cli &>/dev/null; then
        echo "Downloading Gemma 4 2B .litertlm model from HuggingFace..."
        huggingface-cli download google/gemma-4-2b-it --local-dir "$DEST_DIR" --include "*.litertlm"
    else
        echo "huggingface-cli not found."
        echo "Please install it: pip install huggingface-hub"
        echo ""
        echo "Or manually download the model from:"
        echo "  https://huggingface.co/liteRT/gemma-4-E2B-it"
        echo ""
        echo "Place the .litertlm file in: Detection/Gemma/"
        return 1
    fi

    echo ""
    echo "=== Download complete ==="
    ls -lh "$DEST_DIR/"*.litertlm 2>/dev/null || true
}

# --------------------------------------------------
# Option B: Convert GGUF → LiteRT format
# --------------------------------------------------
convert_from_gguf() {
    GGUF_PATH="$1"

    if [ ! -f "$GGUF_PATH" ]; then
        echo "ERROR: GGUF file not found: $GGUF_PATH"
        exit 1
    fi

    if ! command -v bazel &>/dev/null; then
        echo "ERROR: Bazel is required for GGUF conversion."
        echo "Install: https://bazel.build/install"
        exit 1
    fi

    mkdir -p "$DEST_DIR"
    MODEL_NAME=$(basename "$GGUF_PATH" .gguf)
    OUTPUT_PATH="$DEST_DIR/${MODEL_NAME}.litertlm"

    echo "Converting $GGUF_PATH → $OUTPUT_PATH"
    bazel run //tools:litert_lm_builder -- \
        --input="$GGUF_PATH" \
        --output="$OUTPUT_PATH" \
        --backend=metal

    echo ""
    echo "=== Conversion complete ==="
    ls -lh "$OUTPUT_PATH"
}

# --------------------------------------------------
# Main
# --------------------------------------------------
case "${1:-}" in
    --convert)
        convert_from_gguf "${2:-}"
        ;;
    --help|-h)
        echo "Usage: ./scripts/download-gemma-model.sh [--convert <gguf_path>]"
        echo ""
        echo "Without flags: downloads pre-converted .litertlm model (requires huggingface-cli)"
        echo "--convert:     converts a GGUF file to .litertlm format (requires Bazel)"
        exit 0
        ;;
    "")
        download_preconverted
        ;;
    *)
        echo "Unknown option: $1"
        echo "Run ./scripts/download-gemma-model.sh --help for usage"
        exit 1
        ;;
esac
