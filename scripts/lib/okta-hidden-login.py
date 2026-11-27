# ABOUTME: Finishes an AWS SSO login in a hidden (headless) Chromium, with no clicks from a person.
# ABOUTME: Opens the login link that `aws sso login --no-browser` printed, signs in to Diligent Okta
# ABOUTME: with the password from the macOS Keychain, and clicks AWS "Allow access" if it shows.
# ABOUTME: Keeps its own browser profile (~/.aws/okta-hidden-browser) so Okta remembers the device.
# ABOUTME: Exit 0 = callback reached, 3 = needs a person, 4 = password sent but no login, 5 = password expired, 1 = other.
"""Usage: uv run --quiet --with playwright python -I okta-hidden-login.py <login-url>

Keychain item (one time):
  security add-generic-password -U -s aws-sso-okta -a yklin@diligent.com -w
"""

import os
import re
import subprocess
import sys
import time

from playwright.sync_api import sync_playwright

OKTA_USER = os.environ.get("OKTA_USER", "yklin@diligent.com")
KEYCHAIN_SERVICE = "aws-sso-okta"
PROFILE_DIR = os.path.expanduser("~/.aws/okta-hidden-browser")
SHOT = os.path.expanduser("~/Library/Logs/aws-sso-hidden-last.png")
TIMEOUT_SECS = 120
MAX_PASSWORD_TRIES = 2  # a wrong Keychain password must not lock the Okta account
password_sent = False  # set once a password reaches Okta; the caller then skips its Chrome retry


def say(msg):
    """Purpose: print one status line for the caller's log.
    Usage: say("text")
    Gotchas: never pass the password here."""
    print(f"okta-hidden: {msg}", flush=True)


def keychain_password():
    """Purpose: read the Okta password from the macOS Keychain.
    Usage: pw = keychain_password()  # None when the item is missing
    Gotchas: the first read may show a Keychain prompt; pick "Always Allow" once.
      Nobody can answer that prompt while the Mac is locked, so the read times out at 20 s."""
    try:
        out = subprocess.run(
            ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", OKTA_USER, "-w"],
            capture_output=True, text=True, timeout=20)
    except subprocess.TimeoutExpired:
        say("Keychain read timed out (a Keychain prompt may be waiting)")
        return None
    return out.stdout.rstrip("\n") if out.returncode == 0 else None


def visible(page, selector):
    """Purpose: true when the first match of selector is on screen.
    Usage: if visible(page, "input[type=password]"): ...
    Gotchas: returns False instead of raising while the page is mid-navigation."""
    try:
        return page.locator(selector).first.is_visible()
    except Exception:
        return False


def grab_app_link(response, links):
    """Purpose: keep any Okta Verify app link found in Okta's login API replies.
    Usage: page.on("response", lambda r: grab_app_link(r, links))
    Gotchas: the link carries a one-time challenge, so it is never logged."""
    try:
        if "/idp/idx/" not in response.url:
            return
        links.extend(re.findall(r'"((?:com-okta-authenticator|okta-verify):[^"]+)"', response.text()))
    except Exception:
        pass


def run(url):
    """Purpose: drive the login pages until the AWS callback page loads.
    Usage: sys.exit(run(url))
    Gotchas: page steps are matched by what is on screen, not by URL, because Okta and
      AWS change their paths. MFA pages stop the run with exit 3: no person to approve."""
    global password_sent
    password = None
    tries = 0
    user_submits = 0
    fastpass_at = 0
    code = 1
    with sync_playwright() as p:
        # Okta FastPass may call the Okta Verify app on localhost. Chromium blocks
        # public pages from reaching localhost unless these checks are off.
        ctx = p.chromium.launch_persistent_context(PROFILE_DIR, headless=True, args=[
            "--disable-features=BlockInsecurePrivateNetworkRequests,"
            "PrivateNetworkAccessSendPreflights,LocalNetworkAccessChecks"])
        page = ctx.pages[0] if ctx.pages else ctx.new_page()
        app_links = []
        page.on("response", lambda r: grab_app_link(r, app_links))
        page.goto(url)
        deadline = time.time() + TIMEOUT_SECS
        while time.time() < deadline:
            page.wait_for_timeout(1500)
            if page.url.startswith("http://127.0.0.1"):
                say("reached the AWS callback")
                code = 0
                break
            # Page-text checks come first. The "password expired" page has password
            # boxes too, and the old password must never be typed into them.
            try:
                body = page.locator("body").inner_text(timeout=2000).lower()
            except Exception:
                body = ""
            if any(k in body for k in ("password has expired", "change your password", "new password")):
                say("Okta says the password has expired; needs a person")
                code = 5
                break
            later = page.get_by_role("button", name="Remind me later")
            if later.count() and later.first.is_visible():
                say("Okta says the password expires soon; clicking Remind me later")
                later.first.click()
                continue
            # Okta FastPass: the Okta Verify app on this Mac approves the login. A hidden
            # browser cannot launch the app, so hand the button's link to macOS `open`.
            fastpass = page.get_by_text("Open Okta Verify", exact=True)
            if not fastpass_at and fastpass.count() and fastpass.first.is_visible():
                fastpass_at = time.time()
                if app_links:
                    say("Okta FastPass: opening the Okta Verify app link")
                    subprocess.run(["open", app_links[-1]], capture_output=True, timeout=20)  # output may hold the link
                else:
                    say("Okta FastPass: no app link seen; clicking the button")
                    fastpass.first.click()
                continue
            if fastpass_at and time.time() - fastpass_at < 45:
                continue  # give Okta Verify time to answer before calling it MFA
            if any(k in body for k in ("okta verify", "send push", "enter a code", "verification code")):
                say("Okta asks for MFA; needs a person")
                code = 3
                break
            # Okta shows either one page with both fields or a username page first.
            # Password first, so a two-field page never gets a blank-password submit.
            if visible(page, "input[type='password']"):
                if visible(page, "input[name='identifier']"):
                    user_field = page.locator("input[name='identifier']").first
                    if not user_field.input_value():
                        user_field.fill(OKTA_USER)
                if tries >= MAX_PASSWORD_TRIES:
                    say("Okta rejected the Keychain password; stopping")
                    break
                password = password or keychain_password()
                if not password:
                    say(f"no Keychain item {KEYCHAIN_SERVICE}/{OKTA_USER}; needs a person")
                    code = 3
                    break
                tries += 1
                password_sent = True
                say(f"submitting the Okta password (try {tries}/{MAX_PASSWORD_TRIES})")
                field = page.locator("input[type='password']").first
                field.fill(password)
                field.press("Enter")
                page.wait_for_timeout(3000)
                continue
            if visible(page, "input[name='identifier']"):
                if user_submits >= 3:
                    say("Okta keeps asking for the username; stopping")
                    break
                user_submits += 1
                field = page.locator("input[name='identifier']").first
                if not field.input_value():
                    field.fill(OKTA_USER)
                say("submitting the Okta username")
                field.press("Enter")
                page.wait_for_timeout(2000)
                continue
            allow = page.get_by_role("button", name="Allow access")
            if allow.count() and allow.first.is_visible():
                say("clicking AWS Allow access")
                allow.first.click()
                continue
        else:
            say(f"timed out after {TIMEOUT_SECS}s on {page.url.split('?')[0]}")
        if code != 0:
            page.screenshot(path=SHOT)
            say(f"last page saved to {SHOT}")
        ctx.close()
    return code


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    # Log only the error type: Playwright error text can hold the typed password.
    try:
        code = run(sys.argv[1])
    except Exception as e:
        say(f"failed: {type(e).__name__}")
        code = 1
    # Only an unfinished run after a password counts as "refused". MFA (3) means it was right.
    if code == 1 and password_sent:
        code = 4
    sys.exit(code)
