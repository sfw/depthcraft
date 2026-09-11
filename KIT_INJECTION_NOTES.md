# Kit Injection Implementation Notes

## Overview

This PR implements **kit injection** for Depthcraft Reader, allowing generated demos to import app-bundled JavaScript libraries (specifically Three.js v0.170.0) via the `kit:` URL scheme instead of requiring each package to vendor its own copy.

## How It Works

### 1. Custom URL Scheme Handler

Implemented `KitSchemeHandler` (WKURLSchemeHandler) to intercept and serve `kit:` URL requests:

- **Pattern**: `kit:<kitId>/<path>` → `Resources/demo-kits/<kitId>/<path>`
- **Example**: `kit:three-v0/three.module.min.js` → `Resources/demo-kits/three-v0/three.module.min.js`
- **Allowlist**: Only kits specified in `demo.json`'s `kit` field are accessible
- **MIME types**: Automatically determined from file extension (`.js`, `.json`, `.css`, etc.)

### 2. Demo Loading Flow

1. `DemoWebView.makeUIView()` loads the demo's `demo.json` manifest
2. Creates `KitSchemeHandler` with allowlist: `[manifest.kit]`
3. Registers handler: `config.setURLSchemeHandler(kitHandler, forURLScheme: "kit")`
4. Stores `allowedKitId` in Coordinator for potential future validation
5. Demo HTML can now: `import * as THREE from 'kit:three-v0/three.module.min.js'`

### 3. Navigation Policy

Updated `decidePolicyFor navigationAction` to allow three URL schemes:
- `kit:` — Custom scheme for app-bundled kits
- `file:` — Local demo files (scoped to demo directory)
- Block: `http:`, `https:`, and all other schemes

### 4. Soft-Fail Safety Net

Kit failures (missing kit, invalid path, I/O errors) → JavaScript import fails → existing error handlers catch → `onError()` → fallback.md renders in-frame.

## Package Structure

```
Resources/
└── demo-kits/
    └── three-v0/          # Three.js v0.170.0
        ├── three.module.min.js
        └── kit.js         # Optional helper wrapper
```

**Resources/ packaging**: The `demo-kits/` folder is bundled via XcodeGen's `buildPhase: resources` in `project.yml`. No iOS "Resources" naming trap (which can empty Info.plist) because it's under the existing Resources folder structure handled by XcodeGen.

## Allowlist Implementation

Each demo declares its kit dependency in `demo.json`:

```json
{
  "schemaVersion": "0.1.0",
  "demoId": "kit-demo",
  "title": "Kit Injection Test",
  "kit": "three-v0",     // ← Only this kit accessible
  "entry": "index.html",
  "fallback": "fallback.md"
}
```

**Unknown kit** → Scheme handler registers with empty allowlist → kit: imports fail → soft-fail.

## Demo Import Patterns

### Generated Demos (Kit Injection)
```javascript
import * as THREE from 'kit:three-v0/three.module.min.js';
```

### Hand-Authored Demos (Self-Bundled)
```javascript
import * as THREE from './three.module.min.js';
```

**Both patterns work**. The hand-authored `rotating-cube` fixture still bundles `three.module.min.js` locally and loads it via relative path.

## Testing Instructions

### 1. Happy Path: Kit-Injected Demo Renders

**Demo**: `kit-demo` in fixture
**Expected**: Rotating gradient cube renders offline (Wi-Fi off)
**Verify**: Canvas element visible, WebGL rendering, no fallback

### 2. Hand-Authored Demo Still Works

**Demo**: `rotating-cube` in fixture
**Expected**: Original self-bundled cube still renders
**Verify**: Demo loads from `./three.module.min.js`, not kit:

### 3. Sandbox: External CDN Blocked

**Demo**: `sandbox-test` in fixture
**Expected**: All external fetch/script blocked, local files allowed
**Verify**: Test results show ❌ blocked for https://, ✅ allowed for ./

### 4. Soft-Fail: Corrupt Kit Entry

**Test**: Manually break kit file or change demo.json to invalid kit
**Expected**: Demo fails to import → error handler fires → fallback.md renders
**Verify**: Fallback markdown displays in-frame (not black void)

### 5. UI: Reset/Next Visible on Rendered Mesh

**Demo**: Any working demo (kit-demo or rotating-cube)
**Expected**: Teal Reset/Next buttons visible below canvas
**Verify**: Reset button resets cube rotation to 0

### 6. Non-Regression: Lessons Without Demos

**Test**: Navigate to lessons without demos
**Expected**: Lesson content renders normally, no demo-related errors

## Force Soft-Fail for Dogfood

To test soft-fail behavior, corrupt the kit or allowlist:

### Option 1: Break Kit File
```bash
# Rename or delete the kit file in the app bundle
# Resources/demo-kits/three-v0/three.module.min.js
```

### Option 2: Change Demo Manifest to Unknown Kit
```json
{
  "kit": "invalid-kit-id"
}
```

### Option 3: Comment Out Scheme Handler Registration
In `DemoHostView.swift`, temporarily skip `setURLSchemeHandler` call.

Any approach → kit: import fails → fallback.md renders.

## Known Limitations

1. **Single kit version**: Only `three-v0` (v0.170.0) currently bundled
2. **No dynamic kit loading**: Kit must be in app bundle at build time
3. **No kit refresh**: Updating kit requires app rebuild
4. **Offline-only**: No CDN fallback by design (per product requirements)

## Next Steps (Out of Scope)

- Package-vendored kits (if needed for specific demos)
- Kit versioning / migration strategy
- Extend to other libraries (chart.js, d3, etc.)
- demoWriter prompt density improvements
- Tap-to-explain on demo elements
