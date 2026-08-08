#import "PjsuaSmokeCheck.h"
#include <pjsua2.hpp>

BOOL PjsuaBindingsAvailable(void) {
    return pj::Endpoint::instance().libGetVersion() != nullptr;
}
