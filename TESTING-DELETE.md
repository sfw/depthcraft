# Testing Guide: Library Course Delete

## Setup (Mac)

```bash
cd apps/DepthcraftReader
brew install xcodegen  # if not already installed
xcodegen generate
open DepthcraftReader.xcodeproj
```

Select iPad simulator → Run (⌘R)

## Prerequisites

Ensure you have multiple courses in Library for thorough testing:
1. Import or generate at least 2-3 test courses
2. Open one course and interact with it (progress, notes)
3. Return to Library

## Test Cases

### 1. Cancel Delete (Verify No Action)

**Steps:**
1. In Library, long-press on any course card
2. Select "Delete Course" from context menu
3. Modal sheet appears with:
   - Red warning icon
   - "Delete Course" title
   - Course title displayed (read-only, should wrap if long)
   - Permanent warning text
   - "Type DELETE to confirm" label + text field
   - "Delete Course" button (disabled/grayed out)
   - "Cancel" button
4. Type something other than "DELETE" (e.g., "delete", "test")
5. Verify "Delete Course" button remains disabled
6. Tap "Cancel" or toolbar cancel button
7. **EXPECT**: Modal dismisses, course remains in Library, no data lost

### 2. Delete Non-Active Course

**Steps:**
1. In Library, identify which course is active (has teal left border)
2. Long-press on a DIFFERENT course card
3. Select "Delete Course" from context menu
4. In modal, type exactly: `DELETE` (all caps)
5. Verify "Delete Course" button becomes enabled (red, prominent)
6. Tap "Delete Course"
7. **EXPECT**: 
   - Modal dismisses
   - Deleted course removed from Library shelf
   - Active course unchanged
   - App remains stable
   - No crash or UI issues

### 3. Delete Active Course

**Steps:**
1. In Library, identify the active course (teal left border / most recent)
2. Long-press on that course card
3. Select "Delete Course" from context menu
4. Type exactly: `DELETE`
5. Tap "Delete Course"
6. **EXPECT**:
   - Modal dismisses
   - Deleted course removed from Library
   - Library remains visible (empty state or remaining courses)
   - No crash or navigation trap
   - If you navigate to another course, it loads cleanly

### 4. Delete All Courses (Empty Library)

**Steps:**
1. Delete all courses from Library one by one
2. **EXPECT**:
   - Library shows empty state gracefully
   - Import/Generate buttons still accessible
   - No crash or trap

### 5. Verify Data Cleanup

**After deleting a course:**
1. Check that progress for that packageId is cleared (device-local UserDefaults)
2. Check that notes for that packageId are cleared
3. Verify package directory removed from Documents
4. Import or generate the same course again
5. **EXPECT**: Fresh state (no old progress/notes)

### 6. Seriousness Gate Verification

**Steps:**
1. Open delete modal
2. Try each of these inputs:
   - Empty field → button disabled
   - `delete` (lowercase) → button disabled
   - `Delete` (mixed case) → button disabled
   - `DEL` (partial) → button disabled
   - `DELETE` (exact) → button ENABLED ✅
3. Verify only exact `DELETE` enables the button

## Edge Cases

### Long Course Titles
- Test with a course that has a very long title
- Verify title wraps properly in modal (read-only)
- Verify no truncation or overflow issues

### Context Menu on iPad
- Test long-press gesture on iPad simulator
- Verify context menu appears correctly
- Verify menu item labels and icons are clear

### Keyboard Behavior
- Modal should auto-focus the text field
- Keyboard should appear on iPad
- Autocapitalization should be enabled (helps with DELETE entry)
- Verify no autocorrect interference

## Acceptance Criteria (from Brief)

✅ From Library, user can start delete on a course  
✅ Gate requires typing `DELETE` before destructive confirm enables  
✅ Title shown read-only  
✅ After delete, course gone from shelf  
✅ App stable (no trap on missing package)  
✅ Cancel leaves course intact  

## Known Limitations (v1)

- ❌ No delete from course home overflow menu (out of scope for v1)
- ❌ No bulk delete
- ❌ No undo/recycle bin
- ❌ No cloud sync tombstones
- ❌ Bundled/how-to courses not auto-reinstalled after delete (per Scott lock)
