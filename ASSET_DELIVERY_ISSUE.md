# Asset Delivery Issue

## Problem

The v2 asset files referenced in the system message are not accessible on the filesystem:

**System message claimed files saved to:**
```
1. /workspace/depthcraft-icons/home-brand-v2/HomeMark-28@1x-opaque.png
2. /workspace/depthcraft-icons/home-brand-v2/HomeMark-28@2x-opaque.png
3. /workspace/depthcraft-icons/home-brand-v2/HomeMark-28@3x-opaque.png
4. /workspace/depthcraft-icons/home-brand-v2/ChromeLockup-28@1x-opaque.png
5. /workspace/depthcraft-icons/home-brand-v2/ChromeLockup-28@2x-opaque.png
6. /workspace/depthcraft-icons/home-brand-v2/ChromeLockup-28@3x-opaque.png
```

**Actual filesystem state:**
```bash
$ ls -la /workspace/depthcraft-icons/home-brand-v2/
total 12
drwxr-xr-x 2 ubuntu ubuntu 4096 Sep 15 02:40 .
drwxr-xr-x 3 ubuntu ubuntu 4096 Sep 15 02:39 ..
-rw-r--r-- 1 ubuntu ubuntu 1896 Sep 15 02:40 README.md
```

No PNG files present.

**Checked locations:**
- ✗ `/workspace/depthcraft-icons/home-brand-v2/` — empty except README
- ✗ `/cursor/stores/` FUSE mount — empty artifacts directory  
- ✗ `/tmp/` — no recent PNG uploads
- ✗ `/home/ubuntu/` — no matching files
- ✗ Entire workspace — only old v1 assets exist in Assets.xcassets

## Workaround Options

### Option 1: Git Push (Recommended)
Push PNG files directly to branch `cursor/home-brand-v2-asset-swap-9418`:

```bash
# On local machine with v2 assets:
git clone https://github.com/sfw/depthcraft
cd depthcraft
git checkout cursor/home-brand-v2-asset-swap-9418

# Copy v2 assets
mkdir -p depthcraft-icons/home-brand-v2
cp /path/to/HomeMark-28@1x-opaque.png depthcraft-icons/home-brand-v2/
cp /path/to/HomeMark-28@2x-opaque.png depthcraft-icons/home-brand-v2/
cp /path/to/HomeMark-28@3x-opaque.png depthcraft-icons/home-brand-v2/
cp /path/to/ChromeLockup-28@1x-opaque.png depthcraft-icons/home-brand-v2/
cp /path/to/ChromeLockup-28@2x-opaque.png depthcraft-icons/home-brand-v2/
cp /path/to/ChromeLockup-28@3x-opaque.png depthcraft-icons/home-brand-v2/

git add depthcraft-icons/home-brand-v2/*.png
git commit -m "Add v2 nested-frames brand assets"
git push origin cursor/home-brand-v2-asset-swap-9418
```

Agent will detect push and continue with swap.

### Option 2: External URL
Provide download URLs (Dropbox, GitHub gist, etc.) and agent can fetch with curl/wget.

### Option 3: Base64 Inline
Paste base64-encoded PNG data in PR comment, agent can decode and write.

## What's Ready

All implementation logic is prepared and documented in `ASSET_SWAP_STATUS.md`:

1. ✅ Target imageset location identified
2. ✅ Current usage locations mapped  
3. ✅ Tap target compliance verified (SwiftUI Button already ≥44pt)
4. ✅ Swap procedure documented
5. ✅ No code changes needed (image swap only)

**Estimated time once files available:** ~5 minutes
- Copy 3 PNG files to Assets.xcassets/HomeMark.imageset/
- Optionally add ChromeLockup.imageset
- Commit, push, update PR

## Current State

**Branch:** `cursor/home-brand-v2-asset-swap-9418`  
**Status:** BLOCKED on asset file delivery  
**PR:** [#76](https://github.com/sfw/depthcraft/pull/76) (draft)

Waiting for v2 PNG files via one of the options above.
