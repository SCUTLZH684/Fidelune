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

extern void BASSFLACplugin(void);
extern void BASSDSDplugin(void);
extern void BASSWVplugin(void);
extern void BASSAPEplugin(void);
extern void BASSOPUSplugin(void);

static inline HPLUGIN FideluneLoadPluginByIndex(int index) {
    switch (index) {
        case 0: return BASS_PluginLoad((const char *)(uintptr_t)BASSFLACplugin, BASS_PLUGIN_PROC);
        case 1: return BASS_PluginLoad((const char *)(uintptr_t)BASSDSDplugin, BASS_PLUGIN_PROC);
        case 2: return BASS_PluginLoad((const char *)(uintptr_t)BASSWVplugin, BASS_PLUGIN_PROC);
        case 3: return BASS_PluginLoad((const char *)(uintptr_t)BASSAPEplugin, BASS_PLUGIN_PROC);
        case 4: return BASS_PluginLoad((const char *)(uintptr_t)BASSOPUSplugin, BASS_PLUGIN_PROC);
        default: return 0;
    }
}
