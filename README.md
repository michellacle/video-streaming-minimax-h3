# video-streaming-minimax-h3

Single-source configuration and service tooling for video streaming based on
[MiniMax-H3](https://huggingface.co/MiniMaxAI/MiniMax-H3), served via
[llama.cpp](https://github.com/ggml-org/llama.cpp) with an OpenAI-compatible
API. Same philosophy as
[`4x_RTX3090_qwen3.8-27b`](https://github.com/michellacle/4x_RTX3090_qwen3.8-27b):
one repo, one model, config-first, no unnecessary abstraction.

This repo is organized around **deployment targets** — each target is a
self-contained, single source of configuration for one piece of hardware.
Only one target is implemented today.

| Target | Hardware | Status |
|--------|----------|--------|
| [`dev-rtx4070`](targets/dev-rtx4070/) | 1x NVIDIA RTX 4070 (8 GB VRAM) | **Implemented** — dev/test |
| [`prod-multi-gpu`](targets/prod-multi-gpu/) | Multi-GPU production machine | Full-BF16 capacity preflight available |

## `dev-rtx4070` target (implemented)

- **Model:** MiniMax-H3
- **Artifact:** [`unsloth/MiniMax-H3-GGUF`](https://huggingface.co/unsloth/MiniMax-H3-GGUF),
  file `minimax_h3_fl2va_pruned-Q2_K.gguf`
- **Why this quant:** Q2_K is the lowest-bit-width (smallest) quantization
  unsloth publishes for MiniMax-H3. It's the only realistic way to fit the
  model, its GPU-resident layers, and KV cache into an 8 GB RTX 4070 — this
  is a dev/test target, not a quality benchmark.
- **Hardware:** 1x NVIDIA RTX 4070 (8 GB VRAM)
- **Engine:** llama.cpp `llama-server` (CUDA build), OpenAI-compatible API
- **OS:** Linux (tested on Ubuntu; should work on any Linux with NVIDIA
  drivers + CUDA)

All settings for this target live in one file:
[`targets/dev-rtx4070/dev-rtx4070.env.example`](targets/dev-rtx4070/dev-rtx4070.env.example).
Copy it to `targets/dev-rtx4070/dev-rtx4070.env` and edit as needed — every
script in this repo reads its configuration from there.

| Variable            | Default                                 | Description                              |
|---------------------|------------------------------------------|-------------------------------------------|
| `MMH3_HF_REPO`      | `unsloth/MiniMax-H3-GGUF`                | Hugging Face repo hosting the GGUF quants |
| `MMH3_GGUF_FILE`    | `minimax_h3_fl2va_pruned-Q2_K.gguf`      | Specific GGUF artifact to use             |
| `MMH3_MODEL_PATH`   | `~/models/minimax-h3-gguf/<gguf file>`   | Local path to the downloaded GGUF file    |
| `MMH3_PORT`         | `8188`                                    | HTTP port                                 |
| `MMH3_HOST`         | `0.0.0.0`                                 | Bind address                              |
| `MMH3_GPU_LAYERS`   | `-1`                                      | Layers offloaded to GPU (`-1` = as many as fit) |
| `MMH3_CTX_SIZE`     | `8192`                                    | Context window (tokens)                   |
| `MMH3_PARALLEL`     | `1`                                       | Concurrent request slots                  |
| `MMH3_BATCH_SIZE`   | `512`                                     | Prompt batch size                         |
| `MMH3_UBATCH_SIZE`  | `128`                                     | Micro-batch size                          |

Override inline: `MMH3_PORT=9000 bash serve.sh`

### Requirements

| Component | Version | Notes |
|-----------|---------|-------|
| NVIDIA driver | >= 535 | Provides CUDA runtime libraries |
| CUDA toolkit + `cmake`/build tools | any recent | Needed to build llama.cpp with CUDA (`install.sh` invokes `cmake`) |
| Python | 3.9+ | Only used for `download_model.py` (via a small venv) |
| Disk | ~2-3 GB | Q2_K GGUF file + llama.cpp build |
| VRAM | 8 GB (RTX 4070) | Sized for this GPU; not all layers may fit on GPU at this quant/context — remaining layers fall back to CPU RAM automatically |

### Install as systemd service

```bash
sudo bash install.sh
```

This repo supports both install scopes:

- `bash install.sh` — install as the current user's `systemd --user` service
- `sudo bash install.sh` — install system-wide

For a non-root install, the service follows the user's systemd session by
default. If you want it to survive logout or start on reboot without an active
login session:

```bash
sudo loginctl enable-linger "$USER"
```

Options:

```bash
bash install.sh --user-install
sudo bash install.sh --port 9000
sudo bash install.sh --model /path/to/minimax_h3_fl2va_pruned-Q2_K.gguf
sudo bash install.sh --skip-download   # model already on disk
sudo bash install.sh --dry-run         # preview without installing
```

Hugging Face token (only needed if the repo/file requires one):

```bash
export HF_TOKEN=hf_...
sudo -E bash install.sh
```

Manage the service:

```bash
systemctl status video-streaming-minimax-h3-dev-rtx4070      # check status
journalctl -u video-streaming-minimax-h3-dev-rtx4070 -f      # follow logs
sudo bash restart.sh                                          # restart
sudo bash uninstall.sh                                         # remove service
```

For a non-root install:

```bash
systemctl --user status video-streaming-minimax-h3-dev-rtx4070
journalctl --user -u video-streaming-minimax-h3-dev-rtx4070 -f
bash restart.sh --user-install
bash uninstall.sh --user-install
```

### Manual run

```bash
# Download just the Q2_K GGUF file
python3 download_model.py unsloth/MiniMax-H3-GGUF \
  minimax_h3_fl2va_pruned-Q2_K.gguf \
  --local-dir ~/models/minimax-h3-gguf

# Start (requires a llama.cpp `llama-server` build with CUDA; see install.sh)
bash serve.sh

# Stop
bash kill-server.sh

# Validate the running service
bash test.sh

# Check GPU health/usage
bash gpu-status.sh

# Clean logs
bash clean-logs.sh

# Pre-flight check only (don't start)
MMH3_CHECK_ONLY=1 bash serve.sh
```

### Render a simple 30-second MiniMax-H3 test clip

The OpenAI-style `llama.cpp` server path above is not suitable for MiniMax-H3
video generation. For a simple local render test on the RTX 4070 target, use
[`render-test.sh`](/home/michel/code/video-streaming-minimax-h3/render-test.sh),
which follows the published `stable-diffusion.cpp` MiniMax-H3 workflow and
stitches two short segments into one 30-second WebM clip.

```bash
bash render-test.sh
```

What it does:

- builds `stable-diffusion.cpp` with CUDA + WebM support
- downloads the supported MiniMax-H3 diffusion model, text encoder, video VAE,
  and audio VAE
- renders two 15-second segments at 320x192 / 24 fps / 4 steps
- concatenates them into one valid 30-second WebM clip with `ffmpeg`, retaining
  the VP8 video stream and encoding audio as Opus

Outputs land under `~/videos/minimax-h3/<timestamp>/`.

### Check official full-BF16 capacity

The official [MiniMaxAI/MiniMax-H3](https://huggingface.co/MiniMaxAI/MiniMax-H3)
release is a sharded BF16 deployment rather than the GGUF render stack. Before
downloading its roughly 134 GiB of one-variant weights, run:

```bash
bash test-official-bf16.sh
```

The existing 4 x RTX 3090 host has 96 GiB aggregate VRAM, below the 160 GiB
effective capacity floor, so it cannot run that release. Details and official
sources are in [the BF16 viability note](docs/research/minimax-h3-official-bf16.md).

### Render each configured quantization

[`render-quant-tests.sh`](/home/michel/code/video-streaming-minimax-h3/render-quant-tests.sh)
runs the render test for a named configuration. Its default matrix reflects the
video-render assets found on the multi-GPU host:

```bash
# The verified first/last-frame Q4 render configuration
bash create-stick-fighter-video-q4.sh

# The reference-to-video Q6 configuration
bash create-stick-fighter-video-q6.sh

# The compatible FL2VA pruned Q8 configuration from Abiray
bash create-stick-fighter-video-q8.sh

# Run the two verified configurations sequentially
bash render-quant-tests.sh --all
```

These entrypoints use GGUF quantization names (`Q4` and `Q6`; not FP4/FP6).
The Q4 render uses the Q2 text encoder. The Q6 render uses the Q4 text encoder,
as required by the model's published quant pairing. Q6 uses CPU/RAM layer
streaming by default, which is the verified configuration. Multi-GPU model
splitting in the current `stable-diffusion.cpp` build produced an illegal CUDA
memory access with MiniMax-H3 Q6, so it is intentionally not enabled. Results
are organized below `~/videos/minimax-h3/<quant-name>/`; model weights remain
under `~/models/minimax-h3-render/` and are ignored by Git.

The Q8 test uses the 21.6 GB compatible
`MiniMax-H3-FL2VA-Pruned-Q8_0.gguf` denoiser from
[Abiray/MiniMax-H3-Pruned-GGUF](https://huggingface.co/Abiray/MiniMax-H3-Pruned-GGUF),
with the 14.6 GB Q4 text encoder and video/audio VAEs from
[Abiray/MiniMax-H3-GGUF](https://huggingface.co/Abiray/MiniMax-H3-GGUF).
The similarly named 36 GB unpruned Q8 denoiser is incompatible with the
`stable-diffusion.cpp` MiniMax-H3 implementation. See
[the Q8 compatibility note](docs/research/abiray-minimax-h3-q8.md).

## Rendered samples

These test outputs were rendered on the 4 x RTX 3090 host:

- [FL2VA pruned Q4, run 1](samples/fl2va-pruned-q4-20260829-190317.webm)
- [FL2VA pruned Q4, run 2](samples/fl2va-pruned-q4-20260830-022928.webm)
- [Ref2VA pruned Q6](samples/ref2va-pruned-q6-20260830-135402.webm)

## API

OpenAI-compatible endpoints (served by llama.cpp's `llama-server`):

- `GET /health` — health check
- `GET /v1/models` — list models
- `POST /v1/chat/completions` — chat (supports `"stream": true`)
- `POST /v1/completions` — completions

```bash
curl http://localhost:8188/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "MiniMax-H3",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 100
  }'
```

## Adding the `prod-multi-gpu` target later

The scripts in this repo (`serve.sh`, `daemon.sh`, `install.sh`, `restart.sh`,
`uninstall.sh`) select their configuration via a `TARGET` environment
variable (default: `dev-rtx4070`), loaded through `targets/lib.sh`. To add
the production target, follow the pattern in
[`targets/prod-multi-gpu/README.md`](targets/prod-multi-gpu/README.md) —
no changes to the dev/test target's config or scripts should be required.

## Files

| File / directory                     | Purpose                                             |
|---------------------------------------|------------------------------------------------------|
| `targets/dev-rtx4070/`                | Single source of config for the RTX 4070 dev/test target |
| `targets/prod-multi-gpu/`             | Placeholder for the future multi-GPU production target |
| `targets/lib.sh`                      | Shared helper: loads config for the selected `TARGET` |
| `install.sh`                          | Build llama.cpp, download model, install as systemd service |
| `uninstall.sh`                        | Remove systemd service                              |
| `download_model.py`                   | Download a single GGUF file from Hugging Face       |
| `daemon.sh`                           | Systemd entry point (no interactive UI)             |
| `serve.sh`                            | Manual start with health check                      |
| `test.sh`                             | Quick smoke test (health, models, chat, streaming)  |
| `kill-server.sh`                      | Stop the server                                     |
| `gpu-status.sh`                       | GPU health and memory usage                         |
| `restart.sh`                          | Restart the systemd service                         |
| `clean-logs.sh`                       | Clean up log/pid files                              |

## Logging

- **Systemd:** `journalctl -u video-streaming-minimax-h3-dev-rtx4070 -f`
- **Manual:** `/tmp/minimax-h3-serve.log`
- **PID file:** `/tmp/minimax-h3-<PORT>.pid`

## Design philosophy

This repo does one thing at a time: serve MiniMax-H3, quantized down to
Q2_K, on a single 8 GB RTX 4070 — a dev/test target for iterating before
moving to real GPU hardware. Every parameter for this target is tuned for
that specific combination and lives in one config file. A future, more
capable target can be added alongside it without touching this one. If you
have different hardware today, fork and adjust `targets/dev-rtx4070/`.
