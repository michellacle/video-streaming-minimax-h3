# Abiray MiniMax-H3 Q8 compatibility

## Status

The full, non-pruned
[`MiniMax-H3-FL2VA-Q8_0.gguf`](https://huggingface.co/Abiray/MiniMax-H3-GGUF)
cannot be loaded by `stable-diffusion.cpp`'s MiniMax-H3 implementation. The
compatible Q8 denoiser is
[`MiniMax-H3-FL2VA-Pruned-Q8_0.gguf`](https://huggingface.co/Abiray/MiniMax-H3-Pruned-GGUF)
(21.6 GB).

## Root cause

The failed full-model GGUF supplies each `adaln_proj.linear` tensor as
`[256, 1016064, 1, 1]`. The runtime detects its non-pruned
`time_embedder.proj_out.weight` and expects `[2688, 96768, 1, 1]`, so metadata
validation fails before inference. These layouts have equal element counts but
represent incompatible conditioning architectures.

The authoritative
[`merge_safetensors.py`](https://github.com/leejet/stable-diffusion.cpp/blob/master/scripts/merge_safetensors.py)
recipe constructs the supported model from the full backbone while excluding
its `adaln_proj.linear.*` and `time_embedder.*` tensors, then adds the pruned
AdaLN tensors and `adaln_t_table`. The matching runtime implementation is in
[`minimax_h3.hpp`](https://github.com/leejet/stable-diffusion.cpp/blob/master/src/model/diffusion/minimax_h3.hpp).

## Compatible asset manifest

| Role | Repository | File | Approx. size |
| --- | --- | --- | ---: |
| Denoiser | [Abiray/MiniMax-H3-Pruned-GGUF](https://huggingface.co/Abiray/MiniMax-H3-Pruned-GGUF) | `MiniMax-H3-FL2VA-Pruned-Q8_0.gguf` | 21.6 GB |
| Text encoder | [Abiray/MiniMax-H3-GGUF](https://huggingface.co/Abiray/MiniMax-H3-GGUF) | `text_encoders/qwen3vl_32b_minimax_h3-Q4_K_M.gguf` | 14.6 GB |
| Video VAE | [Abiray/MiniMax-H3-GGUF](https://huggingface.co/Abiray/MiniMax-H3-GGUF) | `vae/minimax_h3_video_vae_fp16.safetensors` | 5.21 GB |
| Audio VAE | [Abiray/MiniMax-H3-GGUF](https://huggingface.co/Abiray/MiniMax-H3-GGUF) | `vae/minimax_h3_audio_vae_fp32.safetensors` | 605 MB |

The total download is approximately 42 GB. On `gpus`, use the known-safe
single-GPU CPU/RAM layer streaming configuration:

```bash
bash create-stick-fighter-video-q8.sh
```
