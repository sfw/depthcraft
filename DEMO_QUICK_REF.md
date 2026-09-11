# Interactive Demo Spike — Quick Reference

## What was built
✅ Sandboxed Three.js demos that run inline with lesson content
✅ Demo directive: `:::demo id="rotating-cube":::` in lesson markdown
✅ Teal Reset/Next controls (Next is placeholder for v0)
✅ Soft-fail to fallback.md when demo can't load
✅ Sample rotating-cube demo in l01-what-is-a-harness
✅ No breaking changes to existing packages

## How it works
1. Lesson markdown is parsed → extracts demo IDs from `:::demo id="...":::` directives
2. Demo loaded from `demos/<id>/` with demo.json manifest
3. WKWebView renders demo HTML via `loadFileURL` (ES module support)
4. **Sandbox:** File URLs scoped to demo directory; all http/https blocked
5. Reset button reloads demo to initial state
6. Falls back to fallback.md (rendered as HTML) on errors

## Sandbox enforcement
- Uses `loadFileURL(_:allowingReadAccessTo:)` for proper ES module support
- Blocks all http/https requests in navigation AND response policies
- URL-scoped allowlist: only file:// URLs within demo directory allowed
- Debug builds log blocked requests
- **Test:** `sandbox-test` demo attempts external fetches; all should fail

## Package structure
```
lessons/<lessonId>/
  lesson.md           ← add :::demo id="...":::
  demos/
    <demoId>/
      demo.json       ← manifest
      index.html      ← entry HTML
      *.js, *.json    ← local assets
      fallback.md     ← error fallback
```

## demo.json schema
```json
{
  "schemaVersion": "0.1.0",
  "demoId": "rotating-cube",
  "title": "3D Coordinate System",
  "kit": "three-v0",
  "entry": "index.html",
  "fallback": "fallback.md"
}
```

## Testing (Mac required)
```bash
cd apps/DepthcraftReader
xcodegen generate
open DepthcraftReader.xcodeproj
# Run on iPad simulator, navigate to l01
```

**Test cases:**
1. **Airplane mode**: Demo loads offline
2. **Sandbox**: Run `sandbox-test` demo → external requests blocked
3. **Soft-fail**: Corrupt demo files → fallback.md shown as HTML
4. **Non-regression**: Open l02 (no demos) → lesson works
5. **Reset**: Tap Reset → cube resets orientation

## Known limitations (v0 spike)
- Kit injection not working (demos self-bundle Three.js)
- Demos shown **below content** (not inline at exact `:::demo:::` position) — **awaiting Product Designer signoff**
- No step navigation
- No error telemetry

## Files
- Views: `DemoHostView.swift`, `LessonContentView.swift`
- Models: `PackageModels.swift` (+DemoManifest)
- Services: `MarkdownHTML.swift` (demo extraction), `PackageLoader.swift` (+demo methods)
- Resources: `demo-kits/three-v0/` (bundled Three.js)
- Sample: `Fixtures/.../demos/rotating-cube/`

## PR
https://github.com/sfw/depthcraft/pull/13
