#!/usr/bin/env python3
"""download_model.py -- download a single GGUF file from Hugging Face.

Unlike a full snapshot download, this pulls exactly one file from a repo,
which is what we need for a GGUF quantization (e.g. the Q2_K MiniMax-H3
artifact used by the dev-rtx4070 target).

Usage:
    python3 download_model.py REPO_ID FILENAME --local-dir PATH [--token TOKEN]

Examples:
    python3 download_model.py unsloth/MiniMax-H3-GGUF \\
        minimax_h3_fl2va_pruned-Q2_K.gguf \\
        --local-dir ~/models/minimax-h3-gguf

    HF_TOKEN=xxx python3 download_model.py unsloth/MiniMax-H3-GGUF \\
        minimax_h3_fl2va_pruned-Q2_K.gguf --local-dir ~/models/minimax-h3-gguf
"""

import sys
import os
import argparse
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description="Download a GGUF file from Hugging Face")
    parser.add_argument("repo_id", help="Hugging Face repo (e.g. unsloth/MiniMax-H3-GGUF)")
    parser.add_argument("filename", help="File to download from the repo (e.g. minimax_h3_fl2va_pruned-Q2_K.gguf)")
    parser.add_argument("--local-dir", required=True, help="Local directory to download to")
    parser.add_argument("--token", default=None, help="HF token (or set HF_TOKEN env var)")
    args = parser.parse_args()

    token = args.token or os.environ.get("HF_TOKEN")
    local_dir = Path(args.local_dir).expanduser()
    target_path = local_dir / args.filename

    # Check if already downloaded
    if target_path.exists():
        size_gb = target_path.stat().st_size / 1e9
        print(f"Model file already exists at {target_path} ({size_gb:.1f} GB)")
        return 0

    print(f"Downloading {args.repo_id}/{args.filename} to {local_dir} ...")
    print("(This may take a while depending on file size and bandwidth)")

    local_dir.mkdir(parents=True, exist_ok=True)

    from huggingface_hub import hf_hub_download

    try:
        downloaded_path = hf_hub_download(
            repo_id=args.repo_id,
            filename=args.filename,
            local_dir=str(local_dir),
            token=token,
        )
    except Exception as e:
        print(f"ERROR: Download failed: {e}", file=sys.stderr)
        return 1

    downloaded_path = Path(downloaded_path)
    if downloaded_path.exists():
        size_gb = downloaded_path.stat().st_size / 1e9
        print(f"Downloaded successfully: {downloaded_path} ({size_gb:.1f} GB)")
        return 0
    else:
        print("ERROR: Download completed but file not found on disk.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
