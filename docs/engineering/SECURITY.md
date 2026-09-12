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

## What We Don't Guarantee

### Not Yet Hardened (P1 / deferred)
- **Package validation**: Path-traversal / schema validation for malicious `.depthcraft` packages (user controls package imports in v0.1)
- **XSS in lessons/quizzes**: Lesson/quiz content rendered as-is; no CSP or sanitization (trusted-content model for field trial)
- **Extend security**: Extend feature is UX-gated (confirmation modal) but not crypto-signed

### Non-Goals
- App Store review / notarization (field trial = local build)
- Formal audits or penetration testing
- GDPR / CCPA / SOC2 compliance (no accounts, no telemetry, no PII collection)
- Multi-user / enterprise key management (single-device BYOK only)

## Dogfood Checklist (PR Verification)

Before accepting this PR, verify:

- [ ] **Keychain save/load**: Add API keys in Settings → Generate a course → Keys retrieved from Keychain (not cached)
- [ ] **Key masking**: Edit custom endpoint → Existing key shows placeholder, not cleartext
- [ ] **Demo offline**: Open demo in airplane mode → Renders (no network requests)
- [ ] **Demo egress blocked**: Inspect demo WebView → No http(s) requests in debug console
- [ ] **No key leakage**: Generate with bad key → Error message does NOT echo raw key or `Authorization` header
- [ ] **No keys in commits**: `git log -p` this PR → No `sk-`, `Bearer`, or API keys in diffs
- [ ] **No keys in packages**: Generate course → Inspect `.depthcraft/` → No keys in JSON/HTML

## Reporting Security Issues

Field-trial version → Report to Scott (scott@depthcraft.dev) or Lab Partner (GitHub issue labeled `needs-lab-partner`).

Do NOT open public issues for exploits or key leakage.
