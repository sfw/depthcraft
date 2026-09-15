# Home Brand v2 Assets (Nested Frames)

## Required Assets for Asset Swap

The following v2 assets are needed to complete the home brand asset swap:

### Toolbar Mark (Primary Use)
- `HomeMark-28@1x-opaque.png` — 28×28px for @1x displays
- `HomeMark-28@2x-opaque.png` — 56×56px for @2x displays (most iPad Pro)
- `HomeMark-28@3x-opaque.png` — 84×84px for @3x displays

### Chrome Lockup (Optional, if replacing mark+wordmark combinations)
- `ChromeLockup-28@1x-opaque.png`
- `ChromeLockup-28@2x-opaque.png`
- `ChromeLockup-28@3x-opaque.png`

### Reference
- `Depthcraft-HomeMark-512-opaque.png` — master 512px source for generating scales
- `_compare-v1-v2-28@3x.png` — before/after comparison

## Current Status

**Assets NOT YET AVAILABLE** — The image files were referenced but not found on disk.

## Target Location

Once available, assets should be copied to:
```
/workspace/apps/DepthcraftReader/Assets.xcassets/HomeMark.imageset/
```

Replacing the existing v1 files:
- HomeMark-28@1x-opaque.png
- HomeMark-28@2x-opaque.png
- HomeMark-28@3x-opaque.png

## Design Specifications (from AD README)

- Height: **22–28pt** (prefer **28pt** for iPad)
- Clear space: ≥0.5× mark height
- Tap target: **≥44pt** (visual may be 28pt, expand hit area as needed)
- Format: **Opaque** variants on warm paper chrome (`#F5F0E6`)
- Wordmark ink: `#1C1917` (never teal lettermark)

## Implementation Notes

Current usage locations (from PR #60):
1. **LibraryView** — HomeMark top leading, 28pt height, decorative
2. **CourseHomeView** — HomeMark top leading, 28pt height, decorative
3. Both use `Image("HomeMark").resizable().aspectRatio(contentMode: .fit).frame(height: 28)`

Logo→Library tap behavior added in PR #75 — preserve that navigation wiring.

---

**Next Step:** Place v2 PNG files in this directory, then run asset swap script or manually copy to Assets.xcassets.
