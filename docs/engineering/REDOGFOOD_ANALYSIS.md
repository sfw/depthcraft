# Mac Re-Dogfood Analysis & Fixes

## What Failed @ `d44bcbc` (Prior "Fixes")

### 1. Sandbox Regression (CRITICAL FAILURE)
**What I tried (`81318b1` → `d44bcbc`):**
- Removed `fetch` and `raw` from content rules resource-type list
- Thought: "Let navigation delegates handle http(s) fetch blocking"

**What actually happened:**
- ❌ External CDN fetch: **ALLOWED** (regression - was blocked before)
- ❌ External XHR: **ALLOWED** (regression - was blocked before)
- ✅ External script/image: Still blocked (content rules)
- ❌ Local `./demo.json` fetch: Still **BLOCKED** (didn't help)

**Why it failed:**
- **Navigation delegates ONLY see navigation requests**, NOT fetch/XHR subresource loads
- Removing `fetch`/`raw` from content rules disabled http(s) blocking for those resource types
- WKWebView's same-origin policy blocks file:// → file:// fetches by default
- So I broke external blocking WITHOUT fixing local fetches

### 2. Cube Still Invisible (NO IMPROVEMENT)
**What I tried (`81318b1`):**
- Deferred Three.js init with `requestAnimationFrame` until container has non-zero dimensions

**What actually happened:**
- Cube still invisible (~8 pixels of face colors, gradient only)
- rAF defer made no difference

**Why it failed (unknown - need data):**
Possible causes:
- Three.js module import blocked by allowlist?
- Container reports non-zero but canvas still 0?
- WebGL context creation failing?
- Canvas not actually appended to DOM?
- Renderer size not applied?
- Z-index/CSS issue hiding canvas?

## Fixes Applied @ `3ddf076`

### 1. Sandbox Fix (CORRECT APPROACH)
**Strategy: Block http(s) for ALL resource types, allow file:// cross-origin**

Changes:
```swift
// 1. RESTORED fetch/raw to content rules
let blockRules = """
[{
    "trigger": {
        "url-filter": "^https?://.*",  // ONLY matches http/https
        "resource-type": ["script", "image", "style-sheet", "font", "fetch", "raw"]
    },
    "action": { "type": "block" }
}]
"""

// 2. ENABLED file:// cross-origin access
config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
```

**Why this works:**
- `url-filter: "^https?://.*"` regex ONLY matches `http://` and `https://` URLs
- `file://` URLs don't match → not blocked by content rules
- `allowFileAccessFromFileURLs` allows `file://` origin to fetch from same `file://` directory
- `allowedDirectory` prefix check in navigation delegate still enforces package-local boundary
- Navigation delegates remain as belt-and-suspenders for http(s)

**Expected result:**
- ❌ External CDN fetch: **BLOCKED**
- ❌ External XHR: **BLOCKED**
- ❌ External script/image: **BLOCKED**
- ✅ Local `./demo.json` fetch: **ALLOWED**

### 2. Cube Debug Instrumentation (DATA COLLECTION)
**Strategy: Don't guess - instrument everything and see where it fails**

Changes:
- Extensive `debugLog()` function that writes to console + visible overlay
- Logs every init step: import, container size, WebGL, renderer, canvas, cube
- Try-catch with `window.webkit.messageHandlers.demoError` reporting
- Visible debug overlay (black bg, green text, top-left) that auto-hides after 3s

**Debug steps logged:**
1. "Module script starting..."
2. "✅ Three.js imported successfully" (or error)
3. "Attempting init: container 0x0" (polling)
4. "✅ Container has size: 375x400"
5. "✅ Scene created"
6. "✅ Camera created"
7. "✅ WebGL renderer created" (or error)
8. "✅ Renderer size set: 375x400"
9. "✅ Pixel ratio set: 2"
10. "✅ Canvas appended to container"
11. "Canvas dimensions: 750x800, style: 375pxx400px"
12. "✅ Cube created and added to scene"
13. "✅ Wireframe edges added"
14. "✅ Camera positioned at z=5"
15. "Starting animation loop..."
16. "🎉 Initialization complete!"

**What Lab Partner needs to do:**
- Screenshot the debug overlay when cube loads
- Report the last successful step before it stops or completes
- If it completes but cube still invisible → different issue (CSS/viewport/clear color)

## Why Prior Approach Failed

### Misconception 1: "Navigation delegates catch everything"
**Wrong.** They only catch:
- Top-level navigation (page loads, redirects)
- iframe navigations
- Form submissions

They do NOT catch:
- `fetch()` API calls
- `XMLHttpRequest`
- Resource loads from `<img>`, `<script>`, `<link>` tags (those are subresources)

Content rules are required to block subresource loads.

### Misconception 2: "Removing resource types from content rules allows file://"
**Wrong.** Content rules use `url-filter` to match which URLs to block. The regex `^https?://.*` already ONLY matches http/https URLs. Adding or removing resource types doesn't change which URLs match - it only changes which types of loads get blocked when the URL matches.

Removing `fetch`/`raw` just disabled blocking for those load types entirely (for all URLs that matched the filter, i.e. http/https).

### Misconception 3: "rAF defer will fix canvas size"
**Insufficient data.** The prior fix assumed the problem was timing (canvas initialized before layout). But with only ~8 pixels visible, it's more likely:
- WebGL context failing
- Module import blocked
- Canvas rendering but hidden
- Or some other issue

Debug instrumentation will reveal the actual failure mode.

## Success Criteria for Re-Dogfood @ `3ddf076`

### Must Pass:
1. **Sandbox:**
   - `sandbox-test` shows: all external blocked + local `./demo.json` allowed
   - No regression from pre-`d44bcbc` behavior

2. **Cube debug:**
   - Debug overlay visible with init steps
   - Lab Partner screenshots and reports last successful step
   - This gives data for targeted fix

### Should Still Pass:
- Inline placement
- Read-intent
- Soft-fail
- Non-regression (l02)
- Xcode 26 compile
- Offline
- Reset
- Scroll

## Next Steps After Re-Dogfood

**If sandbox passes:** ✅ Sandbox done

**If cube debug shows failure point:**
- Module import fail → check allowlist for three.module.min.js
- Container 0x0 → layout timing issue, try different approach
- WebGL fail → check iOS simulator WebGL support, add fallback
- Canvas not appended → DOM structure issue
- Init completes but cube invisible → CSS/viewport/clear color issue

**If cube debug shows "🎉 Initialization complete!" but cube still invisible:**
- Canvas likely rendering but hidden or viewport issue
- Check z-index, canvas position, clear color, camera frustum

Lab Partner provides data → we fix the actual problem, not a guessed problem.
