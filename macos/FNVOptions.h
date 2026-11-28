#pragma once

#import <AppKit/AppKit.h>

#ifdef FNV_GAME_SKYRIM
#define GAME_TITLE       @"The Elder Scrolls V: Skyrim"
#define GAME_EXE         @"TESV.exe"
#define GAME_ESM         @"Data/Skyrim.esm"
#define GAME_DIR         @"Skyrim"
#define GAME_LOG         @"skyrim.log"
#define GAME_ARGV0       "skyrim-macos"
#define GAME_EXE_C       "TESV.exe"
#define GAME_PREF_PREFIX @"Skyrim"
#elif defined(FNV_GAME_FALLOUT3)
#define GAME_TITLE       @"Fallout 3"
#define GAME_EXE         @"Fallout3.exe"
#define GAME_ESM         @"Data/Fallout3.esm"
#define GAME_DIR         @"Fallout3"
#define GAME_LOG         @"fallout3.log"
#define GAME_ARGV0       "f3-macos"
#define GAME_EXE_C       "Fallout3.exe"
#define GAME_PREF_PREFIX @"Fallout3"
#else
#define GAME_TITLE       @"Fallout: New Vegas"
#define GAME_EXE         @"FalloutNV.exe"
#define GAME_ESM         @"Data/FalloutNV.esm"
#define GAME_DIR         @"FalloutNV"
#define GAME_LOG         @"fnv.log"
#define GAME_ARGV0       "fnv-macos"
#define GAME_EXE_C       "FalloutNV.exe"
#define GAME_PREF_PREFIX @"FNV"
#endif

typedef NS_ENUM(NSInteger, FNVDisplayMode) {
    FNVDisplayModeWindowed = 0,
    FNVDisplayModeFullscreen = 1,
    FNVDisplayModeBorderlessFullscreen = 2,
};

typedef struct {
    unsigned renderScale;
    int upscaler;
    int antiAliasing;
    FNVDisplayMode displayMode;
} FNVLaunchSettings;

#ifndef FNV_PROBE
void FNVApplyIniSettings(NSMutableArray<NSString *> *lines,
                         NSDictionary<NSString *, NSDictionary *> *settings);

@interface FNVOptionsController : NSObject

- (instancetype)initWithNativeW:(unsigned)nativeW
                        nativeH:(unsigned)nativeH
                     fullPanelH:(unsigned)fullPanelH
                       backingW:(unsigned)backingW
                       backingH:(unsigned)backingH
                      refreshHz:(int)refreshHz;

- (BOOL)shouldShowLauncher;
- (void)enableOptionsOnNextLaunch;
- (NSWindow *)presentWindowWithDelegate:(id<NSWindowDelegate>)delegate
                                 onPlay:(void (^)(FNVLaunchSettings settings))onPlay;
- (FNVLaunchSettings)currentLaunchSettings;
- (void)prepareGameFilesInRoot:(NSURL *)root
                       userDir:(NSURL *)userDir
                          outW:(unsigned)outW
                          outH:(unsigned)outH;

@end
#endif
