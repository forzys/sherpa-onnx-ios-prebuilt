#!/usr/bin/env bash
# 编译 sherpa-onnx v2 的 iOS xcframework（不含 espeak-ng / GPL），替换 react-native-sherpa-onnx 自带的 1.12 预编译库。
# 用法：scripts/sherpa-onnx-ios/build-ios.sh <工作目录>
# 产物：<工作目录>/out/sherpa_onnx.xcframework（已合并 onnxruntime，结构与 RN 包原版一致）
set -euo pipefail

SHERPA_VERSION=2.0.3
ORT_VERSION=1.28.2             # 与上游 build-ios.sh 默认版本一致
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mkdir -p "${1:?需要工作目录}" && cd "$1" && pwd)"
SRC="$WORK/sherpa-onnx"
JOBS="$(sysctl -n hw.ncpu)"

# 1. 源码（v2 起上游已移除 espeak-ng / piper-phonemize，见 k2-fsa/sherpa-onnx#4055，不含 GPL 代码）
if [ ! -d "$SRC" ]; then
  git clone --depth 1 --branch "v$SHERPA_VERSION" https://github.com/k2-fsa/sherpa-onnx.git "$SRC"
fi

# 1b. 预下载 CMake 依赖到源码目录：各依赖的 cmake 会优先找 ${CMAKE_SOURCE_DIR}/<文件名>，
#     CMake 自带的下载在部分网络下 SSL 失败，改用系统 curl（带重试和 hf-mirror 备用地址）
python3 - "$SRC" <<'PY'
import glob, os, re, subprocess, sys
src = sys.argv[1]
skip = ("onnxruntime", "googletest", "pybind", "asio", "websocketpp", "portaudio", "directml", "cargs")
for path in sorted(glob.glob(os.path.join(src, "cmake", "*.cmake"))):
    name = os.path.basename(path)
    if any(k in name for k in skip):
        continue
    text = open(path).read()
    urls = re.findall(r'set\([\w-]+_URL2?\s+"(https://[^"$]+)"', text)
    files = re.findall(r'\$\{CMAKE_SOURCE_DIR\}/([^\s)]+)', text)
    if not urls or not files:
        continue
    target = os.path.join(src, files[0])
    if os.path.exists(target):
        continue
    for url in urls:
        if subprocess.call(["curl", "-fsSL", "--retry", "3", "-o", target, url]) == 0:
            print("downloaded", files[0])
            break
    else:
        sys.exit(f"下载失败：{files[0]}")
PY
# kaldi-native-fbank 内部还依赖 eigen
[ -f "$SRC/eigen-5.0.1.tar.gz" ] || curl -fsSL --retry 3 -o "$SRC/eigen-5.0.1.tar.gz" \
  https://gitlab.com/libeigen/eigen/-/archive/5.0.1/eigen-5.0.1.tar.gz \
  || curl -fsSL -o "$SRC/eigen-5.0.1.tar.gz" https://hf-mirror.com/csukuangfj/sherpa-onnx-cmake-deps/resolve/main/eigen-5.0.1.tar.gz

# 2. onnxruntime 静态库
ORT="$WORK/ort/onnxruntime.xcframework"
if [ ! -d "$ORT" ]; then
  mkdir -p "$WORK/ort" && cd "$WORK/ort"
  curl -fL -o ort.zip "https://github.com/csukuangfj/onnxruntime-libs/releases/download/v$ORT_VERSION/onnxruntime-ios-static-xcframework-$ORT_VERSION.xcframework.zip"
  unzip -q ort.zip -d unpacked && mv "$(find unpacked -type d -name onnxruntime.xcframework | head -1)" . && rm -rf ort.zip unpacked
fi

# 3. 编译：真机 arm64、模拟器 arm64 / x86_64
build() { # <目录名> <PLATFORM> <ort 切片>
  local slice="$ORT/$3/onnxruntime.framework"
  mkdir -p "$WORK/ortlib/$3"
  cp "$slice/onnxruntime" "$WORK/ortlib/$3/libonnxruntime.a"
  SHERPA_ONNXRUNTIME_LIB_DIR="$WORK/ortlib/$3" SHERPA_ONNXRUNTIME_INCLUDE_DIR="$slice/Headers" \
  cmake -S "$SRC" -B "$WORK/build/$1" \
    -DCMAKE_TOOLCHAIN_FILE="$SRC/toolchains/ios.toolchain.cmake" -DPLATFORM="$2" \
    -DENABLE_BITCODE=0 -DENABLE_ARC=1 -DENABLE_VISIBILITY=0 -DDEPLOYMENT_TARGET=13.0 \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX="$WORK/install/$1" \
    -DSHERPA_ONNX_ENABLE_PYTHON=OFF -DSHERPA_ONNX_ENABLE_TESTS=OFF -DSHERPA_ONNX_ENABLE_CHECK=OFF \
    -DSHERPA_ONNX_ENABLE_PORTAUDIO=OFF -DSHERPA_ONNX_ENABLE_JNI=OFF -DSHERPA_ONNX_ENABLE_C_API=ON \
    -DSHERPA_ONNX_ENABLE_WEBSOCKET=OFF -DSHERPA_ONNX_ENABLE_BINARY=OFF
  cmake --build "$WORK/build/$1" -j "$JOBS"
  cmake --install "$WORK/build/$1" >/dev/null
}
build os64 OS64 ios-arm64
build sim_arm64 SIMULATORARM64 ios-arm64_x86_64-simulator
build sim_x86_64 SIMULATOR64 ios-arm64_x86_64-simulator

# 4. 合并成单个静态库（含 onnxruntime），再做 xcframework
merge() { # <输出> <install 目录> <ort 静态库>
  libtool -static -o "$1" "$2"/lib/*.a "$3" 2>/dev/null
}
OUT="$WORK/out" && rm -rf "$OUT" && mkdir -p "$OUT/tmp"
merge "$OUT/tmp/device.a" "$WORK/install/os64" "$WORK/ortlib/ios-arm64/libonnxruntime.a"
for a in sim_arm64 sim_x86_64; do
  lipo_arch=$([ $a = sim_arm64 ] && echo arm64 || echo x86_64)
  lipo -thin $lipo_arch "$WORK/ortlib/ios-arm64_x86_64-simulator/libonnxruntime.a" -output "$OUT/tmp/ort_$a.a"
  merge "$OUT/tmp/$a.a" "$WORK/install/$a" "$OUT/tmp/ort_$a.a"
done
lipo -create "$OUT/tmp/sim_arm64.a" "$OUT/tmp/sim_x86_64.a" -output "$OUT/tmp/sim.a"
mkdir -p "$OUT/tmp/dev" "$OUT/tmp/simlib"
cp "$OUT/tmp/device.a" "$OUT/tmp/dev/libsherpa-onnx.a"
cp "$OUT/tmp/sim.a" "$OUT/tmp/simlib/libsherpa-onnx.a"
xcodebuild -create-xcframework \
  -library "$OUT/tmp/dev/libsherpa-onnx.a" -headers "$WORK/install/os64/include" \
  -library "$OUT/tmp/simlib/libsherpa-onnx.a" -headers "$WORK/install/os64/include" \
  -output "$OUT/sherpa_onnx.xcframework"
echo "$SHERPA_VERSION" > "$OUT/sherpa_onnx.xcframework/VERSION.txt"
rm -rf "$OUT/tmp"

# 5. 检查：不能有 espeak-ng / piper-phonemize 的函数或目标文件（注意 OfflineSpeaker 里也含 "eSpeak" 字样，不能简单 grep）
for lib in "$OUT"/sherpa_onnx.xcframework/*/libsherpa-onnx.a; do
  fn=$(nm "$lib" 2>/dev/null | grep -cE ' _espeak_|piper[0-9]*phonemize' || true)
  obj=$(ar t "$lib" 2>/dev/null | grep -cE '^(speech|wavegen|espeak_api|phonemize|translate|dictionary)\.(c|cpp)\.o$' || true)
  [ "$fn" = 0 ] && [ "$obj" = 0 ] || { echo "仍含 espeak：$lib（函数 $fn，目标文件 $obj）"; exit 1; }
done
echo "完成：$OUT/sherpa_onnx.xcframework"
