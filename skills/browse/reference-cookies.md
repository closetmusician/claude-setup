<!-- ABOUTME: browse/reference-cookies.md — Cookie profile setup for browser automation. -->
<!-- ABOUTME: Demoted from skills/setup-browser-cookies/ (unused standalone skill). -->
<!-- ABOUTME: Use when the browse skill needs a specific cookie profile for authenticated sessions. -->
<!-- ABOUTME: This is an auxiliary reference, not a callable skill. -->

# Browser Cookie Profile Setup (Reference)

Parent skill: [browse](/Users/yklin/.claude/skills/browse/SKILL.md)

This document covers setting up cookie profiles for browser automation tasks. Used
when the /browse skill needs to access authenticated sessions.

## CDP mode check

First, check if browse is already connected to the user's real browser:
```bash
$B status 2>/dev/null | grep -q "Mode: cdp" && echo "CDP_MODE=true" || echo "CDP_MODE=false"
```
If `CDP_MODE=true`: tell the user "Not needed — you're connected to your real browser via CDP. Your cookies and sessions are already available." and stop. No cookie import needed.

## How it works

1. Find the browse binary
2. Run `cookie-import-browser` to detect installed browsers and open the picker UI
3. User selects which cookie domains to import in their browser
4. Cookies are decrypted and loaded into the Playwright session

## Steps

### 1. Find the browse binary

Use the standard browse setup block (see [browse/SKILL.md](/Users/yklin/.claude/skills/browse/SKILL.md) §SETUP) to resolve `$B`.

### 2. Open the cookie picker

```bash
$B cookie-import-browser
```

This auto-detects installed Chromium browsers and opens
an interactive picker UI in your default browser where you can:
- Switch between installed browsers
- Search domains
- Click "+" to import a domain's cookies
- Click trash to remove imported cookies

Tell the user: **"Cookie picker opened — select the domains you want to import in your browser, then tell me when you're done."**

### 3. Direct import (alternative)

If the user specifies a domain directly (e.g., `import cookies for github.com`), skip the UI:

```bash
$B cookie-import-browser comet --domain github.com
```

Replace `comet` with the appropriate browser if specified.

### 4. Verify

After the user confirms they're done:

```bash
$B cookies
```

Show the user a summary of imported cookies (domain counts).

## Notes

- On macOS, the first import per browser may trigger a Keychain dialog — click "Allow" / "Always Allow"
- On Linux, `v11` cookies may require `secret-tool`/libsecret access; `v10` cookies use Chromium's standard fallback key
- Cookie picker is served on the same port as the browse server (no extra process)
- Only domain names and cookie counts are shown in the UI — no cookie values are exposed
- The browse session persists cookies between commands, so imported cookies work immediately
