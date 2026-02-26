# Removed: Intel NPU + OpenVINO Support

**Removed:** 2026-02-24

## What Was Removed

- **flake.nix**: `intelNpuOverlay` — custom overlay that built `intel-npu-driver` from git main and patched `whisper-cpp` with OpenVINO support (`-DWHISPER_OPENVINO=ON`)
- **athena/configuration.nix**: `intel-npu-driver`, `level-zero` from `hardware.graphics.extraPackages`, render group, `LD_LIBRARY_PATH` for OpenVINO
- **voice.d/core.sh**: `OV_DEVICE` env var and `--ov-e-device` argument passthrough

## Why

NPU acceleration for whisper.cpp on Linux never worked. The OpenVINO NPU plugin has an upstream bug:

```
L0 pfnCreate2 result: ZE_RESULT_ERROR_UNSUPPORTED_FEATURE, code 0x78000003
```

Tracked in [whisper.cpp #2929](https://github.com/ggml-org/whisper.cpp/issues/2929) (open, no fix).

Tested multiple driver versions (v1.24.0 through git main) against OpenVINO 2025.4.2 — all failed. The issue is in OpenVINO's NPU plugin for Linux, not the driver.

## What Still Works

- `whisper-cpp` in `modules/desktop.nix` (CPU mode, no overlay needed)
- `faster-whisper` Python package in `home/default.nix`
- Voice scripts (`voice.d/`) — just use CPU now
- NPU hardware itself is fine (`/dev/accel0`, `intel_vpu` kernel module loads)

## To Revisit

- [whisper.cpp #2929](https://github.com/ggml-org/whisper.cpp/issues/2929)
- OpenVINO 2026.x releases for Linux NPU fixes
- [openvino-genai](https://github.com/openvinotoolkit/openvino.genai) WhisperPipeline as alternative

## Hardware

- Intel Core Ultra (Lunar Lake) with integrated NPU
- athena host
