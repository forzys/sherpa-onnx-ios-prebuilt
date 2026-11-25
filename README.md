# sherpa-onnx iOS prebuilt

Prebuilt `sherpa_onnx.xcframework` for iOS, built from the official
[k2-fsa/sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) source with
[`build-ios.sh`](./build-ios.sh). Used as a drop-in replacement for the
framework that [react-native-sherpa-onnx](https://github.com/XDcobra/react-native-sherpa-onnx) downloads.

| Release | sherpa-onnx | onnxruntime | Slices |
| --- | --- | --- | --- |
| v2.0.3 | 2.0.3 | 1.28.2 (static, merged) | ios-arm64, ios-arm64_x86_64-simulator |

- Single static library `libsherpa-onnx.a` per slice, with onnxruntime merged in, plus the C / C++ API headers.
- sherpa-onnx v2 no longer contains espeak-ng or piper-phonemize
  ([k2-fsa/sherpa-onnx#4055](https://github.com/k2-fsa/sherpa-onnx/pull/4055)); the build script also checks that no espeak code is present.
- The SHA256 of each zip is listed in the release notes.

## Rebuild

```bash
./build-ios.sh /path/to/workdir
# output: /path/to/workdir/out/sherpa_onnx.xcframework
```

## Licenses

This repository only redistributes build outputs of open-source projects:

- sherpa-onnx — Apache-2.0
- onnxruntime — MIT
- Other bundled dependencies (kaldi-native-fbank, kaldi-decoder, kaldifst, openfst, simple-sentencepiece, utf8proc, eigen, nlohmann/json, kissfft, hclust-cpp) keep their own permissive licenses (Apache-2.0 / MIT / BSD / MPL-2.0).

The build script in this repository is released under the Apache-2.0 license.
