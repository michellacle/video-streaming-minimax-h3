# MiniMax-H3 Q8 compatibility

## Status

Neither the full, non-pruned
[`MiniMax-H3-FL2VA-Q8_0.gguf`](https://huggingface.co/Abiray/MiniMax-H3-GGUF)
nor the pruned
[`MiniMax-H3-FL2VA-Pruned-Q8_0.gguf`](https://huggingface.co/Abiray/MiniMax-H3-Pruned-GGUF)
can be loaded by the currently installed `stable-diffusion.cpp` MiniMax-H3
implementation.

The working Q8 alternative is
[`minimax_h3_fl2va_pruned-Q8_0.gguf`](https://huggingface.co/unsloth/MiniMax-H3-GGUF)
from Unsloth. Its filename and GGUF tensor metadata match the same artifact
family as the Leejet Q4/Q6 files already validated by this repository.

## Root cause

The full-model GGUF supplies each `adaln_proj.linear` tensor as
`[256, 1016064, 1, 1]`. The runtime detects its non-pruned
`time_embedder.proj_out.weight` and expects `[2688, 96768, 1, 1]`, so metadata
validation fails before inference. These layouts have equal element counts but
represent incompatible conditioning architectures.

The pruned Q8 GGUF passes that initial AdaLN distinction, but then fails model
metadata validation across its backbone (for example,
`blocks.5.mlp.fc1.weight` is `[5376, 28672, 1, 1]` while the runtime expects
`[1, 28672, 1, 1]`). Its metadata schema is therefore also incompatible with
the runtime that successfully renders the existing Leejet Q4/Q6 files.

The authoritative
[`merge_safetensors.py`](https://github.com/leejet/stable-diffusion.cpp/blob/master/scripts/merge_safetensors.py)
recipe constructs the supported model from the full backbone while excluding
its `adaln_proj.linear.*` and `time_embedder.*` tensors, then adds the pruned
AdaLN tensors and `adaln_t_table`. The matching runtime implementation is in
[`minimax_h3.hpp`](https://github.com/leejet/stable-diffusion.cpp/blob/master/src/model/diffusion/minimax_h3.hpp).

## Q8 artifacts tested

| Role | Repository | File | Approx. size |
| --- | --- | --- | ---: |
| Denoiser | [Abiray/MiniMax-H3-GGUF](https://huggingface.co/Abiray/MiniMax-H3-GGUF) | `MiniMax-H3-FL2VA-Q8_0.gguf` | 36 GB |
| Denoiser | [Abiray/MiniMax-H3-Pruned-GGUF](https://huggingface.co/Abiray/MiniMax-H3-Pruned-GGUF) | `MiniMax-H3-FL2VA-Pruned-Q8_0.gguf` | 21.6 GB |
| Denoiser | [unsloth/MiniMax-H3-GGUF](https://huggingface.co/unsloth/MiniMax-H3-GGUF) | `minimax_h3_fl2va_pruned-Q8_0.gguf` | 21.4 GB |

The Unsloth repository also publishes the matching 18.2 GB Q4 text encoder and
both VAEs. The Q8 render entrypoint downloads this complete artifact family to
`~/models/minimax-h3-render-q8/`, separate from the Q4/Q6 cache:

```bash
bash create-stick-fighter-video-q8.sh
```
