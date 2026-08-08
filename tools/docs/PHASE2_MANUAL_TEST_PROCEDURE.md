# Manual Test Procedure: PJSIP Audio/Media Core (Phase 2)

Exercises the real SIP/media path built in this phase against the
dedicated TLS/SRTP test extension provisioned in Plan 01, on the real
HA-Phone box (`~/projects/Ha-Phone`, Asterisk 22 LTS).

**STATUS AS OF THIS DOCUMENT'S AUTHORING: the TLS transport is NOT YET
LIVE on the box.** Plan 01's `cont-init.d`/`[transport-tls]` changes
(commits `e2666cf`, `2f96ad5` in the `Ha-Phone` repo) are code-complete
locally but have **not been pushed to GitHub or deployed/restarted on
the real Home Assistant add-on box** — that push and the subsequent
container restart are pending user action. Every "place a real call"
step below is therefore **not executable yet**; this document exists
so the procedure is ready to run the moment the box is updated, and
so Task 2 of this plan has a concrete script to hand to the user
rather than an undefined "test it somehow" instruction.

## Test Extension (Plan 01 / Plan 04 / Plan 05)

| Field | Value |
|-------|-------|
| Extension number | `13` |
| SIP password | `L3FP6wuEIj9jp3sC` |
| Host | `192.168.7.10` |
| Transport | TLS, port 5061 |
| Media encryption | SDES |

**Extension-range discrepancy (carried forward from 02-04-SUMMARY.md /
02-05-SUMMARY.md, unresolved as of this writing):** Plan 01's own task
text specifies the dedicated Phase 2 test extension should come from
the 80-99 sub-range (D-04), specifically to avoid colliding with the
active 10-99 household extension range. The extension actually
supplied and wired into both apps' build configs is `13`, which is
**inside** the active 10-99 range. This was not investigated further
by Plans 04/05 (out of scope for app-side work) and remains
unreconciled here too (out of scope for this manual-test-doc-authoring
task). **Before running the codec/registration matrix below, confirm
with the household PBX admin (the user) that extension 13 is genuinely
a safe, dedicated test extension and not an active household line** —
running test calls against a real household extension risks
interference with real incoming calls.

These credentials are recorded here in plaintext for developer/tester
convenience. Per this plan's threat model (T-2-11), this is an
accepted risk scoped to a local-network-only, non-production dev/test
extension — same risk tier as Phase 1's dev-only signing key
documentation, not a production credential.

## CALL-01: Codec + Audio Routing Test Matrix (D-07)

For each codec, temporarily zero out the other 3 codecs' priority
(`Endpoint.codecSetPriority` to 0 for the others, or restrict the test
extension's Asterisk `allow=` list to a single codec for that run) so
negotiation is forced onto the codec under test, then place a real
call and confirm audible, intelligible two-way audio:

| Codec | Direction | Mic | Speaker | Bluetooth | Pass/Fail | Notes |
|-------|-----------|-----|---------|-----------|-----------|-------|
| opus/48000 | MO (outgoing) | | | | | |
| opus/48000 | MT (incoming) | | | | | |
| g722/16000 | MO | | | | | |
| g722/16000 | MT | | | | | |
| pcma/8000 (alaw) | MO | | | | | |
| pcmu/8000 (ulaw) | MO | | | | | |

**If any MT (incoming) row fails to ring/connect at all** (not a codec
or audio-quality failure, but no INVITE ever reaching the device):
SIP registration in this phase is deferred until the user taps Answer
(D-05/CALL-05's transient-registration design), so the original INVITE
may expire before a SIP contact exists to route it to. Check whether
Asterisk's dialplan for this test extension holds/retries the call for
a window comparable to push-wake + registration latency (per
ARCHITECTURE.md Pattern 1, "PBX Holds the Call, Push Is Just a
Doorbell") — a failure here is diagnostic of a hold/retry-timing gap
in the cross-repo Ha-Phone dialplan, not necessarily an app-side
`onIncomingCall`/answer-path defect.

Also exercise: DTMF digits received correctly at an IVR/echo-test
extension (CALL-02); hold + blind transfer to a second working
extension (CALL-04); mid-call WiFi-to-cellular network switch,
confirming audio survives the handoff (CALL-01 stability bar, D-09,
per `Endpoint.handleIpChange`).

## CALL-05: Transient Registration Verification (D-10, corrected per Pitfall 2)

The legacy `chan_sip`-era registry-listing CLI command (removed
entirely on this Asterisk 22 box, since `chan_sip` itself was dropped)
does NOT exist and must never be run. Use instead, via the HA-Phone
add-on's terminal/SSH:

1. Before placing any call: `asterisk -rx "pjsip show contacts"` --
   confirm NO contact exists for the test extension.
2. Place/answer a call from the app.
3. During the call: `asterisk -rx "pjsip show aor 13"`
   and `asterisk -rx "pjsip show endpoint 13"` --
   confirm a contact now exists.
4. End the call.
5. Immediately after: re-run `pjsip show contacts` -- confirm the
   contact is gone again (transient, not persistent).

## Result Log Table

| Date | Platform | Test | Expected | Observed | Pass/Fail | Notes |
|------|----------|------|----------|----------|-----------|-------|
| | android | opus MO | audible both ways | | | Pending: TLS transport not yet live on box |
| | android | g722 MO | audible both ways | | | Pending: TLS transport not yet live on box |
| | android | pcma/pcmu MO | audible both ways | | | Pending: TLS transport not yet live on box |
| | android | DTMF | digits received at PBX | | | Pending: TLS transport not yet live on box |
| | android | hold+transfer | call transfers cleanly | | | Pending: TLS transport not yet live on box |
| | android | network switch | audio survives handoff | | | Pending: TLS transport not yet live on box |
| | android | CALL-05 registration | contact exists only during call | | | Pending: TLS transport not yet live on box |
| | ios | all CALL-01..05 | NOT PERFORMED -- D-15/D-16 Simulator-only gap | n/a | Not performed | Blocked per D-15/D-16 zero-budget constraint; see 02-PHASE-SIGNOFF.md |

## iOS Status (Phase 2)

iOS is verified for Phase 2 ONLY structurally: PJSIP 2.17 builds via
the GitHub Actions macOS runner (Plan 03), SipCallController's unit
tests pass on the iOS Simulator (Plan 05). Per 02-05-SUMMARY.md and
02-07-SUMMARY.md, neither plan's iOS code has actually been confirmed
green on that CI run yet — `ios-ci.yml` has not been re-triggered
against these commits from this sandbox (no `gh` CLI, no push
capability here, same constraint documented in Phase 1's sign-off). No
real device or real audio I/O is exercised on iOS in Phase 2. See
`02-PHASE-SIGNOFF.md` for the full gap documentation and resumption
trigger (D-17/D-18).

## Automated Suite Status (as of this document's authoring)

| Suite | Command | Result |
|-------|---------|--------|
| Android unit tests | `cd android-app && ./gradlew testDebugUnitTest --console=plain` | 24 tests, 0 failures (`CallControlTest` x5, `DialpadSanitizeTest` x4, `NetworkChangeHandlerTest` x1, `EnvelopeVerifierTest` x5, `DtmfControllerTest` x2, `CodecConfigTest` x2, `DialpadTest` x5) |
| HA-Phone backend (cross-repo) | `python3 -m pytest backend/tests/test_api.py backend/tests/test_cont_init_tls.py -x` | 93 passed, 2 skipped, 0 failed (95 collected). Required an isolated venv built from `backend/requirements.txt` — the shared `~/.local` environment's `pydantic==2.5.3` is incompatible with `sqlmodel==0.0.38` (`TypeError: BaseModel.model_dump() got an unexpected keyword argument 'context'`); a scratch venv with a current `pydantic` (2.13.4) resolved it without touching the shared environment or any repo files, per the workaround documented in Plan 01's checkpoint output. |
| iOS unit tests | `xcodebuild test -scheme HAPhoneTestApp -destination 'platform=iOS Simulator,name=iPhone 16'` | NOT RUN -- no Xcode/xcodebuild/Swift toolchain in this Linux sandbox. Structural-only verification per Plan 03/05/07 (grep-based signature checks against real, already-compiled interfaces); real compile/test happens exclusively on Plan 03's GitHub Actions macOS runner, whose live run against these commits is unconfirmed as of this writing (see "iOS Status" above). |
