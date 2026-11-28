#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "FNVGuestMemory.h"
#include "host.h"
#include "input.h"
#include "script_bridge.h"
#include "script_ext.h"

extern void script_ext_set_fnv_extras(uint32_t input_globals_ptr,
                                      uint32_t ini_get_fn,
                                      uint32_t ini_pref_get_fn,
                                      uint32_t setting_lookup_fn);
extern void input_dinput_keyboard_state(uint8_t out[256]);
extern void input_dinput_mouse_state(int32_t *dx, int32_t *dy, int32_t *dz, uint8_t b[8]);

uint8_t *MEM;
uint32_t host_image_base = 0x400000u;
uint32_t host_text_start = 0x401000u;
uint32_t host_text_end = 0x1000000u;

static int trap_hit;
void rt_trap(CPU *c, int code, uint32_t addr) {
    (void)c;
    fprintf(stderr, "unexpected trap code=%d addr=%#x\n", code, addr);
    trap_hit = code;
    abort();
}

// ---- synthetic guest functions -------------------------------------------------------------
enum {
    FN_ADD_CDECL = 0x00410000u,
    FN_THIS_SUB = 0x00410010u,
    FN_INI_GET = 0x0044f560u,
    FN_LOOKUP_FORM = 0x004839c0u,
    FN_INI_PREF_GET = 0x004de490u,
    FN_EXTRACT = 0x005accb0u,
    FN_PARSE = 0x005b1ba0u,
    FN_SETTING_LOOKUP = 0x005e02b0u,
    FN_CONSOLE_PRINT = 0x00703c00u,
};

static char last_console_msg[512];
static uint32_t expected_param_info;
static uint32_t expected_this_obj;
static uint32_t fake_extract_mode;
static uint32_t fake_extract_u0;
static uint32_t fake_extract_u1;
static uint32_t fake_extract_u2;
static const char *fake_extract_str;
static float fake_extract_floats[9];
static int fake_extract_nfloats;

static void g_add_cdecl(CPU *c) {
    uint32_t sp = REG(c, R_ESP);
    assert(G32(sp) == HOST_EXIT_THUNK);
    uint32_t a = G32(sp + 4u);
    uint32_t b = G32(sp + 8u);
    // Clobber caller registers, flags, TOP, and ST0 to verify guest_call_cdecl saves CPU.
    SETREG(c, R_EAX, a + b);
    SETREG(c, R_ECX, 0xdeadbeefu);
    SETREG(c, R_EDX, 0xcafebabeu);
    c->r[REG_TOP] = 5;
    double garbage = -999.5;
    memcpy(c->r + 4352, &garbage, 8);
}

static void g_this_sub(CPU *c) {
    uint32_t sp = REG(c, R_ESP);
    assert(G32(sp) == HOST_EXIT_THUNK);
    uint32_t self = REG(c, R_ECX);
    uint32_t a = G32(sp + 4u);
    uint32_t b = G32(sp + 8u);
    SETREG(c, R_EAX, self + a - b);
}

static void g_parse(CPU *c) { SETREG(c, R_EAX, 1u); }

static void g_extract(CPU *c) {
    uint32_t sp = REG(c, R_ESP);
    assert(G32(sp + 4u + 0u) == expected_param_info && expected_param_info != 0u);
    assert(G32(sp + 4u + 4u) == 0x30030000u);
    assert(G32(sp + 4u + 8u) == 0x30031000u);
    assert(G32(sp + 4u + 12u) == expected_this_obj);
    assert(G32(sp + 4u + 16u) == 0x30035000u);
    assert(G32(sp + 4u + 20u) == 0x30040000u);
    assert(G32(sp + 4u + 24u) == 0x30045000u);
    if (fake_extract_mode == 1) {
        P32(G32(sp + 4u + 28u), fake_extract_u0);
    } else if (fake_extract_mode == 2) {
        P32(G32(sp + 4u + 28u), fake_extract_u0);
        P32(G32(sp + 4u + 32u), fake_extract_u1);
    } else if (fake_extract_mode == 3) {
        uint32_t str_out = G32(sp + 4u + 28u);
        snprintf((char *)MEM + str_out, 512, "%s", fake_extract_str ? fake_extract_str : "");
        for (int i = 0; i < fake_extract_nfloats && i < 9; i++) {
            uint32_t f_out = G32(sp + 4u + 32u + 4u * (uint32_t)i);
            memcpy(MEM + f_out, &fake_extract_floats[i], 4);
        }
    } else if (fake_extract_mode == 4) {
        P32(G32(sp + 4u + 28u), fake_extract_u0);
        P32(G32(sp + 4u + 32u), fake_extract_u1);
        P32(G32(sp + 4u + 36u), fake_extract_u2);
    }
    SETREG(c, R_EAX, 1u);
}

static void g_console_print(CPU *c) {
    uint32_t sp = REG(c, R_ESP);
    const char *fmt = GSTR(G32(sp + 4u));
    const char *msg = GSTR(G32(sp + 8u));
    assert(strcmp(fmt, "%s") == 0);
    snprintf(last_console_msg, sizeof last_console_msg, "%s", msg ? msg : "");
    SETREG(c, R_EAX, 1u);
}

static void g_lookup_form(CPU *c) {
    uint32_t fid = G32(REG(c, R_ESP) + 4u);
    SETREG(c, R_EAX, fid == 0x02001234u ? 0x31001000u : 0u);
}

enum {
    FAKE_INI_COL = 0x33000000u,
    FAKE_INI_PREF_COL = 0x33001000u,
    FAKE_SET_SENS = 0x33010000u,
    FAKE_SET_BOOL = 0x33010100u,
    FAKE_SET_INT = 0x33010200u,
};

static void g_ini_get(CPU *c) { SETREG(c, R_EAX, FAKE_INI_COL); }
static void g_ini_pref_get(CPU *c) { SETREG(c, R_EAX, FAKE_INI_PREF_COL); }
static void g_setting_lookup(CPU *c) {
    uint32_t col = REG(c, R_ECX);
    const char *name = GSTR(G32(REG(c, R_ESP) + 4u));
    uint32_t res = 0u;
    if (col == FAKE_INI_COL) {
        if (strcasecmp(name, "bFlag:General") == 0) res = FAKE_SET_BOOL;
        else if (strcasecmp(name, "iCount:General") == 0) res = FAKE_SET_INT;
    } else if (col == FAKE_INI_PREF_COL) {
        if (strcasecmp(name, "fMouseSensitivity:Controls") == 0) res = FAKE_SET_SENS;
    }
    SETREG(c, R_EAX, res);
}

const uint32_t rt_fn_addr[] = {
    FN_ADD_CDECL,
    FN_THIS_SUB,
    FN_INI_GET,
    FN_LOOKUP_FORM,
    FN_INI_PREF_GET,
    FN_EXTRACT,
    FN_PARSE,
    FN_SETTING_LOOKUP,
    FN_CONSOLE_PRINT,
};
const GuestFn rt_fn_ptr[] = {
    g_add_cdecl,
    g_this_sub,
    g_ini_get,
    g_lookup_form,
    g_ini_pref_get,
    g_extract,
    g_parse,
    g_setting_lookup,
    g_console_print,
};
const int rt_fn_count = (int)(sizeof rt_fn_addr / sizeof *rt_fn_addr);

// ---- test helpers --------------------------------------------------------------------------
static uint32_t cmd_slot(uint32_t opcode) {
    return host_script_cmd_base + (opcode - 0x1000u) * 0x28u;
}

static uint32_t call_exec(CPU *c, uint32_t opcode, uint32_t this_obj, uint32_t result_ptr) {
    uint32_t slot = cmd_slot(opcode);
    uint32_t exec = G32(slot + 0x18u);
    assert(exec >= SCRIPT_THUNK_BASE && exec < SCRIPT_THUNK_END);
    expected_param_info = G32(slot + 0x14u);
    expected_this_obj = this_obj;
    uint32_t sp = 0x30020000u;
    P32(sp, 0x12345678u);
    P32(sp + 4u, expected_param_info); // paramInfo
    P32(sp + 8u, 0x30030000u);         // scriptData
    P32(sp + 12u, this_obj);           // thisObj
    P32(sp + 16u, 0x30035000u);        // containingObj
    P32(sp + 20u, 0x30040000u);        // scriptObj
    P32(sp + 24u, 0x30045000u);        // eventList
    P32(sp + 28u, result_ptr);         // result
    P32(sp + 32u, 0x30031000u);        // opcodeOffsetPtr
    SETREG(c, R_ESP, sp);
    rt_call(c, exec);
    assert(REG(c, R_ESP) == sp + 4u); // __cdecl: callee leaves args for caller
    return REG(c, R_EAX) & 0xFFu;
}

static uint32_t call_eval(CPU *c, uint32_t opcode, uint32_t this_obj, uint32_t arg1, uint32_t arg2, uint32_t result_ptr) {
    uint32_t slot = cmd_slot(opcode);
    uint32_t eval = G32(slot + 0x20u);
    assert(eval >= SCRIPT_THUNK_BASE && eval < SCRIPT_THUNK_END);
    uint32_t sp = 0x30020000u;
    P32(sp, 0x12345678u);
    P32(sp + 4u, this_obj);
    P32(sp + 8u, arg1);
    P32(sp + 12u, arg2);
    P32(sp + 16u, result_ptr);
    SETREG(c, R_ESP, sp);
    rt_call(c, eval);
    assert(REG(c, R_ESP) == sp + 4u);
    return REG(c, R_EAX) & 0xFFu;
}

static double read_double(uint32_t addr) {
    double v = 0.0;
    memcpy(&v, MEM + addr, 8);
    return v;
}

static uint32_t thunk_hit;
static void test_thunk_fn(CPU *c) {
    thunk_hit++;
    RET(c, ARG(c, 0) + 7u, 0);
}

int main(void) {
    MEM = fnv_reserve_guest();
    assert(MEM != MAP_FAILED);

    // 1. Test script_thunk_alloc + rt_call routing on 0xFEE20000..0xFEE30000
    uint32_t th = script_thunk_alloc("test_thunk", test_thunk_fn);
    assert(th == SCRIPT_THUNK_BASE);
    CPU cpu = {0};
    SETREG(&cpu, R_ESP, 0x30010000u);
    P32(0x30010000u, 0x99999999u);
    P32(0x30010004u, 35u);
    rt_call(&cpu, th);
    assert(thunk_hit == 1 && REG(&cpu, R_EAX) == 42u && REG(&cpu, R_ESP) == 0x30010004u);

    // 2. Test guest_call_cdecl / guest_call_thiscall & full CPU state preservation
    SETREG(&cpu, R_ESP, 0x30018000u);
    SETREG(&cpu, R_ECX, 0x11223344u);
    cpu.r[REG_TOP] = 2;
    double st0_orig = 3.14159265;
    memcpy(cpu.r + 4352, &st0_orig, 8);
    uint32_t c_args[2] = {10u, 32u};
    assert(guest_call_cdecl(&cpu, FN_ADD_CDECL, 2, c_args) == 42u);
    assert(REG(&cpu, R_ESP) == 0x30018000u);
    assert(REG(&cpu, R_ECX) == 0x11223344u);
    assert(cpu.r[REG_TOP] == 2);
    double st0_after = 0.0;
    memcpy(&st0_after, cpu.r + 4352, 8);
    assert(st0_after == st0_orig);
    uint32_t t_args[2] = {20u, 5u};
    assert(guest_call_thiscall(&cpu, FN_THIS_SUB, 100u, 2, t_args) == 115u);
    assert(REG(&cpu, R_ECX) == 0x11223344u);

    // 3. Test unset and FNV_SCRIPT_EXT=0 both keep vanilla bounds
    unsetenv("FNV_SCRIPT_EXT");
    script_ext_init_table(0x01190910u, 0x0118e8e0u, 205u, FN_PARSE, FN_EXTRACT, FN_CONSOLE_PRINT, FN_LOOKUP_FORM);
    assert(host_script_cmd_base == 0x01190910u);
    assert(host_script_cmd_count == 0x280u);
    assert(host_script_cmd_max_opcode == 0x1280u);
    setenv("FNV_SCRIPT_EXT", "0", 1);
    script_ext_init_table(0x01190910u, 0x0118e8e0u, 205u, FN_PARSE, FN_EXTRACT, FN_CONSOLE_PRINT, FN_LOOKUP_FORM);
    assert(host_script_cmd_base == 0x01190910u);
    assert(host_script_cmd_count == 0x280u);
    assert(host_script_cmd_max_opcode == 0x1280u);
    setenv("FNV_SCRIPT_EXT", "1", 1);

    // 4. Populate synthetic vanilla tables in guest memory and initialize extended table
    const uint32_t v_script = 0x20000000u;
    const uint32_t v_console = 0x20100000u;
    const uint32_t str_pool = 0x20200000u;
    for (uint32_t i = 0; i < 0x280u; i++) {
        uint32_t slot = v_script + i * 0x28u;
        P32(slot + 0x08u, 0x1000u + i);
        P32(slot + 0x18u, 0x005b4b20u);
        P32(slot + 0x1cu, FN_PARSE);
    }
    static const char *const cnames[10] = {
        "SetGameSetting", "SetINISetting", "GetINISetting", "RefreshINI", "Save",
        "SaveINI", "QuitGame", "LoadGame", "CloseAllMenus", "SetVel",
    };
    uint32_t sp_off = 0;
    for (uint32_t i = 0; i < 10u; i++) {
        uint32_t saddr = str_pool + sp_off;
        size_t len = strlen(cnames[i]) + 1;
        memcpy(MEM + saddr, cnames[i], len);
        sp_off += (uint32_t)len;
        uint32_t slot = v_console + i * 0x28u;
        P32(slot + 0x00u, saddr);
        P32(slot + 0x08u, 0x0100u + i);
        P32(slot + 0x18u, 0x005c0000u + i * 0x10u);
    }

    script_thunk_reset();
    script_ext_set_fnv_extras(0x32010000u, FN_INI_GET, FN_INI_PREF_GET, FN_SETTING_LOOKUP);
    script_ext_init_table(v_script, v_console, 10u, FN_PARSE, FN_EXTRACT, FN_CONSOLE_PRINT, FN_LOOKUP_FORM);
    assert(host_script_cmd_base != v_script);
    assert(host_script_cmd_count == 0x1000u);
    assert(host_script_cmd_max_opcode == 0x2000u);

    // Check copied vanilla entries, gap padding, and imported console commands
    assert(G32(cmd_slot(0x1001u) + 0x08u) == 0x1001u);
    assert(G32(cmd_slot(0x1280u) + 0x08u) == 0x1280u && G32(cmd_slot(0x1280u) + 0x18u) == 0u);
    assert(G32(cmd_slot(0x1435u) + 0x08u) == 0x1435u);
    assert(strcmp(GSTR(G32(cmd_slot(0x1435u))), "SetGameSetting") == 0);
    assert(G32(cmd_slot(0x143eu) + 0x08u) == 0x143eu);
    assert(strcmp(GSTR(G32(cmd_slot(0x143eu))), "SetVel") == 0);

    // 5. Execute & Eval version commands
    const uint32_t res_ptr = 0x30050000u;
    assert(call_exec(&cpu, 0x1400u, 0u, res_ptr) == 1u && read_double(res_ptr) == 1.0);
    setenv("FNV_NVSE_VERSION", "6", 1);
    assert(call_eval(&cpu, 0x1400u, 0u, 0u, 0u, res_ptr) == 1u && read_double(res_ptr) == 6.0);
    unsetenv("FNV_NVSE_VERSION");
    assert(call_exec(&cpu, 0x1401u, 0u, res_ptr) == 1u && read_double(res_ptr) == 0.0);
    assert(call_exec(&cpu, 0x1402u, 0u, res_ptr) == 1u && read_double(res_ptr) == 0.0);

    // 6. GetBaseObject & GetType
    const uint32_t fake_base = 0x31002000u;
    const uint32_t fake_refr = 0x31003000u;
    MEM[fake_base + 0x04u] = 40; // kFormType_TESObjectWEAP = 40
    P32(fake_base + 0x0cu, 0x00012345u);
    MEM[fake_refr + 0x04u] = 61; // kFormType_TESObjectREFR = 61
    P32(fake_refr + 0x20u, fake_base);
    assert(call_exec(&cpu, 0x1403u, fake_refr, res_ptr) == 1u);
    assert(G32(res_ptr) == 0x00012345u && G32(res_ptr + 4u) == 0u);

    fake_extract_mode = 1;
    fake_extract_u0 = 0u; // omitted -> fallback to thisObj
    assert(call_exec(&cpu, 0x140Au, fake_refr, res_ptr) == 1u && read_double(res_ptr) == 61.0);
    fake_extract_u0 = fake_base;
    assert(call_exec(&cpu, 0x140Au, fake_refr, res_ptr) == 1u && read_double(res_ptr) == 40.0);
    assert(call_eval(&cpu, 0x140Au, fake_refr, fake_base, 0u, res_ptr) == 1u && read_double(res_ptr) == 40.0);

    // 7. Keyboard / mouse commands + delta non-destruction
    input_mouse_move(17, -9);
    input_mouse_button(0, 1); // scancode 256
    fake_extract_mode = 2;
    fake_extract_u0 = 256u;
    fake_extract_u1 = 0u;
    assert(call_exec(&cpu, 0x1453u, 0u, res_ptr) == 1u && read_double(res_ptr) == 1.0);
    assert(call_exec(&cpu, 0x145Bu, 0u, res_ptr) == 1u && read_double(res_ptr) == 1.0);
    fake_extract_mode = 1;
    fake_extract_u0 = 0u;
    assert(call_exec(&cpu, 0x145Cu, 0u, res_ptr) == 1u && read_double(res_ptr) == 256.0);
    // Verify mouse deltas were NOT cleared by mouse button queries!
    int32_t dx = 0, dy = 0, dz = 0;
    uint8_t mb[8] = {0};
    input_mouse_state(&dx, &dy, &dz, mb);
    assert(dx == 17 && dy == -9 && mb[0] == 0x80);

    fake_extract_mode = 1;
    fake_extract_u0 = 0x11u; // DIK_W
    assert(call_exec(&cpu, 0x1455u, 0u, res_ptr) == 1u); // HoldKey
    assert(call_exec(&cpu, 0x1459u, 0u, res_ptr) == 1u && read_double(res_ptr) == 1.0);
    fake_extract_u0 = 0u;
    assert(call_exec(&cpu, 0x145Au, 0u, res_ptr) == 1u && read_double(res_ptr) == (double)0x11);
    fake_extract_u0 = 0x11u;
    assert(call_exec(&cpu, 0x1456u, 0u, res_ptr) == 1u); // ReleaseKey
    assert(call_exec(&cpu, 0x1459u, 0u, res_ptr) == 1u && read_double(res_ptr) == 0.0);

    // 8. PrintToConsole (safe formatting) & BuildRef
    fake_extract_mode = 3;
    fake_extract_str = "HP=%.1f idx=%d raw=%s";
    fake_extract_floats[0] = 75.5f;
    fake_extract_floats[1] = 7.0f;
    fake_extract_nfloats = 2;
    assert(call_exec(&cpu, 0x14A0u, 0u, res_ptr) == 1u);
    assert(strcmp(last_console_msg, "HP=75.5 idx=7 raw=%s") == 0);

    fake_extract_mode = 2;
    fake_extract_u0 = 2u;
    fake_extract_u1 = 0x001234u;
    assert(call_exec(&cpu, 0x14D9u, 0u, res_ptr) == 1u && G32(res_ptr) == 0x02001234u);
    fake_extract_u1 = 0x009999u;
    assert(call_exec(&cpu, 0x14D9u, 0u, res_ptr) == 1u && G32(res_ptr) == 0u);

    // 9. DisableKey / EnableKey / IsKeyDisabled + TapKey single-frame pulse
    input_key(0x2Au, 1); // physical LShift down
    fake_extract_mode = 1;
    fake_extract_u0 = 0x2Au;
    assert(call_exec(&cpu, 0x1457u, 0u, res_ptr) == 1u); // DisableKey
    assert(call_exec(&cpu, 0x1469u, 0u, res_ptr) == 1u && read_double(res_ptr) == 1.0);
    assert(call_eval(&cpu, 0x1469u, 0u, 0x2Au, 0u, res_ptr) == 1u && read_double(res_ptr) == 1.0);
    uint8_t di_keys[256];
    input_dinput_keyboard_state(di_keys);
    assert(di_keys[0x2Au] == 0); // masked from DirectInput
    fake_extract_mode = 2;
    fake_extract_u0 = 0x2Au;
    fake_extract_u1 = 0u;
    assert(call_exec(&cpu, 0x1453u, 0u, res_ptr) == 1u && read_double(res_ptr) == 1.0); // IsKeyPressed still sees physical LShift!
    fake_extract_mode = 1;
    fake_extract_u0 = 0x2Au;
    assert(call_exec(&cpu, 0x1458u, 0u, res_ptr) == 1u); // EnableKey
    assert(call_exec(&cpu, 0x1469u, 0u, res_ptr) == 1u && read_double(res_ptr) == 0.0);
    input_dinput_keyboard_state(di_keys);
    assert(di_keys[0x2Au] == 0x80);
    input_key(0x2Au, 0);

    fake_extract_mode = 1;
    fake_extract_u0 = 0x13u; // DIK_R
    assert(call_exec(&cpu, 0x1454u, 0u, res_ptr) == 1u); // TapKey
    input_dinput_keyboard_state(di_keys);
    assert(di_keys[0x13u] == 0x80);
    input_dinput_keyboard_state(di_keys);
    assert(di_keys[0x13u] == 0);

    // 10. OSInputGlobals control commands (Sprint Mod path)
    const uint32_t ig = 0x32000000u;
    P32(0x32010000u, ig);
    memset(MEM + ig + 0x1b94u, 0xFF, 28 * 4);
    MEM[ig + 0x1b94u + 9u] = 42u;  // Run = LShift (0x2A)
    MEM[ig + 0x1b94u + 8u] = 58u;  // AlwaysRun = CapsLock (0x3A)
    MEM[ig + 0x1bb0u + 6u] = 0u;   // Attack = Mouse0 (256)

    fake_extract_mode = 2;
    fake_extract_u0 = 9u;
    fake_extract_u1 = 0u;
    assert(call_exec(&cpu, 0x145Du, 0u, res_ptr) == 1u && read_double(res_ptr) == 42.0); // GetControl 9
    assert(call_eval(&cpu, 0x145Du, 0u, 9u, 0u, res_ptr) == 1u && read_double(res_ptr) == 42.0);
    fake_extract_mode = 1;
    fake_extract_u0 = 6u;
    assert(call_exec(&cpu, 0x145Eu, 0u, res_ptr) == 1u && read_double(res_ptr) == 256.0); // GetAltControl 6
    fake_extract_u0 = 42u;
    assert(call_exec(&cpu, 0x1468u, 0u, res_ptr) == 1u && read_double(res_ptr) == 1.0); // IsControl 42
    fake_extract_u0 = 256u;
    assert(call_exec(&cpu, 0x1468u, 0u, res_ptr) == 1u && read_double(res_ptr) == 1.0); // IsControl 256
    fake_extract_u0 = 99u;
    assert(call_exec(&cpu, 0x1468u, 0u, res_ptr) == 1u && read_double(res_ptr) == 0.0);

    // DisableControl 9 masks LShift from DirectInput; IsControlPressed & IsKeyPressed still see it
    input_key(42, 1);
    fake_extract_mode = 1;
    fake_extract_u0 = 9u;
    assert(call_exec(&cpu, 0x1462u, 0u, res_ptr) == 1u); // DisableControl 9
    assert(call_exec(&cpu, 0x146Au, 0u, res_ptr) == 1u && read_double(res_ptr) == 1.0);
    assert(call_exec(&cpu, 0x146Bu, 0u, res_ptr) == 1u && read_double(res_ptr) == 1.0); // IsControlPressed 9
    input_dinput_keyboard_state(di_keys);
    assert(di_keys[42] == 0);
    assert(call_exec(&cpu, 0x1463u, 0u, res_ptr) == 1u); // EnableControl 9
    assert(call_exec(&cpu, 0x146Au, 0u, res_ptr) == 1u && read_double(res_ptr) == 0.0);
    input_dinput_keyboard_state(di_keys);
    assert(di_keys[42] == 0x80);
    input_key(42, 0);

    // IsControlPressed for mouse-bound control 6
    input_mouse_button(0, 1);
    fake_extract_mode = 1;
    fake_extract_u0 = 6u;
    assert(call_exec(&cpu, 0x146Bu, 0u, res_ptr) == 1u && read_double(res_ptr) == 1.0);
    input_mouse_button(0, 0);

    // GetKeyPress 0 and GetMouseButtonPress 0 return -1 when nothing is pressed
    fake_extract_mode = 1;
    fake_extract_u0 = 0u;
    assert(call_exec(&cpu, 0x145Au, 0u, res_ptr) == 1u && read_double(res_ptr) == -1.0);
    assert(call_exec(&cpu, 0x145Cu, 0u, res_ptr) == 1u && read_double(res_ptr) == -1.0);

    // TapControl 8 pulses CapsLock (58) for 1 frame
    fake_extract_mode = 1;
    fake_extract_u0 = 8u;
    assert(call_exec(&cpu, 0x1464u, 0u, res_ptr) == 1u);
    input_dinput_keyboard_state(di_keys);
    assert(di_keys[58] == 0x80);
    input_dinput_keyboard_state(di_keys);
    assert(di_keys[58] == 0);

    // SetControl 9 -1 -> GetControl 9 == -1, then restore 42; SetAltControl 6 257
    fake_extract_mode = 4;
    fake_extract_u0 = 9u;
    fake_extract_u1 = 0xFFFFFFFFu;
    fake_extract_u2 = 0u;
    assert(call_exec(&cpu, 0x1465u, 0u, res_ptr) == 1u);
    fake_extract_mode = 2;
    fake_extract_u0 = 9u;
    fake_extract_u1 = 0u;
    assert(call_exec(&cpu, 0x145Du, 0u, res_ptr) == 1u && read_double(res_ptr) == -1.0);
    fake_extract_mode = 4;
    fake_extract_u0 = 9u;
    fake_extract_u1 = 42u;
    fake_extract_u2 = 0u;
    assert(call_exec(&cpu, 0x1465u, 0u, res_ptr) == 1u);
    assert(MEM[ig + 0x1b94u + 9u] == 42u);
    fake_extract_mode = 2;
    fake_extract_u0 = 6u;
    fake_extract_u1 = 257u;
    assert(call_exec(&cpu, 0x1466u, 0u, res_ptr) == 1u); // SetAltControl
    assert(MEM[ig + 0x1bb0u + 6u] == 1u);

    // DisableControl 9 + SetControl 9 -1 re-syncs disabled scancode mask cleanly
    input_key(42, 1);
    fake_extract_mode = 1;
    fake_extract_u0 = 9u;
    assert(call_exec(&cpu, 0x1462u, 0u, res_ptr) == 1u); // DisableControl 9
    input_dinput_keyboard_state(di_keys);
    assert(di_keys[42] == 0);
    fake_extract_mode = 4;
    fake_extract_u0 = 9u;
    fake_extract_u1 = 0xFFFFFFFFu;
    fake_extract_u2 = 0u;
    assert(call_exec(&cpu, 0x1465u, 0u, res_ptr) == 1u); // SetControl 9 -1
    input_dinput_keyboard_state(di_keys);
    assert(di_keys[42] == 0x80);
    fake_extract_u1 = 42u;
    assert(call_exec(&cpu, 0x1465u, 0u, res_ptr) == 1u); // SetControl 9 42 (control 9 still disabled)
    input_dinput_keyboard_state(di_keys);
    assert(di_keys[42] == 0);
    fake_extract_mode = 1;
    fake_extract_u0 = 9u;
    assert(call_exec(&cpu, 0x1463u, 0u, res_ptr) == 1u); // EnableControl 9
    input_dinput_keyboard_state(di_keys);
    assert(di_keys[42] == 0x80);
    input_key(42, 0);

    // 11. GetNumericIniSetting & SetNumericIniSetting
    const uint32_t ini_str_base = 0x33020000u;
    strcpy((char *)MEM + ini_str_base, "fMouseSensitivity:Controls");
    strcpy((char *)MEM + ini_str_base + 64u, "bFlag:General");
    strcpy((char *)MEM + ini_str_base + 128u, "iCount:General");
    float sens0 = 0.0025f;
    memcpy(MEM + FAKE_SET_SENS + 4u, &sens0, 4);
    P32(FAKE_SET_SENS + 8u, ini_str_base);
    MEM[FAKE_SET_BOOL + 4u] = 1u;
    P32(FAKE_SET_BOOL + 8u, ini_str_base + 64u);
    P32(FAKE_SET_INT + 4u, (uint32_t)-42);
    P32(FAKE_SET_INT + 8u, ini_str_base + 128u);

    fake_extract_mode = 3;
    fake_extract_nfloats = 0;
    fake_extract_str = "fMouseSensitivity:Controls";
    assert(call_exec(&cpu, 0x149Cu, 0u, res_ptr) == 1u);
    assert(fabs(read_double(res_ptr) - 0.0025) < 1e-6);
    fake_extract_str = "bFlag:General";
    assert(call_exec(&cpu, 0x149Cu, 0u, res_ptr) == 1u && read_double(res_ptr) == 1.0);
    fake_extract_str = "iCount:General";
    assert(call_exec(&cpu, 0x149Cu, 0u, res_ptr) == 1u && read_double(res_ptr) == -42.0);
    fake_extract_str = "fMissing:Controls";
    assert(call_exec(&cpu, 0x149Cu, 0u, res_ptr) == 1u && read_double(res_ptr) == -1.0);

    fake_extract_str = "fMouseSensitivity:Controls";
    fake_extract_floats[0] = 0.005f;
    fake_extract_nfloats = 1;
    assert(call_exec(&cpu, 0x149Du, 0u, res_ptr) == 1u && read_double(res_ptr) == 1.0);
    fake_extract_nfloats = 0;
    assert(call_exec(&cpu, 0x149Cu, 0u, res_ptr) == 1u);
    assert(fabs(read_double(res_ptr) - 0.005) < 1e-6);

    // 12. Unimplemented opcode sentinel returns AL=1 and zeroes result without trapping
    double sentinel_pre = 123.0;
    memcpy(MEM + res_ptr, &sentinel_pre, 8);
    assert(call_exec(&cpu, 0x14FFu, 0u, res_ptr) == 1u && read_double(res_ptr) == 0.0);
    assert(trap_hit == 0);

    puts("PASS: script_bridge + ScriptCommands relocation + clean-room NVSE-lite handlers");
    return 0;
}
