# Local Dark Souls II Switch build

Built on Linux from [MajulaRecomp](https://github.com/hazevauks/MajulaRecomp), tag `ds2-2014-final`, commit `01b6dce9dd6700f71c2d76ba3ff7e759212407c5`.

## Input

- Original Xbox 360 disc: Title ID `465307E4`, Media ID `72EA8B94`, executable version `0.0.0.8`.
- `Default.xex` SHA-256: `fc81381c20292c0a75dd2e99d3a14f583b2671b91c3ba4871f760ea44b50041f`.
- Extraction: 121 files, 6,131,414,015 bytes. The original ISO was left intact.

## Tools and build

- ReXGlue 0.10.0, the modified SDK bundled with the port; host compiler Clang 23.1.1.
- ReXGlue command after the host build: `bash tools/rexglue_linux.sh --version` (loads its local runtime libraries).
- devkitA64 GCC 15.2.0 and libnx, extracted from the official `devkitpro/devkita64` OCI image. The image manifest is saved at `_tools/downloads/devkita64-manifest.json`; downloaded layers were checked against their SHA-256 digests.
- CMake 4.4.5, Ninja 1.13.2, Microsoft DXC 1.9.2609, SPIRV-Cross `vulkan-sdk-1.4.304.0`, and the port's uam source.
- ARM64 Release build, optimized code generation, Renut/deko3d renderer, no NVK driver, no LTO or PGO.

Linux adaptations allow the deko3d-only build without an NVK archive, pass DXC as a single executable, and teach the jump-table audit to follow the optimizer's register-transfer stubs. `tools/build_linux.sh` drives the build; `/tmp/ds2-majula` is an alias that avoids commas and spaces in linker arguments. Tools and game data remain inside this project.

## Preparing a fresh Linux x86-64 checkout

Install Clang with C++23 standard-library support, Python 3.12 or newer, Git, GNU Make, pkg-config, `glslangValidator` (the build script expects `/usr/bin/glslangValidator`), and the development headers needed to build SDL3 on your distribution. The versions above describe the validated machine.

From this checkout's root, download the portable host tools and shader compiler:

```bash
mkdir -p _tools/downloads _tools/bin _tools/dxc
curl -fL https://github.com/Kitware/CMake/releases/download/v4.4.5/cmake-4.4.5-linux-x86_64.tar.gz -o _tools/downloads/cmake.tar.gz
tar -xzf _tools/downloads/cmake.tar.gz -C _tools
curl -fL https://github.com/ninja-build/ninja/releases/download/v1.13.2/ninja-linux.zip -o _tools/downloads/ninja.zip
python3 -c 'import zipfile; zipfile.ZipFile("_tools/downloads/ninja.zip").extractall("_tools/bin")'
chmod +x _tools/bin/ninja
curl -fL https://github.com/microsoft/DirectXShaderCompiler/releases/download/v1.9.2609/linux_dxc_2026_09_28.x86_x64.tar.gz -o _tools/downloads/dxc.tar.gz
tar -xzf _tools/downloads/dxc.tar.gz -C _tools/dxc
mkdir -p app/thirdparty/reblue-XenosRecomp/thirdparty/dxc-bin/bin/x64 app/thirdparty/reblue-XenosRecomp/thirdparty/dxc-bin/lib/x64
cp _tools/dxc/bin/dxc app/thirdparty/reblue-XenosRecomp/thirdparty/dxc-bin/bin/x64/dxc-linux
cp _tools/dxc/lib/libdxcompiler.so _tools/dxc/lib/libdxil.so app/thirdparty/reblue-XenosRecomp/thirdparty/dxc-bin/lib/x64/
git clone --depth 1 --branch vulkan-sdk-1.4.304.0 https://github.com/KhronosGroup/SPIRV-Cross.git _tools/SPIRV-Cross
python3 tools/local_toolchain.py --install
python3 tools/fetch_thirdparty.py
python3 tools/extract_iso.py "/path/to/your/Dark Souls II.iso"
```

`local_toolchain.py` extracts only the Switch development tools from the official devkitPro image, without a Docker daemon or system installation. It downloads the image's current `latest` manifest and records the selected layers; a later image can contain different toolchain versions from the validated build above. It needs internet access and space for the downloaded image and extracted tools.

## Building

To rebuild using the downloaded tools and sources:

```bash
bash tools/build_linux.sh host
bash tools/build_linux.sh codegen
bash tools/build_linux.sh shaders
bash tools/build_linux.sh switch
bash tools/build_linux.sh package
```

The shader stage uses a local Python worker pool; a restricted sandbox may need to permit its local socket.

## Validation and output

- 647 generated files; function-pointer audit registered 83,401 entry points and found no missing vtable entries.
- Jump-table audit: zero truncated tables, wrong targets, or missed tables among the cases it can classify. It also lists unclassified shapes and bounds for review; this is not a proof of complete runtime coverage.
- All 1,481 shader containers translated, and all optimized GLSL outputs passed uam compilation.
- Switch build succeeded. `tools/check_switch_build.py`: all checks passed, entry at zero, optimized code generation, no NVK driver, only the known guest halt, and zero unintended vector fused multiply-adds.
- Staged game filenames and sizes match the extraction.

Executable: `out/nx_dk/ds2.nro`. SD card folder: `out/nx_dk/sdcard/`.

Build output and logs remain local under `out/`. To save a stage's output, redirect it to a log, for example `bash tools/build_linux.sh switch > out/switch-linux.log 2>&1` after creating `out/`.

Switch hardware gameplay, graphics, audio, saves, performance, and stability have not been tested in this session.
