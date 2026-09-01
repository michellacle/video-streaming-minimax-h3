---
name: remote-video-rendering
description: Render MiniMax-H3 videos reliably on the gpus host. Use for any request to create, render, inspect, or retrieve a video in this repository. It centralizes Gold/Silver/Bronze quality selection, Tailscale remote jobs, metrics, and delivery validation.
compatibility: Requires this repository, Tailscale access to michel@gpus, and the repository's remote-render.sh launcher.
---

# Remote Video Rendering

## Required quality decision

Before starting a new render, ask the user exactly one quality question with
these choices:

1. **Gold (Recommended)** — Q8 FL2VA, 1024x576 landscape or 576x1024 vertical,
   20 steps, 24 FPS, seed 42. Best available visual quality. A five-second
   scene takes about 18 minutes; a single 15-second segment can take 80+ minutes.
2. **Silver** — Q8 FL2VA, 864x480 landscape or 480x864 vertical, 12 steps,
   24 FPS, seed 42. Faster with reduced fine detail. Expect about 7 minutes for
   a five-second scene.
3. **Bronze** — Q8 FL2VA, 320x192 landscape or 192x320 vertical, 4 steps,
   24 FPS, seed 42. Fast smoke-test quality. Expect about 2 minutes for a
   fifteen-second scene.

Never select a tier silently unless the user explicitly asked to use the
existing gold configuration. For all tiers, use a five-second scene by default;
use a single 15-second segment only after the user explicitly requests it.

## Build the render

1. If a prompt is needed, invoke `h3-prompt-writing` first and prepare the
   correct H3 mode. Use the H3 text as `MMH3_RENDER_PROMPT`.
2. For ordinary text-to-video work, use
   [`create-custom-video-q8.sh`](../../../create-custom-video-q8.sh). It uses
   the compatible Unsloth Q8 FL2VA model and adds audio loudness normalization
   plus a final -15 dBFS acceptance gate.
3. Start the job only through
   [`remote-render.sh`](../../../remote-render.sh). It encapsulates the
   `michel@gpus` Tailscale host, isolated process session, logs, PID, and GPU
   dispatch. The default `--gpu auto` chooses an idle GPU by VRAM use and
   reserves it for the entire render. Use `--gpu N` only to deliberately pin a
   job to an otherwise idle GPU:

   ```bash
   bash remote-render.sh start \
     --gpu auto \
     --env MMH3_RENDER_PROMPT='...' \
     --env MMH3_RENDER_WIDTH=1024 \
     --env MMH3_RENDER_HEIGHT=576 \
     --env MMH3_RENDER_STEPS=20 \
     --env MMH3_RENDER_SEGMENT_SECONDS=5 \
     --env MMH3_RENDER_TOTAL_SECONDS=5 \
     --env MMH3_RENDER_SEGMENTS=1 \
     create-custom-video-q8.sh
   ```

   The launcher starts the remote process under `setsid` and `nohup`, redirects
   standard input/output, pins `CUDA_VISIBLE_DEVICES` to the assigned GPU, and
   stores the GPU index, status, `render.log`, and PID under
   `~/videos/minimax-h3/remote-jobs/<job-id>/`. SSH/Tailscale disconnects do
   not terminate that process.

   The default admission limit is two simultaneous render jobs. This is
   intentional: Q8 layer streaming uses substantial shared host RAM as well as
   VRAM; three concurrent jobs triggered the Linux OOM killer on the 125 GiB
   host. The launcher refuses a third job before it can destabilize existing
   renders. Raise `MMH3_REMOTE_MAX_CONCURRENT_JOBS` only after a measured
   capacity test.
4. Preserve the returned job ID. Reconnect safely with:

   ```bash
   bash remote-render.sh status <job-id>
   bash remote-render.sh logs <job-id>
   ```

Do not use a foreground `tailscale ssh ... bash create-...` command for a
long render. Do not enable multi-GPU layer splitting: it is known to produce
illegal CUDA memory access with this MiniMax-H3 build. GPU 0 is the supported
single-GPU renderer; CPU/RAM layer streaming is intentional.

## Verify and deliver

After `state=completed`:

1. Retrieve the remote clip over Tailscale and compare SHA-256 checksums.
2. Validate duration, dimensions, FPS, video/audio codecs, and final audio mean
   volume with `ffprobe` and `ffmpeg volumedetect`.
3. Extract and inspect representative frames; inspect start/end frames when
   reference images or required composition are involved.
4. Record `metrics.tsv` measurements in the README only for shareable benchmark
   tests. Do not commit client/private images, prompts, or output unless the
   user explicitly asks to publish them.
5. Produce H.264/AAC MP4 with `-movflags +faststart` when the user needs a
   social-ready file.
