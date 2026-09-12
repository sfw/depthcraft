# Product Brief (P2): Extend Cancel / First-Open Race

**Status**: ✅ Implementation Complete | 🔲 Dogfood Pending | 🔲 PD Review Pending  
**PR**: [#18 - Fix upgrade dialog race: reliable Cancel + first Open](https://github.com/sfw/depthcraft/pull/18)  
**Branch**: `cursor/fix-upgrade-dialog-race-15c4`

---

## Product Lock: No Silent Auto-Apply ⚠️

### Core Requirement

After extending a course package (producing a newer `contentVersion` for the same `packageId`), first "Open in Reader" **MUST reliably show** the "Course Updated" confirmation dialog.

**No silent auto-apply under any circumstance.**

### The Bug (from Mac dogfood @ 2f945a3)

- **First Open flake**: Sometimes showed dialog, sometimes didn't
- **Cancel partial**: Cancel button didn't fully discard upgrade
- **Second Open worked**: Dialog appeared correctly on retry (but shouldn't need retry)
- **Progress preserve on Apply**: Already working ✅ (don't regress)

---

## Product Requirements

| # | Requirement | Status |
|---|-------------|--------|
| 1 | First Open after producing newer `contentVersion` **reliably** presents confirm dialog | ✅ Fixed |
| 2 | Cancel **reliably** discards pending upgrade; device-local progress unchanged | ✅ Fixed |
| 3 | Apply merges progress by stable IDs; old complete / new incomplete | ✅ Preserved |
| 4 | No silent auto-apply | ✅ Enforced |
| 5 | Add regression test if feasible | ✅ Added (6 tests) |

---

## Dogfood Accept Criteria

### Cancel Path — Must Pass 5/5 Attempts

1. **Setup**:
   - Generate course (creates v1)
   - Complete 2-3 lessons to establish progress
   - Extend course (creates v2 with additional content)

2. **First Open Test**:
   - Tap "Open in Reader" in GenerationView
   - ✅ **"Course Updated" alert appears immediately**
   - ✅ **Alert shows version info: "v2 available, current: v1"**
   - ✅ **Has "Apply Update" and "Cancel" buttons**
   - ❌ **FAIL if alert doesn't show** (this was the bug)

3. **Cancel Test**:
   - Tap "Cancel" button
   - ✅ **Alert dismisses**
   - ✅ **Course home shows old version (v1)**
   - ✅ **New content from v2 NOT visible**
   - ✅ **Progress unchanged** (completed lessons still complete)
   - ✅ **No stuck draft or wrong version**

4. **Retry Test**:
   - Navigate to "Switch Package"
   - Tap v2 package again
   - ✅ **Alert shows again** (user can change their mind)

### Apply Path — Must Pass 5/5 Attempts

1. **Setup**: Same as Cancel Path above

2. **First Open + Apply Test**:
   - Tap "Open in Reader" → alert appears
   - Tap "Apply Update"
   - ✅ **Course home shows new version (v2)**
   - ✅ **Old completed lessons still complete** (progress preserved)
   - ✅ **Old incomplete lessons still incomplete**
   - ✅ **New lessons from v2 added as incomplete**
   - ✅ **Can navigate to all lessons** (old + new)
   - ✅ **No stuck draft or wrong version**

3. **Progress Merge Verification**:
   - Check unit progress bars
   - ✅ **Units with completed lessons show correct progress**
   - ✅ **New units show 0% progress**
   - Navigate to old completed lesson
   - ✅ **Shows green checkmark, "Completed" status**
   - Navigate to new lesson
   - ✅ **No checkmark, "Not started" status**

### Non-Regression — Must Pass

1. **Same Version**:
   - Load v1 twice
   - ✅ **No dialog on second load** (immediate apply, no upgrade)

2. **Different Package**:
   - Load "Course A", then load "Course B"
   - ✅ **No dialog** (different `packageId`, not an upgrade)

3. **Older Version**:
   - Load v2, then try to load v1
   - ✅ **Error message** ("Cannot load older version")
   - ✅ **Stays on v2** (downgrade blocked)

---

## Technical Summary

### Root Cause

SwiftUI alert binding with computed `get`/`set` had race condition:

```swift
// OLD CODE (broken)
.alert("Course Updated", isPresented: .init(
    get: { store.pendingPackageUpgrade != nil },
    set: { if !$0 { store.cancelPackageUpgrade() } }  // ← Called by SwiftUI lifecycle!
))
```

**Problem**: `set` closure invoked during view transitions, clearing upgrade state before alert could display.

### Solution

Explicit state flags managed only by user actions:

```swift
// NEW CODE (fixed)
@Published var showUpgradeDialog = false  // Explicit flag
@Published var pendingPackageUpgrade: LoadedCourse?  // Full course object

.alert("Course Updated", isPresented: $store.showUpgradeDialog)  // Direct binding
```

**Key insight**: Separate "should show dialog" (boolean flag) from "what to show" (pending data). Only set/clear flags via explicit method calls, never via SwiftUI lifecycle.

### State Machine

```
IDLE
  ↓ (loadPackage detects upgrade)
PENDING_UPGRADE (showUpgradeDialog=true, pendingPackageUpgrade=v2)
  ↓ Cancel                    ↓ Apply
IDLE (both cleared)      UPGRADED (applied, both cleared)
```

### Files Changed

- `CourseStore.swift` - State management fix
- `RootView.swift` - Alert binding simplification
- `GenerationTests.swift` - 6 new regression tests

---

## Test Coverage

### Unit Tests Added

`PackageUpgradeTests` class with 6 test cases:

1. ✅ `testFirstOpenAfterExtendShowsDialog` - Dialog triggers reliably
2. ✅ `testCancelDiscardsUpgrade` - Cancel doesn't apply
3. ✅ `testConfirmAppliesUpgradeAndMergesProgress` - Apply + progress merge
4. ✅ `testSecondOpenAfterCancelShowsDialogAgain` - Retry works
5. ✅ `testNoUpgradeDialogForSameVersion` - Same version = no dialog
6. ✅ `testCannotLoadOlderVersion` - Downgrade blocked

**Run**: `xcodebuild test -scheme DepthcraftReader -destination 'platform=iOS Simulator,name=iPad Pro (12.9-inch) (6th generation)'`

### Manual Testing

See `TESTING_GUIDE.md` for step-by-step instructions.

---

## Implementation Details

### State Variables

```swift
// CourseStore.swift

@Published var pendingPackageUpgrade: LoadedCourse?
// Contains full parsed course when upgrade available
// nil = no upgrade pending

@Published var showUpgradeDialog = false
// true = show "Course Updated" alert to user
// false = hide alert
// Only set/cleared by explicit user actions
```

### Key Methods

```swift
func loadPackage(from url: URL) {
    let loaded = try PackageLoader.load(from: url)
    
    // Upgrade detection
    if let current = course,
       current.manifest.packageId == loaded.manifest.packageId,
       loaded.manifest.contentVersion > current.manifest.contentVersion {
        // Newer version of same course
        pendingPackageUpgrade = loaded
        showUpgradeDialog = true  // Show dialog
        return  // Don't auto-apply
    }
    
    // Not an upgrade: apply immediately
    applyPackageLoad(loaded: loaded, url: url)
}

func confirmPackageUpgrade() {
    guard let pending = pendingPackageUpgrade else { return }
    showUpgradeDialog = false  // Hide dialog
    pendingPackageUpgrade = nil  // Clear pending
    applyPackageLoad(loaded: pending, url: pending.rootURL)  // Apply upgrade
}

func cancelPackageUpgrade() {
    showUpgradeDialog = false  // Hide dialog
    pendingPackageUpgrade = nil  // Clear pending
    // Current course unchanged
}

private func applyPackageLoad(loaded: LoadedCourse, url: URL) {
    course = loaded
    progress = progressStore.load(
        packageId: loaded.manifest.packageId,
        lessonIds: Array(loaded.curriculum.lessons.keys),
        unitIds: loaded.curriculum.units.map(\.id)
    )
    // progressStore.load() handles merge: keeps existing completions,
    // adds new lessons/units as incomplete
}
```

### Alert Binding

```swift
// RootView.swift

.alert("Course Updated", isPresented: $store.showUpgradeDialog) {
    Button("Apply Update") {
        store.confirmPackageUpgrade()
    }
    Button("Cancel", role: .cancel) {
        store.cancelPackageUpgrade()
    }
} message: {
    if let pending = store.pendingPackageUpgrade,
       let current = store.course {
        Text("A newer version (v\(pending.manifest.contentVersion)) of \"\(pending.manifest.title)\" is available. Your progress for existing lessons will be preserved, and new content will be added.\n\nCurrent: v\(current.manifest.contentVersion)")
    }
}
```

---

## Edge Cases Handled

1. **App force-quit during pending upgrade**: On restart, loads most recent package (no orphaned state)
2. **Multiple extends in sequence**: Each open triggers dialog if version > current
3. **Background app switch**: Alert remains visible when app returns to foreground
4. **Airplane mode**: All flows work offline (packages are local files)
5. **Same version reload**: No dialog, applies immediately
6. **Different packageId**: No dialog, applies immediately (not an upgrade)
7. **Downgrade attempt**: Error message, blocks load, stays on current version

---

## Non-Goals (Out of Scope)

This PR does **NOT** include:

- New extend features (future)
- Planner changes (separate concern)
- Generate UI redesign (separate concern)
- Tap-to-explain features (separate feature)
- Upgrade changelog/diff view (future enhancement)
- Auto-apply preference setting (future enhancement)
- Persistent upgrade state across restarts (current: ephemeral is OK)
- Multiple pending upgrades queue (current: one at a time is OK)

---

## Merge Checklist

Before merging to `main`:

- [ ] **PD Review**: Product lock verified, accept criteria clear
- [ ] **Mac Dogfood (Cancel)**: 5/5 attempts show dialog, Cancel works
- [ ] **Mac Dogfood (Apply)**: Progress merges correctly, no stuck state
- [ ] **Unit Tests**: All 6 new tests pass
- [ ] **Regression Tests**: Existing course load flows unaffected
- [ ] **Code Review**: Lab Partner approval
- [ ] Remove DRAFT status when all above complete

---

## Related Context

- **Original Implementation**: PR #16 (Opt-in extend/refresh for versioned packages)
- **Bug Report**: Mac dogfood @ 2f945a3 - first Open missed alert
- **Schema**: `manifest.contentVersion` field (integer, v1, v2, etc.)
- **Progress**: Device-local, keyed by `packageId`, merge strategy in `ProgressStore`

---

## Questions for PD Review

1. **Dialog wording**: Is current message clear enough? Should we show a diff/changelog?
2. **Cancel UX**: Should Cancel remember "don't ask again for this version"?
3. **Auto-apply preference**: Future: user setting to skip dialog for trusted generators?
4. **Upgrade indicator**: Should extended package show a badge in "Switch Package" list?
5. **Notification**: Should we add a banner/badge on course home if upgrade available but not opened yet?

---

## Success Metrics

**Definition of Done**:
- 5/5 Mac dogfood attempts: First Open shows dialog reliably
- 5/5 Mac dogfood attempts: Cancel discards without applying
- 5/5 Mac dogfood attempts: Apply preserves progress correctly
- All 6 unit tests pass
- No regressions in existing flows
- PD accepts product lock implementation

**Ready to ship**: When all above metrics met ✅
