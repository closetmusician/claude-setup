-- ABOUTME: Presses Return on a Diligent Okta sign-in tab in Google Chrome.
-- ABOUTME: Chrome's password manager has already filled the form; Return submits it.
-- ABOUTME: Uses a real key press because Chrome hides autofilled passwords from page JS.
-- ABOUTME: Prints one word: pressed, none, notfront. Needs Accessibility permission.
-- ABOUTME: Called by scripts/aws-sso-boards-refresh.sh during an SSO login.

-- Purpose: find the Okta sign-in tab, bring it to the front, press Escape then Return.
-- Usage: osascript scripts/lib/okta-submit.applescript
-- Gotchas: Escape closes Chrome's autofill drop-down first. The key press only happens
--   after a re-check that Chrome is frontmost on the Okta tab, so keys never go elsewhere.
--   Prints notfront when the screen is locked or another app is in front.
--   A locked screen swallows key presses, so targetReady() checks the lock before each key.
on run
	set found to false
	tell application "Google Chrome"
		repeat with w in windows
			set i to 0
			repeat with t in tabs of w
				set i to i + 1
				if (URL of t starts with "https://diligent.okta.com/") and (title of t contains "Sign In") then
					set active tab index of w to i
					set index of w to 1
					set found to true
					exit repeat
				end if
			end repeat
			if found then exit repeat
		end repeat
		if not found then return "none"
		activate
	end tell
	delay 1

	if not targetReady() then return "notfront"
	tell application "System Events" to key code 53 -- Escape
	delay 0.3
	if not targetReady() then return "notfront"
	tell application "System Events" to key code 36 -- Return
	return "pressed"
end run

-- Purpose: true when the screen is unlocked and Chrome is frontmost on the Okta tab.
-- Usage: if not targetReady() then return "notfront"
-- Gotchas: called again right before each key, so a focus change or lock in the
--   delays stops the press. macOS may omit the lock key when unlocked, so a missing key = unlocked.
on targetReady()
	set lockState to do shell script "ioreg -n Root -d1 -a | plutil -extract IOConsoleUsers.0.CGSSessionScreenIsLocked raw - 2>/dev/null || true"
	if lockState is "true" then return false
	tell application "System Events" to set frontApp to name of first process whose frontmost is true
	if frontApp is not "Google Chrome" then return false
	tell application "Google Chrome" to set frontURL to URL of active tab of front window
	return frontURL starts with "https://diligent.okta.com/"
end targetReady
