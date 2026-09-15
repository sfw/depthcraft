# Home Brand v2 Asset Swap — Status Report

**Branch:** `cursor/home-brand-v2-asset-swap-9418`  
**Base:** `main` @ `b2c2cfe` (PR #75 — Library root + logo→Library)  
**Status:** ⚠️ **BLOCKED** — v2 assets not accessible

## Problem

The v2 nested-frames assets referenced in the task are not present on the filesystem:
- Expected location: `/workspace/depthcraft-icons/home-brand-v2/`
- Files needed: `HomeMark-28@1x/2x/3x-opaque.png`, `ChromeLockup-28@*`, `Depthcraft-HomeMark-512-opaque.png`
- Actual state: Directory exists but is empty (created by this agent)

Cannot complete asset swap without at least the three required scales (@1x/@2x/@3x).

## Current HomeMark Usage (from codebase analysis)

### 1. LibraryView (decorative, non-tappable)
```swift
// Line 29-33
Image("HomeMark")
    .resizable()
    .aspectRatio(contentMode: .fit)
    .frame(height: 28)
    .accessibilityHidden(true)
```

Appears in HStack with "Depthcraft" wordmark text.

### 2. Non-Library screens (tappable toolbar buttons → Library)

Logo buttons in toolbar on:
- **CourseHomeView** (line 351)
- **GenerationView** (line 68)
- **SettingsView** (line 74)
- **UnitView** (line 70)
- **QuizFlowView** (line 29, custom logoButton property)

All use same pattern:
```swift
.toolbar {
    ToolbarItem(placement: .topBarLeading) {
        Button {
            navigationPath.wrappedValue.removeAll()  // → Library
        } label: {
            Image("HomeMark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 28)
        }
    }
}
```

### Tap Target Compliance

✅ All logo buttons use SwiftUI `Button`, which enforces system minimum 44×44pt tap target.  
✅ Visual mark is 28pt (per spec), hit area is automatically expanded by SwiftUI.

No custom `contentShape` or hit-area padding needed — current implementation already complies with ≥44pt requirement.

## Asset Target Location

**Xcode imageset:** `/workspace/apps/DepthcraftReader/Assets.xcassets/HomeMark.imageset/`

**Current Contents.json:**
```json
{
  "images" : [
    { "filename" : "HomeMark-28@1x-opaque.png", "idiom" : "universal", "scale" : "1x" },
    { "filename" : "HomeMark-28@2x-opaque.png", "idiom" : "universal", "scale" : "2x" },
    { "filename" : "HomeMark-28@3x-opaque.png", "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

**Current v1 dimensions:**
- `HomeMark-28@1x-opaque.png` — 28×28 px
- `HomeMark-28@2x-opaque.png` — 56×56 px
- `HomeMark-28@3x-opaque.png` — 84×84 px

## Implementation Plan (once assets available)

### Step 1: Replace PNG files
```bash
cd /workspace/apps/DepthcraftReader/Assets.xcassets/HomeMark.imageset/

# Backup v1
mkdir -p ~/Desktop/depthcraft-v1-backup
cp HomeMark-28@*.png ~/Desktop/depthcraft-v1-backup/

# Copy v2 opaque variants (maintain exact filenames)
cp /workspace/depthcraft-icons/home-brand-v2/HomeMark-28@1x-opaque.png .
cp /workspace/depthcraft-icons/home-brand-v2/HomeMark-28@2x-opaque.png .
cp /workspace/depthcraft-icons/home-brand-v2/HomeMark-28@3x-opaque.png .
```

Verify v2 dimensions match v1 (28px, 56px, 84px) or are proportionally correct for 28pt height.

### Step 2: Optional — Chrome lockup consideration

**Current:** LibraryView and CourseHomeView (empty state) show `Image("HomeMark") + Text("Depthcraft")` side-by-side.

**Option:** If AD provided `ChromeLockup` imageset (mark+wordmark as single asset):
1. Create new `ChromeLockup.imageset` in Assets.xcassets
2. Replace HStack in LibraryView line 28-37 with single `Image("ChromeLockup")`
3. Preserve 28pt height, remove Text("Depthcraft")

**Recommendation:** Only if lockup improves kerning/balance vs. current Image+Text combo. Otherwise SKIP (current is fine).

### Step 3: No code changes needed

- Navigation behavior stays identical (PR #75 wiring preserved)
- Hit areas already compliant (SwiftUI Button minimum)
- Accessibility already correct (`accessibilityHidden(true)` for decorative mark)

### Step 4: Dogfood on Mac iPad simulator

```bash
cd apps/DepthcraftReader
xcodegen generate
open DepthcraftReader.xcodeproj
# Select iPad Pro simulator, ⌘R
```

**Verify:**
1. Library: v2 mark displays at 28pt, no layout shift
2. Course Home: v2 mark displays at 28pt, no layout shift
3. All toolbar logo buttons: v2 mark visible, tappable → Library
4. Settings About: verify no HomeMark reference (only version text)

### Step 5: Commit, push, create draft PR

```bash
git add apps/DepthcraftReader/Assets.xcassets/HomeMark.imageset/
git commit -m "Swap home brand to v2 nested-frames opaque assets"
git push -u origin cursor/home-brand-v2-asset-swap-9418
# ManagePullRequest: create_pr, draft=true
```

## Out of Scope (per task spec)

- ❌ App icon (AppIcon.appiconset)
- ❌ Library shelf course cards (no branding on cards currently)
- ❌ Reopening #75 nav architecture
- ❌ Changing logo→Library behavior

## Questions for Lab Partner (if needed)

1. Can v2 PNG files be provided via alternate method (direct upload, external URL, git branch)?
2. Should chrome lockup be introduced, or keep current Image+Text HStack?

---

**Next Step:** Provide v2 asset files at `/workspace/depthcraft-icons/home-brand-v2/` or specify alternate delivery method.
