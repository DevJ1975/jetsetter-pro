---
name: phase-verify
description: Run after completing any development phase or discrete unit of work on JetSetter Pro. Builds the app, runs unit tests, and debugs any failures BEFORE the phase is considered done or work moves on. Invoke automatically whenever a phase/commit-sized chunk of implementation is finished.
---

# Phase Verify

The standing rule for this project: **a phase is not "done" until it builds clean,
its unit tests pass, and any failure has been triaged.** Never move to the next
phase (or report success) on unverified code. Run this whole procedure at the end
of every completed phase.

## 1. Build (compile the whole target)

Use a **raw `xcodebuild`** simulator build, NOT the Xcode-driven `BuildProject`
MCP tool. The Xcode-driven build blanks `DEVELOPMENT_TEAM` (`8V5XV2A6KE` → "") in
`project.pbxproj` while Xcode is open, which dirties the tree. Raw `xcodebuild`
leaves the pbxproj untouched.

```
xcodebuild -project "JetSetter Pro.xcodeproj" -scheme "JetSetter Pro" \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

A quick single-file sanity check while iterating: `XcodeRefreshCodeIssuesInFile`
(fast, live diagnostics) — but it is NOT a substitute for a full build.

## 2. Unit test

Prefer the Testing framework via the xcode-tools MCP: `RunAllTests` (or
`RunSomeTests` scoped to the phase's area). CLI equivalent:

```
xcodebuild -project "JetSetter Pro.xcodeproj" -scheme "JetSetter Pro" \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
```

**If no test target exists yet** (currently true — the app ships with 0 tests;
creating the `JetSetter ProTests` target is Part 0 of the queued test-suite epic
and is GUI-only): do NOT silently skip. Instead:
- State plainly that there is no test target, so automated unit tests can't run.
- Fall back to `RunCodeSnippet` to exercise the phase's new logic directly
  (this is how persistence atomicity was proven — 150/150, 201/201 no lost
  updates), and describe what you verified.
- Flag that real coverage is blocked until the test target is created.

## 3. Debug failures

If the build or any test fails: **stop and fix it before continuing.** Read the
actual error (`GetBuildLog` / `XcodeListNavigatorIssues` for build failures; the
test output for assertion failures), form a hypothesis, fix, and re-run steps 1–2
until green. Do not paper over a failure or defer it to "later."

## 4. Report honestly

End with a one-line verdict per the project's reporting rule:
- ✅ what built and passed (with counts, e.g. "build clean, 12/12 tests pass"), or
- ❌ what failed, with the real output — never claim green on unverified code.
- Note anything that was skipped and why (e.g. "no test target → RunCodeSnippet only").

## Project gotchas (don't relearn these)

- Keep `DEVELOPMENT_TEAM = 8V5XV2A6KE`. Never let a build blank it.
- Do NOT edit `project.pbxproj` while Xcode is open — hand target/capability
  changes to the user (GUI-only in this objectVersion-77 synchronized-folder project).
- Money/booking paths (Duffel/Apple Pay/Stripe) can't be run end-to-end without a
  deployed proxy + Merchant ID + sandbox creds — verify what you can and say what
  you couldn't.
