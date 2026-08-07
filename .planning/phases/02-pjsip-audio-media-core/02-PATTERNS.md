# Phase 2: PJSIP Audio/Media Core - Pattern Map

**Mapped:** 2026-08-04
**Files analyzed:** 24 (13 app-side new/modified, 4 cross-repo Ha-Phone, 3 test files, 2 docs, 1 CI, 1 build-config note)
**Analogs found:** 20 / 24 (4 no-analog: net-new PJSIP glue with no codebase precedent)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `android-app/.../test/sip/PjsuaEndpointHolder.kt` | service | event-driven | `android-app/.../test/CallRegistration.kt` | role-match |
| `android-app/.../test/sip/SipCallController.kt` | service | request-response | `android-app/.../test/CallRegistration.kt` | role-match |
| `android-app/.../test/DialpadComposable.kt` | component | request-response | `android-app/.../test/IncomingCallActivity.kt` (Composable) | role-match |
| `android-app/.../test/ActiveCallActivity.kt` (new screen) | component | request-response | `android-app/.../test/IncomingCallActivity.kt` | exact |
| `android-app/.../test/OutgoingCallActivity.kt` (new screen) | component | request-response | `android-app/.../test/IncomingCallActivity.kt` / `MainActivity.kt` | exact |
| `android-app/.../test/CallRegistration.kt` (MODIFIED — extend `onRegistered`) | service | event-driven | itself (existing `reportIncomingCall`) | exact |
| `android-app/app/src/test/.../sip/CodecConfigTest.kt` | test | transform | `android-app/app/src/test/.../EnvelopeVerifierTest.kt` | role-match |
| `android-app/app/src/test/.../sip/DtmfControllerTest.kt` | test | event-driven | `android-app/app/src/test/.../EnvelopeVerifierTest.kt` | role-match |
| `android-app/app/src/test/.../sip/DialpadTest.kt` | test | transform | `android-app/app/src/test/.../EnvelopeVerifierTest.kt` | role-match |
| `android-app/app/src/test/.../sip/CallControlTest.kt` | test | transform | `android-app/app/src/test/.../EnvelopeVerifierTest.kt` | role-match |
| `ios-app/HAPhoneTestApp/Sip/PjsuaBridge.mm/.h` | service | event-driven | — none in repo — | no-analog |
| `ios-app/HAPhoneTestApp/Sip/SipCallController.swift` | service | request-response | `ios-app/HAPhoneTestApp/PushHandler.swift` | role-match |
| `ios-app/HAPhoneTestApp/Sip/AudioSessionCoordinator.swift` | service | event-driven | `ios-app/HAPhoneTestApp/CallProvider.swift` | role-match |
| `ios-app/HAPhoneTestApp/DialpadView.swift` | component | request-response | `ios-app/HAPhoneTestApp/DiagnosticsView.swift` | role-match |
| `ios-app/HAPhoneTestApp/ActiveCallView.swift` (new screen) | component | request-response | `ios-app/HAPhoneTestApp/DiagnosticsView.swift` | role-match |
| `ios-app/HAPhoneTestApp/OutgoingCallView.swift` (new screen) | component | request-response | `ios-app/HAPhoneTestApp/DiagnosticsView.swift` | role-match |
| `ios-app/HAPhoneTestApp/CallProvider.swift` (MODIFIED — `didActivate`/`didDeactivate`) | service | event-driven | itself (existing `CallProviderDelegate`) | exact |
| `ios-app/HAPhoneTestAppTests/SipCallControllerTests.swift` | test | transform | `ios-app/HAPhoneTestAppTests/PushHandlerTests.swift` | exact |
| `~/projects/Ha-Phone/ha-phone/backend/models.py` (MODIFIED — `Extension.transport`/`.media_encryption`) | model | CRUD | itself (`Trunk.transport`, same file) | exact |
| `~/projects/Ha-Phone/ha-phone/backend/routers/extensions.py` (MODIFIED — pass new fields through) | controller/route | CRUD | itself (`create_extension`/`update_extension`, same file) | exact |
| `~/projects/Ha-Phone/ha-phone/backend/conf_templates/pjsip_extensions.conf.j2` (MODIFIED — add `media_encryption`) | config/template | transform | `~/projects/Ha-Phone/ha-phone/backend/conf_templates/pjsip_trunk.conf.j2` (transport conditional) | exact |
| `~/projects/Ha-Phone/ha-phone/rootfs/etc/cont-init.d/10-asterisk-init.sh` (MODIFIED — cert gen + `[transport-tls]`) | config/script | file-I/O | itself (AMI secret + externip/`pjsip_local.conf` blocks, same file) | exact |
| `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md` | test (manual doc) | — | `tools/docs/MANUAL_TEST_PROCEDURE.md` | exact |
| `.planning/phases/02-.../02-PHASE-SIGNOFF.md` | config (doc) | — | `.planning/phases/01-.../01-PHASE-SIGNOFF.md` | exact |
| `.github/workflows/ios-ci.yml` (MODIFIED — add PJSIP build step) | config (CI) | batch | itself (existing job, same file) | exact |

## Pattern Assignments

### `android-app/.../test/sip/PjsuaEndpointHolder.kt` (service, event-driven)

**Analog:** `android-app/app/src/main/java/de/haphone/app/test/CallRegistration.kt`

**Imports pattern** (lines 1-11):
```kotlin
package de.haphone.app.test

import android.content.Context
import android.net.Uri
import android.telecom.DisconnectCause
import androidx.core.telecom.CallAttributesCompat
import androidx.core.telecom.CallControlScope
import androidx.core.telecom.CallsManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
```
For the new `sip/` package, mirror this exactly but import PJSUA2 (`org.pjsip.pjsua2.Endpoint`/`Account`/`EpConfig`) instead of `androidx.core.telecom`.

**Ownership/lifecycle pattern** (lines 30-36): a single class wraps the external SDK's top-level manager object as a `private val`, exposes a plain `registerApp()`-style init method, and keeps a `CoroutineScope` for anything the underlying API requires off the calling thread:
```kotlin
class CallRegistration(private val context: Context) {
    private val callsManager = CallsManager(context)
    private val scope = CoroutineScope(Dispatchers.Default)

    fun registerApp() {
        callsManager.registerAppWithTelecom(CallsManager.CAPABILITY_BASELINE)
    }
```
`PjsuaEndpointHolder` should follow this exact shape: one `Endpoint` instance owned for the app process lifetime (per RESEARCH.md's "tied to app process lifetime" note), a plain `init()`/`start()` method calling `Endpoint.libCreate()`/`libInit()`/`libStart()`, and codec priorities set here (RESEARCH.md Code Examples: `endpoint.codecSetPriority("opus/48000", 255)` etc.) — this is the natural place for the CALL-01 codec-list assertion Pitfall 3 calls for.

**Doc-comment convention** (lines 13-29, 38-52): every non-obvious API quirk (positional vs named lambda args, suspend vs non-suspend) gets a block comment above the class/method explaining *why*, citing the specific research section. Continue this for PJSUA2's own API quirks (e.g. the `Call::acc` `Account*` vs `Account&` breaking change RESEARCH.md Pitfall 1 flags).

---

### `android-app/.../test/sip/SipCallController.kt` (service, request-response)

**Analog:** same file, `reportIncomingCall` method (lines 53-75)

**Core pattern** — a public method takes a plain data parameter, does the SDK call, and exposes a scoped callback receiver so the caller can act on the result without threading concerns:
```kotlin
fun reportIncomingCall(callId: String, onRegistered: CallControlScope.() -> Unit) {
    val attributes = CallAttributesCompat(
        displayName = "HA-Phone Testanruf",
        address = Uri.parse("haphone:$callId"),
        direction = CallAttributesCompat.DIRECTION_INCOMING,
        callType = CallAttributesCompat.CALL_TYPE_AUDIO_CALL,
    )
    scope.launch {
        callsManager.addCall(
            attributes, { }, { _: DisconnectCause -> }, { }, { },
        ) {
            onRegistered()
        }
    }
}
```
Apply the same shape for each of `makeCall()`, `answer()`, `hold()`, `xfer()`, `sendDtmf()` — one small public method per CALL-0x operation, wrapping the equivalent PJSUA2 `Call`/`CallOpParam` call (RESEARCH.md Code Examples section has the exact C++/PJSUA2 call signatures to port: `call.setHold(prm)`, `call.xfer(uri, prm)`, `call.sendDtmf(dtmfParam)`).

**Integration point (CR-01 precedent — disconnect-on-failure):** `CallRegistration.reportIncomingCall`'s callback receiver deliberately exposes `disconnect()` (via `CallControlScope`) so a caller that detects a problem (there: forged/expired push envelope; here: failed SIP INVITE/negotiation) can end the call itself rather than ringing forever. `SipCallController`'s `answer()` path should thread the same `CallControlScope` through so a SIP negotiation failure can call `disconnect()` — this is explicitly called out as the integration point in 02-CONTEXT.md's Integration Points section.

---

### `android-app/.../test/DialpadComposable.kt` / new Active/Outgoing Call screens (component, request-response)

**Analog:** `android-app/app/src/main/java/de/haphone/app/test/IncomingCallActivity.kt` (whole file, 62 lines)

**Screen structure pattern** (lines 26-42):
```kotlin
class IncomingCallActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val callId = intent.getStringExtra("callId").orEmpty()
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    IncomingCallScreen(
                        callId = callId,
                        onAnswer = { finish() },
                        onDecline = { finish() },
                    )
                }
            }
        }
    }
}
```
**Composable pattern** (lines 44-62) — plain stateless `@Composable` function taking primitive/lambda params, `Column`/`Row` + `Arrangement.spacedBy`/`padding` using the `.dp` grid already established (matches 02-UI-SPEC.md's Spacing Scale, which explicitly cites this file's `padding(32.dp)`/`Arrangement.spacedBy(16.dp)` as the precedent):
```kotlin
@Composable
private fun IncomingCallScreen(callId: String, onAnswer: () -> Unit, onDecline: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text("HA-Phone Testanruf")
        Row(
            modifier = Modifier.padding(top = 24.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Button(onClick = onDecline) { Text("Decline") }
            Button(onClick = onAnswer) { Text("Answer") }
        }
    }
}
```
`DialpadComposable` (3×4 grid per UI-SPEC) and the new Active/Outgoing Call Activities should follow this exact `ComponentActivity` + `MaterialTheme { Surface { ... } }` + private stateless `@Composable` screen function shape — no new architectural pattern needed, just more buttons/rows. Bind the Audio Routing row to `CallControlScope.availableEndpoints`/`currentCallEndpoint` per RESEARCH.md Pattern 2 (never `AudioManager` directly).

---

### `ios-app/HAPhoneTestApp/Sip/SipCallController.swift` (service, request-response)

**Analog:** `ios-app/HAPhoneTestApp/PushHandler.swift` (whole file, 96 lines)

**Protocol-abstraction-for-testability pattern** (lines 5-19) — every platform-framework dependency is wrapped in a small protocol so tests can inject a mock, rather than depending on the concrete `CXProvider`/`CXCallController` type directly:
```swift
protocol IncomingCallReporting {
    func reportNewIncomingCall(with uuid: UUID, update: CXCallUpdate, completion: @escaping (Error?) -> Void)
}
extension CXProvider: IncomingCallReporting {}

protocol CallEnding {
    func endCall(uuid: UUID)
}
struct CXCallControllerEnder: CallEnding {
    let controller = CXCallController()
    func endCall(uuid: UUID) {
        let action = CXEndCallAction(call: uuid)
        controller.request(CXTransaction(action: action)) { _ in }
    }
}
```
`SipCallController` should wrap the PJSUA2 `Call`/`Account`/`Endpoint` C++ objects (via the `PjsuaBridge` Obj-C++ layer) behind a similar small Swift protocol per operation (e.g. `SipCalling { func makeCall(uri: String); func hold(); func xfer(to: String); func sendDtmf(digit: String) }`), so `SipCallControllerTests.swift` can inject a mock bridge exactly the way `PushHandlerTests.swift` injects `MockCallReporter`/`MockCallEnder`.

**Dependency-injected init pattern** (lines 25-36):
```swift
final class PushHandler: NSObject, PKPushRegistryDelegate {
    private let callReporter: IncomingCallReporting
    private let callEnder: CallEnding
    private let diagnosticsLog: DiagnosticsLogging
    private let verifierPublicKeyHex: String

    init(callReporter: IncomingCallReporting, callEnder: CallEnding, diagnosticsLog: DiagnosticsLogging, verifierPublicKeyHex: String) {
        self.callReporter = callReporter
        self.callEnder = callEnder
        self.diagnosticsLog = diagnosticsLog
        self.verifierPublicKeyHex = verifierPublicKeyHex
    }
```
Same shape for `SipCallController`'s init — inject the bridge, not construct it internally.

**Testable-entry-point-for-un-constructible-platform-types pattern** (lines 66-71) — where a real platform type has no public initializer for tests (`PKPushPayload`, `PKPushCredentials`), the plan extracts a plain-Swift-typed entry point (`handleIncomingPush(dict:completion:)`) that both the real delegate method and the test call directly. PJSUA2's own callback types (e.g. `onCallTransferStatus` overrides) may hit the same constraint — plan for a plain-typed shim entry point the same way.

---

### `ios-app/HAPhoneTestApp/Sip/AudioSessionCoordinator.swift` / `CallProvider.swift` (MODIFIED) (service, event-driven)

**Analog:** `ios-app/HAPhoneTestApp/CallProvider.swift` (whole file, 27 lines — existing, to be extended)

```swift
import CallKit

enum CallProviderFactory {
    static func makeProvider() -> CXProvider {
        let configuration = CXProviderConfiguration(localizedName: "HA-Phone Test")
        configuration.supportsVideo = false
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        return CXProvider(configuration: configuration)
    }
}

final class CallProviderDelegate: NSObject, CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {}
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        action.fulfill()
    }
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        action.fulfill()
    }
}
```
Phase 2 adds the two audio-session delegate methods this Phase-1 placeholder never implemented — `provider(_:didActivate:)` / `provider(_:didDeactivate:)` — and that is exactly where `AudioSessionCoordinator` plugs in (RESEARCH.md Pattern 2 code example):
```swift
func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    try? audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
}
```
Keep `CallProviderDelegate`'s existing `action.fulfill()`-per-action shape for the new `CXSetHeldCallAction`/`CXPlayDTMFCallAction`/`CXTransferCallAction` handlers CALL-02/04 need — same one-method-per-action pattern already established for answer/end.

---

### `ios-app/HAPhoneTestApp/DialpadView.swift` / new Active/Outgoing Call SwiftUI views (component, request-response)

**Analog:** `ios-app/HAPhoneTestApp/DiagnosticsView.swift` (whole file, 79 lines)

**SwiftUI screen-struct pattern** (lines 9-64) — `@State`-backed `View` struct, `NavigationView { List { Section(...) { ... } } }`, `.toolbar`, `.onAppear`:
```swift
struct DiagnosticsView: View {
    @State private var logLines: [String] = []
    var body: some View {
        NavigationView {
            List {
                Section("Current VoIP Token") { ... }
                Section("Log") { ... }
            }
            .navigationTitle("Diagnostics")
            .toolbar { ... }
            .onAppear(perform: reload)
            .refreshable { reload() }
        }
    }
}
```
This is the only real SwiftUI screen precedent in the codebase (role-match, not exact — it is a list/log view, not a call-control grid), but it establishes the project's SwiftUI conventions to reuse: plain system styling (`List`, `NavigationView`, no custom design system — matches 02-UI-SPEC.md's "plain SwiftUI system styling" scope note), `@State` for local UI state, and a `private func reload()`-style helper for state refresh. `DialpadView` (3×4 `LazyVGrid` per UI-SPEC's grid spec) and the new `ActiveCallView`/`OutgoingCallView` should follow this same struct shape and reuse `AVRoutePickerView` (RESEARCH.md Supporting Libraries — iOS) for the audio-routing control specifically, per UI-SPEC's "prefer `AVRoutePickerView` over a custom picker" instruction.

---

### Test files: `SipCallControllerTests.swift`, `CodecConfigTest.kt`, `DtmfControllerTest.kt`, `DialpadTest.kt`, `CallControlTest.kt`

**iOS Analog:** `ios-app/HAPhoneTestAppTests/PushHandlerTests.swift` (lines 1-60 read)
```swift
private final class MockCallReporter: IncomingCallReporting {
    private(set) var callOrder: [String] = []
    private(set) var reportedUUIDs: [UUID] = []
    func reportNewIncomingCall(with uuid: UUID, update: CXCallUpdate, completion: @escaping (Error?) -> Void) {
        callOrder.append("reportNewIncomingCall")
        reportedUUIDs.append(uuid)
        completion(nil)
    }
}
final class PushHandlerTests: XCTestCase {
    private func makeHandler(reporter: MockCallReporter, ender: MockCallEnder, log: MockDiagnosticsLog) -> PushHandler {
        PushHandler(callReporter: reporter, callEnder: ender, diagnosticsLog: log, verifierPublicKeyHex: publicKeyHex)
    }
    func testWellFormedPayloadReportsImmediately() { ... }
}
```
Pattern: private mock classes conforming to the protocols above, recording call order + arguments in arrays, a `makeX(...)` test-fixture factory method, `XCTestCase` subclass with descriptively-named `test...` methods. `SipCallControllerTests` should define a `MockSipBridge` the same way and assert `sendDtmf`/`makeCall`/`setHold`/`xfer` were invoked with the correct arguments — no live PJSUA2/network calls in the unit test (Simulator-only per D-16).

**Android Analog:** `android-app/app/src/test/java/de/haphone/app/test/EnvelopeVerifierTest.kt` (whole file, 57 lines)
```kotlin
class EnvelopeVerifierTest {
    private val publicKeyHex = "..."
    private fun fixtureEnvelope(): Map<String, Any> = mapOf(...)

    @Test
    fun goldenCanonicalBytesMatchFixture() {
        val bytes = EnvelopeVerifier.canonicalBytes(fixtureEnvelope())
        assertEquals(expectedCanonical, String(bytes!!, Charsets.UTF_8))
    }
}
```
Pattern: plain JUnit4 `@Test` methods (no Robolectric/instrumentation needed since these are pure-function/fixture-based tests), backtick-free camelCase descriptive test names, a private fixture-builder function. `CodecConfigTest` (assert codec priority list contains `opus/48000` etc. — direct port of Pitfall 3's build-verification gate), `DtmfControllerTest`, `DialpadTest` (dialed digits → correct `sip:` URI string), and `CallControlTest` (hold/xfer parameter construction) should all follow this exact fixture + plain-`@Test`-method shape; only mock the `CallControlScope`/PJSUA2 surface where an object under test genuinely needs a collaborator (fakes preferred, per the injected-rules `kotlin/testing.md` "Fakes Over Mocks" guidance).

---

### `~/projects/Ha-Phone/ha-phone/backend/models.py` (model, CRUD)

**Analog:** same file — `Trunk.transport` field (lines 122-133)

```python
class Trunk(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    registrar_host: str = ""
    port: int = 5060
    transport: str = "udp"  # udp | tcp | tls
    domain: str = ""  # SIP domain — empty = same as registrar_host
    ...
    codecs: str = "ulaw,alaw"  # comma-separated Asterisk codec names, in priority order
```

Add to `Extension` (lines 9-30) a matching field pair, following the exact same "plain `str` with a comment enumerating the legal values" convention already used for `Trunk.transport` (do NOT invent an enum type — nothing else in this file uses one):
```python
transport: str = "udp"  # udp | tls  (D-06: TLS/SRTP test extension)
media_encryption: str = "none"  # none | sdes | dtls
```
Also add the corresponding optional fields to `ExtensionUpdate` (lines 33-42, same `Optional[...] = Field(default=None, ...)` pattern already used for every other partial-update field there) — `ExtensionOut`/`ExtensionCreateOut` (lines 45-58) should stay unchanged unless the new fields need to be surfaced in the API response for admin UI purposes.

---

### `~/projects/Ha-Phone/ha-phone/backend/routers/extensions.py` (controller/route, CRUD)

**Analog:** same file — `create_extension`/`update_extension` (lines 312-374)

**Imports pattern** (lines 1-26): plain `re`, `secrets`, FastAPI `APIRouter`/`Depends`/`HTTPException`, `sqlmodel` `Session`/`select`, project-relative imports from `backend.models`, `backend.conf_generator`, `backend.regeneration`, `backend.ami`.

**Create/update + regenerate-then-reload pattern** (lines 312-339):
```python
@router.post("/extensions", response_model=ExtensionCreateOut)
async def create_extension(extension: Extension, session: Session = Depends(get_session)):
    validate_number(session, extension.number, kind="extension")
    if not extension.sip_password:
        extension.sip_password = secrets.token_urlsafe(12)
    session.add(extension)
    session.commit()
    session.refresh(extension)
    ...
    summary = _regenerate_extension_bundle(session, f"extensions.create:{extension.number}")
    if step_succeeded(summary, "extensions"):
        await ami.ami_reload_pjsip()
    ...
    return _extension_create_out(extension)
```
Since `Extension` is passed directly as the request body model (line 313: `extension: Extension`), the new `transport`/`media_encryption` fields on the model automatically flow through `create_extension` with **no code change needed there** — only `update_extension`'s partial-update loop (lines 354-355, `for field, value in extension_data.model_dump(exclude_unset=True, exclude_none=True).items(): setattr(existing, field, value)`) needs the new `ExtensionUpdate` fields added (see models.py above) to also flow through automatically, since it iterates whatever fields are present on the model — no per-field code needed there either. The only required change in this file is adding the two new fields to `ExtensionUpdate` in `models.py` and, if desired, surfacing them on `ExtensionOut`.

**Client-input sanitization pattern (V5 Input Validation, RESEARCH.md Security Domain)** (lines 144-145):
```python
def _dial_string(value: str) -> str:
    return re.sub(r"[^0-9+*#]", "", value)
```
Port this exact regex/allowed-charset logic to both the Android and iOS dialpad components (client-side, before constructing any `sip:` URI for `makeCall`/`xfer`/`sendDtmf`) — RESEARCH.md's Known Threat Patterns table explicitly calls for mirroring this server-side pattern client-side to prevent SIP URI/header injection via a malformed dialpad string.

---

### `~/projects/Ha-Phone/ha-phone/backend/conf_templates/pjsip_extensions.conf.j2` (config/template, transform)

**Analog:** `~/projects/Ha-Phone/ha-phone/backend/conf_templates/pjsip_trunk.conf.j2` (lines 1-2, 26-32)

```jinja
{% set transport = "transport-tls" if trunk.transport == "tls" else "transport-udp" %}
...
[trunk-registration]
type = registration
outbound_auth = trunk-auth
server_uri = sip:{{ server_target }}
client_uri = sip:{{ reg_user }}@{{ sip_domain }}
contact_user = {{ reg_user }}
transport = {{ transport }}
```
`pjsip_extensions.conf.j2`'s endpoint block (lines 6-51) currently has **no** `transport=` line for any extension at all — per RESEARCH.md's Pitfall 4 / Anti-Pattern, this must stay true even for the new TLS test extension (Asterisk auto-selects the transport the REGISTER arrived on; explicitly setting `transport=transport-tls` on the endpoint is documented to cause connection issues). The only new template line needed is a conditional `media_encryption` line, following the same `{% if %}...{% else %}...{% endif %}` conditional-block style already used in this exact file for `video_capable` (lines 12-17):
```jinja
{% if ext.video_capable %}
allow             = h264
max_video_streams = 1
{% else %}
max_video_streams = 0
{% endif %}
```
Add, e.g., right after `callerid` (line 51):
```jinja
{% if ext.media_encryption and ext.media_encryption != "none" %}
media_encryption = {{ ext.media_encryption }}
{% endif %}
```
Do **not** add a `transport = {{ ext.transport }}` line to the endpoint block — see Anti-Pattern above. `ext.transport` (if the field is kept on the model at all) is informational/for-future-use only in this template; the actual transport selection is driven entirely by the new `[transport-tls]` global stanza described below.

---

### `~/projects/Ha-Phone/ha-phone/rootfs/etc/cont-init.d/10-asterisk-init.sh` (config/script, file-I/O)

**Analog:** same file — AMI secret generation (lines 21-27) + externip/`pjsip_local.conf` heredoc block (lines 154-203)

**Idempotent secret/cert generation pattern** (lines 21-27):
```bash
if [ ! -f /data/asterisk/ami_secret ]; then
    bashio::log.info "Generating AMI secret..."
    python3 -c "import secrets; print(secrets.token_urlsafe(32))" > /data/asterisk/ami_secret
    chmod 600 /data/asterisk/ami_secret
    bashio::log.info "AMI secret written to /data/asterisk/ami_secret."
fi
```
Port this exact "check file exists, generate only if missing (first-boot only), `chmod 600`" shape for the new self-signed TLS cert — swap the `python3 -c "import secrets..."` line for RESEARCH.md's Don't-Hand-Roll recommendation (`openssl req -x509 ...`), writing to (e.g.) `/data/asterisk/tls/asterisk.crt` / `/data/asterisk/tls/asterisk.key`, matching the `/data/asterisk/...` path convention already used for `ami_secret`/`session_secret`.

**Dynamically-generated `.conf` heredoc pattern** (lines 160-203):
```bash
PJSIP_LOCAL="/data/asterisk/pjsip_local.conf"
if [ -n "$EXTERNAL_IP" ]; then
    cat > "$PJSIP_LOCAL" <<HEREDOC
; Auto-generated by cont-init.d/10-asterisk-init.sh — do not edit manually
; Extends transport-udp defined in /etc/asterisk/pjsip.conf

[transport-udp](+)
external_signaling_address = ${EXTERNAL_IP}
...
HEREDOC
else
    cat > "$PJSIP_LOCAL" <<'HEREDOC'
; ...LAN-only fallback placeholder...
HEREDOC
fi
```
Append the new `[transport-tls]` stanza to this same `pjsip_local.conf` heredoc (RESEARCH.md's illustrative config, Code Examples section):
```ini
[transport-tls]
type       = transport
protocol   = tls
bind       = 0.0.0.0:5061
cert_file  = /data/asterisk/tls/asterisk.crt
priv_key_file = /data/asterisk/tls/asterisk.key
method     = tlsv1_2
```
Keep the same "do-not-edit-manually" header comment convention and the same fail-soft placeholder-on-failure branch shape (lines 195-203) — if cert generation fails, write a comment-only stanza rather than aborting boot, matching the existing externip-failure fallback behavior.

## Shared Patterns

### Report-First / Attach-SIP-After (carried over from Phase 1)
**Source:** `android-app/.../test/CallRegistration.kt` lines 53-74 (`reportIncomingCall`'s `onRegistered` callback) and `ios-app/HAPhoneTestApp/PushHandler.swift` lines 82-94 (`callReporter.reportNewIncomingCall` completion block)
**Apply to:** `PjsuaEndpointHolder.kt`/`SipCallController.kt` (Android) and `SipCallController.swift`/`CallProvider.swift` (iOS) — all SIP registration/INVITE/answer logic must run inside these existing callbacks, never before the call is reported to CallKit/Telecom.

### Protocol/Interface Abstraction for Testability
**Source:** `ios-app/HAPhoneTestApp/PushHandler.swift` lines 5-19 (`IncomingCallReporting`/`CallEnding` protocols wrapping `CXProvider`/`CXCallController`)
**Apply to:** `SipCallController.swift` — wrap the Obj-C++ `PjsuaBridge` behind a small Swift protocol so `SipCallControllerTests.swift` can inject a mock without a real PJSUA2 runtime.

### Disconnect-on-Failure (CR-01 precedent)
**Source:** `android-app/.../test/CallRegistration.kt` lines 42-46 (doc comment) — `CallControlScope` receiver exposes `disconnect()` so a caller can end a bad call rather than let it ring forever
**Apply to:** Android `SipCallController.answer()` and iOS `SipCallController`'s answer path — both must be able to invoke `disconnect()`/`CXEndCallAction` if SIP negotiation fails, mirroring the existing envelope-invalid handling.

### Idempotent First-Boot Secret/Config Generation
**Source:** `~/projects/Ha-Phone/ha-phone/rootfs/etc/cont-init.d/10-asterisk-init.sh` lines 21-27 (AMI secret) and 154-203 (externip → `pjsip_local.conf`)
**Apply to:** the new TLS cert generation + `[transport-tls]` stanza in the same file — same "check-exists, generate-once, chmod 600, fail-soft placeholder" shape.

### Client-Side Input Sanitization Mirroring Server-Side Pattern
**Source:** `~/projects/Ha-Phone/ha-phone/backend/routers/extensions.py` lines 144-145 (`_dial_string`, `re.sub(r"[^0-9+*#]", "", value)`)
**Apply to:** `DialpadComposable.kt` and `DialpadView.swift` — sanitize dialpad-entered strings client-side before constructing any `sip:` URI, using the same allowed-charset regex/logic.

### Compose/SwiftUI Screen Structure (Activity + MaterialTheme / View + NavigationView)
**Source:** `android-app/.../test/IncomingCallActivity.kt` (whole file) and `ios-app/HAPhoneTestApp/DiagnosticsView.swift` (whole file)
**Apply to:** all new screens (`ActiveCallActivity`/`OutgoingCallActivity` on Android, `ActiveCallView`/`OutgoingCallView`/`DialpadView` on iOS) — same stateless-composable / `@State`-backed-View-struct conventions, plain Material3/system styling per 02-UI-SPEC.md.

## No Analog Found

Files with no close match in the codebase (planner should use RESEARCH.md patterns instead):

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `ios-app/HAPhoneTestApp/Sip/PjsuaBridge.mm/.h` | service | event-driven | No existing Obj-C++ bridge code in the repo at all — this is the first C++/Obj-C++ interop file. Use RESEARCH.md's cited official sample (`pjsip-apps/src/pjsua2/ios-swift-pjsua2` in the pjproject source tree) as the reference implementation instead of a codebase analog. |
| Android JNI/Gradle module wiring for `pjsua2.jar`/`.so` (new local Gradle module, no single file name yet) | config | file-I/O | `android-app/app/build.gradle.kts` currently only declares standard Maven dependencies (`androidx.core:core-telecom`, Firebase, Tink) — no local/JNI module precedent exists yet in this project. Follow RESEARCH.md's official Android build_instructions.html steps directly. |
| `~/projects/Ha-Phone/ha-phone/backend/conf_templates/pjsip_local.conf.j2` vs. bash-heredoc-in-`10-asterisk-init.sh` choice for `[transport-tls]` | config | file-I/O | `pjsip_local.conf` is unusual in this codebase: it's the one generated Asterisk conf written directly by bash (heredoc) rather than by the Python `render_conf`/Jinja pipeline used for every other `.conf.j2` file. No second example of this bash-heredoc-conf pattern exists to cross-check against — treat the existing externip block in the same file as the sole precedent (already cited above) rather than looking for a second one. |
| Android NDK/SWIG toolchain install + `configure-android` invocation scripting | config | batch | No existing native cross-compile step exists anywhere in this repo (Phase 1 was pure Kotlin/Swift, no NDK). Follow RESEARCH.md's Standard Stack "Installation" section directly — there is nothing analogous to adapt from. |

## Metadata

**Analog search scope:** `ios-app/HAPhoneTestApp/`, `ios-app/HAPhoneTestAppTests/`, `android-app/app/src/main/java/de/haphone/app/test/`, `android-app/app/src/test/java/de/haphone/app/test/`, `~/projects/Ha-Phone/ha-phone/backend/` (models.py, routers/extensions.py, conf_templates/), `~/projects/Ha-Phone/ha-phone/rootfs/etc/cont-init.d/`, `tools/docs/`, `.github/workflows/`, `.planning/phases/01-push-wakeup-proof-of-concept/`
**Files scanned:** 22 read directly (full or targeted sections); build configs (`project.yml`, `build.gradle.kts`) inspected for dependency/toolchain precedent
**Pattern extraction date:** 2026-08-04
