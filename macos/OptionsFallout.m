#import "FNVOptions.h"

#ifndef FNV_PROBE

#include "FNVDisplay.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static NSString *prefKey(NSString *suffix) {
    return [GAME_PREF_PREFIX stringByAppendingString:suffix];
}

typedef struct {
    int preset;                  // 0=Keep FalloutPrefs.ini, 1=Low, 2=Medium, 3=High, 4=Ultra
    unsigned renderScale;        // 50..100 (default 100 = Native)
    int upscaler;                // 0=Bilinear, 1=MetalFX Spatial
    int antiAliasing;            // 0=Off, 1=SMAA, 2=FXAA (Metal post-process)
    int anisotropy;              // 0, 2, 4, 8, 15
    int screenEffects;           // 0=None, 1=Bloom, 2=HDR
    BOOL vsync;                  // iPresentInterval (0/1)

    // Advanced -> Detail
    int textureSize;             // 0=High (skip 0), 1=Medium (skip 1), 2=Low (skip 2)
    int radialBlurQuality;       // 0=Low, 1=Medium, 2=High
    BOOL depthOfField;           // bDoDepthOfField
    BOOL transparencyMultisampling; // bTransparencyMultisampling (stored; forced 0 in INI for Metal)
    int decalCap;                // 2..10 (iMaxDecalsPerFrame)

    // Advanced -> Water
    BOOL waterRefractions;       // bUseWaterRefractions
    BOOL waterReflections;       // bUseWaterReflections
    int waterReflectionQuality;  // 0=Low (256), 1=Medium (512), 2=High (1024)
    BOOL waterSoftReflections;   // bUseWaterReflectionBlur / iWaterBlurAmount
    BOOL waterFullSceneReflections;  // bAutoWaterSilhouetteReflections (inverted: 0=On, 1=Off)
    BOOL waterFullDetailReflections; // bForceHighDetailReflections
    BOOL waterDisplacement;      // bUseWaterDisplacements
    BOOL waterDepthFog;          // bUseWaterDepth
    int waterMultisampling;      // 0=Low (1), 1=Medium (2), 2=High (4) (forced 0 in INI for Metal)

    // Advanced -> Shadows
    BOOL enableShadows;          // bDrawShadows
    int shadowQuality;           // 0=Low (256), 1=Medium (512), 2=High (1024)
    int shadowFiltering;         // 0=Low (0), 1=Medium (1), 2=High (2)
    int maxInteriorShadows;      // 2..6 (iActorShadowCountInt)
    int maxExteriorShadows;      // 2..6 (iActorShadowCountExt)

    // Advanced -> View Distance
    int objectFade;              // 1..15 (fLODFadeOutMultObjects x1)
    int actorFade;               // 2..15 (fLODFadeOutMultActors x1)
    int grassFade;               // 0..7  (fGrassStartFadeDistance x1000)
    int specularityFade;         // 2..15 (fSpecularLODStartFade x100)
    int lightFade;               // 2..35 (fLightLODStartFade x100)
    int itemFade;                // 1..15 (fLODFadeOutMultItems x1)
    int shadowFade;              // 1..10 (fShadowLODStartFade x100)

    // Advanced -> Distant LOD
    int treeLodFade;             // 0..40   (fTreeLoadDistance x1000)
    int objectLodFade;           // 25..50  (fBlockLoadDistanceLow x1000)
    int landQuality;             // 75..150 (fSplitDistanceMult /100)

    // Port-specific options
    int fovPreset;               // 0=Keep FALLOUT.INI, 1=Original, 2=Expanded, 3=Wide, 4=Custom
    int worldFov;                // 75..105 (fDefaultWorldFOV)
    int firstPersonFov;          // 55..75  (fDefault1stPersonFOV)
    BOOL fullscreen;
    BOOL disableMouseAccel;
    BOOL nvseMode;
    BOOL skipLauncher;
} FalloutOptions;

static int clampInt(int v, int lo, int hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

static void applyFovPresetDefaults(FalloutOptions *opts, int fovPreset) {
    switch (fovPreset) {
    case 2: // Expanded
        opts->worldFov = 90; opts->firstPersonFov = 60;
        break;
    case 3: // Wide
        opts->worldFov = 100; opts->firstPersonFov = 65;
        break;
    case 1: // Original
    default:
        opts->worldFov = 75; opts->firstPersonFov = 55;
        break;
    }
}

static int matchingFovPreset(int worldFov, int firstPersonFov) {
    if (worldFov == 75 && firstPersonFov == 55) return 1;
    if (worldFov == 90 && firstPersonFov == 60) return 2;
    if (worldFov == 100 && firstPersonFov == 65) return 3;
    return 4;
}

// Exact official Windows Fallout 3 / FNV Launcher presets
static void applyPresetDefaults(FalloutOptions *opts, int preset) {
    switch (preset) {
    case 1: // Low
        opts->anisotropy = 0;
        opts->screenEffects = 0; // None
        opts->textureSize = 1;   // Medium
        opts->radialBlurQuality = 0; // Low
        opts->depthOfField = NO;
        opts->transparencyMultisampling = NO;
        opts->decalCap = 2;

        opts->waterRefractions = NO;
        opts->waterReflections = NO;
        opts->waterReflectionQuality = 0; // Low
        opts->waterSoftReflections = NO;
        opts->waterFullSceneReflections = NO;
        opts->waterFullDetailReflections = NO;
        opts->waterDisplacement = NO;
        opts->waterDepthFog = NO;
        opts->waterMultisampling = 0; // Low

        opts->enableShadows = NO;
        opts->shadowQuality = 0;   // Low
        opts->shadowFiltering = 0; // Low
        opts->maxInteriorShadows = 2;
        opts->maxExteriorShadows = 2;

        opts->objectFade = 2;
        opts->actorFade = 2;
        opts->grassFade = 0;
        opts->specularityFade = 2;
        opts->lightFade = 2;
        opts->itemFade = 1;
        opts->shadowFade = 1;

        opts->treeLodFade = 0;
        opts->objectLodFade = 25;
        opts->landQuality = 75;
        break;

    case 2: // Medium
        opts->anisotropy = 0;    // Off on Windows Medium preset
        opts->screenEffects = 2; // HDR
        opts->textureSize = 0;   // High
        opts->radialBlurQuality = 0; // Low
        opts->depthOfField = NO;
        opts->transparencyMultisampling = NO;
        opts->decalCap = 5;

        opts->waterRefractions = YES;
        opts->waterReflections = YES;
        opts->waterReflectionQuality = 1; // Medium
        opts->waterSoftReflections = NO;
        opts->waterFullSceneReflections = NO;
        opts->waterFullDetailReflections = NO;
        opts->waterDisplacement = YES;
        opts->waterDepthFog = YES;
        opts->waterMultisampling = 0; // Low

        opts->enableShadows = YES;
        opts->shadowQuality = 0;   // Low
        opts->shadowFiltering = 1; // Medium
        opts->maxInteriorShadows = 4;
        opts->maxExteriorShadows = 2;

        opts->objectFade = 2;
        opts->actorFade = 2;
        opts->grassFade = 3;
        opts->specularityFade = 5;
        opts->lightFade = 10;
        opts->itemFade = 3;
        opts->shadowFade = 2;

        opts->treeLodFade = 25;
        opts->objectLodFade = 50;
        opts->landQuality = 100;
        break;

    case 3: // High
        opts->anisotropy = 8;
        opts->screenEffects = 2; // HDR
        opts->textureSize = 0;   // High
        opts->radialBlurQuality = 1; // Medium
        opts->depthOfField = YES;
        opts->transparencyMultisampling = YES;
        opts->decalCap = 10;

        opts->waterRefractions = YES;
        opts->waterReflections = YES;
        opts->waterReflectionQuality = 1; // Medium
        opts->waterSoftReflections = YES;
        opts->waterFullSceneReflections = NO;
        opts->waterFullDetailReflections = NO;
        opts->waterDisplacement = YES;
        opts->waterDepthFog = YES;
        opts->waterMultisampling = 2; // High

        opts->enableShadows = YES;
        opts->shadowQuality = 1;   // Medium
        opts->shadowFiltering = 2; // High
        opts->maxInteriorShadows = 4;
        opts->maxExteriorShadows = 2;

        opts->objectFade = 7;
        opts->actorFade = 6;
        opts->grassFade = 5;
        opts->specularityFade = 10;
        opts->lightFade = 25;
        opts->itemFade = 4;
        opts->shadowFade = 4;

        opts->treeLodFade = 26;
        opts->objectLodFade = 50;
        opts->landQuality = 100;
        break;

    case 4: // Ultra
    default:
        opts->anisotropy = 15;
        opts->screenEffects = 2; // HDR
        opts->textureSize = 0;   // High
        opts->radialBlurQuality = 2; // High
        opts->depthOfField = YES;
        opts->transparencyMultisampling = YES;
        opts->decalCap = 10;

        opts->waterRefractions = YES;
        opts->waterReflections = YES;
        opts->waterReflectionQuality = 2; // High
        opts->waterSoftReflections = YES;
        opts->waterFullSceneReflections = YES;
        opts->waterFullDetailReflections = YES;
        opts->waterDisplacement = YES;
        opts->waterDepthFog = YES;
        opts->waterMultisampling = 2; // High

        opts->enableShadows = YES;
        opts->shadowQuality = 2;   // High
        opts->shadowFiltering = 2; // High
        opts->maxInteriorShadows = 6;
        opts->maxExteriorShadows = 6;

        opts->objectFade = 15;
        opts->actorFade = 15;
        opts->grassFade = 7;
        opts->specularityFade = 15; // 1500.0000 on Windows Ultra preset
        opts->lightFade = 35;
        opts->itemFade = 15;
        opts->shadowFade = 10;

        opts->treeLodFade = 40;
        opts->objectLodFade = 50;
        opts->landQuality = 150;
        break;
    }
}

static FalloutOptions loadFalloutOptions(void) {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    FalloutOptions opts = {0};
    id pObj = [ud objectForKey:prefKey(@"QualityPreset")];
    opts.preset = pObj ? (int)[pObj integerValue] : 4; // Ultra default
    if (opts.preset < 0 || opts.preset > 4) opts.preset = 4;
    applyPresetDefaults(&opts, opts.preset > 0 ? opts.preset : 4);

    id rsObj = [ud objectForKey:prefKey(@"RenderScale")];
    opts.renderScale = rsObj ? (unsigned)[rsObj integerValue] : 100u;
    if (opts.renderScale < 50u || opts.renderScale > 100u) opts.renderScale = 100u;
    id upObj = [ud objectForKey:prefKey(@"Upscaler")];
    opts.upscaler = upObj ? (int)[upObj integerValue] : 1;
    if (opts.upscaler < 0 || opts.upscaler > 1) opts.upscaler = 1;
    id aaObj = [ud objectForKey:prefKey(@"AntiAliasing")];
    opts.antiAliasing = aaObj ? (int)[aaObj integerValue] : 0;
    if (opts.antiAliasing < 0 || opts.antiAliasing > 2) opts.antiAliasing = 0;

    id aObj = [ud objectForKey:prefKey(@"Anisotropy")];
    if (aObj) { opts.anisotropy = clampInt((int)[aObj integerValue], 0, 15); }
    id eObj = [ud objectForKey:prefKey(@"ScreenEffects")];
    if (eObj) {
        int raw = (int)[eObj integerValue];
        // Migrate legacy value 3 ("HDR + Depth of Field") to HDR + DoF=YES
        if (raw == 3) { opts.screenEffects = 2; opts.depthOfField = YES; }
        else { opts.screenEffects = clampInt(raw, 0, 2); }
    }
    id vsObj = [ud objectForKey:prefKey(@"VSync")];
    opts.vsync = vsObj ? [vsObj boolValue] : YES;

    // Advanced -> Detail
    id tObj = [ud objectForKey:prefKey(@"TextureSize")];
    if (tObj) opts.textureSize = clampInt((int)[tObj integerValue], 0, 2);
    id rbObj = [ud objectForKey:prefKey(@"RadialBlurQuality")];
    if (rbObj) opts.radialBlurQuality = clampInt((int)[rbObj integerValue], 0, 2);
    id dofObj = [ud objectForKey:prefKey(@"DepthOfField")];
    if (dofObj) opts.depthOfField = [dofObj boolValue];
    id tmsObj = [ud objectForKey:prefKey(@"TransparencyMultisampling")];
    if (tmsObj) opts.transparencyMultisampling = [tmsObj boolValue];
    id dcObj = [ud objectForKey:prefKey(@"DecalCap")];
    if (dcObj) opts.decalCap = clampInt((int)[dcObj integerValue], 2, 10);

    // Advanced -> Water
    id wrfObj = [ud objectForKey:prefKey(@"WaterRefractions")];
    if (wrfObj) opts.waterRefractions = [wrfObj boolValue];
    id wrlObj = [ud objectForKey:prefKey(@"WaterReflections")];
    if (wrlObj) opts.waterReflections = [wrlObj boolValue];
    id wrqObj = [ud objectForKey:prefKey(@"WaterReflectionQuality")];
    if (wrqObj) opts.waterReflectionQuality = clampInt((int)[wrqObj integerValue], 0, 2);
    id wsrObj = [ud objectForKey:prefKey(@"WaterSoftReflections")];
    if (wsrObj) opts.waterSoftReflections = [wsrObj boolValue];
    id wfsObj = [ud objectForKey:prefKey(@"WaterFullSceneReflections")];
    if (wfsObj) opts.waterFullSceneReflections = [wfsObj boolValue];
    id wfdObj = [ud objectForKey:prefKey(@"WaterFullDetailReflections")];
    if (wfdObj) opts.waterFullDetailReflections = [wfdObj boolValue];
    id wdObj = [ud objectForKey:prefKey(@"WaterDisplacement")];
    if (wdObj) opts.waterDisplacement = [wdObj boolValue];
    id wdfObj = [ud objectForKey:prefKey(@"WaterDepthFog")];
    if (wdfObj) opts.waterDepthFog = [wdfObj boolValue];
    id wmsObj = [ud objectForKey:prefKey(@"WaterMultisampling")];
    if (wmsObj) opts.waterMultisampling = clampInt((int)[wmsObj integerValue], 0, 2);

    // Advanced -> Shadows
    id esObj = [ud objectForKey:prefKey(@"EnableShadows")];
    if (esObj) opts.enableShadows = [esObj boolValue];
    id sqObj = [ud objectForKey:prefKey(@"AdvShadowQuality")];
    if (sqObj) opts.shadowQuality = clampInt((int)[sqObj integerValue], 0, 2);
    id sfObj = [ud objectForKey:prefKey(@"ShadowFiltering")];
    if (sfObj) opts.shadowFiltering = clampInt((int)[sfObj integerValue], 0, 2);
    id misObj = [ud objectForKey:prefKey(@"MaxInteriorShadows")];
    if (misObj) opts.maxInteriorShadows = clampInt((int)[misObj integerValue], 2, 6);
    id mesObj = [ud objectForKey:prefKey(@"MaxExteriorShadows")];
    if (mesObj) opts.maxExteriorShadows = clampInt((int)[mesObj integerValue], 2, 6);

    // Advanced -> View Distance
    id ofObj = [ud objectForKey:prefKey(@"ObjectFade")];
    if (ofObj) opts.objectFade = clampInt((int)[ofObj integerValue], 1, 15);
    id afObj = [ud objectForKey:prefKey(@"ActorFade")];
    if (afObj) opts.actorFade = clampInt((int)[afObj integerValue], 2, 15);
    id gfObj = [ud objectForKey:prefKey(@"GrassFade")];
    if (gfObj) opts.grassFade = clampInt((int)[gfObj integerValue], 0, 7);
    id spfObj = [ud objectForKey:prefKey(@"SpecularityFade")];
    if (spfObj) opts.specularityFade = clampInt((int)[spfObj integerValue], 2, 15);
    id lfObj = [ud objectForKey:prefKey(@"LightFade")];
    if (lfObj) opts.lightFade = clampInt((int)[lfObj integerValue], 2, 35);
    id ifObj = [ud objectForKey:prefKey(@"ItemFade")];
    if (ifObj) opts.itemFade = clampInt((int)[ifObj integerValue], 1, 15);
    id shfObj = [ud objectForKey:prefKey(@"ShadowFade")];
    if (shfObj) opts.shadowFade = clampInt((int)[shfObj integerValue], 1, 10);

    // Advanced -> Distant LOD
    id tlfObj = [ud objectForKey:prefKey(@"TreeLodFade")];
    if (tlfObj) opts.treeLodFade = clampInt((int)[tlfObj integerValue], 0, 40);
    id olfObj = [ud objectForKey:prefKey(@"ObjectLodFade")];
    if (olfObj) opts.objectLodFade = clampInt((int)[olfObj integerValue], 25, 50);
    id lqObj = [ud objectForKey:prefKey(@"LandQuality")];
    if (lqObj) opts.landQuality = clampInt((int)[lqObj integerValue], 75, 150);

    id fpObj = [ud objectForKey:prefKey(@"FovPreset")];
    opts.fovPreset = fpObj ? (int)[fpObj integerValue] : 1; // Original default
    if (opts.fovPreset < 0 || opts.fovPreset > 4) opts.fovPreset = 1;
    applyFovPresetDefaults(&opts, (opts.fovPreset >= 1 && opts.fovPreset <= 3) ? opts.fovPreset : 1);
    id wfObj = [ud objectForKey:prefKey(@"WorldFov")];
    if (wfObj) opts.worldFov = clampInt((int)[wfObj integerValue], 75, 105);
    id fpfObj = [ud objectForKey:prefKey(@"FirstPersonFov")];
    if (fpfObj) opts.firstPersonFov = clampInt((int)[fpfObj integerValue], 55, 75);
    if (opts.fovPreset >= 1 && opts.fovPreset <= 3) {
        applyFovPresetDefaults(&opts, opts.fovPreset);
    } else if (opts.fovPreset == 4) {
        opts.fovPreset = matchingFovPreset(opts.worldFov, opts.firstPersonFov);
    }
    id fsObj = [ud objectForKey:prefKey(@"Fullscreen")];
    opts.fullscreen = fsObj ? [fsObj boolValue] : YES;
    id maObj = [ud objectForKey:prefKey(@"DisableMouseAccel")];
    opts.disableMouseAccel = maObj ? [maObj boolValue] : YES;
    id skObj = [ud objectForKey:prefKey(@"SkipLauncher")];
    opts.skipLauncher = skObj ? [skObj boolValue] : NO;
#ifndef FNV_GAME_FALLOUT3
    id nvObj = [ud objectForKey:prefKey(@"NVSEMode")];
    opts.nvseMode = nvObj ? [nvObj boolValue] : NO;
#endif

    const char *envPreset = getenv("FNV_PRESET");
    if (envPreset && envPreset[0]) {
        if (!strcasecmp(envPreset, "keep") || !strcmp(envPreset, "0")) opts.preset = 0;
        else if (!strcasecmp(envPreset, "low") || !strcmp(envPreset, "1")) { opts.preset = 1; applyPresetDefaults(&opts, 1); }
        else if (!strcasecmp(envPreset, "medium") || !strcmp(envPreset, "2")) { opts.preset = 2; applyPresetDefaults(&opts, 2); }
        else if (!strcasecmp(envPreset, "high") || !strcmp(envPreset, "3")) { opts.preset = 3; applyPresetDefaults(&opts, 3); }
        else if (!strcasecmp(envPreset, "ultra") || !strcmp(envPreset, "4")) { opts.preset = 4; applyPresetDefaults(&opts, 4); }
    }
    const char *envScale = getenv("FNV_RENDER_SCALE");
    if (envScale && envScale[0]) {
        unsigned v = (unsigned)strtoul(envScale, NULL, 10);
        if (v >= 50u && v <= 100u) opts.renderScale = v;
    }
    const char *envUp = getenv("FNV_UPSCALER");
    if (envUp && envUp[0]) {
        if (!strcasecmp(envUp, "bilinear") || !strcmp(envUp, "0")) opts.upscaler = 0;
        else if (!strcasecmp(envUp, "metalfx") || !strcmp(envUp, "1")) opts.upscaler = 1;
    }
    const char *envAA = getenv("FNV_AA");
    if (envAA && envAA[0]) {
        if (!strcasecmp(envAA, "off") || !strcasecmp(envAA, "none") || !strcmp(envAA, "0")) opts.antiAliasing = 0;
        else if (!strcasecmp(envAA, "smaa") || !strcmp(envAA, "1")) opts.antiAliasing = 1;
        else if (!strcasecmp(envAA, "fxaa") || !strcmp(envAA, "2")) opts.antiAliasing = 2;
    }
    const char *envFov = getenv("FNV_FOV");
    if (envFov && envFov[0]) {
        opts.worldFov = clampInt((int)strtol(envFov, NULL, 10), 75, 105);
        opts.fovPreset = matchingFovPreset(opts.worldFov, opts.firstPersonFov);
    }
    const char *envFpFov = getenv("FNV_1ST_PERSON_FOV");
    if (envFpFov && envFpFov[0]) {
        opts.firstPersonFov = clampInt((int)strtol(envFpFov, NULL, 10), 55, 75);
        opts.fovPreset = matchingFovPreset(opts.worldFov, opts.firstPersonFov);
    }
    const char *envMA = getenv("FNV_MOUSE_ACCEL");
    if (envMA && envMA[0]) opts.disableMouseAccel = (atoi(envMA) == 0);
#ifndef FNV_GAME_FALLOUT3
    const char *envNvse = getenv("FNV_SCRIPT_EXT");
    if (envNvse && envNvse[0]) opts.nvseMode = (atoi(envNvse) != 0);
#endif
    if (getenv("FNV_WINDOWED")) opts.fullscreen = NO;
    return opts;
}

static void saveFalloutOptions(FalloutOptions opts) {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    [ud setInteger:opts.preset forKey:prefKey(@"QualityPreset")];
    [ud setInteger:(NSInteger)opts.renderScale forKey:prefKey(@"RenderScale")];
    [ud setInteger:opts.upscaler forKey:prefKey(@"Upscaler")];
    [ud setInteger:opts.antiAliasing forKey:prefKey(@"AntiAliasing")];
    [ud setInteger:opts.anisotropy forKey:prefKey(@"Anisotropy")];
    [ud setInteger:opts.screenEffects forKey:prefKey(@"ScreenEffects")];
    [ud setBool:opts.vsync forKey:prefKey(@"VSync")];

    [ud setInteger:opts.textureSize forKey:prefKey(@"TextureSize")];
    [ud setInteger:opts.radialBlurQuality forKey:prefKey(@"RadialBlurQuality")];
    [ud setBool:opts.depthOfField forKey:prefKey(@"DepthOfField")];
    [ud setBool:opts.transparencyMultisampling forKey:prefKey(@"TransparencyMultisampling")];
    [ud setInteger:opts.decalCap forKey:prefKey(@"DecalCap")];

    [ud setBool:opts.waterRefractions forKey:prefKey(@"WaterRefractions")];
    [ud setBool:opts.waterReflections forKey:prefKey(@"WaterReflections")];
    [ud setInteger:opts.waterReflectionQuality forKey:prefKey(@"WaterReflectionQuality")];
    [ud setBool:opts.waterSoftReflections forKey:prefKey(@"WaterSoftReflections")];
    [ud setBool:opts.waterFullSceneReflections forKey:prefKey(@"WaterFullSceneReflections")];
    [ud setBool:opts.waterFullDetailReflections forKey:prefKey(@"WaterFullDetailReflections")];
    [ud setBool:opts.waterDisplacement forKey:prefKey(@"WaterDisplacement")];
    [ud setBool:opts.waterDepthFog forKey:prefKey(@"WaterDepthFog")];
    [ud setInteger:opts.waterMultisampling forKey:prefKey(@"WaterMultisampling")];

    [ud setBool:opts.enableShadows forKey:prefKey(@"EnableShadows")];
    [ud setInteger:opts.shadowQuality forKey:prefKey(@"AdvShadowQuality")];
    [ud setInteger:opts.shadowFiltering forKey:prefKey(@"ShadowFiltering")];
    [ud setInteger:opts.maxInteriorShadows forKey:prefKey(@"MaxInteriorShadows")];
    [ud setInteger:opts.maxExteriorShadows forKey:prefKey(@"MaxExteriorShadows")];

    [ud setInteger:opts.objectFade forKey:prefKey(@"ObjectFade")];
    [ud setInteger:opts.actorFade forKey:prefKey(@"ActorFade")];
    [ud setInteger:opts.grassFade forKey:prefKey(@"GrassFade")];
    [ud setInteger:opts.specularityFade forKey:prefKey(@"SpecularityFade")];
    [ud setInteger:opts.lightFade forKey:prefKey(@"LightFade")];
    [ud setInteger:opts.itemFade forKey:prefKey(@"ItemFade")];
    [ud setInteger:opts.shadowFade forKey:prefKey(@"ShadowFade")];

    [ud setInteger:opts.treeLodFade forKey:prefKey(@"TreeLodFade")];
    [ud setInteger:opts.objectLodFade forKey:prefKey(@"ObjectLodFade")];
    [ud setInteger:opts.landQuality forKey:prefKey(@"LandQuality")];

    [ud setInteger:opts.fovPreset forKey:prefKey(@"FovPreset")];
    [ud setInteger:opts.worldFov forKey:prefKey(@"WorldFov")];
    [ud setInteger:opts.firstPersonFov forKey:prefKey(@"FirstPersonFov")];
    [ud setBool:opts.fullscreen forKey:prefKey(@"Fullscreen")];
    [ud setBool:opts.disableMouseAccel forKey:prefKey(@"DisableMouseAccel")];
#ifndef FNV_GAME_FALLOUT3
    [ud setBool:opts.nvseMode forKey:prefKey(@"NVSEMode")];
#endif
    [ud setBool:opts.skipLauncher forKey:prefKey(@"SkipLauncher")];
    [ud synchronize];
}

@interface FNVOptionsController ()
@property (nonatomic) unsigned nativeW;
@property (nonatomic) unsigned nativeH;
@property (nonatomic) unsigned backingW;
@property (nonatomic) unsigned backingH;
@property (nonatomic) int refreshHz;
@property (nonatomic) FalloutOptions workingOpts;
@property (nonatomic) FalloutOptions savedOpts;
@property (nonatomic) BOOL hasSavedOpts;
@property (nonatomic, copy) void (^onPlay)(FNVLaunchSettings settings);

// Main window controls
@property (nonatomic, strong) NSWindow *optionsWindow;
@property (nonatomic, strong) NSPopUpButton *presetPopup;
@property (nonatomic, strong) NSButton *advancedBtn;
@property (nonatomic, strong) NSPopUpButton *scalePopup;
@property (nonatomic, strong) NSPopUpButton *upscalerPopup;
@property (nonatomic, strong) NSPopUpButton *aaPopup;
@property (nonatomic, strong) NSTextField *resPreviewLabel;
@property (nonatomic, strong) NSPopUpButton *anisoPopup;
@property (nonatomic, strong) NSPopUpButton *effectsPopup;
@property (nonatomic, strong) NSPopUpButton *displayPopup;
@property (nonatomic, strong) NSButton *vsyncCheck;
@property (nonatomic, strong) NSPopUpButton *fovPresetPopup;
@property (nonatomic, strong) NSSlider *worldFovSlider;
@property (nonatomic, strong) NSSlider *firstPersonFovSlider;
@property (nonatomic, strong) NSTextField *worldFovValueLabel;
@property (nonatomic, strong) NSTextField *firstPersonFovValueLabel;
@property (nonatomic, strong) NSTextField *fovTipLabel;
@property (nonatomic, strong) NSButton *mouseAccelCheck;
@property (nonatomic, strong) NSButton *nvseModeCheck;
@property (nonatomic, strong) NSButton *skipLauncherCheck;

// Advanced sheet controls
@property (nonatomic, strong) NSWindow *advancedWindow;
// Detail
@property (nonatomic, strong) NSPopUpButton *advTexturePopup;
@property (nonatomic, strong) NSPopUpButton *advRadialBlurPopup;
@property (nonatomic, strong) NSButton *advDofCheck;
@property (nonatomic, strong) NSButton *advTransMsCheck;
@property (nonatomic, strong) NSSlider *advDecalCapSlider;
@property (nonatomic, strong) NSTextField *advDecalCapLabel;
// Water
@property (nonatomic, strong) NSButton *advWaterRefrCheck;
@property (nonatomic, strong) NSButton *advWaterReflCheck;
@property (nonatomic, strong) NSPopUpButton *advWaterReflQualityPopup;
@property (nonatomic, strong) NSButton *advWaterSoftReflCheck;
@property (nonatomic, strong) NSButton *advWaterFullSceneCheck;
@property (nonatomic, strong) NSButton *advWaterFullDetailCheck;
@property (nonatomic, strong) NSButton *advWaterDisplacementCheck;
@property (nonatomic, strong) NSButton *advWaterDepthFogCheck;
@property (nonatomic, strong) NSPopUpButton *advWaterMsPopup;
// Shadows
@property (nonatomic, strong) NSButton *advEnableShadowsCheck;
@property (nonatomic, strong) NSPopUpButton *advShadowQualityPopup;
@property (nonatomic, strong) NSPopUpButton *advShadowFilterPopup;
@property (nonatomic, strong) NSSlider *advMaxIntShadowsSlider;
@property (nonatomic, strong) NSTextField *advMaxIntShadowsLabel;
@property (nonatomic, strong) NSSlider *advMaxExtShadowsSlider;
@property (nonatomic, strong) NSTextField *advMaxExtShadowsLabel;
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
@property (nonatomic, strong) NSSlider *advShadowFadeSlider;
@property (nonatomic, strong) NSTextField *advShadowFadeLabel;
// Distant LOD
@property (nonatomic, strong) NSSlider *advTreeLodSlider;
@property (nonatomic, strong) NSTextField *advTreeLodLabel;
@property (nonatomic, strong) NSSlider *advObjectLodSlider;
@property (nonatomic, strong) NSTextField *advObjectLodLabel;
@property (nonatomic, strong) NSSlider *advLandQualitySlider;
@property (nonatomic, strong) NSTextField *advLandQualityLabel;
@end

@implementation FNVOptionsController

- (instancetype)initWithNativeW:(unsigned)nativeW
                        nativeH:(unsigned)nativeH
                       backingW:(unsigned)backingW
                       backingH:(unsigned)backingH
                      refreshHz:(int)refreshHz {
    self = [super init];
    if (self) {
        _nativeW = nativeW;
        _nativeH = nativeH;
        _backingW = backingW;
        _backingH = backingH;
        _refreshHz = refreshHz;
    }
    return self;
}

- (BOOL)shouldShowLauncher {
    FalloutOptions opts = loadFalloutOptions();
    const char *headlessEnv = getenv("FNV_HEADLESS");
    BOOL isHeadless = (headlessEnv && headlessEnv[0] && headlessEnv[0] != '0');
    BOOL optionHeld = (NSEvent.modifierFlags & NSEventModifierFlagOption) != 0;
    return !isHeadless && !getenv("FNV_SKIP_LAUNCHER") && (!opts.skipLauncher || optionHeld);
}

- (void)enableOptionsOnNextLaunch {
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:prefKey(@"SkipLauncher")];
    [NSUserDefaults.standardUserDefaults synchronize];
}

- (FNVLaunchSettings)currentLaunchSettings {
    FalloutOptions opts = loadFalloutOptions();
    self.savedOpts = opts;
    self.hasSavedOpts = YES;
    return (FNVLaunchSettings){opts.renderScale, opts.upscaler, opts.antiAliasing, opts.fullscreen};
}

- (void)updateDetailControlsEnabled {
    BOOL enable = (self.presetPopup.selectedItem.tag != 0);
    self.anisoPopup.enabled = enable;
    self.effectsPopup.enabled = enable;
    self.advancedBtn.enabled = enable;
}

- (void)presetChanged:(id)sender {
    (void)sender;
    int p = (int)self.presetPopup.selectedItem.tag;
    if (p > 0) {
        FalloutOptions tmp = self.workingOpts;
        tmp.preset = p;
        applyPresetDefaults(&tmp, p);
        self.workingOpts = tmp;
        [self.anisoPopup selectItemWithTag:tmp.anisotropy];
        [self.effectsPopup selectItemWithTag:tmp.screenEffects];
    } else {
        FalloutOptions tmp = self.workingOpts;
        tmp.preset = 0;
        self.workingOpts = tmp;
    }
    [self updateDetailControlsEnabled];
}

- (void)updateResolutionPreview {
    unsigned pct = (unsigned)self.scalePopup.selectedItem.tag;
    if (pct < 50u) pct = 50u;
    if (pct > 100u) pct = 100u;
    unsigned rw = self.nativeW, rh = self.nativeH;
    if (pct < 100u) {
        rw = ((self.nativeW * pct / 100u) + 1u) & ~1u;
        rh = ((self.nativeH * pct / 100u) + 1u) & ~1u;
        if (rw < 640u) rw = 640u;
        if (rh < 480u) rh = 480u;
    }
    BOOL scaled = (rw != self.nativeW || rh != self.nativeH);
    self.upscalerPopup.enabled = scaled;
    if (scaled) {
        NSString *up = (self.upscalerPopup.selectedItem.tag == 1) ? @"MetalFX" : @"Bilinear";
        self.resPreviewLabel.stringValue = [NSString stringWithFormat:@"Render: %ux%u → %ux%u (%@)",
                                            rw, rh, self.nativeW, self.nativeH, up];
    } else {
        self.resPreviewLabel.stringValue = [NSString stringWithFormat:@"Render: %ux%u (Native)",
                                            self.nativeW, self.nativeH];
    }
}

- (void)scaleChanged:(id)sender { (void)sender; [self updateResolutionPreview]; }
- (void)upscalerChanged:(id)sender { (void)sender; [self updateResolutionPreview]; }

- (void)updateFovUI {
    int fp = (int)self.fovPresetPopup.selectedItem.tag;
    int wf = clampInt((int)llround(self.worldFovSlider.doubleValue), 75, 105);
    int fpf = clampInt((int)llround(self.firstPersonFovSlider.doubleValue), 55, 75);
    BOOL enable = (fp != 0);
    self.worldFovSlider.enabled = enable;
    self.firstPersonFovSlider.enabled = enable;
    self.worldFovValueLabel.stringValue = [NSString stringWithFormat:@"%d°", wf];
    self.firstPersonFovValueLabel.stringValue = [NSString stringWithFormat:@"%d°", fpf];
    self.worldFovValueLabel.textColor = enable ? NSColor.labelColor : NSColor.tertiaryLabelColor;
    self.firstPersonFovValueLabel.textColor = enable ? NSColor.labelColor : NSColor.tertiaryLabelColor;
    if (!enable) {
        self.fovTipLabel.stringValue = @"Keeping existing FOV settings in FALLOUT.INI.";
    } else if (fpf > 65) {
        self.fovTipLabel.stringValue = @"Pip-Boy stays 75°. >65° 1st-person may clip arms or iron sights.";
    } else {
        self.fovTipLabel.stringValue = @"Pip-Boy & terminals stay at 75° (untouched).";
    }
}

- (void)fovPresetChanged:(id)sender {
    (void)sender;
    int fp = (int)self.fovPresetPopup.selectedItem.tag;
    if (fp >= 1 && fp <= 3) {
        FalloutOptions tmp = {0};
        applyFovPresetDefaults(&tmp, fp);
        self.worldFovSlider.integerValue = tmp.worldFov;
        self.firstPersonFovSlider.integerValue = tmp.firstPersonFov;
    }
    [self updateFovUI];
}

- (void)fovSliderChanged:(id)sender {
    (void)sender;
    int wf = clampInt((int)llround(self.worldFovSlider.doubleValue), 75, 105);
    int fpf = clampInt((int)llround(self.firstPersonFovSlider.doubleValue), 55, 75);
    self.worldFovSlider.integerValue = wf;
    self.firstPersonFovSlider.integerValue = fpf;
    [self.fovPresetPopup selectItemWithTag:matchingFovPreset(wf, fpf)];
    [self updateFovUI];
}

#pragma mark - Advanced Sheet

- (void)updateAdvancedWaterEnabled {
    BOOL refl = (self.advWaterReflCheck.state == NSControlStateValueOn);
    self.advWaterReflQualityPopup.enabled = refl;
    self.advWaterSoftReflCheck.enabled = refl;
    self.advWaterFullSceneCheck.enabled = refl;
    self.advWaterFullDetailCheck.enabled = refl;
}

- (void)updateAdvancedShadowsEnabled {
    BOOL sh = (self.advEnableShadowsCheck.state == NSControlStateValueOn);
    self.advShadowQualityPopup.enabled = sh;
    self.advShadowFilterPopup.enabled = sh;
    self.advMaxIntShadowsSlider.enabled = sh;
    self.advMaxExtShadowsSlider.enabled = sh;
    self.advMaxIntShadowsLabel.textColor = sh ? NSColor.labelColor : NSColor.tertiaryLabelColor;
    self.advMaxExtShadowsLabel.textColor = sh ? NSColor.labelColor : NSColor.tertiaryLabelColor;
}

- (void)advWaterReflToggled:(id)sender { (void)sender; [self updateAdvancedWaterEnabled]; }
- (void)advShadowsToggled:(id)sender { (void)sender; [self updateAdvancedShadowsEnabled]; }

- (void)advSliderChanged:(id)sender {
    (void)sender;
    self.advDecalCapLabel.stringValue = [NSString stringWithFormat:@"%d", (int)llround(self.advDecalCapSlider.doubleValue)];
    self.advMaxIntShadowsLabel.stringValue = [NSString stringWithFormat:@"%d", (int)llround(self.advMaxIntShadowsSlider.doubleValue)];
    self.advMaxExtShadowsLabel.stringValue = [NSString stringWithFormat:@"%d", (int)llround(self.advMaxExtShadowsSlider.doubleValue)];
    self.advObjectFadeLabel.stringValue = [NSString stringWithFormat:@"%d", (int)llround(self.advObjectFadeSlider.doubleValue)];
    self.advActorFadeLabel.stringValue = [NSString stringWithFormat:@"%d", (int)llround(self.advActorFadeSlider.doubleValue)];
    self.advGrassFadeLabel.stringValue = [NSString stringWithFormat:@"%d", (int)llround(self.advGrassFadeSlider.doubleValue)];
    self.advSpecFadeLabel.stringValue = [NSString stringWithFormat:@"%d", (int)llround(self.advSpecFadeSlider.doubleValue)];
    self.advLightFadeLabel.stringValue = [NSString stringWithFormat:@"%d", (int)llround(self.advLightFadeSlider.doubleValue)];
    self.advItemFadeLabel.stringValue = [NSString stringWithFormat:@"%d", (int)llround(self.advItemFadeSlider.doubleValue)];
    self.advShadowFadeLabel.stringValue = [NSString stringWithFormat:@"%d", (int)llround(self.advShadowFadeSlider.doubleValue)];
    self.advTreeLodLabel.stringValue = [NSString stringWithFormat:@"%d", (int)llround(self.advTreeLodSlider.doubleValue)];
    self.advObjectLodLabel.stringValue = [NSString stringWithFormat:@"%d", (int)llround(self.advObjectLodSlider.doubleValue)];
    self.advLandQualityLabel.stringValue = [NSString stringWithFormat:@"%d", (int)llround(self.advLandQualitySlider.doubleValue)];
}

- (void)populateAdvancedControlsFrom:(FalloutOptions)opts {
    [self.advTexturePopup selectItemWithTag:opts.textureSize];
    [self.advRadialBlurPopup selectItemWithTag:opts.radialBlurQuality];
    self.advDofCheck.state = opts.depthOfField ? NSControlStateValueOn : NSControlStateValueOff;
    self.advTransMsCheck.state = opts.transparencyMultisampling ? NSControlStateValueOn : NSControlStateValueOff;
    self.advDecalCapSlider.integerValue = opts.decalCap;

    self.advWaterRefrCheck.state = opts.waterRefractions ? NSControlStateValueOn : NSControlStateValueOff;
    self.advWaterReflCheck.state = opts.waterReflections ? NSControlStateValueOn : NSControlStateValueOff;
    [self.advWaterReflQualityPopup selectItemWithTag:opts.waterReflectionQuality];
    self.advWaterSoftReflCheck.state = opts.waterSoftReflections ? NSControlStateValueOn : NSControlStateValueOff;
    self.advWaterFullSceneCheck.state = opts.waterFullSceneReflections ? NSControlStateValueOn : NSControlStateValueOff;
    self.advWaterFullDetailCheck.state = opts.waterFullDetailReflections ? NSControlStateValueOn : NSControlStateValueOff;
    self.advWaterDisplacementCheck.state = opts.waterDisplacement ? NSControlStateValueOn : NSControlStateValueOff;
    self.advWaterDepthFogCheck.state = opts.waterDepthFog ? NSControlStateValueOn : NSControlStateValueOff;
    [self.advWaterMsPopup selectItemWithTag:opts.waterMultisampling];

    self.advEnableShadowsCheck.state = opts.enableShadows ? NSControlStateValueOn : NSControlStateValueOff;
    [self.advShadowQualityPopup selectItemWithTag:opts.shadowQuality];
    [self.advShadowFilterPopup selectItemWithTag:opts.shadowFiltering];
    self.advMaxIntShadowsSlider.integerValue = opts.maxInteriorShadows;
    self.advMaxExtShadowsSlider.integerValue = opts.maxExteriorShadows;

    self.advObjectFadeSlider.integerValue = opts.objectFade;
    self.advActorFadeSlider.integerValue = opts.actorFade;
    self.advGrassFadeSlider.integerValue = opts.grassFade;
    self.advSpecFadeSlider.integerValue = opts.specularityFade;
    self.advLightFadeSlider.integerValue = opts.lightFade;
    self.advItemFadeSlider.integerValue = opts.itemFade;
    self.advShadowFadeSlider.integerValue = opts.shadowFade;

    self.advTreeLodSlider.integerValue = opts.treeLodFade;
    self.advObjectLodSlider.integerValue = opts.objectLodFade;
    self.advLandQualitySlider.integerValue = opts.landQuality;

    [self advSliderChanged:nil];
    [self updateAdvancedWaterEnabled];
    [self updateAdvancedShadowsEnabled];
}

- (void)readAdvancedControlsInto:(FalloutOptions *)opts {
    opts->textureSize = (int)self.advTexturePopup.selectedItem.tag;
    opts->radialBlurQuality = (int)self.advRadialBlurPopup.selectedItem.tag;
    opts->depthOfField = (self.advDofCheck.state == NSControlStateValueOn);
    opts->transparencyMultisampling = (self.advTransMsCheck.state == NSControlStateValueOn);
    opts->decalCap = clampInt((int)llround(self.advDecalCapSlider.doubleValue), 2, 10);

    opts->waterRefractions = (self.advWaterRefrCheck.state == NSControlStateValueOn);
    opts->waterReflections = (self.advWaterReflCheck.state == NSControlStateValueOn);
    opts->waterReflectionQuality = (int)self.advWaterReflQualityPopup.selectedItem.tag;
    opts->waterSoftReflections = (self.advWaterSoftReflCheck.state == NSControlStateValueOn);
    opts->waterFullSceneReflections = (self.advWaterFullSceneCheck.state == NSControlStateValueOn);
    opts->waterFullDetailReflections = (self.advWaterFullDetailCheck.state == NSControlStateValueOn);
    opts->waterDisplacement = (self.advWaterDisplacementCheck.state == NSControlStateValueOn);
    opts->waterDepthFog = (self.advWaterDepthFogCheck.state == NSControlStateValueOn);
    opts->waterMultisampling = (int)self.advWaterMsPopup.selectedItem.tag;

    opts->enableShadows = (self.advEnableShadowsCheck.state == NSControlStateValueOn);
    opts->shadowQuality = (int)self.advShadowQualityPopup.selectedItem.tag;
    opts->shadowFiltering = (int)self.advShadowFilterPopup.selectedItem.tag;
    opts->maxInteriorShadows = clampInt((int)llround(self.advMaxIntShadowsSlider.doubleValue), 2, 6);
    opts->maxExteriorShadows = clampInt((int)llround(self.advMaxExtShadowsSlider.doubleValue), 2, 6);

    opts->objectFade = clampInt((int)llround(self.advObjectFadeSlider.doubleValue), 1, 15);
    opts->actorFade = clampInt((int)llround(self.advActorFadeSlider.doubleValue), 2, 15);
    opts->grassFade = clampInt((int)llround(self.advGrassFadeSlider.doubleValue), 0, 7);
    opts->specularityFade = clampInt((int)llround(self.advSpecFadeSlider.doubleValue), 2, 15);
    opts->lightFade = clampInt((int)llround(self.advLightFadeSlider.doubleValue), 2, 35);
    opts->itemFade = clampInt((int)llround(self.advItemFadeSlider.doubleValue), 1, 15);
    opts->shadowFade = clampInt((int)llround(self.advShadowFadeSlider.doubleValue), 1, 10);

    opts->treeLodFade = clampInt((int)llround(self.advTreeLodSlider.doubleValue), 0, 40);
    opts->objectLodFade = clampInt((int)llround(self.advObjectLodSlider.doubleValue), 25, 50);
    opts->landQuality = clampInt((int)llround(self.advLandQualitySlider.doubleValue), 75, 150);
}

- (void)ensureAdvancedWindow {
    if (self.advancedWindow) return;

    NSRect rect = NSMakeRect(0, 0, 470, 382);
    self.advancedWindow = [[NSWindow alloc] initWithContentRect:rect
                                                      styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                        backing:NSBackingStoreBuffered
                                                          defer:NO];
    self.advancedWindow.title = [NSString stringWithFormat:@"%@ — Advanced Options", GAME_TITLE];
    self.advancedWindow.releasedWhenClosed = NO;
    NSView *cv = self.advancedWindow.contentView;

    NSTabView *tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(16, 54, 438, 314)];
    [cv addSubview:tabs];

    NSTextField *(^mkLabel)(NSView *, NSString *, CGFloat, CGFloat, CGFloat) =
        ^NSTextField *(NSView *v, NSString *txt, CGFloat x, CGFloat y, CGFloat w) {
        NSTextField *l = [NSTextField labelWithString:txt];
        l.alignment = NSTextAlignmentRight;
        l.frame = NSMakeRect(x, y, w, 20);
        [v addSubview:l];
        return l;
    };
    NSPopUpButton *(^mkLMHPopup)(NSView *, CGFloat, CGFloat, CGFloat, BOOL) =
        ^NSPopUpButton *(NSView *v, CGFloat x, CGFloat y, CGFloat w, BOOL invertTags) {
        NSPopUpButton *p = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, y, w, 26) pullsDown:NO];
        if (invertTags) {
            // Texture quality: iTexMipMapSkip 2=Low, 1=Medium, 0=High
            [p addItemWithTitle:@"Low"];    p.lastItem.tag = 2;
            [p addItemWithTitle:@"Medium"]; p.lastItem.tag = 1;
            [p addItemWithTitle:@"High"];   p.lastItem.tag = 0;
        } else {
            [p addItemWithTitle:@"Low"];    p.lastItem.tag = 0;
            [p addItemWithTitle:@"Medium"]; p.lastItem.tag = 1;
            [p addItemWithTitle:@"High"];   p.lastItem.tag = 2;
        }
        [v addSubview:p];
        return p;
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
    mkLabel(dv, @"Texture Quality:", 12, 232, 165);
    self.advTexturePopup = mkLMHPopup(dv, 186, 230, 180, YES);
    mkLabel(dv, @"Radial Blur Quality:", 12, 198, 165);
    self.advRadialBlurPopup = mkLMHPopup(dv, 186, 196, 180, NO);
    self.advDofCheck = [NSButton checkboxWithTitle:@"Depth of Field" target:nil action:nil];
    self.advDofCheck.frame = NSMakeRect(186, 164, 210, 18);
    [dv addSubview:self.advDofCheck];
    self.advTransMsCheck = [NSButton checkboxWithTitle:@"Transparency Multisampling" target:nil action:nil];
    self.advTransMsCheck.frame = NSMakeRect(186, 138, 220, 18);
    [dv addSubview:self.advTransMsCheck];
    NSSlider *sDecal = nil; NSTextField *lDecal = nil;
    mkSliderRow(dv, @"Decal Cap:", 98, 2, 10, &sDecal, &lDecal);
    self.advDecalCapSlider = sDecal; self.advDecalCapLabel = lDecal;
    [tabs addTabViewItem:detailItem];

    // --- Tab 2: Water ---
    NSTabViewItem *waterItem = [[NSTabViewItem alloc] initWithIdentifier:@"water"];
    waterItem.label = @"Water";
    NSView *wv = waterItem.view;
    self.advWaterRefrCheck = [NSButton checkboxWithTitle:@"Water Refractions" target:nil action:nil];
    self.advWaterRefrCheck.frame = NSMakeRect(24, 240, 200, 18);
    [wv addSubview:self.advWaterRefrCheck];
    self.advWaterReflCheck = [NSButton checkboxWithTitle:@"Water Reflections" target:self action:@selector(advWaterReflToggled:)];
    self.advWaterReflCheck.frame = NSMakeRect(24, 214, 200, 18);
    [wv addSubview:self.advWaterReflCheck];
    mkLabel(wv, @"Reflection Quality:", 28, 182, 138);
    self.advWaterReflQualityPopup = mkLMHPopup(wv, 174, 180, 160, NO);
    self.advWaterSoftReflCheck = [NSButton checkboxWithTitle:@"Soft Reflections" target:nil action:nil];
    self.advWaterSoftReflCheck.frame = NSMakeRect(48, 152, 220, 18);
    [wv addSubview:self.advWaterSoftReflCheck];
    self.advWaterFullSceneCheck = [NSButton checkboxWithTitle:@"Full Scene Reflections" target:nil action:nil];
    self.advWaterFullSceneCheck.frame = NSMakeRect(48, 128, 220, 18);
    [wv addSubview:self.advWaterFullSceneCheck];
    self.advWaterFullDetailCheck = [NSButton checkboxWithTitle:@"Full Detail Reflections" target:nil action:nil];
    self.advWaterFullDetailCheck.frame = NSMakeRect(48, 104, 220, 18);
    [wv addSubview:self.advWaterFullDetailCheck];
    self.advWaterDisplacementCheck = [NSButton checkboxWithTitle:@"Water Displacement" target:nil action:nil];
    self.advWaterDisplacementCheck.frame = NSMakeRect(24, 74, 200, 18);
    [wv addSubview:self.advWaterDisplacementCheck];
    self.advWaterDepthFogCheck = [NSButton checkboxWithTitle:@"Depth Fog" target:nil action:nil];
    self.advWaterDepthFogCheck.frame = NSMakeRect(228, 74, 160, 18);
    [wv addSubview:self.advWaterDepthFogCheck];
    mkLabel(wv, @"Water Multisampling:", 16, 36, 150);
    self.advWaterMsPopup = mkLMHPopup(wv, 174, 34, 160, NO);
    [tabs addTabViewItem:waterItem];

    // --- Tab 3: Shadows ---
    NSTabViewItem *shadowsItem = [[NSTabViewItem alloc] initWithIdentifier:@"shadows"];
    shadowsItem.label = @"Shadows";
    NSView *sv = shadowsItem.view;
    self.advEnableShadowsCheck = [NSButton checkboxWithTitle:@"Enable Shadows" target:self action:@selector(advShadowsToggled:)];
    self.advEnableShadowsCheck.frame = NSMakeRect(24, 236, 200, 18);
    [sv addSubview:self.advEnableShadowsCheck];
    mkLabel(sv, @"Shadow Quality:", 12, 198, 146);
    self.advShadowQualityPopup = mkLMHPopup(sv, 166, 196, 180, NO);
    mkLabel(sv, @"Shadow Filtering:", 12, 164, 146);
    self.advShadowFilterPopup = mkLMHPopup(sv, 166, 162, 180, NO);
    NSSlider *sInt = nil; NSTextField *lInt = nil;
    mkSliderRow(sv, @"Max Interior Shadows:", 122, 2, 6, &sInt, &lInt);
    self.advMaxIntShadowsSlider = sInt; self.advMaxIntShadowsLabel = lInt;
    NSSlider *sExt = nil; NSTextField *lExt = nil;
    mkSliderRow(sv, @"Max Exterior Shadows:", 86, 2, 6, &sExt, &lExt);
    self.advMaxExtShadowsSlider = sExt; self.advMaxExtShadowsLabel = lExt;
    [tabs addTabViewItem:shadowsItem];

    // --- Tab 4: View Distance ---
    NSTabViewItem *vdItem = [[NSTabViewItem alloc] initWithIdentifier:@"viewdistance"];
    vdItem.label = @"View Distance";
    NSView *vv = vdItem.view;
    NSSlider *sObj = nil, *sAct = nil, *sGr = nil, *sSp = nil, *sLi = nil, *sIt = nil, *sSh = nil;
    NSTextField *lObj = nil, *lAct = nil, *lGr = nil, *lSp = nil, *lLi = nil, *lIt = nil, *lSh = nil;
    mkSliderRow(vv, @"Object Fade:",      236, 1, 15, &sObj, &lObj);
    mkSliderRow(vv, @"Actor Fade:",       202, 2, 15, &sAct, &lAct);
    mkSliderRow(vv, @"Grass Fade:",       168, 0,  7, &sGr,  &lGr);
    mkSliderRow(vv, @"Specularity Fade:", 134, 2, 15, &sSp,  &lSp);
    mkSliderRow(vv, @"Light Fade:",       100, 2, 35, &sLi,  &lLi);
    mkSliderRow(vv, @"Item Fade:",         66, 1, 15, &sIt,  &lIt);
    mkSliderRow(vv, @"Shadow Fade:",       32, 1, 10, &sSh,  &lSh);
    self.advObjectFadeSlider = sObj; self.advObjectFadeLabel = lObj;
    self.advActorFadeSlider  = sAct; self.advActorFadeLabel  = lAct;
    self.advGrassFadeSlider  = sGr;  self.advGrassFadeLabel  = lGr;
    self.advSpecFadeSlider   = sSp;  self.advSpecFadeLabel   = lSp;
    self.advLightFadeSlider  = sLi;  self.advLightFadeLabel  = lLi;
    self.advItemFadeSlider   = sIt;  self.advItemFadeLabel   = lIt;
    self.advShadowFadeSlider = sSh;  self.advShadowFadeLabel = lSh;
    [tabs addTabViewItem:vdItem];

    // --- Tab 5: Distant LOD ---
    NSTabViewItem *lodItem = [[NSTabViewItem alloc] initWithIdentifier:@"lod"];
    lodItem.label = @"Distant LOD";
    NSView *lv = lodItem.view;
    NSSlider *sTree = nil, *sObjLod = nil, *sLand = nil;
    NSTextField *lTree = nil, *lObjLod = nil, *lLand = nil;
    mkSliderRow(lv, @"Tree LOD Fade:",   214,  0,  40, &sTree,   &lTree);
    mkSliderRow(lv, @"Object LOD Fade:", 172, 25,  50, &sObjLod, &lObjLod);
    mkSliderRow(lv, @"Land Quality:",    130, 75, 150, &sLand,   &lLand);
    self.advTreeLodSlider     = sTree;   self.advTreeLodLabel     = lTree;
    self.advObjectLodSlider   = sObjLod; self.advObjectLodLabel   = lObjLod;
    self.advLandQualitySlider = sLand;   self.advLandQualityLabel = lLand;
    [tabs addTabViewItem:lodItem];

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
    if (p <= 0) p = 4;
    FalloutOptions tmp = self.workingOpts;
    applyPresetDefaults(&tmp, p);
    [self populateAdvancedControlsFrom:tmp];
}

- (void)advCancelClicked:(id)sender {
    (void)sender;
    [self.optionsWindow endSheet:self.advancedWindow returnCode:NSModalResponseCancel];
}

- (void)advOkClicked:(id)sender {
    (void)sender;
    FalloutOptions tmp = self.workingOpts;
    [self readAdvancedControlsInto:&tmp];
    self.workingOpts = tmp;
    [self.optionsWindow endSheet:self.advancedWindow returnCode:NSModalResponseOK];
}

- (void)exploreGameDataClicked:(id)sender {
    (void)sender;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *dir = nil;
    const char *envRoot = getenv("FNV_ROOT");
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
    FalloutOptions opts = self.workingOpts;
    opts.preset = (int)self.presetPopup.selectedItem.tag;
    opts.renderScale = (unsigned)self.scalePopup.selectedItem.tag;
    opts.upscaler = (int)self.upscalerPopup.selectedItem.tag;
    opts.antiAliasing = (int)self.aaPopup.selectedItem.tag;
    opts.anisotropy = (int)self.anisoPopup.selectedItem.tag;
    opts.screenEffects = (int)self.effectsPopup.selectedItem.tag;
    opts.vsync = (self.vsyncCheck.state == NSControlStateValueOn);
    opts.fovPreset = (int)self.fovPresetPopup.selectedItem.tag;
    opts.worldFov = clampInt((int)llround(self.worldFovSlider.doubleValue), 75, 105);
    opts.firstPersonFov = clampInt((int)llround(self.firstPersonFovSlider.doubleValue), 55, 75);
    opts.fullscreen = (self.displayPopup.selectedItem.tag != 0);
    opts.disableMouseAccel = (self.mouseAccelCheck.state == NSControlStateValueOn);
    if (self.nvseModeCheck) {
        opts.nvseMode = (self.nvseModeCheck.state == NSControlStateValueOn);
    }
    opts.skipLauncher = (self.skipLauncherCheck.state == NSControlStateValueOn);
    saveFalloutOptions(opts);

    const char *envScale = getenv("FNV_RENDER_SCALE");
    if (envScale && envScale[0]) {
        unsigned v = (unsigned)strtoul(envScale, NULL, 10);
        if (v >= 50u && v <= 100u) opts.renderScale = v;
    }
    const char *envUp = getenv("FNV_UPSCALER");
    if (envUp && envUp[0]) {
        if (!strcasecmp(envUp, "bilinear") || !strcmp(envUp, "0")) opts.upscaler = 0;
        else if (!strcasecmp(envUp, "metalfx") || !strcmp(envUp, "1")) opts.upscaler = 1;
    }
    const char *envAA = getenv("FNV_AA");
    if (envAA && envAA[0]) {
        if (!strcasecmp(envAA, "off") || !strcasecmp(envAA, "none") || !strcmp(envAA, "0")) opts.antiAliasing = 0;
        else if (!strcasecmp(envAA, "smaa") || !strcmp(envAA, "1")) opts.antiAliasing = 1;
        else if (!strcasecmp(envAA, "fxaa") || !strcmp(envAA, "2")) opts.antiAliasing = 2;
    }
    const char *envFov = getenv("FNV_FOV");
    if (envFov && envFov[0]) {
        opts.worldFov = clampInt((int)strtol(envFov, NULL, 10), 75, 105);
        opts.fovPreset = matchingFovPreset(opts.worldFov, opts.firstPersonFov);
    }
    const char *envFpFov = getenv("FNV_1ST_PERSON_FOV");
    if (envFpFov && envFpFov[0]) {
        opts.firstPersonFov = clampInt((int)strtol(envFpFov, NULL, 10), 55, 75);
        opts.fovPreset = matchingFovPreset(opts.worldFov, opts.firstPersonFov);
    }
    if (getenv("FNV_WINDOWED")) opts.fullscreen = NO;
    const char *envMA = getenv("FNV_MOUSE_ACCEL");
    if (envMA && envMA[0]) opts.disableMouseAccel = (atoi(envMA) == 0);
#ifndef FNV_GAME_FALLOUT3
    const char *envNvse = getenv("FNV_SCRIPT_EXT");
    if (envNvse && envNvse[0]) opts.nvseMode = (atoi(envNvse) != 0);
#endif

    self.savedOpts = opts;
    self.hasSavedOpts = YES;
    if (self.onPlay) {
        self.onPlay((FNVLaunchSettings){opts.renderScale, opts.upscaler, opts.antiAliasing, opts.fullscreen});
    }
}

- (NSWindow *)presentWindowWithDelegate:(id<NSWindowDelegate>)delegate
                                 onPlay:(void (^)(FNVLaunchSettings settings))onPlay {
    self.onPlay = onPlay;
    FalloutOptions opts = loadFalloutOptions();
    self.workingOpts = opts;

#ifdef FNV_GAME_FALLOUT3
    CGFloat extraH = 14;
#else
    CGFloat extraH = 38;
#endif
    NSRect rect = NSMakeRect(0, 0, 480, 584 + extraH);
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
    title.frame = NSMakeRect(24, 548 + extraH, 432, 22);
    [cv addSubview:title];

    NSString *dispStr = (self.backingW != self.nativeW || self.backingH != self.nativeH)
        ? [NSString stringWithFormat:@"Display: %ux%u panel (desktop %ux%u) @ %d Hz",
           self.nativeW, self.nativeH, self.backingW, self.backingH, self.refreshHz]
        : [NSString stringWithFormat:@"Display: %ux%u @ %d Hz",
           self.nativeW, self.nativeH, self.refreshHz];
    NSTextField *sub = [NSTextField labelWithString:dispStr];
    sub.font = [NSFont systemFontOfSize:12];
    sub.textColor = NSColor.secondaryLabelColor;
    sub.frame = NSMakeRect(24, 528 + extraH, 432, 16);
    [cv addSubview:sub];

    NSBox *sep1 = [[NSBox alloc] initWithFrame:NSMakeRect(24, 519 + extraH, 432, 1)];
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

    mkLabel(@"Quality Preset:", 485 + extraH);
    self.presetPopup = mkPopup(483 + extraH);
    [self.presetPopup addItemWithTitle:@"Ultra (Recommended)"]; self.presetPopup.lastItem.tag = 4;
    [self.presetPopup addItemWithTitle:@"High"]; self.presetPopup.lastItem.tag = 3;
    [self.presetPopup addItemWithTitle:@"Medium"]; self.presetPopup.lastItem.tag = 2;
    [self.presetPopup addItemWithTitle:@"Low"]; self.presetPopup.lastItem.tag = 1;
    [self.presetPopup addItemWithTitle:@"Keep FalloutPrefs.ini"]; self.presetPopup.lastItem.tag = 0;
    [self.presetPopup selectItemWithTag:opts.preset];
    self.presetPopup.target = self;
    self.presetPopup.action = @selector(presetChanged:);

    mkLabel(@"Render Scale:", 454 + extraH);
    self.scalePopup = mkPopup(452 + extraH);
    [self.scalePopup addItemWithTitle:@"100% (Native)"]; self.scalePopup.lastItem.tag = 100;
    [self.scalePopup addItemWithTitle:@"85% (Ultra Quality)"]; self.scalePopup.lastItem.tag = 85;
    [self.scalePopup addItemWithTitle:@"75% (Quality)"]; self.scalePopup.lastItem.tag = 75;
    [self.scalePopup addItemWithTitle:@"67% (Balanced)"]; self.scalePopup.lastItem.tag = 67;
    [self.scalePopup addItemWithTitle:@"50% (Performance)"]; self.scalePopup.lastItem.tag = 50;
    if (![self.scalePopup selectItemWithTag:(NSInteger)opts.renderScale]) [self.scalePopup selectItemWithTag:100];
    self.scalePopup.target = self;
    self.scalePopup.action = @selector(scaleChanged:);

    self.resPreviewLabel = [NSTextField labelWithString:@""];
    self.resPreviewLabel.font = [NSFont systemFontOfSize:11];
    self.resPreviewLabel.textColor = NSColor.secondaryLabelColor;
    self.resPreviewLabel.frame = NSMakeRect(198, 433 + extraH, 258, 15);
    [cv addSubview:self.resPreviewLabel];

    mkLabel(@"Upscaler:", 405 + extraH);
    self.upscalerPopup = mkPopup(403 + extraH);
    [self.upscalerPopup addItemWithTitle:@"MetalFX Spatial"]; self.upscalerPopup.lastItem.tag = 1;
    [self.upscalerPopup addItemWithTitle:@"Bilinear"]; self.upscalerPopup.lastItem.tag = 0;
    [self.upscalerPopup selectItemWithTag:opts.upscaler];
    self.upscalerPopup.target = self;
    self.upscalerPopup.action = @selector(upscalerChanged:);

    mkLabel(@"Anti-Aliasing:", 374 + extraH);
    self.aaPopup = mkPopup(372 + extraH);
    [self.aaPopup addItemWithTitle:@"Off"]; self.aaPopup.lastItem.tag = 0;
    [self.aaPopup addItemWithTitle:@"SMAA 1x (Post-Process)"]; self.aaPopup.lastItem.tag = 1;
    [self.aaPopup addItemWithTitle:@"FXAA (Post-Process)"]; self.aaPopup.lastItem.tag = 2;
    [self.aaPopup selectItemWithTag:opts.antiAliasing];

    mkLabel(@"Anisotropic Filtering:", 343 + extraH);
    self.anisoPopup = mkPopup(341 + extraH);
    [self.anisoPopup addItemWithTitle:@"15 Samples (Max)"]; self.anisoPopup.lastItem.tag = 15;
    [self.anisoPopup addItemWithTitle:@"8 Samples"]; self.anisoPopup.lastItem.tag = 8;
    [self.anisoPopup addItemWithTitle:@"4 Samples"]; self.anisoPopup.lastItem.tag = 4;
    [self.anisoPopup addItemWithTitle:@"2 Samples"]; self.anisoPopup.lastItem.tag = 2;
    [self.anisoPopup addItemWithTitle:@"Off (best performance)"]; self.anisoPopup.lastItem.tag = 0;
    if (![self.anisoPopup selectItemWithTag:opts.anisotropy]) [self.anisoPopup selectItemWithTag:15];

    mkLabel(@"Screen Effects:", 312 + extraH);
    self.effectsPopup = mkPopup(310 + extraH);
    [self.effectsPopup addItemWithTitle:@"HDR"]; self.effectsPopup.lastItem.tag = 2;
    [self.effectsPopup addItemWithTitle:@"Bloom"]; self.effectsPopup.lastItem.tag = 1;
    [self.effectsPopup addItemWithTitle:@"None"]; self.effectsPopup.lastItem.tag = 0;
    [self.effectsPopup selectItemWithTag:opts.screenEffects];

    mkLabel(@"Display Mode:", 281 + extraH);
    self.displayPopup = mkPopup(279 + extraH);
    [self.displayPopup addItemWithTitle:@"Fullscreen"]; self.displayPopup.lastItem.tag = 1;
    [self.displayPopup addItemWithTitle:@"Windowed"]; self.displayPopup.lastItem.tag = 0;
    [self.displayPopup selectItemWithTag:opts.fullscreen ? 1 : 0];

    self.vsyncCheck = [NSButton checkboxWithTitle:@"Vertical Sync" target:nil action:nil];
    self.vsyncCheck.frame = NSMakeRect(196, 255 + extraH, 160, 18);
    self.vsyncCheck.state = opts.vsync ? NSControlStateValueOn : NSControlStateValueOff;
    [cv addSubview:self.vsyncCheck];

    mkLabel(@"FOV Preset:", 226 + extraH);
    self.fovPresetPopup = mkPopup(224 + extraH);
    [self.fovPresetPopup addItemWithTitle:@"Original (75° / 55°)"]; self.fovPresetPopup.lastItem.tag = 1;
    [self.fovPresetPopup addItemWithTitle:@"Expanded (90° / 60°)"]; self.fovPresetPopup.lastItem.tag = 2;
    [self.fovPresetPopup addItemWithTitle:@"Wide (100° / 65°)"]; self.fovPresetPopup.lastItem.tag = 3;
    [self.fovPresetPopup addItemWithTitle:@"Custom"]; self.fovPresetPopup.lastItem.tag = 4;
    [self.fovPresetPopup addItemWithTitle:@"Keep FALLOUT.INI"]; self.fovPresetPopup.lastItem.tag = 0;
    [self.fovPresetPopup selectItemWithTag:opts.fovPreset];
    self.fovPresetPopup.target = self;
    self.fovPresetPopup.action = @selector(fovPresetChanged:);

    mkLabel(@"World FOV:", 197 + extraH);
    self.worldFovSlider = [NSSlider sliderWithValue:opts.worldFov minValue:75 maxValue:105 target:self action:@selector(fovSliderChanged:)];
    self.worldFovSlider.frame = NSMakeRect(196, 194 + extraH, 214, 24);
    self.worldFovSlider.numberOfTickMarks = 7;
    self.worldFovSlider.allowsTickMarkValuesOnly = NO;
    self.worldFovSlider.continuous = YES;
    [cv addSubview:self.worldFovSlider];

    self.worldFovValueLabel = [NSTextField labelWithString:@""];
    self.worldFovValueLabel.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.worldFovValueLabel.alignment = NSTextAlignmentRight;
    self.worldFovValueLabel.frame = NSMakeRect(414, 197 + extraH, 42, 20);
    [cv addSubview:self.worldFovValueLabel];

    mkLabel(@"1st-Person FOV:", 169 + extraH);
    self.firstPersonFovSlider = [NSSlider sliderWithValue:opts.firstPersonFov minValue:55 maxValue:75 target:self action:@selector(fovSliderChanged:)];
    self.firstPersonFovSlider.frame = NSMakeRect(196, 166 + extraH, 214, 24);
    self.firstPersonFovSlider.numberOfTickMarks = 5;
    self.firstPersonFovSlider.allowsTickMarkValuesOnly = NO;
    self.firstPersonFovSlider.continuous = YES;
    [cv addSubview:self.firstPersonFovSlider];

    self.firstPersonFovValueLabel = [NSTextField labelWithString:@""];
    self.firstPersonFovValueLabel.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.firstPersonFovValueLabel.alignment = NSTextAlignmentRight;
    self.firstPersonFovValueLabel.frame = NSMakeRect(414, 169 + extraH, 42, 20);
    [cv addSubview:self.firstPersonFovValueLabel];

    self.fovTipLabel = [NSTextField labelWithString:@""];
    self.fovTipLabel.font = [NSFont systemFontOfSize:11];
    self.fovTipLabel.textColor = NSColor.secondaryLabelColor;
    self.fovTipLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.fovTipLabel.maximumNumberOfLines = 2;
    self.fovTipLabel.frame = NSMakeRect(198, 136 + extraH, 258, 26);
    [cv addSubview:self.fovTipLabel];

    self.mouseAccelCheck = [NSButton checkboxWithTitle:@"Disable in-game mouse acceleration (menus & camera)"
                                                target:nil action:nil];
    self.mouseAccelCheck.frame = NSMakeRect(24, 110 + extraH, 432, 18);
    self.mouseAccelCheck.state = opts.disableMouseAccel ? NSControlStateValueOn : NSControlStateValueOff;
    [cv addSubview:self.mouseAccelCheck];

    NSTextField *mouseTip = [NSTextField wrappingLabelWithString:@"Tip: for external mice, also disable Pointer Acceleration in System Settings → Mouse."];
    mouseTip.font = [NSFont systemFontOfSize:11];
    mouseTip.textColor = NSColor.secondaryLabelColor;
    mouseTip.maximumNumberOfLines = 2;
    mouseTip.frame = NSMakeRect(42, 79 + extraH, 414, 28);
    [cv addSubview:mouseTip];

#ifndef FNV_GAME_FALLOUT3
    self.nvseModeCheck = [NSButton checkboxWithTitle:@"NVSE mode (experimental)"
                                              target:nil action:nil];
    self.nvseModeCheck.frame = NSMakeRect(24, 92, 432, 18);
    self.nvseModeCheck.state = opts.nvseMode ? NSControlStateValueOn : NSControlStateValueOff;
    [cv addSubview:self.nvseModeCheck];
#endif

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

    [self updateResolutionPreview];
    [self updateDetailControlsEnabled];
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
    FalloutOptions opts = self.hasSavedOpts ? self.savedOpts : loadFalloutOptions();
#ifndef FNV_GAME_FALLOUT3
    setenv("FNV_SCRIPT_EXT", opts.nvseMode ? "1" : "0", 1);
#endif
    NSFileManager *fm = NSFileManager.defaultManager;

#ifdef FNV_GAME_FALLOUT3
    NSString *localAppDir = [userDir.path stringByAppendingPathComponent:@"LocalAppData/Fallout3"];
    [fm createDirectoryAtPath:localAppDir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *pluginsPath = [localAppDir stringByAppendingPathComponent:@"plugins.txt"];
    if (![fm fileExistsAtPath:pluginsPath]) {
        NSMutableArray<NSString *> *plugins = [NSMutableArray arrayWithObject:@"Fallout3.esm"];
        NSString *dlcListPath = [root.path stringByAppendingPathComponent:@"Data/DLCList.txt"];
        NSString *dlcList = [NSString stringWithContentsOfFile:dlcListPath encoding:NSUTF8StringEncoding error:NULL];
        if (dlcList) {
            for (NSString *raw in [dlcList componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
                NSString *esm = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (esm.length > 0 && ![plugins containsObject:esm] &&
                    [fm fileExistsAtPath:[root.path stringByAppendingPathComponent:[@"Data" stringByAppendingPathComponent:esm]]]) {
                    [plugins addObject:esm];
                }
            }
        }
        [[plugins componentsJoinedByString:@"\r\n"] writeToFile:pluginsPath atomically:YES encoding:NSISOLatin1StringEncoding error:NULL];
    }
#endif

    // Ensure My Games/<Game> directory and seed FALLOUT.INI from Fallout_default.ini on clean install.
    NSString *myGamesDir = [userDir.path stringByAppendingPathComponent:[@"My Games/" stringByAppendingString:GAME_DIR]];
    [fm createDirectoryAtPath:myGamesDir withIntermediateDirectories:YES attributes:nil error:NULL];

    NSString *mainIni = [myGamesDir stringByAppendingPathComponent:@"FALLOUT.INI"];
    for (NSString *leaf in [fm contentsOfDirectoryAtPath:myGamesDir error:NULL]) {
        if ([leaf caseInsensitiveCompare:@"FALLOUT.INI"] == NSOrderedSame) {
            mainIni = [myGamesDir stringByAppendingPathComponent:leaf];
            break;
        }
    }
    if (![fm fileExistsAtPath:mainIni]) {
        NSString *defaultIni = [root URLByAppendingPathComponent:@"Fallout_default.ini"].path;
        if ([fm fileExistsAtPath:defaultIni]) {
            [fm copyItemAtPath:defaultIni toPath:mainIni error:NULL];
        }
    }
    if ([fm fileExistsAtPath:mainIni]) {
        NSString *iniText = [NSString stringWithContentsOfFile:mainIni encoding:NSISOLatin1StringEncoding error:NULL] ?: @"";
        NSMutableArray<NSString *> *iniLines = [[iniText componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] mutableCopy];
        NSMutableDictionary *iniSettings = [NSMutableDictionary dictionary];
        iniSettings[@"controls"] = opts.disableMouseAccel
            ? @{
                @"fforegroundmouseaccelbase": @[@"fForegroundMouseAccelBase", @"0"],
                @"fforegroundmouseacceltop":  @[@"fForegroundMouseAccelTop",  @"0"],
                @"fforegroundmousebase":      @[@"fForegroundMouseBase",      @"0"],
                @"fforegroundmousemult":      @[@"fForegroundMouseMult",      @"0"],
            }
            : @{
                @"fforegroundmouseaccelbase": @[@"fForegroundMouseAccelBase", @"0.005"],
                @"fforegroundmouseacceltop":  @[@"fForegroundMouseAccelTop",  @"0.025"],
                @"fforegroundmousebase":      @[@"fForegroundMouseBase",      @"0"],
                @"fforegroundmousemult":      @[@"fForegroundMouseMult",      @"4"],
            };
        if (opts.fovPreset != 0) {
            iniSettings[@"display"] = @{
                @"fdefaultworldfov":     @[@"fDefaultWorldFOV",     [NSString stringWithFormat:@"%.4f", (double)opts.worldFov]],
                @"fdefault1stpersonfov": @[@"fDefault1stPersonFOV", [NSString stringWithFormat:@"%.4f", (double)opts.firstPersonFov]],
            };
        }
        FNVApplyIniSettings(iniLines, iniSettings);
        [[iniLines componentsJoinedByString:@"\n"] writeToFile:mainIni atomically:YES encoding:NSISOLatin1StringEncoding error:NULL];
    }

    // Update display/graphics/controller keys in FalloutPrefs.ini while preserving all other user settings.
    NSString *prefs = [myGamesDir stringByAppendingPathComponent:@"FalloutPrefs.ini"];
    for (NSString *leaf in [fm contentsOfDirectoryAtPath:myGamesDir error:NULL]) {
        if ([leaf caseInsensitiveCompare:@"FalloutPrefs.ini"] == NSOrderedSame) {
            prefs = [myGamesDir stringByAppendingPathComponent:leaf];
            break;
        }
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
        @"ipresentinterval": @[@"iPresentInterval", opts.vsync ? @1 : @0],
        @"sd3ddevice": @[@"sD3DDevice", @(fnv_display_adapter_description())],
        // Metal backend uses post-process SMAA/FXAA rather than hardware D3D9 MSAA
        @"imultisample": @[@"iMultiSample", @0],
        @"iwatermultisamples": @[@"iWaterMultisamples", @0],
        @"btransparencymultisampling": @[@"bTransparencyMultisampling", @0],
    } mutableCopy];
    if (opts.fovPreset != 0) {
        displaySettings[@"fdefaultworldfov"] = @[@"fDefaultWorldFOV", [NSString stringWithFormat:@"%.4f", (double)opts.worldFov]];
        displaySettings[@"fdefault1stpersonfov"] = @[@"fDefault1stPersonFOV", [NSString stringWithFormat:@"%.4f", (double)opts.firstPersonFov]];
    }
    NSMutableDictionary *allSettings = [@{
        @"display": displaySettings,
        @"controls": @{
            @"buse joystick": @[@"bUse Joystick", @1],
        },
    } mutableCopy];

    if (opts.preset > 0) {
        // Detail
        displaySettings[@"itexmipmapskip"] = @[@"iTexMipMapSkip", @(opts.textureSize)];
        displaySettings[@"itexmipmapminimum"] = @[@"iTexMipMapMinimum", @4];
        displaySettings[@"imaxanisotropy"] = @[@"iMaxAnisotropy", @(opts.anisotropy)];
        displaySettings[@"imaxdecalsperframe"] = @[@"iMaxDecalsPerFrame", @(opts.decalCap)];
        displaySettings[@"fdecallod1"] = @[@"fDecalLOD1", @"500.0000"];
        displaySettings[@"fdecallod2"] = @[@"fDecalLOD2", @"1000.0000"];

        // View Distance
        displaySettings[@"fspecularlodstartfade"] = @[@"fSpecularLODStartFade", [NSString stringWithFormat:@"%.4f", (double)opts.specularityFade * 100.0]];
        displaySettings[@"fshadowlodstartfade"]   = @[@"fShadowLODStartFade",   [NSString stringWithFormat:@"%.4f", (double)opts.shadowFade * 100.0]];
        displaySettings[@"flightlodstartfade"]    = @[@"fLightLODStartFade",    [NSString stringWithFormat:@"%.4f", (double)opts.lightFade * 100.0]];
        allSettings[@"lod"] = @{
            @"flodfadeoutmultobjects": @[@"fLODFadeOutMultObjects", [NSString stringWithFormat:@"%.4f", (double)opts.objectFade]],
            @"flodfadeoutmultactors":  @[@"fLODFadeOutMultActors",  [NSString stringWithFormat:@"%.4f", (double)opts.actorFade]],
            @"flodfadeoutmultitems":   @[@"fLODFadeOutMultItems",   [NSString stringWithFormat:@"%.4f", (double)opts.itemFade]],
        };
        allSettings[@"grass"] = @{
            @"b30grassvs":              @[@"b30GrassVS",              (opts.preset >= 3) ? @1 : @0],
            @"fgrassstartfadedistance": @[@"fGrassStartFadeDistance", [NSString stringWithFormat:@"%.4f", (double)opts.grassFade * 1000.0]],
        };

        // Distant LOD
        allSettings[@"terrainmanager"] = @{
            @"ftreeloaddistance":         @[@"fTreeLoadDistance",         [NSString stringWithFormat:@"%.4f", (double)opts.treeLodFade * 1000.0]],
            @"fblockloaddistancelow":     @[@"fBlockLoadDistanceLow",     [NSString stringWithFormat:@"%.4f", (double)opts.objectLodFade * 1000.0]],
            @"fblockloaddistance":        @[@"fBlockLoadDistance",        @"125000.0000"],
            @"fsplitdistancemult":        @[@"fSplitDistanceMult",        [NSString stringWithFormat:@"%.4f", (double)opts.landQuality / 100.0]],
            @"fhighblockloaddistancelow": @[@"fHighBlockLoadDistanceLow", @"20000.0000"],
        };

        // Shadows
        int shadowRes = (opts.shadowQuality == 2) ? 1024 : ((opts.shadowQuality == 1) ? 512 : 256);
        displaySettings[@"bdrawshadows"]         = @[@"bDrawShadows",         opts.enableShadows ? @1 : @0];
        displaySettings[@"ishadowmapresolution"] = @[@"iShadowMapResolution", @(shadowRes)];
        displaySettings[@"ishadowfilter"]        = @[@"iShadowFilter",        opts.enableShadows ? @(opts.shadowFiltering) : @0];
        displaySettings[@"iactorshadowcountint"] = @[@"iActorShadowCountInt", opts.enableShadows ? @(opts.maxInteriorShadows) : @0];
        displaySettings[@"iactorshadowcountext"] = @[@"iActorShadowCountExt", opts.enableShadows ? @(opts.maxExteriorShadows) : @0];

        // Water
        int waterRes = (opts.waterReflectionQuality == 2) ? 1024 : ((opts.waterReflectionQuality == 1) ? 512 : 256);
        int waterBlur = (opts.waterReflections && opts.waterSoftReflections)
            ? ((opts.waterReflectionQuality >= 2) ? 4 : 2) : 0;
        allSettings[@"water"] = @{
            @"busewaterrefractions":            @[@"bUseWaterRefractions",            opts.waterRefractions ? @1 : @0],
            @"busewaterreflections":            @[@"bUseWaterReflections",            opts.waterReflections ? @1 : @0],
            @"busewaterreflectionblur":         @[@"bUseWaterReflectionBlur",         (opts.waterReflections && opts.waterSoftReflections) ? @1 : @0],
            @"busewaterdisplacements":          @[@"bUseWaterDisplacements",          opts.waterDisplacement ? @1 : @0],
            @"busewaterdepth":                  @[@"bUseWaterDepth",                  opts.waterDepthFog ? @1 : @0],
            @"iwaterreflectwidth":              @[@"iWaterReflectWidth",              @(waterRes)],
            @"iwaterreflectheight":             @[@"iWaterReflectHeight",             @(waterRes)],
            @"iwaterbluramount":                @[@"iWaterBlurAmount",                @(waterBlur)],
            @"bautowatersilhouettereflections": @[@"bAutoWaterSilhouetteReflections", (opts.waterReflections && opts.waterFullSceneReflections) ? @0 : @1],
            @"bforcehighdetailreflections":     @[@"bForceHighDetailReflections",     (opts.waterReflections && opts.waterFullDetailReflections) ? @1 : @0],
        };

        // Screen Effects & Imagespace
        allSettings[@"blurshaderhdr"] = @{
            @"bdohighdynamicrange": @[@"bDoHighDynamicRange", (opts.screenEffects == 2) ? @1 : @0],
        };
        allSettings[@"blurshader"] = @{
            @"buseblurshader": @[@"bUseBlurShader", (opts.screenEffects == 1) ? @1 : @0],
        };
        allSettings[@"imagespace"] = @{
            @"bdodepthoffield":  @[@"bDoDepthOfField",  opts.depthOfField ? @1 : @0],
            @"iradialblurlevel": @[@"iRadialBlurLevel", @(opts.radialBlurQuality)],
        };
    }

    FNVApplyIniSettings(lines, allSettings);

    // Without Fallout3Launcher.exe, Fallout3.exe initializes missing INIPrefSetting LOD
    // multipliers to 0.0000. Dividing by fLODFadeOutMultActors=0 produces +inf in the
    // actor fade check (0xad2960), culling every NPC and starving Actor::Update/dialogue.
    NSDictionary *lodDefaults = @{
        @"flodfadeoutmultobjects": @[@"fLODFadeOutMultObjects", @"5.0000"],
        @"flodfadeoutmultitems":   @[@"fLODFadeOutMultItems",   @"3.0000"],
        @"flodfadeoutmultactors":  @[@"fLODFadeOutMultActors",  @"6.0000"],
    };
    {
        NSMutableSet *pending = [NSMutableSet setWithArray:lodDefaults.allKeys];
        BOOL inside = NO;
        NSInteger insert = -1;
        for (NSUInteger i = 0; i < lines.count; i++) {
            NSString *line = [lines[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if ([line hasPrefix:@"["] && [line hasSuffix:@"]"]) {
                if (inside && insert < 0) insert = (NSInteger)i;
                inside = [[[line substringWithRange:NSMakeRange(1, line.length - 2)] lowercaseString] isEqualToString:@"lod"];
            } else if (inside) {
                NSRange equal = [line rangeOfString:@"="];
                if (equal.location != NSNotFound) {
                    NSString *key = [[[line substringToIndex:equal.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] lowercaseString];
                    NSArray *def = lodDefaults[key];
                    if (def) {
                        double curVal = [[[line substringFromIndex:equal.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] doubleValue];
                        if (!(curVal > 0.0)) {
                            lines[i] = [NSString stringWithFormat:@"%@=%@", def[0], def[1]];
                        }
                        [pending removeObject:key];
                    }
                }
            }
        }
        if (pending.count > 0) {
            if (insert < 0) {
                insert = (NSInteger)lines.count;
                if (!inside) {
                    [lines addObject:@"[LOD]"];
                    insert++;
                }
            }
            for (NSString *key in pending) {
                NSArray *def = lodDefaults[key];
                [lines insertObject:[NSString stringWithFormat:@"%@=%@", def[0], def[1]] atIndex:(NSUInteger)insert++];
            }
        }
    }

    [fm createDirectoryAtPath:prefs.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    NSError *prefsError = nil;
    BOOL prefsOK = [[lines componentsJoinedByString:@"\n"] writeToFile:prefs atomically:YES encoding:NSISOLatin1StringEncoding error:&prefsError];
    NSString *fovLog = (opts.fovPreset == 0) ? @"keep" : [NSString stringWithFormat:@"%d/%d", opts.worldFov, opts.firstPersonFov];
    fprintf(stderr, "[display] render %ux%u -> output %ux%u (scale=%u%% upscaler=%s aa=%s); preset=%d tex=%d aniso=%d shadows=%d/%d waterRefl=%d/%d fx=%d dof=%d fov=%s mouse_accel=%d; user=%s; preferences=%s\n",
            fnv_display_width(), fnv_display_height(), outW, outH,
            opts.renderScale, opts.upscaler == 1 ? "metalfx" : "bilinear",
            opts.antiAliasing == 1 ? "smaa" : (opts.antiAliasing == 2 ? "fxaa" : "off"),
            opts.preset, opts.textureSize, opts.anisotropy,
            opts.enableShadows ? 1 : 0, opts.shadowQuality,
            opts.waterReflections ? 1 : 0, opts.waterReflectionQuality,
            opts.screenEffects, opts.depthOfField ? 1 : 0, fovLog.UTF8String,
            opts.disableMouseAccel ? 0 : 1,
            userDir.fileSystemRepresentation,
            prefsOK ? "written" : prefsError.localizedDescription.UTF8String);
}

@end

#endif
