# Abiray MiniMax-H3 Q8 feasibility

[Abiray/MiniMax-H3-GGUF](https://huggingface.co/Abiray/MiniMax-H3-GGUF)
publishes a full, non-pruned MiniMax-H3 FL2VA Q8_0 GGUF. It is a practical
quality-oriented alternative to the official sharded BF16 release on the
four-RTX-3090 host.

## Required matching assets

| Role | File | Source | Size |
| --- | --- | --- | ---: |
| Denoiser | `unet/MiniMax-H3-FL2VA-Q8_0.gguf` | Abiray | 36 GB |
| Text encoder | `text_encoders/qwen3vl_32b_minimax_h3-Q4_K_M.gguf` | Abiray | 14.6 GB |
| Video VAE | `vae/minimax_h3_video_vae_fp16.safetensors` | Abiray | 5.21 GB |
| Audio VAE | `vae/minimax_h3_audio_vae_fp32.safetensors` | Abiray | 605 MB |

The total download is about 56 GB. Do not mix this full-model Q8 denoiser and
text encoder with the pruned `leejet` quant artifacts.

## Host assessment

The `gpus` host has 456 GB free disk, 120 GiB available RAM, and four 24 GiB
RTX 3090 GPUs. It has enough disk and system RAM to run the Q8 test with
`stable-diffusion.cpp` CPU/RAM layer streaming. The current upstream
multi-GPU split path is not used because it produced an illegal CUDA memory
access with MiniMax-H3 Q6 during validation.

Run the test with:

```bash
bash create-stick-fighter-video-q8.sh
```

Sources: the [Abiray model card](https://huggingface.co/Abiray/MiniMax-H3-GGUF)
for the artifact manifest and sizes, and
[stable-diffusion.cpp's MiniMax-H3 documentation](https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/minimax_h3.md)
for the required four-component `sd-cli` invocation.
