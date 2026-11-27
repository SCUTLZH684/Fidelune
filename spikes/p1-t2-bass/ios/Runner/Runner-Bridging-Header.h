#import "GeneratedPluginRegistrant.h"

#import <Foundation/Foundation.h>

#import "bass.h"
#import "bassmix.h"
#import "bassdsd.h"
#import "bassflac.h"
#import "basswv.h"
#import "bassape.h"
#import "bassopus.h"

static inline STREAMPROC* FideluneStreamProcPush(void) {
    return STREAMPROC_PUSH;
}

static inline STREAMPROC* FideluneStreamProcDummy(void) {
    return STREAMPROC_DUMMY;
}
