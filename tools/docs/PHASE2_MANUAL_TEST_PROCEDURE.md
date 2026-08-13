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
| SIP password | see `android-app/local.properties` (`SIP_TEST_PASSWORD`) or `ios-app/Secrets.xcconfig` (`SIP_TEST_PASSWORD`) -- both gitignored, never committed |
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

**Security correction (code review CR-1):** an earlier revision of this
document recorded the SIP password in plaintext, and that revision was
pushed to this repo's public GitHub remote -- this is a real,
currently-live credential for the real HA-Phone box, not a disposable
value scoped to this repo's own risk tier. T-2-11's "accepted risk"
framing conflated a dev-only *public verification key* (safe to embed
by design, Phase 1 precedent) with a live PBX *account password* (never
safe to commit, public repo or not). **The password must be rotated on
the real box before this procedure is run again** -- it should be
treated as compromised the moment it was pushed, regardless of whether
this document itself gets corrected. Once rotated, update the gitignored
build-config files referenced above with the new value; do not put the
new password back into this file or any other tracked file.

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

**UPDATE (this document's original authoring, 2026-08-08, predates the
result below; corrected here rather than left stale):** Plan 03's Task
3 checkpoint is now **RESOLVED**. `build-test` on GitHub Actions is
green end-to-end (PJSIP build, XcodeGen, app build+link, AND unit
tests) as of commit `d6b623e7` --
https://github.com/iron-exx/ha-phone-app/actions/runs/31588437266/job/94087580778.
This is real compile+link+test proof, not the structural/grep-only
verification this document originally described.

That debugging session also permanently disabled the Opus codec for
iOS (`PJMEDIA_HAS_OPUS_CODEC 0` in
`ios-app/HAPhoneTestApp/Sip/config_site.h`): Homebrew's `opus` is a
macOS-native build and cannot link into an iOS/iOS-Simulator binary
regardless of CPU arch. PJSIP's own bundled codecs (G.711/PCMU/PCMA,
GSM, iLBC, Speex) remain available on iOS; G.722 availability on iOS
depends on PJSIP's own bundled codec set (not Opus-dependent) and was
not otherwise touched. **This means the CALL-01 codec matrix above is
Android-only for Opus in practice** — iOS builds without Opus until a
from-source iOS libopus cross-compile is done as a separate, explicitly
deferred task. See `02-PHASE-SIGNOFF.md` for the full gap documentation.

iOS remains verified for Phase 2 ONLY at the build+unit-test level:
PJSIP 2.17 builds via the GitHub Actions macOS runner (Plan 03) and
`SipCallControllerTests`/`NetworkChangeHandlerTests`/`DialedNumberStateTests`
pass on the iOS Simulator (Plans 05/07), now confirmed by a real green
CI run rather than structural checks alone. No real device or real
audio I/O is exercised on iOS in Phase 2 -- that remains a separate,
zero-budget-constrained gap (D-15/D-16). See `02-PHASE-SIGNOFF.md` for
the full gap documentation and resumption trigger (D-17/D-18).

## Automated Suite Status (as of this document's authoring)

| Suite | Command | Result |
|-------|---------|--------|
| Android unit tests | `cd android-app && ./gradlew testDebugUnitTest --console=plain` | 24 tests, 0 failures (`CallControlTest` x5, `DialpadSanitizeTest` x4, `NetworkChangeHandlerTest` x1, `EnvelopeVerifierTest` x5, `DtmfControllerTest` x2, `CodecConfigTest` x2, `DialpadTest` x5) |
| HA-Phone backend (cross-repo) | `python3 -m pytest backend/tests/test_api.py backend/tests/test_cont_init_tls.py -x` | 93 passed, 2 skipped, 0 failed (95 collected). Required an isolated venv built from `backend/requirements.txt` — the shared `~/.local` environment's `pydantic==2.5.3` is incompatible with `sqlmodel==0.0.38` (`TypeError: BaseModel.model_dump() got an unexpected keyword argument 'context'`); a scratch venv with a current `pydantic` (2.13.4) resolved it without touching the shared environment or any repo files, per the workaround documented in Plan 01's checkpoint output. |
| iOS unit tests | `xcodebuild test -scheme HAPhoneTestApp -destination 'platform=iOS Simulator,name=iPhone 16'` | Cannot run directly in this Linux sandbox (no Xcode/xcodebuild/Swift toolchain). **Superseded by a real result:** GitHub Actions' macOS-runner `build-test` job ran this exact `xcodebuild test` step for real and is green on commit `d6b623e7` -- https://github.com/iron-exx/ha-phone-app/actions/runs/31588437266/job/94087580778 (see "iOS Status" above). This is the authoritative iOS build+test proof for Phase 2, not the grep-based structural checks Plans 03/05/07 originally relied on. |

**Re-confirmation (this execution session, 2026-08-12):** Android suite re-run clean (`./gradlew testDebugUnitTest --console=plain`, `BUILD SUCCESSFUL`, 24/24 tests passing per `app/build/test-results/testDebugUnitTest/TEST-*.xml`); HA-Phone backend suite re-run clean via the same scratch-venv workaround (93 passed, 2 skipped, 0 failed) -- both suites reproduce the counts recorded above with no regressions since this document's original authoring.
