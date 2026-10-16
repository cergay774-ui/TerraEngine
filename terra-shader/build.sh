#!/bin/bash
# Terra Shader: one command build.
#   ./build.sh                 -> setup (first run) + all presets -> build/*.mcpack
#   ./build.sh pack -p android -> only Android
#   ./build.sh mats -s high -m RenderChunk -> quick test build of one preset
cd "$(dirname "$0")" || exit 1
PY=python3
command -v $PY >/dev/null 2>&1 || PY=python
command -v $PY >/dev/null 2>&1 || { echo "Python 3.11+ not found." >&2; exit 1; }

LD_LIBRARY_PATH=./tool/lib $PY tool "$@"
