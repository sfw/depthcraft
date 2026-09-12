# Security — Depthcraft Reader (Field Trial)

## Threat Model

Depthcraft Reader is a **field-trial iPad app** for offline course consumption with optional on-device course generation (BYOK). Security posture is scoped to this use case.

### In Scope
- **API keys** (user-provided, BYOK): Anthropic, OpenAI, OpenRouter, custom OpenAI-compatible endpoints
- **Package integrity**: Local `.depthcraft` packages contain lessons (HTML/markdown), quizzes, and interactive demos
- **Demo sandbox**: WebView-hosted 3D demos with app-bundled kits (e.g. Three.js)
- **Local progress**: Device-local course progress by `packageId`

### Out of Scope (v0.1)
- Network services (no accounts, no iCloud, no remote APIs except user-initiated LLM generation)
- Code signing / notarization for distribution (field trial = local build)
- Third-party audits or formal compliance (this is a research prototype)

## What We Guarantee

### P0: Secrets & BYOK
1. **Keychain storage**: API keys stored exclusively in iOS Keychain (service: `dev.depthcraft.reader`)
2. **No leakage**:
   - Keys never written to `UserDefaults`, logs, analytics, crash reports, or packages
   - Settings UI never displays cleartext keys after save (edit shows placeholder only)
   - Error messages never echo raw keys or full `Authorization` headers
3. **Package immutability**: Generated packages contain no keys (validated before commit)

### P0: Demo Sandbox
1. **Network isolation**: Demo WebViews **cannot** make external http(s) requests
   - WKContentRuleList blocks all `http(s)://` resource loads (scripts, images, fetch/XHR)
   - Navigation delegate enforces no http/https navigation
   - Offline-first: demos must work with app-bundled kits + package-local resources only
2. **Kit injection safety**:
   - `kit:` URL scheme serves app-bundled resources only (e.g. `kit:three-v0/three.module.min.js` → `Resources/demo-kits/three-v0/...`)
   - Kit ID allowlist enforced per-demo (manifest must declare `kit`)
   - Path escape protection: blocks `..`, absolute paths, `://` in resource paths
   - Kit ID format validated (alphanumeric + hyphen only)
3. **File access restriction**:
   - Demo WebView can only access files within its own demo directory (`file://` path allowlisted)
   - Entry point validated: must be `.html` within demo directory
   - No access to other app paths, other packages, or user files
4. **Fallback safety**: Markdown fallback WebView has JavaScript **disabled**

### P1: Package Trust & Schema Validation (PR #27)
1. **Schema validation**: All package JSON validated against `schema/0.1.0/*.schema.json` before load
   - `manifest.json`: schema version `0.1.0`, required fields non-empty, `contentVersion ≥ 1`
   - `curriculum.json`: units/lessons non-empty, no duplicate IDs, cross-references valid
   - `quiz.json`: items non-empty, MC has ≥2 choices + valid `correctId`, cloze has ≥1 answer
   - `demo.json`: `demoId`/`kit`/`entry`/`fallback` paths safe and relative
   - **Note**: Schema version hardcoded to `0.1.0` for field trial; future additive changes (e.g. tap-to-explain in Slice A) may require `0.1.x` schema evolution with backward compatibility
2. **Path traversal protection**: Unit/lesson/demo IDs validated before use
   - Safe ID pattern: `^[a-z0-9][a-z0-9-]*$` (lowercase alphanumeric + hyphens)
   - Rejects: `../`, absolute paths (`/`), schemes (`://`), whitespace padding
   - Applied to: unit IDs, lesson IDs, demo IDs, asset paths in loaders
3. **Content version monotonic**: Cannot load older `contentVersion` over newer (explicit error)
4. **Upgrade confirmation**: Version bumps require user approval (modal dialog, no silent swap)

### P1: Content Injection / XSS Protection (PR #27)
1. **Markdown → HTML XSS-safe**:
   - All text content HTML-escaped via `escape()` function (`&` → `&amp;`, `<` → `&lt;`, `>` → `&gt;`)
   - Inline formatting (`**bold**`, `*italic*`, `` `code` ``) wraps escaped text
   - Code blocks escape line content before wrapping in `<pre><code>`
   - Demo ID placeholders HTML-escaped before insertion (defense in depth)
2. **Lesson WebView**: JavaScript **disabled** (`allowsContentJavaScript = false`)
3. **Quiz content**: Rendered with SwiftUI `Text()` views (inherently XSS-safe, no HTML interpretation)
4. **Demo fallback**: Uses safe `renderDemoFallback()` (no lesson eyebrow, JS disabled)

## What We Don't Guarantee

### Deferred to P2 (Post-Field Trial)
- **User package import UI**: Size limits, MIME type checks, signature verification (v0.1 is bundled-only)
- **Telemetry / Analytics**: Audit for PII leakage, user consent (v0.1 has no telemetry)
- **iCloud / Sync**: Encrypted progress data, sync conflict handling (v0.1 is device-local)
- **Accounts / Auth**: Secure token storage, OAuth flows (v0.1 has no server)
- **Rate limiting**: Abuse detection, cost controls (BYOK = user's API provider limits)

### Non-Goals
- App Store review / notarization (field trial = local build)
- Formal audits or penetration testing
- GDPR / CCPA / SOC2 compliance (no accounts, no telemetry, no PII collection)
- Multi-user / enterprise key management (single-device BYOK only)

## Dogfood Checklist (PR Verification)

### P0 Verification (Keychain & Demo Sandbox)
Before accepting P0-related PRs, verify:

- [ ] **Keychain save/load**: Add API keys in Settings → Generate a course → Keys retrieved from Keychain (not cached)
- [ ] **Key masking**: Edit custom endpoint → Existing key shows placeholder, not cleartext
- [ ] **Demo offline**: Open demo in airplane mode → Renders (no network requests)
- [ ] **Demo egress blocked**: Inspect demo WebView → No http(s) requests in debug console
- [ ] **No key leakage**: Generate with bad key → Error message does NOT echo raw key or `Authorization` header
- [ ] **No keys in commits**: `git log -p` this PR → No `sk-`, `Bearer`, or API keys in diffs
- [ ] **No keys in packages**: Generate course → Inspect `.depthcraft/` → No keys in JSON/HTML

### P1 Verification (Schema Validation & XSS)
Before accepting P1-related PRs, verify:

- [ ] **Package validation**: Load bundled package → Should succeed with "✅ Package validated" debug print
- [ ] **Path traversal rejection**: Attempt package with unit ID `../etc` → Should reject with pattern error
- [ ] **Absolute path rejection**: Attempt lesson ID `/var/log` → Should reject as absolute path
- [ ] **Malicious demo ID**: Attempt demo ID `<script>alert(1)</script>` → Should reject as invalid pattern
- [ ] **Quiz validation**: Attempt quiz with `correctId: "nonexistent"` → Should reject with validation error
- [ ] **XSS escaping**: Lesson markdown with `<script>alert(1)</script>` → Should render as escaped text `&lt;script&gt;`
- [ ] **Quiz plain text**: Quiz prompt with HTML → Should display as plain text (no HTML interpretation)
- [ ] **Demo fallback safe**: Demo fallback with HTML → Should render safely without JS execution
- [ ] **Content version downgrade**: Attempt to load older version over newer → Should reject with error
- [ ] **Upgrade dialog**: Load newer version of same package → Should show confirmation modal

## Reporting Security Issues

Field-trial version → Report via GitHub to Lab Partner / Scott:
- For sensitive issues (exploits, key leakage): Use GitHub's private security advisory or contact maintainers directly through GitHub
- For non-sensitive security improvements: Open GitHub issue labeled `needs-lab-partner`

Do NOT open public issues for exploits or key leakage.

## Testing Recommendations (Pre-Production)

Before public release, test:

1. **Malicious Package Payloads:**
   - Path traversal in unit/lesson/demo IDs: `../etc`, `../../`, `/etc/passwd`
   - Invalid schema version: `"schemaVersion": "99.0.0"`
   - Negative contentVersion: `"contentVersion": -1`
   - Duplicate IDs, missing required fields
   - Very large JSON files (DoS via memory)

2. **XSS Attempts:**
   - Lesson markdown with `<script>`, `<iframe>`, `<img onerror>`
   - Quiz prompt with HTML/JS injection
   - Demo ID with special chars: `<img>`, `'; alert(1); '`
   - Unicode homoglyphs or RTL override characters

3. **Demo Sandbox Escape:**
   - Kit path traversal: `kit:three-v0/../../secrets.json`
   - Network requests from demo JS: `fetch('https://evil.com')`
   - File access outside demo dir: `fetch('file:///etc/passwd')`

4. **Package Integrity:**
   - Load curriculum with non-existent lesson ID in unit
   - Quiz with `correctId` not in choices
   - Demo manifest with mismatched `demoId`

## Changelog

### 2026-09-12 — P1 Security Hardening (PR #27)
- ✅ Added `SchemaValidator.swift` for manifest/curriculum/quiz/demo validation
- ✅ Integrated schema validation into `PackageLoader.swift`
- ✅ Added path traversal checks for all unit/lesson/demo ID lookups
- ✅ Verified XSS protection in markdown rendering (escape function)
- ✅ Verified quiz content rendered safely (SwiftUI Text, no HTML)
- ✅ HTML-escaped demo ID placeholders in markdown (defense in depth)
- ✅ Added comprehensive security tests (SecurityValidationTests, MarkdownXSSTests)
- ✅ Updated SECURITY.md with P1 guarantees and dogfood checklist

### Prior to 2026-09-12 — P0 Baseline (PR #26)
- ✅ Keychain storage for BYOK (no plain-text keys)
- ✅ Demo sandbox: kit allowlist, path traversal checks, network blocking
- ✅ Content version monotonic enforcement (no downgrades)
- ✅ Upgrade confirmation dialog (no silent package swap)
