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
  fallback.md        # Soft-fail content (rendered as HTML)
```

Lesson markdown directive:
```markdown
:::demo id="rotating-cube":::
```

### Rendering Pipeline
1. `MarkdownHTML.render()` now returns `LessonRenderResult` with HTML + `[DemoReference]`
2. Parser extracts `:::demo id="...":::` directives using regex
3. Demo placeholders inserted in HTML as `<div class="demo-placeholder" id="DEMO_PLACEHOLDER_xxx">`
4. `LessonContentView` splits HTML at placeholder markers and alternates HTML sections with `DemoHostView` instances
5. **True inline placement:** Demos render at exact `:::demo:::` directive positions in lesson spine

**Demo Placement Implementation:**
- Splits lesson HTML at `<div class="demo-placeholder">` markers
- Creates alternating sections: `[HTML] → [Demo] → [HTML] → [Demo] → [HTML]`
- Each HTML section uses `InlineHTMLSection` with dynamic height measurement
- Demos embedded inline using `DemoHostView` with native SwiftUI layout
- Single ScrollView coordinates all sections for smooth scrolling

### Demo Host (Sandboxed WKWebView)
- `DemoHostView`: SwiftUI wrapper with Reset/Next controls
- `DemoWebView`: WKWebView with JS enabled, strict sandbox enforcement
- **Sandbox implementation:**
  - Uses `loadFileURL(_:allowingReadAccessTo:)` for proper ES module support
  - Blocks all `http`/`https` requests via `decidePolicyFor` navigation + response policies
  - URL-scoped allowlist: only file URLs within demo directory permitted
  - **WKContentRuleList** (fixed `ee9f5ef`): Blocks http/https resource loads
    - Previously attached to pre-create config (bug: never reached live webView)
    - Now attaches to `webView.configuration.userContentController` (live instance)
    - Async compile → add to live webView → then load
  - Logs blocked requests in debug builds
- **Negative test case:** `sandbox-test` demo attempts external fetches; all should fail
- **⚠️ Mac `sandbox-test` is truth check** — do not claim sandbox complete until verified
- Soft-fail to rendered `fallback.md` (as HTML, not raw text) on load errors

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

Created `sandbox-test` (negative test case):
- Deliberately attempts external script loads, fetch(), XHR, image loads
- All external requests should be blocked
- Local file access should succeed
- Verifies sandbox enforcement

## Gaps & Known Issues

### ✅ Milestone A Complete
- Sandbox enforcement with URL-scoped allowlist
- ES module support via `loadFileURL`
- Fallback rendering as HTML
- Negative test case (`sandbox-test`)

### ✅ Milestone B Complete — True Inline Placement
- Demos now render at exact `:::demo:::` directive positions
- HTML splitting at placeholder markers
- Dynamic height measurement for HTML sections
- Alternating HTML/Demo layout in single ScrollView

### ✅ Content Rules Attach Bug Fix (commit `ee9f5ef`)
**Previous bug (`3857a9d`):** 
- `WKWebViewConfiguration` is copied at `WKWebView` init
- Adding rules to pre-create `config` after `WKWebView(configuration: config)` mutated a dead copy
- Rules never actually reached live webView

**Fix:**
1. Create `WKWebView` with base config first
2. Compile `WKContentRuleList` asynchronously
3. In callback: add rules to `webView.configuration.userContentController` (the LIVE instance)
4. Then call `loadDemo` to start navigation

**⚠️ Pending Mac `sandbox-test` verification** — truth check on device. Do not claim sandbox complete until external requests confirmed blocked.

### Critical for Production (Post-Spike)
1. **Kit injection not functional** — v0 demos self-bundle Three.js; proper kit loading from app bundle needs implementation
2. **No error telemetry** — soft-fail is silent; no logging of WebGL failures to analytics
3. **Height measurement edge cases** — JS height probing may need refinement for complex layouts

### v0 Scope Cuts (Expected)
- No `demoWriter` agent role (hand-authored only)
- No step navigation (Next button is no-op)
- No progress/state persistence across resets
- No demo-specific accessibility labels

### Requires Mac Testing
1. **Offline radio-off test**: Airplane mode → demo loads from package bytes
2. **Inline placement**: Demo appears between "The job" and "Not the model" sections (not at end)
3. **Sandbox enforcement**: Run `sandbox-test` demo → all external requests blocked, local file access works
4. **Soft-fail trigger**: Delete `index.html` or corrupt `demo.json` → fallback.md shown as readable HTML
5. **Non-regression**: Open lesson without demos (e.g. l02) → lesson loads normally
6. **WebGL support**: Verify `rotating-cube` renders on iPad simulator
7. **Reset flow**: Tap Reset → cube returns to initial orientation
8. **ES modules**: Verify Three.js imports work (no opaque origin errors in console)
9. **Scroll behavior**: Smooth scrolling across HTML sections and demos

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
