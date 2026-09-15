# Benchmarks

Measured on 2026-09-15. These are single-machine observations, not general claims about Whisper or Intel GPUs.

## Conclusion

Multilingual Whisper `small` with Vulkan is the best tested configuration for this machine and interactive ompweb dictation.

- A 62.44-second real Brazilian Portuguese recording completed through HTTP in 33.10 seconds: 0.53 realtime factor, or 1.89x realtime throughput.
- Direct Vulkan processing of the same recording was 13.7% faster than CPU and produced the same strict word error rate.
- Vulkan's benefit was workload-sensitive: it was 1.73x faster on the 8.33-second sample but only 1.14x faster on the 62.44-second sample.
- `large-v3-turbo` was 3.17x slower than `small` on the long recording and had worse measured word error rate, so it was rejected.
- Quantized `medium` and `large-v3-turbo` variants were also slower and less accurate on the original short technical sample.

## Test environment

| Component | Measured value |
|---|---|
| Host | Proxmox VE 9.2.11, kernel 7.0.14-14-pve |
| CPU | Intel Core i5-9500T, 6 cores/6 threads, 2.2-3.7 GHz |
| GPU | Intel UHD Graphics 630, Coffee Lake GT2 |
| LXC | Unprivileged Debian 13.6, 6 cores, 8 GiB RAM, no swap |
| whisper.cpp | v1.9.4 |
| Build | Release, `GGML_VULKAN=ON` |
| Vulkan | Mesa 25.0.7 Intel driver; FP16 supported; no matrix cores |
| Primary model | Multilingual `ggml-small.bin`, F16, 487.01 MB loaded |
| Decode | Automatic language, beam size 5, best-of 5, no timestamps |
| Threads | 6 |
| Prompt | Same bilingual technical prompt as the checked-in systemd service |

Installed package versions:

| Package | Version |
|---|---|
| cmake | 3.31.6-2 |
| ffmpeg | 7:7.1.5-0+deb13u1 |
| git | 1:2.47.3-0+deb13u1 |
| glslc | 2025.2-1 |
| libvulkan-dev | 1.4.309.0-1 |
| mesa-vulkan-drivers | 25.0.7-2+deb13u1 |
| spirv-headers | 1.6.1+1.4.309.0-1 |
| vulkan-tools | 1.4.304.0+dfsg1-1 |

## Metrics

- **Total time:** `whisper_print_timings` total for direct CLI tests.
- **HTTP wall time:** curl `time_total`, including upload, FFmpeg conversion, and inference.
- **Realtime factor (RTF):** processing seconds divided by audio seconds. Lower is better; below 1.0 is faster than realtime.
- **Throughput:** audio seconds divided by processing seconds. Higher is better.
- **Speedup:** CPU total divided by Vulkan total.
- **WER:** case-insensitive word-level Levenshtein distance divided by 138 reference words. Punctuation is ignored; diacritics and lexical differences count.

Raw recordings are not published. The Portuguese reference and each model transcript are checked into `benchmarks/`, allowing WER reproduction.

## Real Brazilian Portuguese: 62.44 seconds

A native speaker read [`reference-pt-BR.txt`](benchmarks/reference-pt-BR.txt) naturally, including imperfect sentence-ending intonation. Capture format was mono PCM WAV, 16 kHz, 16-bit. Mean volume was -24.4 dB and peak volume was -1.4 dB.

Capture command on macOS:

```sh
ffmpeg -f avfoundation -i ':0' -t 75 \
  -ac 1 -ar 16000 -c:a pcm_s16le sample.wav
```

Actual captured duration was 62.442688 seconds.

### End-to-end HTTP result

| Audio | HTTP time | RTF | Throughput | Status |
|---:|---:|---:|---:|---:|
| 62.443 s | 33.100 s | 0.530 | 1.887x realtime | 200 |

This path included upload to `whisper-server`, request parsing, and inference. The submitted WAV needed no lossy browser-format decode, although `--convert` remained enabled.

At this observed rate, 60 seconds of similar audio would take about 31.8 seconds. A five-minute recording would take about 158.8 seconds if scaling remained linear. Those values are extrapolations, not measured guarantees.

### Direct Vulkan versus CPU

Same audio, model, prompt, decoding parameters, and process count. CPU mode added only `--no-gpu`.

| Backend | Total | RTF | Throughput | WER | Language confidence |
|---|---:|---:|---:|---:|---:|
| Vulkan | 33.047 s | 0.529 | 1.889x | 10.14% | Portuguese 98.37% |
| CPU | 37.574 s | 0.602 | 1.662x | 10.14% | Portuguese 98.36% |

Vulkan speedup was 1.137x, reducing total latency by 12.05%.

Detailed timing:

| Stage | Vulkan | CPU | Observation |
|---|---:|---:|---|
| Model load | 405.45 ms | 383.86 ms | Similar |
| Mel | 53.03 ms | 62.74 ms | Vulkan run 1.18x faster |
| Sample | 1,409.06 ms | 1,154.89 ms | CPU faster |
| Encode | 16,922.82 ms | 15,212.92 ms | CPU faster on UHD 630 |
| Decode | 84.72 ms | 2,427.10 ms | Vulkan 28.65x faster |
| Batched decode | 12,599.82 ms | 15,965.48 ms | Vulkan 1.27x faster |
| Prompt | 1,461.44 ms | 2,202.09 ms | Vulkan 1.51x faster |
| **Total** | **33,047.43 ms** | **37,574.30 ms** | **Vulkan 1.14x faster** |

The two backends made slightly different word choices but reached the same strict WER. Vulkan transcript: [`transcript-vulkan-pt-BR.txt`](benchmarks/transcript-vulkan-pt-BR.txt). CPU transcript: [`transcript-cpu-pt-BR.txt`](benchmarks/transcript-cpu-pt-BR.txt).

### Accuracy details

Against 138 reference words:

| Measurement | Result |
|---|---:|
| Hypothesis words | 142 |
| Strict word errors | 14 |
| Strict WER | 10.14% |
| Errors excluding inserted `[MÚSICA DE FUNDO]` | 11 |
| WER excluding that three-word insertion | 7.97% |

Notable Vulkan differences:

| Reference | Output |
|---|---|
| `Whisper` | `Weasper` |
| `contêiner` | `container` |
| `usamos` | `vamos` |
| `e APIs REST` | `API Rust` |
| `com systemd` | `como SystemD` |
| `hesitações` | `exitações` |
| no trailing music | `[MÚSICA DE FUNDO]` |

Sentence boundaries remained good despite imperfect spoken intonation. The main weakness was technical vocabulary, not sentence retention.

Reproduce the strict score:

```sh
python3 scripts/wer.py \
  benchmarks/reference-pt-BR.txt \
  benchmarks/transcript-vulkan-pt-BR.txt
```

Expected output:

```text
Reference words:  138
Hypothesis words: 142
Word errors:      14
WER:              10.14%
```

## Long-form larger-model evaluation

`large-v3-turbo` F16 was retested because short recordings can overstate large-model startup cost. It used the same 62.44-second real voice recording and Vulkan settings.

| Model | Total | RTF | Throughput | Strict WER | Relative to small |
|---|---:|---:|---:|---:|---:|
| `small` F16 | 33.047 s | 0.529 | 1.889x | 10.14% | baseline |
| `large-v3-turbo` F16 | 104.678 s | 1.676 | 0.597x | 12.32% | 3.17x slower |

`large-v3-turbo` auto-detected Portuguese with 99.92% confidence, but dropped the complete clause about Proxmox and SSH, inserted `SQL`, changed `produz` to `reproduz`, and appended `Obrigado`. Its transcript is [`transcript-large-v3-turbo-pt-BR.txt`](benchmarks/transcript-large-v3-turbo-pt-BR.txt).

The larger model produced no accuracy improvement on this representative sample and exceeded ompweb's existing 60-second transcription timeout. It was therefore not adopted. Further larger-model tests were stopped: previously tested quantized alternatives had already been slower and less accurate, while the strongest practical candidate had now failed both latency and accuracy criteria on real long-form speech.

## Short-sample Vulkan versus CPU

Original controlled sample: 8.33 seconds, multilingual `small`, identical decoding settings and exact same transcript from both backends.

| Backend | Total | Wall | RTF | Throughput |
|---|---:|---:|---:|---:|
| Vulkan | 10.855 s | 11.28 s | 1.303 | 0.767x realtime |
| CPU | 18.729 s | 19.07 s | 2.248 | 0.445x realtime |

Vulkan was 1.73x faster overall and reduced latency by 42.0%.

Key stage comparison:

| Stage | Vulkan | CPU | Vulkan speedup |
|---|---:|---:|---:|
| Encode | 8.51 s | 8.67 s | 1.02x |
| Batched decode | 1.25 s | 8.70 s | 6.97x |

This short test made Vulkan's decoder advantage dominant. The 62.44-second test spent much more time encoding, where this UHD 630 did not beat the i5-9500T CPU. Both results are retained because one short sample would substantially overstate long-form GPU speedup.

## Model-size comparison on short technical speech

All candidates used Vulkan. The exact same approximately 8.33-second accented-English technical sample was used for comparative runs.

| Model | Warm latency | Accuracy observation |
|---|---:|---|
| `small` F16 | 10.85 s | Exact expected transcript |
| `medium` Q5_0 | 36.3 s | Worse than `small` |
| `large-v3-turbo` F16 | 47.7 s | Worse than `small` |
| `large-v3-turbo` Q5_0 | 52.1 s | Worse than `small`; slower than F16 |

Quantization did not help this Vulkan/iGPU combination. Model size alone did not predict accuracy on short technical dictation.

## Other endpoint samples

| Sample | Format | Approximate request time | Observation |
|---|---|---:|---|
| Accented English technical sentence | WebM/Opus | 10.46 s | Exact transcript |
| Brazilian Portuguese | MP4/AAC | 11.12 s after reboot | Correct Portuguese detection and transcript |
| Mixed Portuguese/English technical terms | Ogg/Opus | about 11 s | Correctly recognized ompweb, Git, API, TypeScript, and Docker; synthetic `Proxmox` became `próximo opus` |
| Portuguese synthetic long sample | WebM/Opus, 33.326 s | 18.280 s | RTF 0.549, but omitted most middle content; 73.85% WER |

The synthetic long sample used macOS Portuguese TTS. Its poor transcript conflicts with the much better real-voice result, so synthetic speech is retained as a warning rather than treated as representative accuracy evidence.

## OpenVINO status

OpenVINO was not benchmarked. In whisper.cpp it accelerates only the encoder and requires converted model artifacts plus an additional runtime. On the representative long sample, the CPU encoder was already 10.1% faster than Vulkan's encoder; Vulkan won through decoder and prompt work. OpenVINO may still behave differently, but adding it without measured benefit would make disaster recovery heavier.

## Limitations

- One physical host and one Intel UHD 630.
- One native speaker for the long accuracy sample.
- Single runs rather than statistical distributions.
- No concurrency, power-consumption, thermal-throttling, or cold-host study.
- No OpenVINO measurement.
- WER treats speaker deviations from the supplied text as recognition errors.
- HTTP timing from WAV understates FFmpeg work required for compressed browser recordings, although short WebM, MP4, and Ogg compatibility was separately exercised.
- Linear projections are estimates only.
