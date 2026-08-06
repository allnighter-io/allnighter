# OpenCode Go parser fixtures

This directory holds HTML fixtures for `OpenCodeGoCapacityProbe` and the
related executor / credential-store tests.

## What is here today

Only **synthetic, hand-authored** HTML. The two committed fixtures
(`go-dashboard-ssr.html`, `go-dashboard-dataslot.html`) are stand-ins for the
parser's `solid_ssr_v1` and `data_slot_v1` strategies. They were typed by a
developer; **no credentialed scrape against `opencode.ai/workspace/{id}/go`
has been performed to produce them.** Every fixture carries an unmissable
header comment that says so. Do not mistake those files for captured evidence
of the real dashboard — that confusion is the failure this directory exists
to prevent.

The fixture files in this directory are not test inputs in disguise. They
are the *shape* the parser must handle, expressed in plain HTML. The parser
does not care whether a given fixture was hand-written or captured, but the
reader of this directory must always be able to tell.

**No real captured fixture exists yet.** The first one only gets added when
the founder decides the dogfood gate has earned it.

## Capturing a REAL fixture (when that day comes)

A real fixture is a saved copy of the authenticated `/go` HTML the browser
sees while logged in. It contains the user's own data and therefore can
contain identifying or sensitive information. Capture is always an explicit
local developer action — never an automated step in CI, never a script that
fires from a build, never a side effect of a normal refresh. The following
procedure exists to make that obligation unambiguous.

1. **Trigger.** Only the founder or a developer the founder has explicitly
   named starts a capture. The trigger is a manual `curl` (or a deliberate
   browser "Save Page Source") — not a helper, not a test, not a hook.
2. **Scope.** Capture only the HTML body of the response, not cookies, not
   the full HAR, not network panel output, not screenshot pixels, not any
   file the browser stores. Do not capture the URL bar contents, account
   menu, or anything outside the response body.
3. **Pre-redaction pass.** Before the file is read by anyone else (including
   the author, a few days later), delete:
   - any string that looks like a session cookie value (anything matching
     `auth=...` or another high-entropy token);
   - any workspace id string, unless the founder has confirmed it is OK to
     keep for the fixture;
   - any email address, account name, or user-facing identifier;
   - any URL query parameter that was added by the page itself.
4. **Stays off-repo until reviewed.** The redacted capture lives outside the
   working tree (`~/Downloads`, a private scratch dir, etc.) until the
   founder has eyeballed the file end to end. It does not get committed,
   does not get pasted into chat, does not get attached to a PR description.
5. **Filename.** When reviewed and approved, the file lands here with a name
   that makes its provenance obvious, e.g.
   `go-dashboard-ssr-real-2026-MM-DD.html`. The synthetic files in this
   directory keep their names; the real file is *additive*, never a
   replacement.
6. **Header.** The new file replaces the synthetic header with one that
   states the real capture date, the response status code, the (already
   redacted) final host class, and the strategy id. A template lives at the
   top of the existing synthetic fixtures; copy and adapt it.
7. **Provenance in the test.** The test that consumes the real fixture
   names the file by path and asserts only on the strategy id and the
   parser's structural decisions (e.g. "matches solid_ssr_v1"), never on
   specific values that came from a real account.

## Rules that apply even after a real fixture exists

- **No session cookies, ever.** If a capture contains a cookie value, it
  fails review and is re-taken with cookies stripped. Cookie-shaped
  substrings in a committed fixture file are a stop-the-line condition.
- **No account data, ever.** Workspace ids, emails, plan names, model ids,
  dollar amounts, and reset times from a real account are personal data and
  are not committed. A redacted real fixture is structural only.
- **One capture per real-page change, maximum.** A drift test on the
  captured shape is the value; running the same captured page through
  every test in the suite is just adding more ways for values to leak.
- **Refresh is manual.** When the real page changes, the next capture is
  again a manual local action, not a scheduled job. The synthetic fixtures
  carry the test suite in the meantime; drift between them and reality is
  expected and acceptable until a fresh capture lands.

## What this directory is not

- Not a place to store raw captures for later.
- Not a place to store anything that needs access control.
- Not a place for a generated dump of the live page.
- Not a replacement for SOL review of the parser logic itself.
