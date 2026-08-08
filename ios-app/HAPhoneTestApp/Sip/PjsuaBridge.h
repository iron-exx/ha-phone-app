#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Obj-C++ wrapper around PJSUA2's Endpoint/Account/Call C++ classes --
/// this is the only C++ interop boundary in the iOS app (02-PATTERNS.md
/// "No Analog Found": first Obj-C++ bridge in this repo). Swift-facing
/// code (SipCallController) talks to this through the SipCallOperations
/// protocol via PjsuaBridgeOperations below, never directly to C++ types.
@interface PjsuaBridge : NSObject

// NS_SWIFT_NAME pins the exact Swift-visible spelling for every method
// below (Task 3 addition, discovered while wiring PjsuaBridgeSipCallOperations
// -- the default Clang-importer "Omit Needless Words" heuristic for
// "VerbWithNoun:" selectors is not reliably predictable in this sandbox
// without a real Swift compiler to check against (D-02), so this closes
// that blocking Swift/Obj-C interop ambiguity outright rather than guessing).
- (void)start NS_SWIFT_NAME(start()); // libCreate/libInit/libStart + codec priority (CALL-01/D-07)
- (void)registerAccountWithDomain:(NSString *)domain username:(NSString *)username password:(NSString *)password NS_SWIFT_NAME(registerAccount(domain:username:password:));
- (void)unregisterAccount NS_SWIFT_NAME(unregisterAccount());
- (void)makeCallWithUri:(NSString *)uri NS_SWIFT_NAME(makeCall(uri:));
- (BOOL)answerCall NS_SWIFT_NAME(answerCall()); // NO = SIP negotiation failed
- (void)setHold:(BOOL)onHold NS_SWIFT_NAME(setHold(_:));
- (void)setMuted:(BOOL)muted NS_SWIFT_NAME(setMuted(_:));
- (void)transferToUri:(NSString *)uri NS_SWIFT_NAME(transfer(uri:));
- (void)sendDtmf:(NSString *)digit NS_SWIFT_NAME(sendDtmf(_:));
- (void)hangupCall NS_SWIFT_NAME(hangupCall());
- (void)handleIpChange NS_SWIFT_NAME(handleIpChange()); // D-09/RESEARCH.md Pattern 3 -- ICE restart on network change

@end

NS_ASSUME_NONNULL_END
