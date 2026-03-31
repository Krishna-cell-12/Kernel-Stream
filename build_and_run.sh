#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if [[ ! -d "venv" ]]; then
  python3 -m venv venv
fi

source "venv/bin/activate"

python3 -m pip install --upgrade pip
python3 -m pip install -r server/requirements.txt

python3 -m grpc_tools.protoc \
  -Iproto \
  --python_out=server \
  --grpc_python_out=server \
  proto/metrics.proto

make clean
make

echo
echo "Build complete."
echo "Start server with: source venv/bin/activate && python3 server/aggregator.py"
echo "Start agent with:  sudo ./monitor"

