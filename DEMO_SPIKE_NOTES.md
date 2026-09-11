# Interactive Demo v0 Engineering Spike

## Summary
Implements sandboxed interactive Three.js demos inline with lesson content. Demos are optional, hand-authored, package-local, and soft-fail to fallback markdown on errors.

## Implementation

### Schema & Models (0.1.x additive)
- Added `DemoManifest` model (`demo.json` schema)
- Extended `PackageLoader` with `demoManifest()` and `demoDirectory()` methods
- No breaking changes to existing package structure

### Package Structure
```
lessons/<lessonId>/demos/<demoId>/
  demo.json          # schemaVersion, demoId, title, kit, entry, fallback
  index.html         # Entry point
  three.module.min.js # Bundled Three.js (or other assets)
  fallback.md        # Soft-fail content
```

Lesson markdown directive:
```markdown
:::demo id="rotating-cube":::
```

### Rendering Pipeline
1. `MarkdownHTML.render()` now returns `LessonRenderResult` with HTML + `[DemoReference]`
2. Parser extracts `:::demo id="...":::` directives using regex
3. Demo placeholders inserted in HTML for positioning (currently unused in v0)
4. `LessonContentView` shows lesson WebView + demos stacked vertically

### Demo Host (Sandboxed WKWebView)
- `DemoHostView`: SwiftUI wrapper with Reset/Next controls
- `DemoWebView`: WKWebView with JS enabled, network blocked
- Loads demo from package-local `baseURL` (offline by design)
- Soft-fail to `fallback.md` on load errors or missing WebGL

### Reset/Next Controls
- **Reset**: UUID-based `key` forces full WebView reload → initial state
- **Next**: Placeholder button (teal, no-op in v0) for future step navigation
- Both styled in teal per product spec

### Demo Kit (Provisional)
- `Resources/demo-kits/three-v0/` contains Three.js v0.170.0
- Kit bundled with app (not vendored into packages)
- Package `demo.json` declares `"kit": "three-v0"`
- v0: demos self-bundle Three.js in demo dir; kit injection is a placeholder

### Non-Regression
- Lessons without `:::demo:::` directives render as before (simple `LessonWebView`)
- Existing text+quiz packages unaffected
- `renderResult.demos.isEmpty` check routes to legacy path

## Sample Demo
Created `rotating-cube` in `l01-what-is-a-harness`:
- Colorful 3D cube rotating on multiple axes
- Demonstrates Three.js scene/camera/renderer pattern
- Self-contained with bundled `three.module.min.js`
- Fallback explains WebGL requirement

## Gaps & Known Issues

### Critical for Production
1. **Kit injection not functional** — v0 demos self-bundle Three.js; proper kit loading from app bundle needs work
2. **Demo positioning approximate** — demos shown after lesson content, not inline at exact directive location
3. **WebView height heuristics** — fixed layout may clip content
4. **No error telemetry** — soft-fail is silent; no logging of WebGL failures

### v0 Scope Cuts (Expected)
- No `demoWriter` agent role (hand-authored only)
- No step navigation (Next button is no-op)
- No progress/state persistence across resets
- No demo-specific accessibility labels

### Requires Mac Testing
1. **Offline radio-off test**: Airplane mode → demo loads from package bytes
2. **Soft-fail trigger**: Delete `index.html` or corrupt `demo.json` → fallback.md shown
3. **Non-regression**: Open lesson without demos (e.g. l02) → lesson loads normally
4. **WebGL support**: Verify Three.js renders on iPad simulator
5. **Reset flow**: Tap Reset → cube returns to initial orientation

## Files Changed
- Models: `PackageModels.swift` (+DemoManifest)
- Services: `PackageLoader.swift` (+demo methods), `MarkdownHTML.swift` (demo extraction)
- Views: `DemoHostView.swift` (new), `LessonContentView.swift` (new), `LessonPlayerView.swift` (refactor)
- Resources: `demo-kits/three-v0/` (Three.js bundle)
- Fixture: `l01-what-is-a-harness/demos/rotating-cube/`
- Config: `project.yml` (Resources folder)

## Next Steps (Post-Spike)
1. Fix kit injection: load `kit.js` from app bundle, inject into demo HTML
2. Improve demo positioning: parse HTML and embed demos at exact placeholder locations
3. Add WebGL capability detection before demo load
4. Implement step navigation API for multi-step demos
5. Schema evolution: consider 0.2 cut if demo features become non-optional
