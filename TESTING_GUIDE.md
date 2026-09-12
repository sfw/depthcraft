# Upgrade Dialog Testing Guide

## Quick Summary

This PR fixes the race condition where:
1. First "Open in Reader" after extend sometimes missed the "Course Updated" alert
2. Cancel button only partially worked

## Manual Testing Steps (Mac Dogfood)

### Test 1: First Open Shows Dialog
1. Open DepthcraftReader on iPad simulator
2. Generate a course (e.g., "AI Safety Basics")
3. Let it complete and note it's at v1
4. Tap "Back" to return to course home
5. Tap "Generate" and select "Extend Course"
6. Let extend complete (this creates v2)
7. **Tap "Open in Reader"**
8. ✅ **Expected**: "Course Updated" alert appears immediately
   - Shows: "A newer version (v2) of [title] is available..."
   - Has "Apply Update" and "Cancel" buttons
9. ❌ **Bug (before fix)**: Alert doesn't show, silently stays on v1

### Test 2: Cancel Discards Upgrade
1. Follow Test 1 steps 1-8 to get the alert showing
2. **Tap "Cancel"**
3. ✅ **Expected**: 
   - Alert dismisses
   - Still on v1 (check version in course list or via Settings)
   - Progress unchanged
   - New v2 content NOT visible
4. ❌ **Bug (before fix)**: Partial state corruption

### Test 3: Cancel Then Reopen Shows Dialog Again
1. Follow Test 2 to cancel the upgrade
2. Go to "Switch Package" view
3. **Tap on the v2 package again**
4. ✅ **Expected**: "Course Updated" alert shows again
5. This time you can choose Apply or Cancel again

### Test 4: Apply Updates Course and Merges Progress
1. Start with a course on v1
2. **Mark 2-3 lessons as complete** (take quizzes and pass them)
3. Extend the course (creates v2 with additional lessons)
4. Tap "Open in Reader" → alert appears
5. **Tap "Apply Update"**
6. ✅ **Expected**:
   - Course updates to v2
   - Previously completed lessons still show as complete
   - New lessons appear as incomplete
   - All your progress is intact
   - Can navigate through both old and new lessons

### Test 5: Progress Merge Verification
1. After applying update from Test 4
2. Go to course home
3. Check unit progress bars
4. Navigate to a lesson you completed in v1
5. ✅ **Expected**: Shows green checkmark, "Completed" status
6. Navigate to a new lesson added in v2
7. ✅ **Expected**: No checkmark, "Not started" status

## Automated Test Coverage

Run the test suite:
```bash
xcodebuild test -scheme DepthcraftReader -destination 'platform=iOS Simulator,name=iPad Pro (12.9-inch) (6th generation)'
```

The following tests verify the fix:

### `PackageUpgradeTests.testFirstOpenAfterExtendShowsDialog`
- Creates v1 course, loads it, marks progress
- Creates v2 course, attempts to load it
- Asserts `showUpgradeDialog == true`
- Asserts `pendingPackageUpgrade != nil`
- Asserts current course still v1 (not applied yet)

### `PackageUpgradeTests.testCancelDiscardsUpgrade`
- Loads v1, marks progress, triggers v2 upgrade
- Calls `cancelPackageUpgrade()`
- Asserts dialog hidden, pending cleared
- Asserts still on v1 with original progress

### `PackageUpgradeTests.testConfirmAppliesUpgradeAndMergesProgress`
- Loads v1 with 3 lessons, completes 2
- Triggers v2 upgrade with 5 lessons
- Calls `confirmPackageUpgrade()`
- Asserts now on v2 with 5 lessons
- Asserts lessons 1-2 still complete
- Asserts lessons 3-5 incomplete (3 was incomplete, 4-5 are new)

### `PackageUpgradeTests.testSecondOpenAfterCancelShowsDialogAgain`
- Triggers upgrade, cancels it
- Attempts to load v2 again
- Asserts dialog shows again

### `PackageUpgradeTests.testNoUpgradeDialogForSameVersion`
- Loads v1 twice
- Asserts no dialog on second load

### `PackageUpgradeTests.testCannotLoadOlderVersion`
- Loads v2 first
- Attempts to load v1
- Asserts error message about older version
- Asserts stays on v2

## Edge Cases to Verify

1. **App restart**: If upgrade alert is shown, user force-quits app → on restart, should show most recent package (no orphaned pending state)
2. **Multiple extends**: v1 → v2 → v3 where user cancels v2 but then opens v3 directly
3. **Background app switch**: Show alert, switch to another app, switch back → alert should still be visible
4. **Airplane mode**: All upgrade flows should work offline since packages are local

## Known Limitations

- Downgrade (v2 → v1) is blocked with an error message (by design)
- Same version (v1 → v1) applies immediately without dialog (no upgrade needed)
- Different package IDs always load immediately (they're separate courses)

## Files Changed

- `apps/DepthcraftReader/Sources/Services/CourseStore.swift`
  - Added `showUpgradeDialog` flag
  - Changed `pendingPackageUpgrade` to store `LoadedCourse?`
  - Updated state management in confirm/cancel

- `apps/DepthcraftReader/Sources/Views/RootView.swift`
  - Changed alert binding to use `$store.showUpgradeDialog` directly

- `apps/DepthcraftReader/Tests/GenerationTests.swift`
  - Added `PackageUpgradeTests` test class with 6 test cases
