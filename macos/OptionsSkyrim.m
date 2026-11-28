#import "FNVOptions.h"

#ifndef FNV_PROBE

#include "FNVDisplay.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static NSString *const kPrefQualityPreset      = @"SkyrimQualityPreset";
static NSString *const kPrefAnisotropy         = @"SkyrimAnisotropy";
static NSString *const kPrefRenderScale        = @"SkyrimRenderScale";
static NSString *const kPrefUpscaler           = @"SkyrimUpscaler";
static NSString *const kPrefAntiAliasing       = @"SkyrimAntiAliasing";
static NSString *const kPrefTextureQuality     = @"SkyrimTextureQuality";
static NSString *const kPrefRadialBlur         = @"SkyrimRadialBlurQuality";
static NSString *const kPrefShadowQuality      = @"SkyrimShadowQuality";
static NSString *const kPrefDecalQuantity      = @"SkyrimDecalQuantity";
static NSString *const kPrefVanillaFxaa        = @"SkyrimVanillaFXAA";
static NSString *const kPrefReflectLand        = @"SkyrimWaterReflectLand";
static NSString *const kPrefReflectTrees       = @"SkyrimWaterReflectTrees";
static NSString *const kPrefReflectObjects     = @"SkyrimWaterReflectObjects";
static NSString *const kPrefReflectSky         = @"SkyrimWaterReflectSky";
static NSString *const kPrefObjectFade         = @"SkyrimObjectFade";
static NSString *const kPrefActorFade          = @"SkyrimActorFade";
static NSString *const kPrefGrassFade          = @"SkyrimGrassFade";
static NSString *const kPrefSpecularityFade    = @"SkyrimSpecularityFade";
static NSString *const kPrefLightFade          = @"SkyrimLightFade";
static NSString *const kPrefItemFade           = @"SkyrimItemFade";
static NSString *const kPrefDistantObjectDetail= @"SkyrimDistantObjectDetail";
static NSString *const kPrefObjectDetailFade   = @"SkyrimObjectDetailFade";
static NSString *const kPrefFovPreset          = @"SkyrimFovPreset";
static NSString *const kPrefWorldFov           = @"SkyrimWorldFov";
static NSString *const kPrefFirstPersonFov     = @"SkyrimFirstPersonFov";
static NSString *const kPrefFullscreen         = @"SkyrimFullscreen";
static NSString *const kPrefMouseAccel         = @"SkyrimMouseAcceleration";
static NSString *const kPrefSkipLauncher       = @"SkyrimSkipLauncher";

typedef struct {
    int preset;                  // 0=Keep SkyrimPrefs.ini, 1=Low, 2=Medium, 3=High, 4=Ultra
    int anisotropy;              // 0, 2, 4, 8, 16
    unsigned renderScale;        // 50..100
    int upscaler;                // 0=Bilinear, 1=MetalFX Spatial
    int antiAliasing;            // 0=Off, 1=SMAA, 2=FXAA (Metal post-process)

    // Advanced -> Detail
    int textureQuality;          // 0=High (skip 0), 1=Medium (skip 1), 2=Low (skip 2)
    int radialBlurQuality;       // 0=Low, 1=Medium, 2=High
    int shadowQuality;           // 0=Keep, 1=Low (512), 2=Medium (1024), 3=High (2048), 4=Ultra (4096)
    int decalQuantity;           // 0=None, 1=Medium, 2=High, 3=Ultra
    BOOL vanillaFxaa;            // bFXAAEnabled
    BOOL reflectLand;            // bReflectLODLand
    BOOL reflectTrees;           // bReflectLODTrees
    BOOL reflectObjects;         // bReflectLODObjects
    BOOL reflectSky;             // bReflectSky

    // Advanced -> View Distance
    int objectFade;              // 1..15 (fLODFadeOutMultObjects x1)
    int actorFade;               // 2..15 (fLODFadeOutMultActors x1)
    int grassFade;               // 0..7  (fGrassStartFadeDistance x1000)
    int specularityFade;         // 2..20 (fSpecularLODStartFade x100)
    int lightFade;               // 2..35 (fLightLODStartFade x100)
    int itemFade;                // 1..15 (fLODFadeOutMultItems x1)
    int distantObjectDetail;     // 0=Low, 1=Medium, 2=High, 3=Ultra
    BOOL objectDetailFade;       // On=3072/4096, Off=10000000/10000000

    // Port-specific options
    int fovPreset;               // 0=Keep Skyrim.ini, 1=Original, 2=Expanded, 3=Wide, 4=Custom
    int worldFov;                // 65..105 (fDefaultWorldFOV / fDefaultFOV)
    int firstPersonFov;          // 65..95  (fDefault1stPersonFOV)
    FNVDisplayMode displayMode;
    BOOL mouseAcceleration;
    BOOL skipLauncher;
} SkyrimOptions;

static int clampInt(int v, int lo, int hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

static void applySkyrimFovPresetDefaults(SkyrimOptions *opts, int fovPreset) {
    switch (fovPreset) {
    case 2: // Expanded
        opts->worldFov = 85; opts->firstPersonFov = 80;
        break;
    case 3: // Wide
        opts->worldFov = 95; opts->firstPersonFov = 85;
        break;
    case 1: // Original
    default:
        opts->worldFov = 65; opts->firstPersonFov = 65;
        break;
    }
}

static int matchingSkyrimFovPreset(int worldFov, int firstPersonFov) {
    if (worldFov == 65 && firstPersonFov == 65) return 1;
    if (worldFov == 85 && firstPersonFov == 80) return 2;
    if (worldFov == 95 && firstPersonFov == 85) return 3;
    return 4;
}

// Exact official Windows Skyrim (2011 / LE) Launcher presets
static void applySkyrimPresetDefaults(SkyrimOptions *opts, int preset) {
    switch (preset) {
    case 1: // Low
        opts->anisotropy = 0;
        opts->textureQuality = 1;    // Medium
        opts->radialBlurQuality = 0; // Low
        opts->shadowQuality = 1;     // Low
        opts->decalQuantity = 0;     // None
        opts->vanillaFxaa = NO;
        opts->reflectLand = NO;
        opts->reflectTrees = NO;
        opts->reflectObjects = NO;
        opts->reflectSky = YES;

        opts->objectFade = 2;
        opts->actorFade = 2;
        opts->grassFade = 0;
        opts->specularityFade = 2;
        opts->lightFade = 2;
        opts->itemFade = 1;
        opts->distantObjectDetail = 0; // Low
        opts->objectDetailFade = YES;
        break;

    case 2: // Medium
        opts->anisotropy = 0;        // Off on Windows Medium preset
        opts->textureQuality = 0;    // High
        opts->radialBlurQuality = 0; // Low
        opts->shadowQuality = 2;     // Medium
        opts->decalQuantity = 1;     // Medium
        opts->vanillaFxaa = YES;     // On on Windows Medium preset
        opts->reflectLand = YES;
        opts->reflectTrees = NO;
        opts->reflectObjects = NO;
        opts->reflectSky = NO;

        opts->objectFade = 2;
        opts->actorFade = 3;
        opts->grassFade = 3;
        opts->specularityFade = 5;
        opts->lightFade = 10;
        opts->itemFade = 3;
        opts->distantObjectDetail = 1; // Medium
        opts->objectDetailFade = YES;
        break;

    case 3: // High
        opts->anisotropy = 8;
        opts->textureQuality = 0;    // High
        opts->radialBlurQuality = 1; // Medium
        opts->shadowQuality = 3;     // High
        opts->decalQuantity = 2;     // High
        opts->vanillaFxaa = NO;
        opts->reflectLand = YES;
        opts->reflectTrees = YES;
        opts->reflectObjects = YES;
        opts->reflectSky = NO;

        opts->objectFade = 7;
        opts->actorFade = 6;
        opts->grassFade = 5;
        opts->specularityFade = 10;
        opts->lightFade = 25;
        opts->itemFade = 4;
        opts->distantObjectDetail = 2; // High
        opts->objectDetailFade = NO;
        break;

    case 4: // Ultra
    default:
        opts->anisotropy = 16;
        opts->textureQuality = 0;    // High
        opts->radialBlurQuality = 2; // High
        opts->shadowQuality = 4;     // Ultra
        opts->decalQuantity = 3;     // Ultra
        opts->vanillaFxaa = NO;
        opts->reflectLand = YES;
        opts->reflectTrees = YES;
        opts->reflectObjects = YES;
        opts->reflectSky = YES;

        opts->objectFade = 15;
        opts->actorFade = 15;
        opts->grassFade = 7;
        opts->specularityFade = 20;
        opts->lightFade = 35;
        opts->itemFade = 15;
        opts->distantObjectDetail = 3; // Ultra
        opts->objectDetailFade = NO;
        break;
    }
}

static unsigned clampScale(long v) {
    if (v < 50) return 50;
    if (v > 100) return 100;
    return (unsigned)v;
}

static SkyrimOptions loadSkyrimOptions(unsigned nativeW) {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    SkyrimOptions opts = {0};
    id pObj = [ud objectForKey:kPrefQualityPreset];
    opts.preset = pObj ? (int)[pObj integerValue] : 3; // High default
    if (opts.preset < 0 || opts.preset > 4) opts.preset = 3;
    applySkyrimPresetDefaults(&opts, opts.preset > 0 ? opts.preset : 3);
    if (opts.preset == 0) opts.shadowQuality = 0;

    id anObj = [ud objectForKey:kPrefAnisotropy];
    if (anObj) opts.anisotropy = clampInt((int)[anObj integerValue], 0, 16);

    unsigned defScale = (nativeW >= 2000u) ? 75u : 100u;
    id sObj = [ud objectForKey:kPrefRenderScale];
    opts.renderScale = sObj ? clampScale([sObj integerValue]) : defScale;
    id uObj = [ud objectForKey:kPrefUpscaler];
    opts.upscaler = uObj ? ([uObj integerValue] ? 1 : 0) : 1;
    id aObj = [ud objectForKey:kPrefAntiAliasing];
    opts.antiAliasing = aObj ? clampInt((int)[aObj integerValue], 0, 2) : 0;

    // Advanced -> Detail
    id tObj = [ud objectForKey:kPrefTextureQuality];
    if (tObj) opts.textureQuality = clampInt((int)[tObj integerValue], 0, 2);
    id rbObj = [ud objectForKey:kPrefRadialBlur];
    if (rbObj) opts.radialBlurQuality = clampInt((int)[rbObj integerValue], 0, 2);
    id shObj = [ud objectForKey:kPrefShadowQuality];
    if (shObj) opts.shadowQuality = clampInt((int)[shObj integerValue], 0, 4);
    id dqObj = [ud objectForKey:kPrefDecalQuantity];
    if (dqObj) opts.decalQuantity = clampInt((int)[dqObj integerValue], 0, 3);
    id fxObj = [ud objectForKey:kPrefVanillaFxaa];
    if (fxObj) opts.vanillaFxaa = [fxObj boolValue];
    id rlObj = [ud objectForKey:kPrefReflectLand];
    if (rlObj) opts.reflectLand = [rlObj boolValue];
    id rtObj = [ud objectForKey:kPrefReflectTrees];
    if (rtObj) opts.reflectTrees = [rtObj boolValue];
    id roObj = [ud objectForKey:kPrefReflectObjects];
    if (roObj) opts.reflectObjects = [roObj boolValue];
    id rsObj = [ud objectForKey:kPrefReflectSky];
    if (rsObj) opts.reflectSky = [rsObj boolValue];

    // Advanced -> View Distance
    id ofObj = [ud objectForKey:kPrefObjectFade];
    if (ofObj) opts.objectFade = clampInt((int)[ofObj integerValue], 1, 15);
    id afObj = [ud objectForKey:kPrefActorFade];
    if (afObj) opts.actorFade = clampInt((int)[afObj integerValue], 2, 15);
    id gfObj = [ud objectForKey:kPrefGrassFade];
    if (gfObj) opts.grassFade = clampInt((int)[gfObj integerValue], 0, 7);
    id spfObj = [ud objectForKey:kPrefSpecularityFade];
    if (spfObj) opts.specularityFade = clampInt((int)[spfObj integerValue], 2, 20);
    id lfObj = [ud objectForKey:kPrefLightFade];
    if (lfObj) opts.lightFade = clampInt((int)[lfObj integerValue], 2, 35);
    id ifObj = [ud objectForKey:kPrefItemFade];
    if (ifObj) opts.itemFade = clampInt((int)[ifObj integerValue], 1, 15);
    id dodObj = [ud objectForKey:kPrefDistantObjectDetail];
    if (dodObj) opts.distantObjectDetail = clampInt((int)[dodObj integerValue], 0, 3);
    id odfObj = [ud objectForKey:kPrefObjectDetailFade];
    if (odfObj) opts.objectDetailFade = [odfObj boolValue];

    id fpObj = [ud objectForKey:kPrefFovPreset];
    opts.fovPreset = fpObj ? (int)[fpObj integerValue] : 1; // Original default
    if (opts.fovPreset < 0 || opts.fovPreset > 4) opts.fovPreset = 1;
    applySkyrimFovPresetDefaults(&opts, (opts.fovPreset >= 1 && opts.fovPreset <= 3) ? opts.fovPreset : 1);
    id wfObj = [ud objectForKey:kPrefWorldFov];
    if (wfObj) opts.worldFov = clampInt((int)[wfObj integerValue], 65, 105);
    id fpfObj = [ud objectForKey:kPrefFirstPersonFov];
    if (fpfObj) opts.firstPersonFov = clampInt((int)[fpfObj integerValue], 65, 95);
    if (opts.fovPreset >= 1 && opts.fovPreset <= 3) {
        applySkyrimFovPresetDefaults(&opts, opts.fovPreset);
    } else if (opts.fovPreset == 4) {
        opts.fovPreset = matchingSkyrimFovPreset(opts.worldFov, opts.firstPersonFov);
    }
    id dmObj = [ud objectForKey:@"SkyrimDisplayMode"];
    if (dmObj) {
        NSInteger dm = [dmObj integerValue];
        opts.displayMode = (dm >= FNVDisplayModeWindowed && dm <= FNVDisplayModeBorderlessFullscreen)
            ? (FNVDisplayMode)dm
            : FNVDisplayModeFullscreen;
    } else {
        id fsObj = [ud objectForKey:kPrefFullscreen];
        opts.displayMode = (!fsObj || [fsObj boolValue]) ? FNVDisplayModeFullscreen : FNVDisplayModeWindowed;
    }
    id maObj = [ud objectForKey:kPrefMouseAccel];
    opts.mouseAcceleration = maObj ? [maObj boolValue] : NO;
    id skObj = [ud objectForKey:kPrefSkipLauncher];
    opts.skipLauncher = skObj ? [skObj boolValue] : NO;

    const char *envScale = getenv("SKYRIM_RENDER_SCALE");
    if (envScale && envScale[0]) opts.renderScale = clampScale(strtol(envScale, NULL, 10));
    const char *envUp = getenv("SKYRIM_UPSCALER");
    if (envUp && envUp[0]) {
        if (!strcasecmp(envUp, "bilinear") || !strcmp(envUp, "0")) opts.upscaler = 0;
        else if (!strcasecmp(envUp, "metalfx") || !strcasecmp(envUp, "metalfx-spatial") || !strcmp(envUp, "1")) opts.upscaler = 1;
    }
    const char *envAA = getenv("SKYRIM_AA");
    if (envAA && envAA[0]) {
        if (!strcasecmp(envAA, "smaa") || !strcmp(envAA, "1")) opts.antiAliasing = 1;
        else if (!strcasecmp(envAA, "fxaa") || !strcmp(envAA, "2")) opts.antiAliasing = 2;
        else if (!strcasecmp(envAA, "off") || !strcasecmp(envAA, "none") || !strcmp(envAA, "0")) opts.antiAliasing = 0;
    }
    const char *envSh = getenv("SKYRIM_SHADOWS");
    if (envSh && envSh[0]) {
        if (!strcasecmp(envSh, "low") || !strcmp(envSh, "1")) opts.shadowQuality = 1;
        else if (!strcasecmp(envSh, "medium") || !strcmp(envSh, "2")) opts.shadowQuality = 2;
        else if (!strcasecmp(envSh, "high") || !strcmp(envSh, "3")) opts.shadowQuality = 3;
        else if (!strcasecmp(envSh, "ultra") || !strcmp(envSh, "4")) opts.shadowQuality = 4;
        else if (!strcasecmp(envSh, "keep") || !strcmp(envSh, "0")) opts.shadowQuality = 0;
    }
    const char *envFov = getenv("SKYRIM_FOV");
    if (envFov && envFov[0]) {
        opts.worldFov = clampInt((int)strtol(envFov, NULL, 10), 65, 105);
        opts.fovPreset = matchingSkyrimFovPreset(opts.worldFov, opts.firstPersonFov);
    }
    const char *envFpFov = getenv("SKYRIM_1ST_PERSON_FOV");
    if (envFpFov && envFpFov[0]) {
        opts.firstPersonFov = clampInt((int)strtol(envFpFov, NULL, 10), 65, 95);
        opts.fovPreset = matchingSkyrimFovPreset(opts.worldFov, opts.firstPersonFov);
    }
    const char *envMA = getenv("SKYRIM_MOUSE_ACCEL");
    if (envMA && envMA[0]) opts.mouseAcceleration = (atoi(envMA) != 0);
    const char *envBorderless = getenv("FNV_BORDERLESS");
    if (envBorderless && envBorderless[0] && atoi(envBorderless) != 0) {
        opts.displayMode = FNVDisplayModeBorderlessFullscreen;
    }
    if (getenv("FNV_WINDOWED")) opts.displayMode = FNVDisplayModeWindowed;
    return opts;
}

static void saveSkyrimOptions(SkyrimOptions opts) {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    [ud setInteger:opts.preset forKey:kPrefQualityPreset];
    [ud setInteger:opts.anisotropy forKey:kPrefAnisotropy];
    [ud setInteger:(NSInteger)opts.renderScale forKey:kPrefRenderScale];
    [ud setInteger:opts.upscaler forKey:kPrefUpscaler];
    [ud setInteger:opts.antiAliasing forKey:kPrefAntiAliasing];

    [ud setInteger:opts.textureQuality forKey:kPrefTextureQuality];
    [ud setInteger:opts.radialBlurQuality forKey:kPrefRadialBlur];
    [ud setInteger:opts.shadowQuality forKey:kPrefShadowQuality];
    [ud setInteger:opts.decalQuantity forKey:kPrefDecalQuantity];
    [ud setBool:opts.vanillaFxaa forKey:kPrefVanillaFxaa];
    [ud setBool:opts.reflectLand forKey:kPrefReflectLand];
    [ud setBool:opts.reflectTrees forKey:kPrefReflectTrees];
    [ud setBool:opts.reflectObjects forKey:kPrefReflectObjects];
    [ud setBool:opts.reflectSky forKey:kPrefReflectSky];

    [ud setInteger:opts.objectFade forKey:kPrefObjectFade];
    [ud setInteger:opts.actorFade forKey:kPrefActorFade];
    [ud setInteger:opts.grassFade forKey:kPrefGrassFade];
    [ud setInteger:opts.specularityFade forKey:kPrefSpecularityFade];
    [ud setInteger:opts.lightFade forKey:kPrefLightFade];
    [ud setInteger:opts.itemFade forKey:kPrefItemFade];
    [ud setInteger:opts.distantObjectDetail forKey:kPrefDistantObjectDetail];
    [ud setBool:opts.objectDetailFade forKey:kPrefObjectDetailFade];

    [ud setInteger:opts.fovPreset forKey:kPrefFovPreset];
    [ud setInteger:opts.worldFov forKey:kPrefWorldFov];
    [ud setInteger:opts.firstPersonFov forKey:kPrefFirstPersonFov];
    [ud setInteger:opts.displayMode forKey:@"SkyrimDisplayMode"];
    [ud setBool:(opts.displayMode != FNVDisplayModeWindowed) forKey:kPrefFullscreen];
    [ud setBool:opts.mouseAcceleration forKey:kPrefMouseAccel];
    [ud setBool:opts.skipLauncher forKey:kPrefSkipLauncher];
    [ud synchronize];
}

@interface FNVOptionsController ()
@property (nonatomic) unsigned nativeW;
@property (nonatomic) unsigned nativeH;
@property (nonatomic) unsigned fullPanelH;
@property (nonatomic) unsigned backingW;
@property (nonatomic) unsigned backingH;
@property (nonatomic) int refreshHz;
@property (nonatomic) SkyrimOptions workingOpts;
@property (nonatomic) SkyrimOptions savedOpts;
@property (nonatomic) BOOL hasSavedOpts;
@property (nonatomic, copy) void (^onPlay)(FNVLaunchSettings settings);

// Main window controls
@property (nonatomic, strong) NSWindow *optionsWindow;
@property (nonatomic, strong) NSPopUpButton *presetPopup;
@property (nonatomic, strong) NSButton *advancedBtn;
@property (nonatomic, strong) NSPopUpButton *anisoPopup;
@property (nonatomic, strong) NSPopUpButton *scalePopup;
@property (nonatomic, strong) NSPopUpButton *upscalerPopup;
@property (nonatomic, strong) NSPopUpButton *aaPopup;
@property (nonatomic, strong) NSPopUpButton *displayPopup;
@property (nonatomic, strong) NSPopUpButton *fovPresetPopup;
@property (nonatomic, strong) NSSlider *worldFovSlider;
@property (nonatomic, strong) NSSlider *firstPersonFovSlider;
@property (nonatomic, strong) NSTextField *worldFovValueLabel;
@property (nonatomic, strong) NSTextField *firstPersonFovValueLabel;
@property (nonatomic, strong) NSTextField *fovTipLabel;
@property (nonatomic, strong) NSTextField *resPreviewLabel;
@property (nonatomic, strong) NSButton *mouseAccelCheck;
@property (nonatomic, strong) NSButton *skipLauncherCheck;

// Advanced sheet controls
@property (nonatomic, strong) NSWindow *advancedWindow;
// Detail
@property (nonatomic, strong) NSPopUpButton *advTexturePopup;
@property (nonatomic, strong) NSPopUpButton *advRadialBlurPopup;
@property (nonatomic, strong) NSPopUpButton *advShadowPopup;
@property (nonatomic, strong) NSPopUpButton *advDecalPopup;
@property (nonatomic, strong) NSButton *advFxaaCheck;
@property (nonatomic, strong) NSButton *advReflectLandCheck;
@property (nonatomic, strong) NSButton *advReflectTreesCheck;
@property (nonatomic, strong) NSButton *advReflectObjectsCheck;
@property (nonatomic, strong) NSButton *advReflectSkyCheck;
// View Distance
@property (nonatomic, strong) NSSlider *advObjectFadeSlider;
@property (nonatomic, strong) NSTextField *advObjectFadeLabel;
@property (nonatomic, strong) NSSlider *advActorFadeSlider;
@property (nonatomic, strong) NSTextField *advActorFadeLabel;
@property (nonatomic, strong) NSSlider *advGrassFadeSlider;
@property (nonatomic, strong) NSTextField *advGrassFadeLabel;
@property (nonatomic, strong) NSSlider *advSpecFadeSlider;
@property (nonatomic, strong) NSTextField *advSpecFadeLabel;
@property (nonatomic, strong) NSSlider *advLightFadeSlider;
@property (nonatomic, strong) NSTextField *advLightFadeLabel;
@property (nonatomic, strong) NSSlider *advItemFadeSlider;
@property (nonatomic, strong) NSTextField *advItemFadeLabel;
@property (nonatomic, strong) NSPopUpButton *advDistantObjPopup;
@property (nonatomic, strong) NSButton *advObjDetailFadeCheck;
@end

@implementation FNVOptionsController

- (instancetype)initWithNativeW:(unsigned)nativeW
                        nativeH:(unsigned)nativeH
                     fullPanelH:(unsigned)fullPanelH
                       backingW:(unsigned)backingW
                       backingH:(unsigned)backingH
                      refreshHz:(int)refreshHz {
    self = [super init];
    if (self) {
        _nativeW = nativeW;
        _nativeH = nativeH;
        _fullPanelH = fullPanelH ?: nativeH;
        _backingW = backingW;
        _backingH = backingH;
        _refreshHz = refreshHz;
    }
    return self;
}

- (BOOL)shouldShowLauncher {
    SkyrimOptions opts = loadSkyrimOptions(self.nativeW);
    const char *headlessEnv = getenv("FNV_HEADLESS");
    BOOL isHeadless = (headlessEnv && headlessEnv[0] && headlessEnv[0] != '0');
    BOOL optionHeld = (NSEvent.modifierFlags & NSEventModifierFlagOption) != 0;
    return !isHeadless && !getenv("SKYRIM_SKIP_LAUNCHER") && !getenv("FNV_SKIP_LAUNCHER") && (!opts.skipLauncher || optionHeld);
}

- (void)enableOptionsOnNextLaunch {
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:kPrefSkipLauncher];
    [NSUserDefaults.standardUserDefaults synchronize];
}

- (FNVLaunchSettings)currentLaunchSettings {
    SkyrimOptions opts = loadSkyrimOptions(self.nativeW);
    self.savedOpts = opts;
    self.hasSavedOpts = YES;
    return (FNVLaunchSettings){opts.renderScale, opts.upscaler, opts.antiAliasing, opts.displayMode};
}

- (unsigned)selectedRenderScale {
    NSInteger tag = self.scalePopup.selectedItem.tag;
    return tag > 0 ? clampScale(tag) : 100u;
}

- (void)updateOptionsPreview {
    unsigned pct = [self selectedRenderScale];
    unsigned ow = ((self.nativeW / 2u) * 2u); if (ow < 640u) ow = 640u;
    unsigned targetH = (self.displayPopup && self.displayPopup.selectedItem.tag == FNVDisplayModeBorderlessFullscreen && self.fullPanelH > 0)
        ? self.fullPanelH
        : self.nativeH;
    unsigned oh = ((targetH / 2u) * 2u); if (oh < 480u) oh = 480u;
    unsigned rw = ((ow * pct / 100u) / 2u) * 2u; if (rw < 640u) rw = 640u; if (rw > ow) rw = ow;
    unsigned rh = ((oh * pct / 100u) / 2u) * 2u; if (rh < 480u) rh = 480u; if (rh > oh) rh = oh;
    if (pct == 100u) {
        self.resPreviewLabel.stringValue = [NSString stringWithFormat:@"Internal: %ux%u (native, upscaler bypassed)", rw, rh];
        self.upscalerPopup.enabled = NO;
    } else {
        self.resPreviewLabel.stringValue = [NSString stringWithFormat:@"Internal: %ux%u -> Output: %ux%u", rw, rh, ow, oh];
        self.upscalerPopup.enabled = YES;
    }
}

- (void)displayModeChanged:(id)sender { (void)sender; [self updateOptionsPreview]; }

- (void)updateSkyrimDetailControlsEnabled {
    BOOL enable = (self.presetPopup.selectedItem.tag != 0);
    self.anisoPopup.enabled = enable;
    self.advancedBtn.enabled = enable;
}

- (void)presetChanged:(id)sender {
    (void)sender;
    int p = (int)self.presetPopup.selectedItem.tag;
    SkyrimOptions tmp = self.workingOpts;
    tmp.preset = p;
    if (p > 0) {
        applySkyrimPresetDefaults(&tmp, p);
        [self.anisoPopup selectItemWithTag:tmp.anisotropy];
    } else {
        tmp.shadowQuality = 0;
    }
    self.workingOpts = tmp;
    [self updateSkyrimDetailControlsEnabled];
}

- (void)scaleChanged:(id)sender {
    (void)sender;
    [self updateOptionsPreview];
}

- (void)updateFovUI {
    int fp = (int)self.fovPresetPopup.selectedItem.tag;
    int wf = clampInt((int)llround(self.worldFovSlider.doubleValue), 65, 105);
    int fpf = clampInt((int)llround(self.firstPersonFovSlider.doubleValue), 65, 95);
    BOOL enable = (fp != 0);
    self.worldFovSlider.enabled = enable;
    self.firstPersonFovSlider.enabled = enable;
    self.worldFovValueLabel.stringValue = [NSString stringWithFormat:@"%d°", wf];
    self.firstPersonFovValueLabel.stringValue = [NSString stringWithFormat:@"%d°", fpf];
    self.worldFovValueLabel.textColor = enable ? NSColor.labelColor : NSColor.tertiaryLabelColor;
    self.firstPersonFovValueLabel.textColor = enable ? NSColor.labelColor : NSColor.tertiaryLabelColor;
    if (!enable) {
        self.fovTipLabel.stringValue = @"Keeping existing FOV settings in Skyrim.ini.";
    } else if (wf == 65 && fpf == 65) {
        self.fovTipLabel.stringValue = @"Vanilla Skyrim defaults (Skyrim.ini).";
    } else if (fpf > 85) {
        self.fovTipLabel.stringValue = [NSString stringWithFormat:@">85° 1st-person may clip arms/bows. Saves: \"fov %d\" in console (~).", wf];
    } else {
        self.fovTipLabel.stringValue = [NSString stringWithFormat:@"New games apply automatically; existing saves: \"fov %d\" in console (~).", wf];
    }
}

- (void)fovPresetChanged:(id)sender {
    (void)sender;
    int fp = (int)self.fovPresetPopup.selectedItem.tag;
    if (fp >= 1 && fp <= 3) {
        SkyrimOptions tmp = {0};
        applySkyrimFovPresetDefaults(&tmp, fp);
        self.worldFovSlider.integerValue = tmp.worldFov;
        self.firstPersonFovSlider.integerValue = tmp.firstPersonFov;
    }
    [self updateFovUI];
}

- (void)fovSliderChanged:(id)sender {
    (void)sender;
    int wf = clampInt((int)llround(self.worldFovSlider.doubleValue), 65, 105);
    int fpf = clampInt((int)llround(self.firstPersonFovSlider.doubleValue), 65, 95);
    self.worldFovSlider.integerValue = wf;
    self.firstPersonFovSlider.integerValue = fpf;
    [self.fovPresetPopup selectItemWithTag:matchingSkyrimFovPreset(wf, fpf)];
    [self updateFovUI];
}

#pragma mark - Advanced Sheet (Detail + View Distance)

- (void)advSliderChanged:(id)sender {
    (void)sender;
    self.advObjectFadeLabel.stringValue = [NSString stringWithFormat:@"%d", (int)llround(self.advObjectFadeSlider.doubleValue)];
    self.advActorFadeLabel.stringValue  = [NSString stringWithFormat:@"%d", (int)llround(self.advActorFadeSlider.doubleValue)];
    self.advGrassFadeLabel.stringValue  = [NSString stringWithFormat:@"%d", (int)llround(self.advGrassFadeSlider.doubleValue)];
    self.advSpecFadeLabel.stringValue   = [NSString stringWithFormat:@"%d", (int)llround(self.advSpecFadeSlider.doubleValue)];
    self.advLightFadeLabel.stringValue  = [NSString stringWithFormat:@"%d", (int)llround(self.advLightFadeSlider.doubleValue)];
    self.advItemFadeLabel.stringValue   = [NSString stringWithFormat:@"%d", (int)llround(self.advItemFadeSlider.doubleValue)];
}

- (void)populateAdvancedControlsFrom:(SkyrimOptions)opts {
    [self.advTexturePopup selectItemWithTag:opts.textureQuality];
    [self.advRadialBlurPopup selectItemWithTag:opts.radialBlurQuality];
    [self.advShadowPopup selectItemWithTag:(opts.shadowQuality > 0 ? opts.shadowQuality : 3)];
    [self.advDecalPopup selectItemWithTag:opts.decalQuantity];
    self.advFxaaCheck.state = opts.vanillaFxaa ? NSControlStateValueOn : NSControlStateValueOff;
    self.advReflectLandCheck.state = opts.reflectLand ? NSControlStateValueOn : NSControlStateValueOff;
    self.advReflectTreesCheck.state = opts.reflectTrees ? NSControlStateValueOn : NSControlStateValueOff;
    self.advReflectObjectsCheck.state = opts.reflectObjects ? NSControlStateValueOn : NSControlStateValueOff;
    self.advReflectSkyCheck.state = opts.reflectSky ? NSControlStateValueOn : NSControlStateValueOff;

    self.advObjectFadeSlider.integerValue = opts.objectFade;
    self.advActorFadeSlider.integerValue  = opts.actorFade;
    self.advGrassFadeSlider.integerValue  = opts.grassFade;
    self.advSpecFadeSlider.integerValue   = opts.specularityFade;
    self.advLightFadeSlider.integerValue  = opts.lightFade;
    self.advItemFadeSlider.integerValue   = opts.itemFade;
    [self.advDistantObjPopup selectItemWithTag:opts.distantObjectDetail];
    self.advObjDetailFadeCheck.state = opts.objectDetailFade ? NSControlStateValueOn : NSControlStateValueOff;

    [self advSliderChanged:nil];
}

- (void)readAdvancedControlsInto:(SkyrimOptions *)opts {
    opts->textureQuality = (int)self.advTexturePopup.selectedItem.tag;
    opts->radialBlurQuality = (int)self.advRadialBlurPopup.selectedItem.tag;
    opts->shadowQuality = (int)self.advShadowPopup.selectedItem.tag;
    opts->decalQuantity = (int)self.advDecalPopup.selectedItem.tag;
    opts->vanillaFxaa = (self.advFxaaCheck.state == NSControlStateValueOn);
    opts->reflectLand = (self.advReflectLandCheck.state == NSControlStateValueOn);
    opts->reflectTrees = (self.advReflectTreesCheck.state == NSControlStateValueOn);
    opts->reflectObjects = (self.advReflectObjectsCheck.state == NSControlStateValueOn);
    opts->reflectSky = (self.advReflectSkyCheck.state == NSControlStateValueOn);

    opts->objectFade = clampInt((int)llround(self.advObjectFadeSlider.doubleValue), 1, 15);
    opts->actorFade = clampInt((int)llround(self.advActorFadeSlider.doubleValue), 2, 15);
    opts->grassFade = clampInt((int)llround(self.advGrassFadeSlider.doubleValue), 0, 7);
    opts->specularityFade = clampInt((int)llround(self.advSpecFadeSlider.doubleValue), 2, 20);
    opts->lightFade = clampInt((int)llround(self.advLightFadeSlider.doubleValue), 2, 35);
    opts->itemFade = clampInt((int)llround(self.advItemFadeSlider.doubleValue), 1, 15);
    opts->distantObjectDetail = (int)self.advDistantObjPopup.selectedItem.tag;
    opts->objectDetailFade = (self.advObjDetailFadeCheck.state == NSControlStateValueOn);
}

- (void)ensureAdvancedWindow {
    if (self.advancedWindow) return;

    NSRect rect = NSMakeRect(0, 0, 470, 396);
    self.advancedWindow = [[NSWindow alloc] initWithContentRect:rect
                                                      styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                        backing:NSBackingStoreBuffered
                                                          defer:NO];
    self.advancedWindow.title = [NSString stringWithFormat:@"%@ — Advanced Options", GAME_TITLE];
    self.advancedWindow.releasedWhenClosed = NO;
    NSView *cv = self.advancedWindow.contentView;

    NSTabView *tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(16, 54, 438, 328)];
    [cv addSubview:tabs];

    NSTextField *(^mkLabel)(NSView *, NSString *, CGFloat, CGFloat, CGFloat) =
        ^NSTextField *(NSView *v, NSString *txt, CGFloat x, CGFloat y, CGFloat w) {
        NSTextField *l = [NSTextField labelWithString:txt];
        l.alignment = NSTextAlignmentRight;
        l.frame = NSMakeRect(x, y, w, 20);
        [v addSubview:l];
        return l;
    };
    void (^mkSliderRow)(NSView *, NSString *, CGFloat, int, int, NSSlider *__strong *, NSTextField *__strong *) =
        ^(NSView *v, NSString *txt, CGFloat y, int lo, int hi, NSSlider *__strong *outS, NSTextField *__strong *outL) {
        mkLabel(v, txt, 8, y, 146);
        NSSlider *s = [NSSlider sliderWithValue:lo minValue:lo maxValue:hi target:self action:@selector(advSliderChanged:)];
        s.frame = NSMakeRect(162, y - 2, 198, 24);
        s.continuous = YES;
        [v addSubview:s];
        NSTextField *val = [NSTextField labelWithString:@""];
        val.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
        val.alignment = NSTextAlignmentRight;
        val.frame = NSMakeRect(366, y, 40, 20);
        [v addSubview:val];
        *outS = s;
        *outL = val;
    };

    // --- Tab 1: Detail ---
    NSTabViewItem *detailItem = [[NSTabViewItem alloc] initWithIdentifier:@"detail"];
    detailItem.label = @"Detail";
    NSView *dv = detailItem.view;

    mkLabel(dv, @"Texture Quality:", 12, 248, 152);
    self.advTexturePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(172, 246, 200, 26) pullsDown:NO];
    [self.advTexturePopup addItemWithTitle:@"Low"];    self.advTexturePopup.lastItem.tag = 2;
    [self.advTexturePopup addItemWithTitle:@"Medium"]; self.advTexturePopup.lastItem.tag = 1;
    [self.advTexturePopup addItemWithTitle:@"High"];   self.advTexturePopup.lastItem.tag = 0;
    [dv addSubview:self.advTexturePopup];

    mkLabel(dv, @"Radial Blur Quality:", 12, 214, 152);
    self.advRadialBlurPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(172, 212, 200, 26) pullsDown:NO];
    [self.advRadialBlurPopup addItemWithTitle:@"Low"];    self.advRadialBlurPopup.lastItem.tag = 0;
    [self.advRadialBlurPopup addItemWithTitle:@"Medium"]; self.advRadialBlurPopup.lastItem.tag = 1;
    [self.advRadialBlurPopup addItemWithTitle:@"High"];   self.advRadialBlurPopup.lastItem.tag = 2;
    [dv addSubview:self.advRadialBlurPopup];

    mkLabel(dv, @"Shadow Detail:", 12, 180, 152);
    self.advShadowPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(172, 178, 200, 26) pullsDown:NO];
    [self.advShadowPopup addItemWithTitle:@"Low (512)"];     self.advShadowPopup.lastItem.tag = 1;
    [self.advShadowPopup addItemWithTitle:@"Medium (1024)"]; self.advShadowPopup.lastItem.tag = 2;
    [self.advShadowPopup addItemWithTitle:@"High (2048)"];   self.advShadowPopup.lastItem.tag = 3;
    [self.advShadowPopup addItemWithTitle:@"Ultra (4096)"];  self.advShadowPopup.lastItem.tag = 4;
    [dv addSubview:self.advShadowPopup];

    mkLabel(dv, @"Decal Quantity:", 12, 146, 152);
    self.advDecalPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(172, 144, 200, 26) pullsDown:NO];
    [self.advDecalPopup addItemWithTitle:@"None"];   self.advDecalPopup.lastItem.tag = 0;
    [self.advDecalPopup addItemWithTitle:@"Medium"]; self.advDecalPopup.lastItem.tag = 1;
    [self.advDecalPopup addItemWithTitle:@"High"];   self.advDecalPopup.lastItem.tag = 2;
    [self.advDecalPopup addItemWithTitle:@"Ultra"];  self.advDecalPopup.lastItem.tag = 3;
    [dv addSubview:self.advDecalPopup];

    self.advFxaaCheck = [NSButton checkboxWithTitle:@"FXAA (In-Game Shader)" target:nil action:nil];
    self.advFxaaCheck.frame = NSMakeRect(172, 114, 200, 18);
    [dv addSubview:self.advFxaaCheck];

    NSBox *waterBox = [[NSBox alloc] initWithFrame:NSMakeRect(24, 18, 386, 84)];
    waterBox.title = @"Water";
    [dv addSubview:waterBox];
    NSView *wbv = waterBox.contentView;
    self.advReflectLandCheck = [NSButton checkboxWithTitle:@"Reflect Land" target:nil action:nil];
    self.advReflectLandCheck.frame = NSMakeRect(16, 36, 150, 18);
    [wbv addSubview:self.advReflectLandCheck];
    self.advReflectTreesCheck = [NSButton checkboxWithTitle:@"Reflect Trees" target:nil action:nil];
    self.advReflectTreesCheck.frame = NSMakeRect(16, 12, 150, 18);
    [wbv addSubview:self.advReflectTreesCheck];
    self.advReflectObjectsCheck = [NSButton checkboxWithTitle:@"Reflect Objects" target:nil action:nil];
    self.advReflectObjectsCheck.frame = NSMakeRect(190, 36, 160, 18);
    [wbv addSubview:self.advReflectObjectsCheck];
    self.advReflectSkyCheck = [NSButton checkboxWithTitle:@"Reflect Sky" target:nil action:nil];
    self.advReflectSkyCheck.frame = NSMakeRect(190, 12, 160, 18);
    [wbv addSubview:self.advReflectSkyCheck];

    [tabs addTabViewItem:detailItem];

    // --- Tab 2: View Distance ---
    NSTabViewItem *vdItem = [[NSTabViewItem alloc] initWithIdentifier:@"viewdistance"];
    vdItem.label = @"View Distance";
    NSView *vv = vdItem.view;

    NSSlider *sObj = nil, *sAct = nil, *sGr = nil, *sSp = nil, *sLi = nil, *sIt = nil;
    NSTextField *lObj = nil, *lAct = nil, *lGr = nil, *lSp = nil, *lLi = nil, *lIt = nil;
    mkSliderRow(vv, @"Object Fade:",      252, 1, 15, &sObj, &lObj);
    mkSliderRow(vv, @"Actor Fade:",       220, 2, 15, &sAct, &lAct);
    mkSliderRow(vv, @"Grass Fade:",       188, 0,  7, &sGr,  &lGr);
    mkSliderRow(vv, @"Specularity Fade:", 156, 2, 20, &sSp,  &lSp);
    mkSliderRow(vv, @"Light Fade:",       124, 2, 35, &sLi,  &lLi);
    mkSliderRow(vv, @"Item Fade:",         92, 1, 15, &sIt,  &lIt);
    self.advObjectFadeSlider = sObj; self.advObjectFadeLabel = lObj;
    self.advActorFadeSlider  = sAct; self.advActorFadeLabel  = lAct;
    self.advGrassFadeSlider  = sGr;  self.advGrassFadeLabel  = lGr;
    self.advSpecFadeSlider   = sSp;  self.advSpecFadeLabel   = lSp;
    self.advLightFadeSlider  = sLi;  self.advLightFadeLabel  = lLi;
    self.advItemFadeSlider   = sIt;  self.advItemFadeLabel   = lIt;

    mkLabel(vv, @"Distant Object Detail:", 8, 52, 146);
    self.advDistantObjPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(162, 50, 200, 26) pullsDown:NO];
    [self.advDistantObjPopup addItemWithTitle:@"Low"];    self.advDistantObjPopup.lastItem.tag = 0;
    [self.advDistantObjPopup addItemWithTitle:@"Medium"]; self.advDistantObjPopup.lastItem.tag = 1;
    [self.advDistantObjPopup addItemWithTitle:@"High"];   self.advDistantObjPopup.lastItem.tag = 2;
    [self.advDistantObjPopup addItemWithTitle:@"Ultra"];  self.advDistantObjPopup.lastItem.tag = 3;
    [vv addSubview:self.advDistantObjPopup];

    self.advObjDetailFadeCheck = [NSButton checkboxWithTitle:@"Object Detail Fade" target:nil action:nil];
    self.advObjDetailFadeCheck.frame = NSMakeRect(162, 20, 200, 18);
    [vv addSubview:self.advObjDetailFadeCheck];

    [tabs addTabViewItem:vdItem];

    NSButton *resetBtn = [NSButton buttonWithTitle:@"Reset to Preset" target:self action:@selector(advResetClicked:)];
    resetBtn.frame = NSMakeRect(16, 14, 130, 30);
    [cv addSubview:resetBtn];

    NSButton *cancelBtn = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(advCancelClicked:)];
    cancelBtn.frame = NSMakeRect(274, 14, 86, 30);
    cancelBtn.keyEquivalent = @"\033";
    [cv addSubview:cancelBtn];

    NSButton *okBtn = [NSButton buttonWithTitle:@"OK" target:self action:@selector(advOkClicked:)];
    okBtn.frame = NSMakeRect(368, 14, 86, 30);
    okBtn.keyEquivalent = @"\r";
    [cv addSubview:okBtn];
}

- (void)advancedClicked:(id)sender {
    (void)sender;
    [self ensureAdvancedWindow];
    [self populateAdvancedControlsFrom:self.workingOpts];
    [self.optionsWindow beginSheet:self.advancedWindow completionHandler:nil];
}

- (void)advResetClicked:(id)sender {
    (void)sender;
    int p = (int)self.presetPopup.selectedItem.tag;
    if (p <= 0) p = 3;
    SkyrimOptions tmp = self.workingOpts;
    applySkyrimPresetDefaults(&tmp, p);
    [self populateAdvancedControlsFrom:tmp];
}

- (void)advCancelClicked:(id)sender {
    (void)sender;
    [self.optionsWindow endSheet:self.advancedWindow returnCode:NSModalResponseCancel];
}

- (void)advOkClicked:(id)sender {
    (void)sender;
    SkyrimOptions tmp = self.workingOpts;
    [self readAdvancedControlsInto:&tmp];
    self.workingOpts = tmp;
    [self.optionsWindow endSheet:self.advancedWindow returnCode:NSModalResponseOK];
}

- (void)exploreGameDataClicked:(id)sender {
    (void)sender;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *dir = nil;
    const char *envRoot = getenv("SKYRIM_ROOT");
    if (!envRoot || !envRoot[0]) envRoot = getenv("FNV_ROOT");
    if (envRoot && envRoot[0]) {
        dir = [NSURL fileURLWithPath:@(envRoot) isDirectory:YES];
    } else {
        NSURL *bundleGameData = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"GameData" isDirectory:YES];
        if ([fm fileExistsAtPath:bundleGameData.path]) {
            dir = bundleGameData;
        } else {
            dir = [NSURL fileURLWithPath:fm.currentDirectoryPath isDirectory:YES];
        }
    }
    if (dir) {
        [NSWorkspace.sharedWorkspace openURL:dir];
    }
}

- (void)quitClicked:(id)sender {
    (void)sender;
    [NSApp terminate:nil];
}

- (void)playClicked:(id)sender {
    (void)sender;
    SkyrimOptions opts = self.workingOpts;
    opts.preset = (int)self.presetPopup.selectedItem.tag;
    opts.anisotropy = (int)self.anisoPopup.selectedItem.tag;
    opts.renderScale = [self selectedRenderScale];
    opts.upscaler = (int)self.upscalerPopup.selectedItem.tag;
    opts.antiAliasing = (int)self.aaPopup.selectedItem.tag;
    opts.fovPreset = (int)self.fovPresetPopup.selectedItem.tag;
    opts.worldFov = clampInt((int)llround(self.worldFovSlider.doubleValue), 65, 105);
    opts.firstPersonFov = clampInt((int)llround(self.firstPersonFovSlider.doubleValue), 65, 95);
    opts.displayMode = (FNVDisplayMode)self.displayPopup.selectedItem.tag;
    opts.mouseAcceleration = (self.mouseAccelCheck.state != NSControlStateValueOn);
    opts.skipLauncher = (self.skipLauncherCheck.state == NSControlStateValueOn);
    saveSkyrimOptions(opts);

    // Re-apply env overrides if caller explicitly passed them
    SkyrimOptions launchOpts = loadSkyrimOptions(self.nativeW);
    launchOpts = opts;
    const char *envScale = getenv("SKYRIM_RENDER_SCALE");
    if (envScale && envScale[0]) launchOpts.renderScale = clampScale(strtol(envScale, NULL, 10));
    const char *envUp = getenv("SKYRIM_UPSCALER");
    if (envUp && envUp[0]) {
        if (!strcasecmp(envUp, "bilinear") || !strcmp(envUp, "0")) launchOpts.upscaler = 0;
        else if (!strcasecmp(envUp, "metalfx") || !strcasecmp(envUp, "metalfx-spatial") || !strcmp(envUp, "1")) launchOpts.upscaler = 1;
    }
    const char *envAA = getenv("SKYRIM_AA");
    if (envAA && envAA[0]) {
        if (!strcasecmp(envAA, "smaa") || !strcmp(envAA, "1")) launchOpts.antiAliasing = 1;
        else if (!strcasecmp(envAA, "fxaa") || !strcmp(envAA, "2")) launchOpts.antiAliasing = 2;
        else if (!strcasecmp(envAA, "off") || !strcasecmp(envAA, "none") || !strcmp(envAA, "0")) launchOpts.antiAliasing = 0;
    }
    const char *envSh = getenv("SKYRIM_SHADOWS");
    if (envSh && envSh[0]) {
        if (!strcasecmp(envSh, "low") || !strcmp(envSh, "1")) launchOpts.shadowQuality = 1;
        else if (!strcasecmp(envSh, "medium") || !strcmp(envSh, "2")) launchOpts.shadowQuality = 2;
        else if (!strcasecmp(envSh, "high") || !strcmp(envSh, "3")) launchOpts.shadowQuality = 3;
        else if (!strcasecmp(envSh, "ultra") || !strcmp(envSh, "4")) launchOpts.shadowQuality = 4;
        else if (!strcasecmp(envSh, "keep") || !strcmp(envSh, "0")) launchOpts.shadowQuality = 0;
    }
    const char *envFov = getenv("SKYRIM_FOV");
    const char *envFpFov = getenv("SKYRIM_1ST_PERSON_FOV");
    if (envFov && envFov[0]) launchOpts.worldFov = clampInt((int)strtol(envFov, NULL, 10), 65, 105);
    if (envFpFov && envFpFov[0]) launchOpts.firstPersonFov = clampInt((int)strtol(envFpFov, NULL, 10), 65, 95);
    if ((envFov && envFov[0]) || (envFpFov && envFpFov[0])) {
        launchOpts.fovPreset = matchingSkyrimFovPreset(launchOpts.worldFov, launchOpts.firstPersonFov);
    }
    const char *envBorderless = getenv("FNV_BORDERLESS");
    if (envBorderless && envBorderless[0] && atoi(envBorderless) != 0) {
        launchOpts.displayMode = FNVDisplayModeBorderlessFullscreen;
    }
    if (getenv("FNV_WINDOWED")) launchOpts.displayMode = FNVDisplayModeWindowed;
    const char *envMA = getenv("SKYRIM_MOUSE_ACCEL");
    if (envMA && envMA[0]) launchOpts.mouseAcceleration = (atoi(envMA) != 0);

    self.savedOpts = launchOpts;
    self.hasSavedOpts = YES;
    if (self.onPlay) {
        self.onPlay((FNVLaunchSettings){launchOpts.renderScale, launchOpts.upscaler, launchOpts.antiAliasing, launchOpts.displayMode});
    }
}

- (NSWindow *)presentWindowWithDelegate:(id<NSWindowDelegate>)delegate
                                 onPlay:(void (^)(FNVLaunchSettings settings))onPlay {
    self.onPlay = onPlay;
    SkyrimOptions opts = loadSkyrimOptions(self.nativeW);
    self.workingOpts = opts;

    NSRect rect = NSMakeRect(0, 0, 480, 543);
    self.optionsWindow = [[NSWindow alloc] initWithContentRect:rect
                                                     styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                       backing:NSBackingStoreBuffered
                                                         defer:NO];
    self.optionsWindow.title = [NSString stringWithFormat:@"%@ — Options", GAME_TITLE];
    self.optionsWindow.delegate = delegate;
    self.optionsWindow.releasedWhenClosed = NO;
    NSView *cv = self.optionsWindow.contentView;

    NSTextField *title = [NSTextField labelWithString:@"Graphics & Input Options"];
    title.font = [NSFont boldSystemFontOfSize:15];
    title.frame = NSMakeRect(24, 507, 432, 22);
    [cv addSubview:title];

    NSString *dispStr = (self.backingW != self.nativeW || self.backingH != self.nativeH)
        ? [NSString stringWithFormat:@"Display: %ux%u panel (desktop %ux%u) @ %d Hz",
           self.nativeW, self.nativeH, self.backingW, self.backingH, self.refreshHz]
        : [NSString stringWithFormat:@"Display: %ux%u @ %d Hz",
           self.nativeW, self.nativeH, self.refreshHz];
    NSTextField *sub = [NSTextField labelWithString:dispStr];
    sub.font = [NSFont systemFontOfSize:12];
    sub.textColor = NSColor.secondaryLabelColor;
    sub.frame = NSMakeRect(24, 487, 432, 16);
    [cv addSubview:sub];

    NSBox *sep1 = [[NSBox alloc] initWithFrame:NSMakeRect(24, 478, 432, 1)];
    sep1.boxType = NSBoxSeparator;
    [cv addSubview:sep1];

    NSTextField *(^mkLabel)(NSString *, CGFloat) = ^NSTextField *(NSString *txt, CGFloat y) {
        NSTextField *l = [NSTextField labelWithString:txt];
        l.alignment = NSTextAlignmentRight;
        l.frame = NSMakeRect(24, y, 160, 20);
        [cv addSubview:l];
        return l;
    };
    NSPopUpButton *(^mkPopup)(CGFloat) = ^NSPopUpButton *(CGFloat y) {
        NSPopUpButton *p = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(196, y, 260, 26) pullsDown:NO];
        [cv addSubview:p];
        return p;
    };

    mkLabel(@"Quality Preset:", 444);
    self.presetPopup = mkPopup(442);
    [self.presetPopup addItemWithTitle:@"Ultra"]; self.presetPopup.lastItem.tag = 4;
    [self.presetPopup addItemWithTitle:@"High (Recommended)"]; self.presetPopup.lastItem.tag = 3;
    [self.presetPopup addItemWithTitle:@"Medium"]; self.presetPopup.lastItem.tag = 2;
    [self.presetPopup addItemWithTitle:@"Low"]; self.presetPopup.lastItem.tag = 1;
    [self.presetPopup addItemWithTitle:@"Keep SkyrimPrefs.ini"]; self.presetPopup.lastItem.tag = 0;
    [self.presetPopup selectItemWithTag:opts.preset];
    self.presetPopup.target = self;
    self.presetPopup.action = @selector(presetChanged:);

    mkLabel(@"Render Scale:", 413);
    self.scalePopup = mkPopup(411);
    struct { NSString *label; NSInteger tag; } scaleItems[] = {
        {@"100% (Native)", 100}, {@"85% (Quality)", 85}, {@"75% (Recommended)", 75},
        {@"67% (Balanced)", 67}, {@"50% (Performance)", 50},
    };
    for (size_t i = 0; i < sizeof scaleItems / sizeof scaleItems[0]; i++) {
        [self.scalePopup addItemWithTitle:scaleItems[i].label];
        self.scalePopup.lastItem.tag = scaleItems[i].tag;
    }
    if (![self.scalePopup selectItemWithTag:(NSInteger)opts.renderScale]) {
        NSString *custom = [NSString stringWithFormat:@"%u%% (Custom)", opts.renderScale];
        [self.scalePopup addItemWithTitle:custom];
        self.scalePopup.lastItem.tag = (NSInteger)opts.renderScale;
        [self.scalePopup selectItemWithTag:(NSInteger)opts.renderScale];
    }
    self.scalePopup.target = self;
    self.scalePopup.action = @selector(scaleChanged:);

    self.resPreviewLabel = [NSTextField labelWithString:@""];
    self.resPreviewLabel.font = [NSFont systemFontOfSize:11];
    self.resPreviewLabel.textColor = NSColor.secondaryLabelColor;
    self.resPreviewLabel.frame = NSMakeRect(198, 392, 258, 15);
    [cv addSubview:self.resPreviewLabel];

    mkLabel(@"Upscaler:", 364);
    self.upscalerPopup = mkPopup(362);
    [self.upscalerPopup addItemWithTitle:@"MetalFX Spatial"]; self.upscalerPopup.lastItem.tag = 1;
    [self.upscalerPopup addItemWithTitle:@"Bilinear"]; self.upscalerPopup.lastItem.tag = 0;
    [self.upscalerPopup selectItemWithTag:opts.upscaler];

    mkLabel(@"Anti-Aliasing:", 333);
    self.aaPopup = mkPopup(331);
    [self.aaPopup addItemWithTitle:@"Off"]; self.aaPopup.lastItem.tag = 0;
    [self.aaPopup addItemWithTitle:@"SMAA (Post-Process)"]; self.aaPopup.lastItem.tag = 1;
    [self.aaPopup addItemWithTitle:@"FXAA (Fast, Post-Process)"]; self.aaPopup.lastItem.tag = 2;
    [self.aaPopup selectItemWithTag:opts.antiAliasing];

    mkLabel(@"Anisotropic Filtering:", 302);
    self.anisoPopup = mkPopup(300);
    [self.anisoPopup addItemWithTitle:@"16 Samples (Max)"]; self.anisoPopup.lastItem.tag = 16;
    [self.anisoPopup addItemWithTitle:@"8 Samples"]; self.anisoPopup.lastItem.tag = 8;
    [self.anisoPopup addItemWithTitle:@"4 Samples"]; self.anisoPopup.lastItem.tag = 4;
    [self.anisoPopup addItemWithTitle:@"2 Samples"]; self.anisoPopup.lastItem.tag = 2;
    [self.anisoPopup addItemWithTitle:@"Off (best performance)"]; self.anisoPopup.lastItem.tag = 0;
    if (![self.anisoPopup selectItemWithTag:opts.anisotropy]) [self.anisoPopup selectItemWithTag:8];

    mkLabel(@"Display Mode:", 271);
    self.displayPopup = mkPopup(269);
    [self.displayPopup addItemWithTitle:@"Fullscreen"]; self.displayPopup.lastItem.tag = FNVDisplayModeFullscreen;
    [self.displayPopup addItemWithTitle:(self.fullPanelH > self.nativeH) ? @"Borderless Fullscreen (Full Panel)" : @"Borderless Fullscreen"];
    self.displayPopup.lastItem.tag = FNVDisplayModeBorderlessFullscreen;
    [self.displayPopup addItemWithTitle:@"Windowed"]; self.displayPopup.lastItem.tag = FNVDisplayModeWindowed;
    if (![self.displayPopup selectItemWithTag:opts.displayMode]) {
        [self.displayPopup selectItemWithTag:FNVDisplayModeFullscreen];
    }
    self.displayPopup.target = self;
    self.displayPopup.action = @selector(displayModeChanged:);
    self.displayPopup.toolTip = @"Fullscreen uses a native macOS Space and triggers Game Mode. Borderless Fullscreen covers the full panel including beside the camera notch, but macOS Game Mode and Spaces will not engage, and Skyrim's top compass may sit behind the camera housing.";
    [self updateOptionsPreview];

    mkLabel(@"FOV Preset:", 240);
    self.fovPresetPopup = mkPopup(238);
    [self.fovPresetPopup addItemWithTitle:@"Original (65° / 65°)"]; self.fovPresetPopup.lastItem.tag = 1;
    [self.fovPresetPopup addItemWithTitle:@"Expanded (85° / 80°)"]; self.fovPresetPopup.lastItem.tag = 2;
    [self.fovPresetPopup addItemWithTitle:@"Wide (95° / 85°)"]; self.fovPresetPopup.lastItem.tag = 3;
    [self.fovPresetPopup addItemWithTitle:@"Custom"]; self.fovPresetPopup.lastItem.tag = 4;
    [self.fovPresetPopup addItemWithTitle:@"Keep Skyrim.ini"]; self.fovPresetPopup.lastItem.tag = 0;
    [self.fovPresetPopup selectItemWithTag:opts.fovPreset];
    self.fovPresetPopup.target = self;
    self.fovPresetPopup.action = @selector(fovPresetChanged:);

    mkLabel(@"World FOV:", 211);
    self.worldFovSlider = [NSSlider sliderWithValue:opts.worldFov minValue:65 maxValue:105 target:self action:@selector(fovSliderChanged:)];
    self.worldFovSlider.frame = NSMakeRect(196, 208, 214, 24);
    self.worldFovSlider.numberOfTickMarks = 9;
    self.worldFovSlider.allowsTickMarkValuesOnly = NO;
    self.worldFovSlider.continuous = YES;
    [cv addSubview:self.worldFovSlider];

    self.worldFovValueLabel = [NSTextField labelWithString:@""];
    self.worldFovValueLabel.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.worldFovValueLabel.alignment = NSTextAlignmentRight;
    self.worldFovValueLabel.frame = NSMakeRect(414, 211, 42, 20);
    [cv addSubview:self.worldFovValueLabel];

    mkLabel(@"1st-Person FOV:", 183);
    self.firstPersonFovSlider = [NSSlider sliderWithValue:opts.firstPersonFov minValue:65 maxValue:95 target:self action:@selector(fovSliderChanged:)];
    self.firstPersonFovSlider.frame = NSMakeRect(196, 180, 214, 24);
    self.firstPersonFovSlider.numberOfTickMarks = 7;
    self.firstPersonFovSlider.allowsTickMarkValuesOnly = NO;
    self.firstPersonFovSlider.continuous = YES;
    [cv addSubview:self.firstPersonFovSlider];

    self.firstPersonFovValueLabel = [NSTextField labelWithString:@""];
    self.firstPersonFovValueLabel.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.firstPersonFovValueLabel.alignment = NSTextAlignmentRight;
    self.firstPersonFovValueLabel.frame = NSMakeRect(414, 183, 42, 20);
    [cv addSubview:self.firstPersonFovValueLabel];

    self.fovTipLabel = [NSTextField labelWithString:@""];
    self.fovTipLabel.font = [NSFont systemFontOfSize:11];
    self.fovTipLabel.textColor = NSColor.secondaryLabelColor;
    self.fovTipLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.fovTipLabel.maximumNumberOfLines = 2;
    self.fovTipLabel.frame = NSMakeRect(198, 150, 258, 26);
    [cv addSubview:self.fovTipLabel];

    self.mouseAccelCheck = [NSButton checkboxWithTitle:@"Disable in-game mouse acceleration (smoother mouse)"
                                                target:nil action:nil];
    self.mouseAccelCheck.frame = NSMakeRect(24, 124, 432, 18);
    self.mouseAccelCheck.state = opts.mouseAcceleration ? NSControlStateValueOff : NSControlStateValueOn;
    [cv addSubview:self.mouseAccelCheck];

    NSTextField *mouseTip = [NSTextField wrappingLabelWithString:@"Tip: for external mice, also disable Pointer Acceleration in System Settings → Mouse."];
    mouseTip.font = [NSFont systemFontOfSize:11];
    mouseTip.textColor = NSColor.secondaryLabelColor;
    mouseTip.maximumNumberOfLines = 2;
    mouseTip.frame = NSMakeRect(42, 93, 414, 28);
    [cv addSubview:mouseTip];

    self.skipLauncherCheck = [NSButton checkboxWithTitle:@"Skip this window on next launch (hold Option ⌥ to reopen)"
                                                  target:nil action:nil];
    self.skipLauncherCheck.frame = NSMakeRect(24, 68, 432, 18);
    self.skipLauncherCheck.state = opts.skipLauncher ? NSControlStateValueOn : NSControlStateValueOff;
    [cv addSubview:self.skipLauncherCheck];

    NSBox *sep2 = [[NSBox alloc] initWithFrame:NSMakeRect(24, 56, 432, 1)];
    sep2.boxType = NSBoxSeparator;
    [cv addSubview:sep2];

    self.advancedBtn = [NSButton buttonWithTitle:@"Advanced..." target:self action:@selector(advancedClicked:)];
    self.advancedBtn.frame = NSMakeRect(24, 16, 96, 30);
    [cv addSubview:self.advancedBtn];

    NSButton *exploreBtn = [NSButton buttonWithTitle:@"Explore Game Data" target:self action:@selector(exploreGameDataClicked:)];
    exploreBtn.frame = NSMakeRect(126, 16, 144, 30);
    [cv addSubview:exploreBtn];

    NSButton *quitBtn = [NSButton buttonWithTitle:@"Quit" target:self action:@selector(quitClicked:)];
    quitBtn.frame = NSMakeRect(294, 16, 76, 30);
    [cv addSubview:quitBtn];

    NSButton *playBtn = [NSButton buttonWithTitle:@"Play" target:self action:@selector(playClicked:)];
    playBtn.frame = NSMakeRect(378, 16, 78, 30);
    playBtn.keyEquivalent = @"\r";
    [cv addSubview:playBtn];

    [self updateOptionsPreview];
    [self updateSkyrimDetailControlsEnabled];
    [self updateFovUI];
    [self.optionsWindow center];
    [self.optionsWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    return self.optionsWindow;
}

- (void)prepareGameFilesInRoot:(NSURL *)root
                       userDir:(NSURL *)userDir
                          outW:(unsigned)outW
                          outH:(unsigned)outH {
    SkyrimOptions opts = self.hasSavedOpts ? self.savedOpts : loadSkyrimOptions(self.nativeW);
    NSFileManager *fm = NSFileManager.defaultManager;

    // Ensure LocalAppData/Skyrim/plugins.txt exists so official masters/DLCs load without SkyrimLauncher.
    NSString *localSkyrimDir = [userDir.path stringByAppendingPathComponent:@"LocalAppData/Skyrim"];
    [fm createDirectoryAtPath:localSkyrimDir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *pluginsTxt = [localSkyrimDir stringByAppendingPathComponent:@"plugins.txt"];
    if (![fm fileExistsAtPath:pluginsTxt]) {
        NSMutableArray<NSString *> *plugins = [NSMutableArray array];
        NSArray<NSString *> *knownOrder = @[
            @"Skyrim.esm", @"Update.esm", @"Dawnguard.esm", @"HearthFires.esm", @"Dragonborn.esm",
            @"HighResTexturePack01.esp", @"HighResTexturePack02.esp", @"HighResTexturePack03.esp",
        ];
        NSString *dataDir = [root URLByAppendingPathComponent:@"Data"].path;
        for (NSString *p in knownOrder) {
            if ([fm fileExistsAtPath:[dataDir stringByAppendingPathComponent:p]]) [plugins addObject:p];
        }
        if (plugins.count > 0) {
            [[[plugins componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"]
                writeToFile:pluginsTxt atomically:YES encoding:NSISOLatin1StringEncoding error:NULL];
        }
    }

    // Update display/controller keys in SkyrimPrefs.ini while preserving all other user settings.
    NSString *myGamesDir = [userDir.path stringByAppendingPathComponent:@"My Games/Skyrim"];
    [fm createDirectoryAtPath:myGamesDir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *prefs = [myGamesDir stringByAppendingPathComponent:@"SkyrimPrefs.ini"];
    for (NSString *leaf in [fm contentsOfDirectoryAtPath:myGamesDir error:NULL]) {
        if ([leaf caseInsensitiveCompare:@"SkyrimPrefs.ini"] == NSOrderedSame) {
            prefs = [myGamesDir stringByAppendingPathComponent:leaf];
            break;
        }
    }
    if (![fm fileExistsAtPath:prefs]) {
        NSString *defaultPrefs = [root URLByAppendingPathComponent:@"Skyrim/SkyrimPrefs.ini"].path;
        if ([fm fileExistsAtPath:defaultPrefs]) [fm copyItemAtPath:defaultPrefs toPath:prefs error:NULL];
    }
    NSString *skyrimIni = [myGamesDir stringByAppendingPathComponent:@"Skyrim.ini"];
    for (NSString *leaf in [fm contentsOfDirectoryAtPath:myGamesDir error:NULL]) {
        if ([leaf caseInsensitiveCompare:@"Skyrim.ini"] == NSOrderedSame) {
            skyrimIni = [myGamesDir stringByAppendingPathComponent:leaf];
            break;
        }
    }
    if (![fm fileExistsAtPath:skyrimIni]) {
        NSString *defaultIni = [root URLByAppendingPathComponent:@"Skyrim_default.ini"].path;
        if ([fm fileExistsAtPath:defaultIni]) [fm copyItemAtPath:defaultIni toPath:skyrimIni error:NULL];
    }
    if (opts.fovPreset != 0) {
        NSString *iniText = [NSString stringWithContentsOfFile:skyrimIni encoding:NSISOLatin1StringEncoding error:NULL] ?: @"";
        NSMutableArray<NSString *> *iniLines = [[iniText componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] mutableCopy];
        FNVApplyIniSettings(iniLines, @{
            @"display": @{
                @"fdefaultworldfov":     @[@"fDefaultWorldFOV",     [NSString stringWithFormat:@"%.4f", (double)opts.worldFov]],
                @"fdefault1stpersonfov": @[@"fDefault1stPersonFOV", [NSString stringWithFormat:@"%.4f", (double)opts.firstPersonFov]],
            },
        });
        [[iniLines componentsJoinedByString:@"\n"] writeToFile:skyrimIni atomically:YES encoding:NSISOLatin1StringEncoding error:NULL];
    }
    NSString *text = [NSString stringWithContentsOfFile:prefs encoding:NSISOLatin1StringEncoding error:NULL] ?: @"";
    if ([fm fileExistsAtPath:prefs] && ![fm fileExistsAtPath:[prefs stringByAppendingString:@".before-native-display"]]) {
        [fm copyItemAtPath:prefs toPath:[prefs stringByAppendingString:@".before-native-display"] error:NULL];
    }
    NSMutableArray<NSString *> *lines = [[text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] mutableCopy];
    NSMutableDictionary *displaySettings = [@{
        @"isize w": @[@"iSize W", @(fnv_display_width())],
        @"isize h": @[@"iSize H", @(fnv_display_height())],
        @"bfull screen": @[@"bFull Screen", @1],
        @"sd3ddevice": @[@"sD3DDevice", @(fnv_display_adapter_description())],
    } mutableCopy];
    if (opts.shadowQuality == 1) {
        displaySettings[@"ishadowmapresolution"] = @[@"iShadowMapResolution", @512];
        displaySettings[@"ishadowmapresolutionprimary"] = @[@"iShadowMapResolutionPrimary", @512];
        displaySettings[@"ishadowmapresolutionsecondary"] = @[@"iShadowMapResolutionSecondary", @512];
        displaySettings[@"iblurdeferredshadowmask"] = @[@"iBlurDeferredShadowMask", @2];
        displaySettings[@"fshadowdistance"] = @[@"fShadowDistance", @"1500.0000"];
    } else if (opts.shadowQuality == 2) {
        displaySettings[@"ishadowmapresolution"] = @[@"iShadowMapResolution", @1024];
        displaySettings[@"ishadowmapresolutionprimary"] = @[@"iShadowMapResolutionPrimary", @1024];
        displaySettings[@"ishadowmapresolutionsecondary"] = @[@"iShadowMapResolutionSecondary", @512];
        displaySettings[@"iblurdeferredshadowmask"] = @[@"iBlurDeferredShadowMask", @3];
        displaySettings[@"fshadowdistance"] = @[@"fShadowDistance", @"2500.0000"];
    } else if (opts.shadowQuality == 3) {
        displaySettings[@"ishadowmapresolution"] = @[@"iShadowMapResolution", @2048];
        displaySettings[@"ishadowmapresolutionprimary"] = @[@"iShadowMapResolutionPrimary", @2048];
        displaySettings[@"ishadowmapresolutionsecondary"] = @[@"iShadowMapResolutionSecondary", @1024];
        displaySettings[@"iblurdeferredshadowmask"] = @[@"iBlurDeferredShadowMask", @5];
        displaySettings[@"fshadowdistance"] = @[@"fShadowDistance", @"4000.0000"];
    } else if (opts.shadowQuality == 4) {
        displaySettings[@"ishadowmapresolution"] = @[@"iShadowMapResolution", @4096];
        displaySettings[@"ishadowmapresolutionprimary"] = @[@"iShadowMapResolutionPrimary", @4096];
        displaySettings[@"ishadowmapresolutionsecondary"] = @[@"iShadowMapResolutionSecondary", @2048];
        displaySettings[@"iblurdeferredshadowmask"] = @[@"iBlurDeferredShadowMask", @3];
        displaySettings[@"fshadowdistance"] = @[@"fShadowDistance", @"8000.0000"];
    }
    NSMutableDictionary *settings = [@{
        @"display": displaySettings,
        @"main": @{
            @"bgamepadenable": @[@"bGamepadEnable", @1],
        },
        @"controls": @{
            @"bmouseacceleration": @[@"bMouseAcceleration", opts.mouseAcceleration ? @1 : @0],
        },
    } mutableCopy];
    if (opts.fovPreset != 0) {
        settings[@"general"] = @{
            @"fdefaultfov": @[@"fDefaultFOV", [NSString stringWithFormat:@"%.4f", (double)opts.worldFov]],
        };
    }
    if (opts.preset > 0) {
        // Detail
        displaySettings[@"itexmipmapskip"] = @[@"iTexMipMapSkip", @(opts.textureQuality)];
        displaySettings[@"imaxanisotropy"] = @[@"iMaxAnisotropy", @(opts.anisotropy)];
        displaySettings[@"bfloatpointrendertarget"] = @[@"bFloatPointRenderTarget", @0];
        displaySettings[@"bfxaaenabled"] = @[@"bFXAAEnabled", opts.vanillaFxaa ? @1 : @0];

        settings[@"imagespace"] = @{
            @"iradialblurlevel": @[@"iRadialBlurLevel", @(opts.radialBlurQuality)],
        };

        // Decal Quantity (0=None, 1=Medium, 2=High, 3=Ultra)
        if (opts.decalQuantity == 0) {
            displaySettings[@"imaxdecalsperframe"]     = @[@"iMaxDecalsPerFrame", @0];
            displaySettings[@"imaxskindecalsperframe"] = @[@"iMaxSkinDecalsPerFrame", @0];
            settings[@"decals"] = @{
                @"bdecals":        @[@"bDecals",        @0],
                @"bskinneddecals": @[@"bSkinnedDecals", @0],
                @"umaxdecals":     @[@"uMaxDecals",     @0],
                @"umaxskindecals": @[@"uMaxSkinDecals", @0],
            };
        } else if (opts.decalQuantity == 1) {
            displaySettings[@"imaxdecalsperframe"]     = @[@"iMaxDecalsPerFrame", @10];
            displaySettings[@"imaxskindecalsperframe"] = @[@"iMaxSkinDecalsPerFrame", @3];
            settings[@"decals"] = @{
                @"bdecals":        @[@"bDecals",        @1],
                @"bskinneddecals": @[@"bSkinnedDecals", @1],
                @"umaxdecals":     @[@"uMaxDecals",     @100],
                @"umaxskindecals": @[@"uMaxSkinDecals", @35],
            };
        } else if (opts.decalQuantity == 2) {
            displaySettings[@"imaxdecalsperframe"]     = @[@"iMaxDecalsPerFrame", @30];
            displaySettings[@"imaxskindecalsperframe"] = @[@"iMaxSkinDecalsPerFrame", @10];
            settings[@"decals"] = @{
                @"bdecals":        @[@"bDecals",        @1],
                @"bskinneddecals": @[@"bSkinnedDecals", @1],
                @"umaxdecals":     @[@"uMaxDecals",     @250],
                @"umaxskindecals": @[@"uMaxSkinDecals", @50],
            };
        } else {
            displaySettings[@"imaxdecalsperframe"]     = @[@"iMaxDecalsPerFrame", @100];
            displaySettings[@"imaxskindecalsperframe"] = @[@"iMaxSkinDecalsPerFrame", @25];
            settings[@"decals"] = @{
                @"bdecals":        @[@"bDecals",        @1],
                @"bskinneddecals": @[@"bSkinnedDecals", @1],
                @"umaxdecals":     @[@"uMaxDecals",     @1000],
                @"umaxskindecals": @[@"uMaxSkinDecals", @100],
            };
        }

        // Water Reflections
        settings[@"water"] = @{
            @"breflectlodland":    @[@"bReflectLODLand",    opts.reflectLand ? @1 : @0],
            @"breflectlodtrees":   @[@"bReflectLODTrees",   opts.reflectTrees ? @1 : @0],
            @"breflectlodobjects": @[@"bReflectLODObjects", opts.reflectObjects ? @1 : @0],
            @"breflectsky":        @[@"bReflectSky",        opts.reflectSky ? @1 : @0],
        };

        // View Distance
        displaySettings[@"fspecularlodstartfade"] = @[@"fSpecularLODStartFade", [NSString stringWithFormat:@"%.4f", (double)opts.specularityFade * 100.0]];
        displaySettings[@"flightlodstartfade"]    = @[@"fLightLODStartFade",    [NSString stringWithFormat:@"%.4f", (double)opts.lightFade * 100.0]];
        displaySettings[@"fmeshlodlevel2fadedist"] = @[@"fMeshLODLevel2FadeDist", opts.objectDetailFade ? @"3072.0000" : @"10000000.0000"];
        displaySettings[@"fmeshlodlevel1fadedist"] = @[@"fMeshLODLevel1FadeDist", opts.objectDetailFade ? @"4096.0000" : @"10000000.0000"];

        settings[@"lod"] = @{
            @"flodfadeoutmultobjects": @[@"fLODFadeOutMultObjects", [NSString stringWithFormat:@"%.4f", (double)opts.objectFade]],
            @"flodfadeoutmultactors":  @[@"fLODFadeOutMultActors",  [NSString stringWithFormat:@"%.4f", (double)opts.actorFade]],
            @"flodfadeoutmultitems":   @[@"fLODFadeOutMultItems",   [NSString stringWithFormat:@"%.4f", (double)opts.itemFade]],
        };
        settings[@"grass"] = @{
            @"fgrassstartfadedistance": @[@"fGrassStartFadeDistance", [NSString stringWithFormat:@"%.4f", (double)opts.grassFade * 1000.0]],
        };

        // Distant Object Detail (0=Low, 1=Medium, 2=High, 3=Ultra)
        if (opts.distantObjectDetail == 0) {
            settings[@"terrainmanager"] = @{
                @"ftreeloaddistance":     @[@"fTreeLoadDistance",     @"12500.0000"],
                @"fblockmaximumdistance": @[@"fBlockMaximumDistance", @"75000.0000"],
                @"fblocklevel1distance":  @[@"fBlockLevel1Distance",  @"25000.0000"],
                @"fblocklevel0distance":  @[@"fBlockLevel0Distance",  @"15000.0000"],
                @"fsplitdistancemult":    @[@"fSplitDistanceMult",    @"0.4000"],
            };
        } else if (opts.distantObjectDetail == 1) {
            settings[@"terrainmanager"] = @{
                @"ftreeloaddistance":     @[@"fTreeLoadDistance",     @"25000.0000"],
                @"fblockmaximumdistance": @[@"fBlockMaximumDistance", @"100000.0000"],
                @"fblocklevel1distance":  @[@"fBlockLevel1Distance",  @"32768.0000"],
                @"fblocklevel0distance":  @[@"fBlockLevel0Distance",  @"20480.0000"],
                @"fsplitdistancemult":    @[@"fSplitDistanceMult",    @"0.7500"],
            };
        } else if (opts.distantObjectDetail == 2) {
            settings[@"terrainmanager"] = @{
                @"ftreeloaddistance":     @[@"fTreeLoadDistance",     @"40000.0000"],
                @"fblockmaximumdistance": @[@"fBlockMaximumDistance", @"150000.0000"],
                @"fblocklevel1distance":  @[@"fBlockLevel1Distance",  @"40000.0000"],
                @"fblocklevel0distance":  @[@"fBlockLevel0Distance",  @"25000.0000"],
                @"fsplitdistancemult":    @[@"fSplitDistanceMult",    @"1.1000"],
            };
        } else {
            settings[@"terrainmanager"] = @{
                @"ftreeloaddistance":     @[@"fTreeLoadDistance",     @"75000.0000"],
                @"fblockmaximumdistance": @[@"fBlockMaximumDistance", @"250000.0000"],
                @"fblocklevel1distance":  @[@"fBlockLevel1Distance",  @"70000.0000"],
                @"fblocklevel0distance":  @[@"fBlockLevel0Distance",  @"35000.0000"],
                @"fsplitdistancemult":    @[@"fSplitDistanceMult",    @"1.5000"],
            };
        }
    }
    FNVApplyIniSettings(lines, settings);
    [fm createDirectoryAtPath:prefs.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    NSError *prefsError = nil;
    BOOL prefsOK = [[lines componentsJoinedByString:@"\n"] writeToFile:prefs atomically:YES encoding:NSISOLatin1StringEncoding error:&prefsError];
    NSString *fovLog = (opts.fovPreset == 0) ? @"keep" : [NSString stringWithFormat:@"%d/%d", opts.worldFov, opts.firstPersonFov];
    fprintf(stderr, "[display] render %ux%u -> output %ux%u (%u%%) @ %dHz; upscaler=%s; aa=%s; preset=%d tex=%d aniso=%d shadow=%d decals=%d distant=%d fov=%s; mouse_accel=%d; user=%s; preferences=%s\n",
            fnv_display_width(), fnv_display_height(), outW, outH, opts.renderScale, self.refreshHz,
            opts.upscaler == 1 ? "metalfx" : "bilinear",
            opts.antiAliasing == 1 ? "smaa" : (opts.antiAliasing == 2 ? "fxaa" : "off"),
            opts.preset, opts.textureQuality, opts.anisotropy, opts.shadowQuality,
            opts.decalQuantity, opts.distantObjectDetail, fovLog.UTF8String,
            opts.mouseAcceleration ? 1 : 0,
            userDir.fileSystemRepresentation,
            prefsOK ? "written" : prefsError.localizedDescription.UTF8String);
}

@end

#endif
