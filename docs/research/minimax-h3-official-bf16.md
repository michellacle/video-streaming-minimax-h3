# Official MiniMax-H3 BF16 viability

The official [MiniMaxAI/MiniMax-H3](https://huggingface.co/MiniMaxAI/MiniMax-H3)
release is a full-BF16, sharded Diffusers/SGLang deployment. It is distinct from
the single-file GGUF artifacts used by this repository's
[`render-test.sh`](/home/michel/code/video-streaming-minimax-h3/render-test.sh).

## Official component sizes

The Hugging Face weight-index metadata reports:

| Component | Size |
| --- | ---: |
| FL2VA transformer | 61.7 GiB |
| Qwen3-VL-32B text encoder | 62.1 GiB |
| Video VAE | 9.7 GiB |
| Audio VAE | about 0.4 GiB |
| One complete variant | about 134 GiB |

Sources: the official
[transformer index](https://huggingface.co/MiniMaxAI/MiniMax-H3/blob/main/transformer/diffusion_pytorch_model.safetensors.index.json),
[text-encoder index](https://huggingface.co/MiniMaxAI/MiniMax-H3/blob/main/text_encoder/model.safetensors.index.json),
[VAE index](https://huggingface.co/MiniMaxAI/MiniMax-H3/blob/main/vae/diffusion_pytorch_model.safetensors.index.json),
and [repository manifest](https://huggingface.co/api/models/MiniMaxAI/MiniMax-H3).

## Hardware conclusion

The official repository's SGLang example uses four 80 GiB A100/H100 GPUs:

```bash
sglang serve \
  --model-path MiniMaxAI/MiniMax-H3 \
  --num-gpus 4 \
  --ulysses-degree 4 \
  --performance-mode speed \
  --model-variant fl2va
```

Four 24 GiB RTX 3090s provide 96 GiB aggregate VRAM, which is below the
approximately 160 GiB effective capacity required to load the full system with
activation headroom. The host's 120 GiB available RAM is also below the
recommended 150 GiB offload floor. Do not download the official 134 GiB BF16
release on that host for local execution.

Use [`test-official-bf16.sh`](/home/michel/code/video-streaming-minimax-h3/test-official-bf16.sh)
to check a future host. Continue to use the GGUF-based Q4/Q6 scripts on the
existing four-RTX-3090 host.
