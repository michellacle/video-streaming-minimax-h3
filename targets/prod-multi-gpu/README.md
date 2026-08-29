# Target: prod-multi-gpu (placeholder)

This directory is reserved for the future **production, multi-GPU**
deployment target for the MiniMax-H3 video streaming service.

It is intentionally not implemented yet. Per the current plan, only the
`dev-rtx4070` target (single 8 GB RTX 4070) is implemented today.

When this target is built out, it should follow the same pattern as
`targets/dev-rtx4070/`:

- `prod-multi-gpu.env.example` -- single source of configuration for this
  target (model artifact/quant, GPU count, tensor/pipeline parallelism,
  context length, ports, etc.)
- `prod-multi-gpu.service` -- systemd unit for this target
- Higher-precision / larger quantization of MiniMax-H3 (e.g. a higher
  `unsloth/MiniMax-H3-GGUF` quant, or full-precision weights) sized to the
  available multi-GPU VRAM budget.

The top-level scripts (`serve.sh`, `daemon.sh`, `install.sh`, etc.) are
already written to select their configuration via a `TARGET` variable
(defaulting to `dev-rtx4070`), so adding this target should not require
rewriting the dev/test target's scripts or config.
