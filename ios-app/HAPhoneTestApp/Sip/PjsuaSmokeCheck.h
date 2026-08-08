// Compile-time smoke check (Plan 03, Task 2): confirms the pjsua2
// xcframework built by build_pjsip_ios.sh links into the app target.
// Superseded by PjsuaBridge.h in Plan 05, which owns the real
// Endpoint/Account/Call wrapper.
#ifndef PjsuaSmokeCheck_h
#define PjsuaSmokeCheck_h
#import <Foundation/Foundation.h>
BOOL PjsuaBindingsAvailable(void);
#endif
