#!/usr/bin/env bash
# Reproduce this local 2014-disc build using the tools in _tools/.
set -euo pipefail
actual_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# Commas in the ISO folder name break -Wl arguments; use an alias for build paths.
ROOT=/tmp/ds2-majula
if [[ ! -e "$ROOT" ]]; then ln -s "$actual_root" "$ROOT"; fi
[[ "$(readlink -f "$ROOT")" == "$actual_root" ]]
cd "$ROOT"
export PATH="$ROOT/_tools/cmake-4.4.5-linux-x86_64/bin:$ROOT/_tools/bin:$PATH"
export DEVKITPRO="$ROOT/_tools/devkitpro"
export REXSDK_DIR="$ROOT/sdk"
export CXX=clang++
export LD_LIBRARY_PATH="$ROOT/sdk/out/linux-amd64:$ROOT/app/thirdparty/reblue-XenosRecomp/thirdparty/dxc-bin/lib/x64:$ROOT/out/xenos-host/thirdparty/fmt${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
jobs="${DS2_JOBS:-4}"
phase="${1:-all}"
host() {
    cmake -S "$ROOT/sdk" -B "$ROOT/out/host-linux" -G Ninja \
        -DCMAKE_MAKE_PROGRAM="$ROOT/_tools/bin/ninja" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
        -DCMAKE_C_FLAGS=-march=x86-64-v2 -DCMAKE_CXX_FLAGS=-march=x86-64-v2 \
        -DREXGLUE_ENABLE_TRACY=OFF -DCMAKE_SKIP_RPATH=ON
    cmake --build "$ROOT/out/host-linux" --target rexglue -j "$jobs"
}
codegen() {
    export REX_MAX_JUMP_TABLE_ENTRIES=1024
    export REXGLUE_DUMP_IMAGE="$ROOT/out/default_image.bin"
    (cd "$ROOT/app"; "$ROOT/sdk/out/linux-amd64/rexglue" codegen ds2_manifest.toml)
    python3 "$ROOT/tools/post_codegen.py"
    python3 "$ROOT/tools/switch_check.py"
    python3 "$ROOT/tools/pointer_audit.py"
}
shaders() {
    cmake -S "$ROOT/app/thirdparty/reblue-XenosRecomp" -B "$ROOT/out/xenos-host" -G Ninja \
        -DCMAKE_MAKE_PROGRAM="$ROOT/_tools/bin/ninja" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_SKIP_RPATH=ON \
        -DXENOS_RECOMP_RENUT=ON -DXENOS_RECOMP_DXIL=OFF
    cmake --build "$ROOT/out/xenos-host" --target XenosRecomp -j "$jobs"
    cmake -S "$ROOT/app/thirdparty/uam" -B "$ROOT/out/deko3d_tools/uam-build" -G Ninja \
        -DCMAKE_MAKE_PROGRAM="$ROOT/_tools/bin/ninja" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++
    cmake --build "$ROOT/out/deko3d_tools/uam-build" --target uam_tool -j "$jobs"
    cmake -S "$ROOT/_tools/SPIRV-Cross" -B "$ROOT/out/deko3d_tools/spirv-cross-build" -G Ninja \
        -DCMAKE_MAKE_PROGRAM="$ROOT/_tools/bin/ninja" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
        -DSPIRV_CROSS_ENABLE_TESTS=OFF -DSPIRV_CROSS_ENABLE_C_API=OFF
    cmake --build "$ROOT/out/deko3d_tools/spirv-cross-build" --target spirv-cross -j "$jobs"
    ln -sfn uam "$ROOT/out/deko3d_tools/uam-build/uam.exe"
    ln -sfn spirv-cross "$ROOT/out/deko3d_tools/spirv-cross-build/spirv-cross.exe"
    python3 "$ROOT/tools/extract_shaders.py"
    python3 "$ROOT/tools/ds2_dump_shaders.py"
    mkdir -p "$ROOT/out/pc/renut_gpu/early_alpha_hlsl" "$ROOT/out/deko3d_shaders/spirv"
    local xenos="$ROOT/out/xenos-host/XenosRecomp/XenosRecomp"
    local common="$ROOT/app/thirdparty/reblue-XenosRecomp/XenosRecomp/shader_common.h"
    local alpha="$ROOT/out/pc/renut_gpu/early_alpha_hlsl"
    BANJO_HLSL_DUMP_ONLY=1 "$xenos" "$ROOT/out/renut_shader_dump" \
        "$ROOT/out/pc/renut_gpu/early_alpha_pass1.cpp" "$common" "$alpha"
    python3 "$ROOT/tools/renut_early_alpha.py" "$alpha"
    BANJO_DEKO3D_SPIRV_DIR="$ROOT/out/deko3d_shaders/spirv" BANJO_HLSL_OVERRIDE="$alpha" \
        "$xenos" "$ROOT/out/renut_shader_dump" "$ROOT/out/pc/renut_gpu/shader_cache.cpp" "$common"
    python3 "$ROOT/tools/deko3d_shaders.py" --spirv "$ROOT/out/deko3d_shaders/spirv" \
        --out "$ROOT/out/deko3d_shaders/glsl" --no-uam --jobs "$jobs"
    python3 "$ROOT/tools/deko3d_glsl_opt.py" --in "$ROOT/out/deko3d_shaders/glsl/glsl" \
        --out "$ROOT/out/deko3d_shaders/glsl_opt" --check --jobs "$jobs"
    python3 "$ROOT/tools/deko3d_shader_package.py" --glsl "$ROOT/out/deko3d_shaders/glsl_opt" \
        --out "$ROOT/app/out/renut_switch"
    python3 "$ROOT/tools/renut_switch_shader_cache.py" --pc "$ROOT/out/pc"
}
switch_build() {
    cmake -S "$ROOT/app" -B "$ROOT/out/nx_dk" -G Ninja \
        -DCMAKE_MAKE_PROGRAM="$ROOT/_tools/bin/ninja" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE="$ROOT/tools/switch/cmake/switch-devkitA64.cmake" \
        -DDEVKITPRO="$DEVKITPRO" -DREXGLUE_SWITCH_NO_NVK=ON \
        -DREXGLUE_SWITCH_NVK_SDK="$ROOT/sdk/thirdparty/vulkan-headers" \
        -DDS2_GLSLANG_VALIDATOR=/usr/bin/glslangValidator
    cmake --build "$ROOT/out/nx_dk" -j "$jobs"
    python3 "$ROOT/tools/check_switch_build.py" --elf "$ROOT/out/nx_dk/ds2" --nro "$ROOT/out/nx_dk/ds2.nro"
}
package() {
    local dest="$ROOT/out/nx_dk/sdcard/switch/ds2-nx"
    mkdir -p "$dest"
    cp "$ROOT/out/nx_dk/ds2.nro" "$dest/ds2-dk.nro"
    cp "$ROOT/app/ds2_switch.toml" "$dest/ds2.toml"
    cp "$ROOT/docs/local-install.md" "$dest/README.md"
    cp -a --reflink=auto "$ROOT/assets/game_root" "$dest/"
    # Preserve the original game's progression and fog-wall behaviour.
    python3 - "$dest/ds2.toml" <<'PY'
import pathlib, re, sys, tomllib
path = pathlib.Path(sys.argv[1])
text = path.read_text()
for key in ('ds2_early_dull_ember', 'ds2_fog_wall_iframes'):
    text = re.sub(r'(?m)^' + key + r'\s*=.*$', key + ' = false', text)
tomllib.loads(text)
path.write_text(text)
print('Packaged configuration parses; original gameplay settings selected')
PY
    echo "SD card files: $dest"
}
case "$phase" in
    host) host;;
    codegen) codegen;;
    shaders) shaders;;
    switch) switch_build;;
    package) package;;
    all) host; codegen; shaders; switch_build; package;;
    *) echo "Usage: bash tools/build_linux.sh [host|codegen|shaders|switch|package|all]" >&2; exit 2;;
esac
