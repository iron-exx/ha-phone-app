#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Obj-C++ wrapper around PJSUA2's Endpoint/Account/Call C++ classes --
/// this is the only C++ interop boundary in the iOS app (02-PATTERNS.md
/// "No Analog Found": first Obj-C++ bridge in this repo). Swift-facing
/// code (SipCallController) talks to this through the SipCallOperations
/// protocol via PjsuaBridgeOperations below, never directly to C++ types.
@interface PjsuaBridge : NSObject

- (void)start; // libCreate/libInit/libStart + codec priority (CALL-01/D-07)
- (void)registerAccountWithDomain:(NSString *)domain username:(NSString *)username password:(NSString *)password;
- (void)unregisterAccount;
- (void)makeCallWithUri:(NSString *)uri;
- (BOOL)answerCall; // NO = SIP negotiation failed
- (void)setHold:(BOOL)onHold;
- (void)setMuted:(BOOL)muted;
- (void)transferToUri:(NSString *)uri;
- (void)sendDtmf:(NSString *)digit;
- (void)hangupCall;
- (void)handleIpChange; // D-09/RESEARCH.md Pattern 3 -- ICE restart on network change

@end

NS_ASSUME_NONNULL_END
