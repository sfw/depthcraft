#!/usr/bin/env bash
set -euo pipefail
# This file lives at depthcraft-icons/home-brand-v2-delivery/
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$ROOT/apps/DepthcraftReader/Assets.xcassets/HomeMark.imageset"
SRC="$ROOT/depthcraft-icons/home-brand-v2-delivery"
mkdir -p "$DEST"
for f in HomeMark-28@1x-opaque.png HomeMark-28@2x-opaque.png HomeMark-28@3x-opaque.png; do
  base64 -d < "$SRC/$f.b64" > "$DEST/$f"
  echo "wrote $DEST/$f ($(wc -c < "$DEST/$f") bytes)"
done
cd "$ROOT"
python3 - <<'PY2'
from pathlib import Path
try:
    from PIL import Image
except ImportError:
    Image = None
dest = Path("apps/DepthcraftReader/Assets.xcassets/HomeMark.imageset")
expect = {
    "HomeMark-28@1x-opaque.png": ((28, 28), 1069),
    "HomeMark-28@2x-opaque.png": ((56, 56), 2046),
    "HomeMark-28@3x-opaque.png": ((84, 84), 2802),
}
for name, (size, nbytes) in expect.items():
    raw = (dest / name).read_bytes()
    assert len(raw) == nbytes, (name, len(raw), nbytes)
    if Image is not None:
        im = Image.open(dest / name)
        assert im.size == size, (name, im.size, size)
        print(f"OK {name} {im.size} {len(raw)} bytes")
    else:
        print(f"OK {name} {len(raw)} bytes (PIL missing, size check skipped)")
PY2
