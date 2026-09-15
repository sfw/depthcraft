# Classify Demo Test Fixture

This test fixture verifies that ClassifyBins handles various item formats without rendering `[object Object]`.

## Test Cases

1. **Items with `text` property** (standard format)
   - Should display the text value

2. **Items with `label` property** (fallback)
   - Should display the label value

3. **Items with only `id`** (edge case)
   - Should display the id value instead of `[object Object]`

4. **String items** (simple format)
   - Should display the string directly

## Expected Behavior

All chips should display human-readable text. None should show `[object Object]`.

## How to Test

Open this demo in the DepthcraftReader app and verify:
- ✅ All chips show readable labels
- ✅ No `[object Object]` appears
- ✅ Classification and checking work correctly
