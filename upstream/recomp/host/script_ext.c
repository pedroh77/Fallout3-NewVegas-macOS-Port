#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include "host.h"
#include "input.h"
#include "script_bridge.h"
#include "script_ext.h"

extern void input_set_scancode_disabled(int sc, int disabled);
extern int input_is_scancode_disabled(int sc);
extern void input_script_tap_scancode(int sc);
extern void input_script_hold_scancode(int sc);
extern void input_script_release_scancode(int sc);
extern int input_is_script_held(int sc);
extern void input_script_reset_overrides(void);

// Relocated ScriptCommands bounds read by patched generated TUs.
// Initialized to vanilla FNV defaults so unpatched builds and FNV_SCRIPT_EXT=0 stay identical.
uint32_t host_script_cmd_base = 0x01190910u;
uint32_t host_script_cmd_max_opcode = 0x1280u;
uint32_t host_script_cmd_count = 0x280u;

enum {
    CMD_SIZE = 0x28,
    PARAM_SIZE = 12,
    FNV_OPCODE_BASE = 0x1000u,
    FNV_VANILLA_SCRIPT_BASE = 0x01190910u,
    FNV_VANILLA_SCRIPT_COUNT = 0x280u,
    FNV_VANILLA_CONSOLE_BASE = 0x0118e8e0u,
    FNV_VANILLA_CONSOLE_COUNT = 205u,
    EXT_TABLE_COUNT = 0x1000u,
    FNV_DEFAULT_PARSE_FN = 0x005b1ba0u,
    FNV_EXTRACT_ARGS_FN = 0x005accb0u,
    FNV_CONSOLE_PRINT_FN = 0x00703c00u,
    FNV_LOOKUP_FORM_FN = 0x004839c0u,
    FNV_INPUT_GLOBALS_PTR = 0x011f35ccu,
    FNV_INI_GET_FN = 0x0044f560u,
    FNV_INI_PREF_GET_FN = 0x004de490u,
    FNV_SETTING_LOOKUP_FN = 0x005e02b0u,
    FNV_NUM_CONTROLS = 28,
};

enum {
    PARAM_STRING = 0x00u,
    PARAM_INT = 0x01u,
    PARAM_FLOAT = 0x02u,
    PARAM_INVENTORY_OBJ = 0x32u,
};

typedef struct {
    const char *type_str;
    uint32_t type_id;
    uint32_t is_optional;
} NativeParamDesc;

static uint32_t g_extract_fn;
static uint32_t g_console_print_fn;
static uint32_t g_lookup_form_fn;
static uint32_t g_input_globals_ptr;
static uint32_t g_ini_get_fn;
static uint32_t g_ini_pref_get_fn;
static uint32_t g_setting_lookup_fn;
static uint32_t g_empty_str;
static uint8_t g_disabled_keys[264];
static uint8_t g_disabled_controls[FNV_NUM_CONTROLS];

void script_ext_set_fnv_extras(uint32_t input_globals_ptr,
                               uint32_t ini_get_fn,
                               uint32_t ini_pref_get_fn,
                               uint32_t setting_lookup_fn) {
    g_input_globals_ptr = input_globals_ptr;
    g_ini_get_fn = ini_get_fn;
    g_ini_pref_get_fn = ini_pref_get_fn;
    g_setting_lookup_fn = setting_lookup_fn;
}

static uint32_t guest_strdup(const char *s) {
    if (!s || !s[0]) return g_empty_str;
    size_t len = strlen(s) + 1;
    uint32_t addr = gmalloc((uint32_t)len);
    memcpy(MEM + addr, s, len);
    return addr;
}

static void write_u16(uint32_t addr, uint16_t v) { memcpy(MEM + addr, &v, 2); }

static void set_result_double(uint32_t result_ptr, double v) {
    if (!result_ptr) return;
    memcpy(MEM + result_ptr, &v, 8);
}

static void set_result_formid(uint32_t result_ptr, uint32_t form_id) {
    if (!result_ptr) return;
    memset(MEM + result_ptr, 0, 8);
    P32(result_ptr, form_id);
}

static double env_double(const char *name, double defval) {
    const char *s = getenv(name);
    if (!s || !s[0]) return defval;
    char *end = NULL;
    double v = strtod(s, &end);
    return (end && end != s) ? v : defval;
}

static int extract_args(CPU *c, uint32_t caller_esp, int num_out, const uint32_t *out_ptrs) {
    if (!g_extract_fn) return 0;
    uint32_t args[17];
    if (num_out > 10) return 0;
    args[0] = G32(caller_esp + 4u + 4u * 0u); // paramInfo
    args[1] = G32(caller_esp + 4u + 4u * 1u); // scriptData
    args[2] = G32(caller_esp + 4u + 4u * 7u); // opcodeOffsetPtr
    args[3] = G32(caller_esp + 4u + 4u * 2u); // thisObj
    args[4] = G32(caller_esp + 4u + 4u * 3u); // containingObj
    args[5] = G32(caller_esp + 4u + 4u * 4u); // scriptObj
    args[6] = G32(caller_esp + 4u + 4u * 5u); // eventList
    for (int i = 0; i < num_out; i++) {
        args[7 + i] = out_ptrs[i];
    }
    return (guest_call_cdecl(c, g_extract_fn, 7 + num_out, args) & 0xFFu) != 0;
}

// ---- command handlers ----------------------------------------------------------------------

static void cmd_unimplemented(CPU *c) {
    static uint32_t warn_count;
    if (warn_count < 32) {
        warn_count++;
        fprintf(stderr, "[nvse-lite] unimplemented NVSE command invoked (scriptObj=%#x, params=%#x)\n",
                ARG(c, 4), ARG(c, 0));
    }
    set_result_double(ARG(c, 6), 0.0);
    RET(c, 1, 0);
}

static void cmd_get_nvse_version(CPU *c) {
    set_result_double(ARG(c, 6), env_double("FNV_NVSE_VERSION", 1.0));
    RET(c, 1, 0);
}

static void eval_get_nvse_version(CPU *c) {
    set_result_double(ARG(c, 3), env_double("FNV_NVSE_VERSION", 1.0));
    RET(c, 1, 0);
}

static void cmd_get_nvse_revision(CPU *c) {
    set_result_double(ARG(c, 6), env_double("FNV_NVSE_REVISION", 0.0));
    RET(c, 1, 0);
}

static void eval_get_nvse_revision(CPU *c) {
    set_result_double(ARG(c, 3), env_double("FNV_NVSE_REVISION", 0.0));
    RET(c, 1, 0);
}

static void cmd_get_nvse_beta(CPU *c) {
    set_result_double(ARG(c, 6), env_double("FNV_NVSE_BETA", 0.0));
    RET(c, 1, 0);
}

static void eval_get_nvse_beta(CPU *c) {
    set_result_double(ARG(c, 3), env_double("FNV_NVSE_BETA", 0.0));
    RET(c, 1, 0);
}

static void cmd_get_base_object(CPU *c) {
    uint32_t this_obj = ARG(c, 2);
    uint32_t base_form = this_obj ? G32(this_obj + 0x20u) : 0u;
    uint32_t form_id = base_form ? G32(base_form + 0x0cu) : 0u;
    set_result_formid(ARG(c, 6), form_id);
    RET(c, 1, 0);
}

static void cmd_get_type(CPU *c) {
    uint32_t saved_esp = REG(c, R_ESP);
    uint32_t scratch = (saved_esp - 16u) & ~15u;
    P32(scratch, 0u);
    SETREG(c, R_ESP, scratch);
    uint32_t out_ptrs[1] = {scratch};
    int ok = extract_args(c, saved_esp, 1, out_ptrs);
    uint32_t form = ok ? G32(scratch) : 0u;
    SETREG(c, R_ESP, saved_esp);
    if (!ok) {
        RET(c, 0, 0);
        return;
    }
    if (!form) form = ARG(c, 2); // fallback to thisObj when optional arg omitted
    double type_id = form ? (double)MEM[form + 0x04u] : 0.0;
    set_result_double(ARG(c, 6), type_id);
    RET(c, 1, 0);
}

static void eval_get_type(CPU *c) {
    uint32_t form = ARG(c, 1);
    if (!form) form = ARG(c, 0);
    set_result_double(ARG(c, 3), form ? (double)MEM[form + 0x04u] : 0.0);
    RET(c, 1, 0);
}

static int query_scancode_down(int32_t scancode) {
    if (scancode >= 0 && scancode < 256) {
        uint8_t keys[256];
        input_keyboard_state(keys);
        return keys[scancode] != 0 || input_is_script_held(scancode);
    }
    if (scancode >= 256 && scancode < 264) {
        uint8_t btns[8];
        input_mouse_buttons(btns);
        return btns[scancode - 256] != 0 || input_is_script_held(scancode);
    }
    return 0;
}

static void cmd_is_key_pressed(CPU *c) {
    uint32_t saved_esp = REG(c, R_ESP);
    uint32_t scratch = (saved_esp - 16u) & ~15u;
    P32(scratch, 0xffffffffu);
    P32(scratch + 4u, 0u);
    SETREG(c, R_ESP, scratch);
    uint32_t out_ptrs[2] = {scratch, scratch + 4u};
    int ok = extract_args(c, saved_esp, 2, out_ptrs);
    int32_t key = (int32_t)G32(scratch);
    SETREG(c, R_ESP, saved_esp);
    if (!ok) {
        RET(c, 0, 0);
        return;
    }
    set_result_double(ARG(c, 6), query_scancode_down(key) ? 1.0 : 0.0);
    RET(c, 1, 0);
}

static void eval_is_key_pressed(CPU *c) {
    int32_t key = (int32_t)ARG(c, 1);
    set_result_double(ARG(c, 3), query_scancode_down(key) ? 1.0 : 0.0);
    RET(c, 1, 0);
}

static void set_scancode_state(int32_t scancode, int mode) {
    // mode: 0 = release, 1 = hold, 2 = tap (single DirectInput poll pulse)
    if (scancode <= 0 || scancode >= 264) return;
    if (mode == 2) input_script_tap_scancode(scancode);
    else if (mode == 1) input_script_hold_scancode(scancode);
    else input_script_release_scancode(scancode);
}

static uint32_t get_input_globals(void) {
    return g_input_globals_ptr ? G32(g_input_globals_ptr) : 0u;
}

static uint32_t control_table_offset(int32_t ctrl_type) {
    switch (ctrl_type) {
    case 0: return 0x1b94u; // keyBinds[28]
    case 1: return 0x1bb0u; // mouseBinds[28]
    case 2: return 0x1bccu; // joyBinds[28]
    case 3: return 0x1be8u; // xinputBinds[28]
    default: return 0u;
    }
}

static int32_t get_control_bind(int32_t ctrl, int32_t ctrl_type) {
    uint32_t ig = get_input_globals();
    uint32_t off = control_table_offset(ctrl_type);
    if (!ig || !off || ctrl < 0 || ctrl >= FNV_NUM_CONTROLS) return -1;
    uint8_t b = MEM[ig + off + (uint32_t)ctrl];
    if (b == 0xFFu) return -1;
    return (ctrl_type == 1) ? (256 + (int32_t)b) : (int32_t)b;
}

static int is_scancode_bound_to_disabled_control(int sc) {
    uint32_t ig = get_input_globals();
    if (!ig || sc < 0 || sc >= 264) return 0;
    for (int i = 0; i < FNV_NUM_CONTROLS; i++) {
        if (!g_disabled_controls[i]) continue;
        if (sc < 255 && MEM[ig + 0x1b94u + (uint32_t)i] == (uint8_t)sc) return 1;
        if (sc >= 256 && MEM[ig + 0x1bb0u + (uint32_t)i] == (uint8_t)(sc - 256)) return 1;
    }
    return 0;
}

static void sync_scancode_disabled(int sc) {
    if (sc < 0 || sc >= 264) return;
    input_set_scancode_disabled(sc, g_disabled_keys[sc] || is_scancode_bound_to_disabled_control(sc));
}

static void set_control_bind(int32_t ctrl, int32_t key, int32_t ctrl_type) {
    uint32_t ig = get_input_globals();
    uint32_t off = control_table_offset(ctrl_type);
    if (!ig || !off || ctrl < 0 || ctrl >= FNV_NUM_CONTROLS) return;
    int32_t old_sc = (ctrl_type == 0 || ctrl_type == 1) ? get_control_bind(ctrl, ctrl_type) : -1;
    uint8_t encoded = 0xFFu;
    if (ctrl_type == 1) {
        if (key >= 256 && key < 264) encoded = (uint8_t)(key - 256);
        else if (key >= 0 && key < 8) encoded = (uint8_t)key;
    } else if (key >= 0 && key < 255) {
        encoded = (uint8_t)key;
    }
    MEM[ig + off + (uint32_t)ctrl] = encoded;
    if (ctrl_type == 0 || ctrl_type == 1) {
        int32_t new_sc = get_control_bind(ctrl, ctrl_type);
        if (old_sc >= 0) sync_scancode_disabled(old_sc);
        if (new_sc >= 0) sync_scancode_disabled(new_sc);
    }
}

static int is_scancode_a_control(int32_t sc) {
    uint32_t ig = get_input_globals();
    if (!ig || sc < 0 || sc >= 264) return 0;
    for (int i = 0; i < FNV_NUM_CONTROLS; i++) {
        if (sc < 255 && MEM[ig + 0x1b94u + (uint32_t)i] == (uint8_t)sc) return 1;
        if (sc >= 256 && MEM[ig + 0x1bb0u + (uint32_t)i] == (uint8_t)(sc - 256)) return 1;
    }
    return 0;
}

static void handle_key_action(CPU *c, int mode) {
    uint32_t saved_esp = REG(c, R_ESP);
    uint32_t scratch = (saved_esp - 16u) & ~15u;
    P32(scratch, 0xffffffffu);
    SETREG(c, R_ESP, scratch);
    uint32_t out_ptrs[1] = {scratch};
    int ok = extract_args(c, saved_esp, 1, out_ptrs);
    int32_t key = (int32_t)G32(scratch);
    SETREG(c, R_ESP, saved_esp);
    if (!ok) {
        RET(c, 0, 0);
        return;
    }
    set_scancode_state(key, mode);
    set_result_double(ARG(c, 6), 0.0);
    RET(c, 1, 0);
}

static void cmd_tap_key(CPU *c) { handle_key_action(c, 2); }
static void cmd_hold_key(CPU *c) { handle_key_action(c, 1); }
static void cmd_release_key(CPU *c) { handle_key_action(c, 0); }

static int count_keys_pressed(void) {
    uint8_t keys[256];
    input_keyboard_state(keys);
    int n = 0;
    for (int i = 0; i < 256; i++) {
        if (keys[i] || input_is_script_held(i)) n++;
    }
    return n;
}

static int nth_key_pressed(int32_t nth) {
    if (nth < 0) return -1;
    uint8_t keys[256];
    input_keyboard_state(keys);
    int seen = 0;
    for (int i = 0; i < 256; i++) {
        if (keys[i] || input_is_script_held(i)) {
            if (seen == nth) return i;
            seen++;
        }
    }
    return -1;
}

static int count_mouse_pressed(void) {
    uint8_t btns[8];
    input_mouse_buttons(btns);
    int n = 0;
    for (int i = 0; i < 8; i++) {
        if (btns[i] || input_is_script_held(256 + i)) n++;
    }
    return n;
}

static int nth_mouse_pressed(int32_t nth) {
    if (nth < 0) return -1;
    uint8_t btns[8];
    input_mouse_buttons(btns);
    int seen = 0;
    for (int i = 0; i < 8; i++) {
        if (btns[i] || input_is_script_held(256 + i)) {
            if (seen == nth) return 256 + i;
            seen++;
        }
    }
    return -1;
}

static void cmd_get_num_keys_pressed(CPU *c) {
    set_result_double(ARG(c, 6), (double)count_keys_pressed());
    RET(c, 1, 0);
}

static void eval_get_num_keys_pressed(CPU *c) {
    set_result_double(ARG(c, 3), (double)count_keys_pressed());
    RET(c, 1, 0);
}

static void cmd_get_key_press(CPU *c) {
    uint32_t saved_esp = REG(c, R_ESP);
    uint32_t scratch = (saved_esp - 16u) & ~15u;
    P32(scratch, 0u);
    SETREG(c, R_ESP, scratch);
    uint32_t out_ptrs[1] = {scratch};
    int ok = extract_args(c, saved_esp, 1, out_ptrs);
    int32_t nth = (int32_t)G32(scratch);
    SETREG(c, R_ESP, saved_esp);
    if (!ok) {
        RET(c, 0, 0);
        return;
    }
    set_result_double(ARG(c, 6), (double)nth_key_pressed(nth));
    RET(c, 1, 0);
}

static void eval_get_key_press(CPU *c) {
    set_result_double(ARG(c, 3), (double)nth_key_pressed((int32_t)ARG(c, 1)));
    RET(c, 1, 0);
}

static void cmd_get_num_mouse_buttons_pressed(CPU *c) {
    set_result_double(ARG(c, 6), (double)count_mouse_pressed());
    RET(c, 1, 0);
}

static void eval_get_num_mouse_buttons_pressed(CPU *c) {
    set_result_double(ARG(c, 3), (double)count_mouse_pressed());
    RET(c, 1, 0);
}

static void cmd_get_mouse_button_press(CPU *c) {
    uint32_t saved_esp = REG(c, R_ESP);
    uint32_t scratch = (saved_esp - 16u) & ~15u;
    P32(scratch, 0u);
    SETREG(c, R_ESP, scratch);
    uint32_t out_ptrs[1] = {scratch};
    int ok = extract_args(c, saved_esp, 1, out_ptrs);
    int32_t nth = (int32_t)G32(scratch);
    SETREG(c, R_ESP, saved_esp);
    if (!ok) {
        RET(c, 0, 0);
        return;
    }
    set_result_double(ARG(c, 6), (double)nth_mouse_pressed(nth));
    RET(c, 1, 0);
}

static void eval_get_mouse_button_press(CPU *c) {
    set_result_double(ARG(c, 3), (double)nth_mouse_pressed((int32_t)ARG(c, 1)));
    RET(c, 1, 0);
}

static void handle_key_disable(CPU *c, int disable) {
    uint32_t saved_esp = REG(c, R_ESP);
    uint32_t scratch = (saved_esp - 16u) & ~15u;
    P32(scratch, 0xffffffffu);
    SETREG(c, R_ESP, scratch);
    uint32_t out_ptrs[1] = {scratch};
    int ok = extract_args(c, saved_esp, 1, out_ptrs);
    int32_t key = (int32_t)G32(scratch);
    SETREG(c, R_ESP, saved_esp);
    if (!ok) { RET(c, 0, 0); return; }
    if (key >= 0 && key < 264) {
        g_disabled_keys[key] = disable ? 1 : 0;
        sync_scancode_disabled(key);
    }
    set_result_double(ARG(c, 6), 0.0);
    RET(c, 1, 0);
}

static void cmd_disable_key(CPU *c) { handle_key_disable(c, 1); }
static void cmd_enable_key(CPU *c) { handle_key_disable(c, 0); }

static void cmd_is_key_disabled(CPU *c) {
    uint32_t saved_esp = REG(c, R_ESP);
    uint32_t scratch = (saved_esp - 16u) & ~15u;
    P32(scratch, 0xffffffffu);
    SETREG(c, R_ESP, scratch);
    uint32_t out_ptrs[1] = {scratch};
    int ok = extract_args(c, saved_esp, 1, out_ptrs);
    int32_t key = (int32_t)G32(scratch);
    SETREG(c, R_ESP, saved_esp);
    if (!ok) { RET(c, 0, 0); return; }
    set_result_double(ARG(c, 6), input_is_scancode_disabled(key) ? 1.0 : 0.0);
    RET(c, 1, 0);
}

static void eval_is_key_disabled(CPU *c) {
    set_result_double(ARG(c, 3), input_is_scancode_disabled((int32_t)ARG(c, 1)) ? 1.0 : 0.0);
    RET(c, 1, 0);
}

static void cmd_get_control(CPU *c) {
    uint32_t saved_esp = REG(c, R_ESP);
    uint32_t scratch = (saved_esp - 16u) & ~15u;
    P32(scratch, 0xffffffffu);
    P32(scratch + 4u, 0u);
    SETREG(c, R_ESP, scratch);
    uint32_t out_ptrs[2] = {scratch, scratch + 4u};
    int ok = extract_args(c, saved_esp, 2, out_ptrs);
    int32_t ctrl = (int32_t)G32(scratch);
    int32_t ctrl_type = (int32_t)G32(scratch + 4u);
    SETREG(c, R_ESP, saved_esp);
    if (!ok) { RET(c, 0, 0); return; }
    set_result_double(ARG(c, 6), (double)get_control_bind(ctrl, ctrl_type));
    RET(c, 1, 0);
}

static void eval_get_control(CPU *c) {
    set_result_double(ARG(c, 3), (double)get_control_bind((int32_t)ARG(c, 1), (int32_t)ARG(c, 2)));
    RET(c, 1, 0);
}

static void cmd_get_alt_control(CPU *c) {
    uint32_t saved_esp = REG(c, R_ESP);
    uint32_t scratch = (saved_esp - 16u) & ~15u;
    P32(scratch, 0xffffffffu);
    SETREG(c, R_ESP, scratch);
    uint32_t out_ptrs[1] = {scratch};
    int ok = extract_args(c, saved_esp, 1, out_ptrs);
    int32_t ctrl = (int32_t)G32(scratch);
    SETREG(c, R_ESP, saved_esp);
    if (!ok) { RET(c, 0, 0); return; }
    set_result_double(ARG(c, 6), (double)get_control_bind(ctrl, 1));
    RET(c, 1, 0);
}

static void eval_get_alt_control(CPU *c) {
    set_result_double(ARG(c, 3), (double)get_control_bind((int32_t)ARG(c, 1), 1));
    RET(c, 1, 0);
}

static void handle_control_disable(CPU *c, int disable) {
    uint32_t saved_esp = REG(c, R_ESP);
    uint32_t scratch = (saved_esp - 16u) & ~15u;
    P32(scratch, 0xffffffffu);
    SETREG(c, R_ESP, scratch);
    uint32_t out_ptrs[1] = {scratch};
    int ok = extract_args(c, saved_esp, 1, out_ptrs);
    int32_t ctrl = (int32_t)G32(scratch);
    SETREG(c, R_ESP, saved_esp);
    if (!ok) { RET(c, 0, 0); return; }
    if (ctrl >= 0 && ctrl < FNV_NUM_CONTROLS) {
        g_disabled_controls[ctrl] = disable ? 1 : 0;
        int32_t kb = get_control_bind(ctrl, 0);
        int32_t mb = get_control_bind(ctrl, 1);
        if (kb >= 0) sync_scancode_disabled(kb);
        if (mb >= 256) sync_scancode_disabled(mb);
    }
    set_result_double(ARG(c, 6), 0.0);
    RET(c, 1, 0);
}

static void cmd_disable_control(CPU *c) { handle_control_disable(c, 1); }
static void cmd_enable_control(CPU *c) { handle_control_disable(c, 0); }

static void cmd_is_control_disabled(CPU *c) {
    uint32_t saved_esp = REG(c, R_ESP);
    uint32_t scratch = (saved_esp - 16u) & ~15u;
    P32(scratch, 0xffffffffu);
    SETREG(c, R_ESP, scratch);
    uint32_t out_ptrs[1] = {scratch};
    int ok = extract_args(c, saved_esp, 1, out_ptrs);
    int32_t ctrl = (int32_t)G32(scratch);
    SETREG(c, R_ESP, saved_esp);
    if (!ok) { RET(c, 0, 0); return; }
    double r = (ctrl >= 0 && ctrl < FNV_NUM_CONTROLS && g_disabled_controls[ctrl]) ? 1.0 : 0.0;
    set_result_double(ARG(c, 6), r);
    RET(c, 1, 0);
}

static void eval_is_control_disabled(CPU *c) {
    int32_t ctrl = (int32_t)ARG(c, 1);
    double r = (ctrl >= 0 && ctrl < FNV_NUM_CONTROLS && g_disabled_controls[ctrl]) ? 1.0 : 0.0;
    set_result_double(ARG(c, 3), r);
    RET(c, 1, 0);
}

static void cmd_tap_control(CPU *c) {
    uint32_t saved_esp = REG(c, R_ESP);
    uint32_t scratch = (saved_esp - 16u) & ~15u;
    P32(scratch, 0xffffffffu);
    SETREG(c, R_ESP, scratch);
    uint32_t out_ptrs[1] = {scratch};
    int ok = extract_args(c, saved_esp, 1, out_ptrs);
    int32_t ctrl = (int32_t)G32(scratch);
    SETREG(c, R_ESP, saved_esp);
    if (!ok) { RET(c, 0, 0); return; }
    int32_t kb = get_control_bind(ctrl, 0);
    int32_t mb = get_control_bind(ctrl, 1);
    if (kb > 0) input_script_tap_scancode(kb);
    else if (mb >= 256) input_script_tap_scancode(mb);
    set_result_double(ARG(c, 6), 0.0);
    RET(c, 1, 0);
}

static void cmd_set_control(CPU *c) {
    uint32_t saved_esp = REG(c, R_ESP);
    uint32_t scratch = (saved_esp - 16u) & ~15u;
    P32(scratch, 0xffffffffu);
    P32(scratch + 4u, 0xffffffffu);
    P32(scratch + 8u, 0u);
    SETREG(c, R_ESP, scratch);
    uint32_t out_ptrs[3] = {scratch, scratch + 4u, scratch + 8u};
    int ok = extract_args(c, saved_esp, 3, out_ptrs);
    int32_t ctrl = (int32_t)G32(scratch);
    int32_t key = (int32_t)G32(scratch + 4u);
    int32_t ctrl_type = (int32_t)G32(scratch + 8u);
    SETREG(c, R_ESP, saved_esp);
    if (!ok) { RET(c, 0, 0); return; }
    set_control_bind(ctrl, key, ctrl_type);
    set_result_double(ARG(c, 6), 0.0);
    RET(c, 1, 0);
}

static void cmd_set_alt_control(CPU *c) {
    uint32_t saved_esp = REG(c, R_ESP);
    uint32_t scratch = (saved_esp - 16u) & ~15u;
    P32(scratch, 0xffffffffu);
    P32(scratch + 4u, 0xffffffffu);
    SETREG(c, R_ESP, scratch);
    uint32_t out_ptrs[2] = {scratch, scratch + 4u};
    int ok = extract_args(c, saved_esp, 2, out_ptrs);
    int32_t ctrl = (int32_t)G32(scratch);
    int32_t key = (int32_t)G32(scratch + 4u);
    SETREG(c, R_ESP, saved_esp);
    if (!ok) { RET(c, 0, 0); return; }
    set_control_bind(ctrl, key, 1);
    set_result_double(ARG(c, 6), 0.0);
    RET(c, 1, 0);
}

static void cmd_is_control(CPU *c) {
    uint32_t saved_esp = REG(c, R_ESP);
    uint32_t scratch = (saved_esp - 16u) & ~15u;
    P32(scratch, 0xffffffffu);
    SETREG(c, R_ESP, scratch);
    uint32_t out_ptrs[1] = {scratch};
    int ok = extract_args(c, saved_esp, 1, out_ptrs);
    int32_t key = (int32_t)G32(scratch);
    SETREG(c, R_ESP, saved_esp);
    if (!ok) { RET(c, 0, 0); return; }
    set_result_double(ARG(c, 6), is_scancode_a_control(key) ? 1.0 : 0.0);
    RET(c, 1, 0);
}

static void eval_is_control(CPU *c) {
    set_result_double(ARG(c, 3), is_scancode_a_control((int32_t)ARG(c, 1)) ? 1.0 : 0.0);
    RET(c, 1, 0);
}

static int query_control_pressed(int32_t ctrl) {
    int32_t kb = get_control_bind(ctrl, 0);
    if (kb >= 0 && query_scancode_down(kb)) return 1;
    int32_t mb = get_control_bind(ctrl, 1);
    if (mb >= 256 && query_scancode_down(mb)) return 1;
    return 0;
}

static void cmd_is_control_pressed(CPU *c) {
    uint32_t saved_esp = REG(c, R_ESP);
    uint32_t scratch = (saved_esp - 16u) & ~15u;
    P32(scratch, 0xffffffffu);
    SETREG(c, R_ESP, scratch);
    uint32_t out_ptrs[1] = {scratch};
    int ok = extract_args(c, saved_esp, 1, out_ptrs);
    int32_t ctrl = (int32_t)G32(scratch);
    SETREG(c, R_ESP, saved_esp);
    if (!ok) { RET(c, 0, 0); return; }
    set_result_double(ARG(c, 6), query_control_pressed(ctrl) ? 1.0 : 0.0);
    RET(c, 1, 0);
}

static void eval_is_control_pressed(CPU *c) {
    set_result_double(ARG(c, 3), query_control_pressed((int32_t)ARG(c, 1)) ? 1.0 : 0.0);
    RET(c, 1, 0);
}

static uint32_t lookup_ini_setting(CPU *c, uint32_t name_guest_addr) {
    if (!g_setting_lookup_fn || !name_guest_addr) return 0u;
    uint32_t s = 0u;
    if (g_ini_get_fn) {
        uint32_t col = guest_call_cdecl(c, g_ini_get_fn, 0, NULL);
        if (col) s = guest_call_thiscall(c, g_setting_lookup_fn, col, 1, &name_guest_addr);
    }
    if (!s && g_ini_pref_get_fn) {
        uint32_t col = guest_call_cdecl(c, g_ini_pref_get_fn, 0, NULL);
        if (col) s = guest_call_thiscall(c, g_setting_lookup_fn, col, 1, &name_guest_addr);
    }
    return s;
}

static char setting_type_char(uint32_t setting, uint32_t fallback_name_addr) {
    uint32_t np = G32(setting + 0x08u);
    if (np) return (char)MEM[np];
    return fallback_name_addr ? (char)MEM[fallback_name_addr] : '\0';
}

static void cmd_get_numeric_ini_setting(CPU *c) {
    enum { STR_BUF_SZ = 512 };
    uint32_t saved_esp = REG(c, R_ESP);
    uint32_t scratch = (saved_esp - STR_BUF_SZ) & ~15u;
    memset(MEM + scratch, 0, STR_BUF_SZ);
    SETREG(c, R_ESP, scratch);
    uint32_t out_ptrs[1] = {scratch};
    int ok = extract_args(c, saved_esp, 1, out_ptrs);
    double out_val = -1.0;
    if (ok) {
        uint32_t s = lookup_ini_setting(c, scratch);
        if (s) {
            char tc = setting_type_char(s, scratch);
            if (tc == 'f' || tc == 'F') {
                float fv = 0.0f;
                memcpy(&fv, MEM + s + 4u, 4);
                out_val = (double)fv;
            } else if (tc == 'i' || tc == 'I') {
                out_val = (double)(int32_t)G32(s + 4u);
            } else if (tc == 'u' || tc == 'U') {
                out_val = (double)G32(s + 4u);
            } else if (tc == 'b' || tc == 'B') {
                out_val = MEM[s + 4u] ? 1.0 : 0.0;
            } else if (tc == 'c' || tc == 'C') {
                out_val = (double)(int8_t)MEM[s + 4u];
            } else if (tc == 'h' || tc == 'H') {
                out_val = (double)MEM[s + 4u];
            }
        }
    }
    SETREG(c, R_ESP, saved_esp);
    if (!ok) { RET(c, 0, 0); return; }
    set_result_double(ARG(c, 6), out_val);
    RET(c, 1, 0);
}

static void cmd_set_numeric_ini_setting(CPU *c) {
    enum { STR_BUF_SZ = 512, TOTAL_SCRATCH = 512 + 16 };
    uint32_t saved_esp = REG(c, R_ESP);
    uint32_t scratch = (saved_esp - TOTAL_SCRATCH) & ~15u;
    uint32_t str_addr = scratch;
    uint32_t val_addr = scratch + STR_BUF_SZ;
    memset(MEM + scratch, 0, TOTAL_SCRATCH);
    SETREG(c, R_ESP, scratch);
    uint32_t out_ptrs[2] = {str_addr, val_addr};
    int ok = extract_args(c, saved_esp, 2, out_ptrs);
    double updated = 0.0;
    if (ok) {
        float new_val = 0.0f;
        memcpy(&new_val, MEM + val_addr, 4);
        uint32_t s = lookup_ini_setting(c, str_addr);
        if (s) {
            char tc = setting_type_char(s, str_addr);
            if (tc == 'f' || tc == 'F') {
                memcpy(MEM + s + 4u, &new_val, 4);
                updated = 1.0;
            } else if (tc == 'i' || tc == 'I') {
                P32(s + 4u, (uint32_t)(int32_t)new_val);
                updated = 1.0;
            } else if (tc == 'u' || tc == 'U') {
                P32(s + 4u, (uint32_t)new_val);
                updated = 1.0;
            } else if (tc == 'b' || tc == 'B') {
                MEM[s + 4u] = (new_val != 0.0f) ? 1 : 0;
                updated = 1.0;
            } else if (tc == 'c' || tc == 'C') {
                MEM[s + 4u] = (uint8_t)(int8_t)new_val;
                updated = 1.0;
            } else if (tc == 'h' || tc == 'H') {
                MEM[s + 4u] = (uint8_t)new_val;
                updated = 1.0;
            }
        }
    }
    SETREG(c, R_ESP, saved_esp);
    if (!ok) { RET(c, 0, 0); return; }
    set_result_double(ARG(c, 6), updated);
    RET(c, 1, 0);
}

static void format_printc_safe(char *out, size_t out_sz, const char *fmt, const float *vals, int nvals) {
    size_t pos = 0;
    int arg_i = 0;
    for (const char *p = fmt; *p && pos + 1 < out_sz; p++) {
        if (*p != '%') {
            out[pos++] = *p;
            continue;
        }
        const char *spec_start = p++;
        if (*p == '%') {
            out[pos++] = '%';
            continue;
        }
        while (*p && strchr("-+ #0", *p)) p++;
        while (*p && isdigit((unsigned char)*p)) p++;
        if (*p == '.') {
            p++;
            while (*p && isdigit((unsigned char)*p)) p++;
        }
        char conv = *p;
        if (!conv) break;
        if ((size_t)(p - spec_start) > 16) {
            out[pos++] = '%';
            p = spec_start;
            continue;
        }
        char subfmt[24];
        size_t slen = (size_t)(p - spec_start + 1);
        memcpy(subfmt, spec_start, slen);
        subfmt[slen] = '\0';

        float fv = (arg_i < nvals) ? vals[arg_i] : 0.0f;
        int n = 0;
        if (conv == 'f' || conv == 'F' || conv == 'g' || conv == 'G' || conv == 'e' || conv == 'E') {
            arg_i++;
            n = snprintf(out + pos, out_sz - pos, subfmt, (double)fv);
        } else if (conv == 'd' || conv == 'i') {
            arg_i++;
            n = snprintf(out + pos, out_sz - pos, subfmt, (int32_t)fv);
        } else if (conv == 'u' || conv == 'x' || conv == 'X' || conv == 'o') {
            arg_i++;
            n = snprintf(out + pos, out_sz - pos, subfmt, (uint32_t)(int64_t)fv);
        } else if (conv == 'c') {
            arg_i++;
            n = snprintf(out + pos, out_sz - pos, subfmt, (int)(unsigned char)(int32_t)fv);
        } else {
            // Avoid interpreting untrusted %s/%n/%p against host/guest pointers.
            n = snprintf(out + pos, out_sz - pos, "%s", subfmt);
        }
        if (n > 0) {
            size_t add = (size_t)n;
            pos = (pos + add < out_sz) ? (pos + add) : (out_sz - 1);
        }
    }
    out[pos] = '\0';
}

static void cmd_print_to_console(CPU *c) {
    enum { STR_BUF_SZ = 512, NUM_FLOATS = 9, TOTAL_SCRATCH = 512 + 4 * 9 + 16 };
    uint32_t saved_esp = REG(c, R_ESP);
    uint32_t scratch = (saved_esp - TOTAL_SCRATCH) & ~15u;
    uint32_t str_addr = scratch;
    uint32_t flt_base = scratch + STR_BUF_SZ;
    uint32_t fmt_pc_addr = flt_base + 4u * NUM_FLOATS;
    memset(MEM + scratch, 0, TOTAL_SCRATCH);
    SETREG(c, R_ESP, scratch);

    uint32_t out_ptrs[10];
    out_ptrs[0] = str_addr;
    for (int i = 0; i < NUM_FLOATS; i++) {
        out_ptrs[1 + i] = flt_base + 4u * (uint32_t)i;
    }
    int ok = extract_args(c, saved_esp, 10, out_ptrs);
    if (ok) {
        char fmt[STR_BUF_SZ];
        memcpy(fmt, MEM + str_addr, STR_BUF_SZ);
        fmt[STR_BUF_SZ - 1] = '\0';
        float vals[NUM_FLOATS];
        memcpy(vals, MEM + flt_base, sizeof vals);
        char formatted[STR_BUF_SZ];
        format_printc_safe(formatted, sizeof formatted, fmt, vals, NUM_FLOATS);
        if (getenv("FNV_TRACE_SCRIPT")) {
            fprintf(stderr, "[nvse-lite:PrintC] %s\n", formatted);
        }
        if (g_console_print_fn) {
            memcpy(MEM + str_addr, formatted, sizeof formatted);
            memcpy(MEM + fmt_pc_addr, "%s", 3);
            uint32_t pargs[2] = {fmt_pc_addr, str_addr};
            guest_call_cdecl(c, g_console_print_fn, 2, pargs);
        }
    }
    SETREG(c, R_ESP, saved_esp);
    if (!ok) {
        RET(c, 0, 0);
        return;
    }
    set_result_double(ARG(c, 6), 0.0);
    RET(c, 1, 0);
}

static void cmd_build_ref(CPU *c) {
    uint32_t saved_esp = REG(c, R_ESP);
    uint32_t scratch = (saved_esp - 16u) & ~15u;
    P32(scratch, 0u);
    P32(scratch + 4u, 0u);
    SETREG(c, R_ESP, scratch);
    uint32_t out_ptrs[2] = {scratch, scratch + 4u};
    int ok = extract_args(c, saved_esp, 2, out_ptrs);
    uint32_t mod_idx = G32(scratch);
    uint32_t base_id = G32(scratch + 4u);
    SETREG(c, R_ESP, saved_esp);
    if (!ok) {
        RET(c, 0, 0);
        return;
    }
    uint32_t fid = ((mod_idx & 0xFFu) << 24) | (base_id & 0x00FFFFFFu);
    uint32_t form = (g_lookup_form_fn && fid) ? guest_call_cdecl(c, g_lookup_form_fn, 1, &fid) : 0u;
    set_result_formid(ARG(c, 6), form ? fid : 0u);
    RET(c, 1, 0);
}

// ---- command registration helpers ----------------------------------------------------------

static void write_cmd_entry(uint32_t table_base,
                            uint32_t opcode,
                            const char *long_name,
                            const char *short_name,
                            const char *help_text,
                            uint16_t needs_parent,
                            uint16_t num_params,
                            const NativeParamDesc *params,
                            uint32_t execute_fn,
                            uint32_t parse_fn,
                            uint32_t eval_fn,
                            uint32_t flags) {
    uint32_t idx = opcode - FNV_OPCODE_BASE;
    uint32_t slot = table_base + idx * CMD_SIZE;
    uint32_t params_addr = 0u;
    if (num_params > 0 && params) {
        params_addr = gmalloc((uint32_t)num_params * PARAM_SIZE);
        for (uint16_t i = 0; i < num_params; i++) {
            uint32_t p = params_addr + (uint32_t)i * PARAM_SIZE;
            P32(p + 0u, guest_strdup(params[i].type_str));
            P32(p + 4u, params[i].type_id);
            P32(p + 8u, params[i].is_optional);
        }
    }
    P32(slot + 0x00u, guest_strdup(long_name));
    P32(slot + 0x04u, guest_strdup(short_name));
    P32(slot + 0x08u, opcode);
    P32(slot + 0x0cu, guest_strdup(help_text));
    write_u16(slot + 0x10u, needs_parent);
    write_u16(slot + 0x12u, num_params);
    P32(slot + 0x14u, params_addr);
    P32(slot + 0x18u, execute_fn);
    P32(slot + 0x1cu, parse_fn);
    P32(slot + 0x20u, eval_fn);
    P32(slot + 0x24u, flags);
}

static int import_console_command(uint32_t table_base,
                                  uint32_t opcode,
                                  uint32_t vanilla_console_base,
                                  uint32_t console_count,
                                  const char *name) {
    if (!vanilla_console_base) return 0;
    for (uint32_t i = 0; i < console_count; i++) {
        uint32_t src = vanilla_console_base + i * CMD_SIZE;
        uint32_t name_ptr = G32(src + 0x00u);
        if (name_ptr && strcasecmp(GSTR(name_ptr), name) == 0) {
            uint32_t dst = table_base + (opcode - FNV_OPCODE_BASE) * CMD_SIZE;
            memcpy(MEM + dst, MEM + src, CMD_SIZE);
            P32(dst + 0x08u, opcode);
            return 1;
        }
    }
    return 0;
}

void script_ext_init_table(uint32_t vanilla_script_base,
                           uint32_t vanilla_console_base,
                           uint32_t console_count,
                           uint32_t parse_fn,
                           uint32_t extract_fn,
                           uint32_t console_print_fn,
                           uint32_t lookup_form_fn) {
    const char *env = getenv("FNV_SCRIPT_EXT");
    if (!env || !env[0] || strcmp(env, "0") == 0) {
        return;
    }

    g_extract_fn = extract_fn;
    g_console_print_fn = console_print_fn;
    g_lookup_form_fn = lookup_form_fn;
    memset(g_disabled_keys, 0, sizeof g_disabled_keys);
    memset(g_disabled_controls, 0, sizeof g_disabled_controls);
    input_script_reset_overrides();
    g_empty_str = gmalloc(4);
    MEM[g_empty_str] = '\0';

    uint32_t ext_table = gmalloc(EXT_TABLE_COUNT * CMD_SIZE);
    memset(MEM + ext_table, 0, EXT_TABLE_COUNT * CMD_SIZE);

    // 1. Copy vanilla ScriptCommands (0x1000..0x127F) intact.
    memcpy(MEM + ext_table, MEM + vanilla_script_base, FNV_VANILLA_SCRIPT_COUNT * CMD_SIZE);

    // 2. Pad gap 0x1280..0x13FF so direct indexing remains valid.
    for (uint32_t op = 0x1280u; op < 0x1400u; op++) {
        write_cmd_entry(ext_table, op, "", "", "", 0, 0, NULL, 0u, parse_fn, 0u, 0u);
    }

    // 3. Populate 0x1400..0x1FFF with safe unimplemented sentinel by default.
    uint32_t unimpl_exec = script_thunk_alloc("nvse_unimplemented", cmd_unimplemented);
    for (uint32_t op = 0x1400u; op < 0x1000u + EXT_TABLE_COUNT; op++) {
        write_cmd_entry(ext_table, op, "", "", "", 0, 0, NULL, unimpl_exec, parse_fn, 0u, 0u);
    }

    // 4. Register clean-room MVP NVSE commands at standard opcodes.
    uint32_t registered = 0;

    write_cmd_entry(ext_table, 0x1400u, "GetNVSEVersion", "", "returns the installed version of NVSE",
                    0, 0, NULL,
                    script_thunk_alloc("GetNVSEVersion", cmd_get_nvse_version),
                    parse_fn,
                    script_thunk_alloc("Eval_GetNVSEVersion", eval_get_nvse_version), 0u);
    registered++;

    write_cmd_entry(ext_table, 0x1401u, "GetNVSERevision", "", "returns the minor revision of NVSE",
                    0, 0, NULL,
                    script_thunk_alloc("GetNVSERevision", cmd_get_nvse_revision),
                    parse_fn,
                    script_thunk_alloc("Eval_GetNVSERevision", eval_get_nvse_revision), 0u);
    registered++;

    write_cmd_entry(ext_table, 0x1402u, "GetNVSEBeta", "", "returns the beta version of NVSE",
                    0, 0, NULL,
                    script_thunk_alloc("GetNVSEBeta", cmd_get_nvse_beta),
                    parse_fn,
                    script_thunk_alloc("Eval_GetNVSEBeta", eval_get_nvse_beta), 0u);
    registered++;

    write_cmd_entry(ext_table, 0x1403u, "GetBaseObject", "gbo", "returns the base form of a reference",
                    1, 0, NULL,
                    script_thunk_alloc("GetBaseObject", cmd_get_base_object),
                    parse_fn, 0u, 0u);
    registered++;

    static const NativeParamDesc p_opt_form[1] = {{"form", PARAM_INVENTORY_OBJ, 1}};
    write_cmd_entry(ext_table, 0x140Au, "GetType", "", "returns the form type ID of an object",
                    0, 1, p_opt_form,
                    script_thunk_alloc("GetType", cmd_get_type),
                    parse_fn,
                    script_thunk_alloc("Eval_GetType", eval_get_type), 0u);
    registered++;

    // 0x1435..0x143E: standard console commands imported into script table
    static const char *const imported_console_cmds[10] = {
        "SetGameSetting", "SetINISetting", "GetINISetting", "RefreshINI", "Save",
        "SaveINI", "QuitGame", "LoadGame", "CloseAllMenus", "SetVel",
    };
    for (uint32_t i = 0; i < 10u; i++) {
        if (import_console_command(ext_table, 0x1435u + i, vanilla_console_base, console_count,
                                   imported_console_cmds[i])) {
            registered++;
        }
    }

    static const NativeParamDesc p_is_key_pressed[2] = {
        {"key", PARAM_INT, 0},
        {"includeDisabled", PARAM_INT, 1},
    };
    write_cmd_entry(ext_table, 0x1453u, "IsKeyPressed", "", "returns 1 if key scancode is pressed",
                    0, 2, p_is_key_pressed,
                    script_thunk_alloc("IsKeyPressed", cmd_is_key_pressed),
                    parse_fn,
                    script_thunk_alloc("Eval_IsKeyPressed", eval_is_key_pressed), 0u);
    registered++;

    static const NativeParamDesc p_one_key[1] = {{"key", PARAM_INT, 0}};
    write_cmd_entry(ext_table, 0x1454u, "TapKey", "", "taps a DirectInput key scancode",
                    0, 1, p_one_key, script_thunk_alloc("TapKey", cmd_tap_key), parse_fn, 0u, 0u);
    registered++;
    write_cmd_entry(ext_table, 0x1455u, "HoldKey", "", "holds a DirectInput key scancode",
                    0, 1, p_one_key, script_thunk_alloc("HoldKey", cmd_hold_key), parse_fn, 0u, 0u);
    registered++;
    write_cmd_entry(ext_table, 0x1456u, "ReleaseKey", "", "releases a DirectInput key scancode",
                    0, 1, p_one_key, script_thunk_alloc("ReleaseKey", cmd_release_key), parse_fn, 0u, 0u);
    registered++;

    write_cmd_entry(ext_table, 0x1459u, "GetNumKeysPressed", "gnkp", "returns number of keys currently held",
                    0, 0, NULL,
                    script_thunk_alloc("GetNumKeysPressed", cmd_get_num_keys_pressed),
                    parse_fn,
                    script_thunk_alloc("Eval_GetNumKeysPressed", eval_get_num_keys_pressed), 0u);
    registered++;

    static const NativeParamDesc p_nth[1] = {{"which", PARAM_INT, 0}};
    write_cmd_entry(ext_table, 0x145Au, "GetKeyPress", "gkp", "returns the nth pressed key scancode",
                    0, 1, p_nth,
                    script_thunk_alloc("GetKeyPress", cmd_get_key_press),
                    parse_fn,
                    script_thunk_alloc("Eval_GetKeyPress", eval_get_key_press), 0u);
    registered++;

    write_cmd_entry(ext_table, 0x145Bu, "GetNumMouseButtonsPressed", "gnmbp",
                    "returns number of mouse buttons currently held",
                    0, 0, NULL,
                    script_thunk_alloc("GetNumMouseButtonsPressed", cmd_get_num_mouse_buttons_pressed),
                    parse_fn,
                    script_thunk_alloc("Eval_GetNumMouseButtonsPressed", eval_get_num_mouse_buttons_pressed), 0u);
    registered++;

    write_cmd_entry(ext_table, 0x145Cu, "GetMouseButtonPress", "gmbp",
                    "returns the nth pressed mouse button scancode",
                    0, 1, p_nth,
                    script_thunk_alloc("GetMouseButtonPress", cmd_get_mouse_button_press),
                    parse_fn,
                    script_thunk_alloc("Eval_GetMouseButtonPress", eval_get_mouse_button_press), 0u);
    registered++;

    write_cmd_entry(ext_table, 0x1457u, "DisableKey", "", "prevents a key from registering input",
                    0, 1, p_one_key, script_thunk_alloc("DisableKey", cmd_disable_key), parse_fn, 0u, 0u);
    registered++;
    write_cmd_entry(ext_table, 0x1458u, "EnableKey", "", "re-enables a disabled key",
                    0, 1, p_one_key, script_thunk_alloc("EnableKey", cmd_enable_key), parse_fn, 0u, 0u);
    registered++;

    static const NativeParamDesc p_get_ctrl[2] = {
        {"control", PARAM_INT, 0},
        {"type", PARAM_INT, 1},
    };
    write_cmd_entry(ext_table, 0x145Du, "GetControl", "", "returns the scancode bound to a control",
                    0, 2, p_get_ctrl,
                    script_thunk_alloc("GetControl", cmd_get_control),
                    parse_fn,
                    script_thunk_alloc("Eval_GetControl", eval_get_control), 0u);
    registered++;

    static const NativeParamDesc p_one_ctrl[1] = {{"control", PARAM_INT, 0}};
    write_cmd_entry(ext_table, 0x145Eu, "GetAltControl", "", "returns the mouse button bound to a control",
                    0, 1, p_one_ctrl,
                    script_thunk_alloc("GetAltControl", cmd_get_alt_control),
                    parse_fn,
                    script_thunk_alloc("Eval_GetAltControl", eval_get_alt_control), 0u);
    registered++;

    write_cmd_entry(ext_table, 0x1462u, "DisableControl", "", "disables a game control",
                    0, 1, p_one_ctrl, script_thunk_alloc("DisableControl", cmd_disable_control), parse_fn, 0u, 0u);
    registered++;
    write_cmd_entry(ext_table, 0x1463u, "EnableControl", "", "enables a game control",
                    0, 1, p_one_ctrl, script_thunk_alloc("EnableControl", cmd_enable_control), parse_fn, 0u, 0u);
    registered++;
    write_cmd_entry(ext_table, 0x1464u, "TapControl", "", "taps the key bound to a game control",
                    0, 1, p_one_ctrl, script_thunk_alloc("TapControl", cmd_tap_control), parse_fn, 0u, 0u);
    registered++;

    static const NativeParamDesc p_set_ctrl[3] = {
        {"control", PARAM_INT, 0},
        {"key", PARAM_INT, 0},
        {"type", PARAM_INT, 1},
    };
    write_cmd_entry(ext_table, 0x1465u, "SetControl", "", "assigns a scancode to a control",
                    0, 3, p_set_ctrl, script_thunk_alloc("SetControl", cmd_set_control), parse_fn, 0u, 0u);
    registered++;

    static const NativeParamDesc p_set_alt_ctrl[2] = {
        {"control", PARAM_INT, 0},
        {"key", PARAM_INT, 0},
    };
    write_cmd_entry(ext_table, 0x1466u, "SetAltControl", "", "assigns a mouse button to a control",
                    0, 2, p_set_alt_ctrl, script_thunk_alloc("SetAltControl", cmd_set_alt_control), parse_fn, 0u, 0u);
    registered++;

    write_cmd_entry(ext_table, 0x1468u, "IsControl", "", "returns 1 if scancode is bound to any control",
                    0, 1, p_one_key,
                    script_thunk_alloc("IsControl", cmd_is_control),
                    parse_fn,
                    script_thunk_alloc("Eval_IsControl", eval_is_control), 0u);
    registered++;

    write_cmd_entry(ext_table, 0x1469u, "IsKeyDisabled", "", "returns 1 if key scancode is disabled",
                    0, 1, p_one_key,
                    script_thunk_alloc("IsKeyDisabled", cmd_is_key_disabled),
                    parse_fn,
                    script_thunk_alloc("Eval_IsKeyDisabled", eval_is_key_disabled), 0u);
    registered++;

    write_cmd_entry(ext_table, 0x146Au, "IsControlDisabled", "", "returns 1 if control is disabled",
                    0, 1, p_one_ctrl,
                    script_thunk_alloc("IsControlDisabled", cmd_is_control_disabled),
                    parse_fn,
                    script_thunk_alloc("Eval_IsControlDisabled", eval_is_control_disabled), 0u);
    registered++;

    write_cmd_entry(ext_table, 0x146Bu, "IsControlPressed", "", "returns 1 if control key is pressed",
                    0, 1, p_one_ctrl,
                    script_thunk_alloc("IsControlPressed", cmd_is_control_pressed),
                    parse_fn,
                    script_thunk_alloc("Eval_IsControlPressed", eval_is_control_pressed), 0u);
    registered++;

    static const NativeParamDesc p_get_ini[1] = {{"setting", PARAM_STRING, 0}};
    write_cmd_entry(ext_table, 0x149Cu, "GetNumericIniSetting", "", "returns numeric INI setting value",
                    0, 1, p_get_ini,
                    script_thunk_alloc("GetNumericIniSetting", cmd_get_numeric_ini_setting),
                    parse_fn, 0u, 0u);
    registered++;

    static const NativeParamDesc p_set_ini[2] = {
        {"setting", PARAM_STRING, 0},
        {"value", PARAM_FLOAT, 0},
    };
    write_cmd_entry(ext_table, 0x149Du, "SetNumericIniSetting", "", "sets numeric INI setting value",
                    0, 2, p_set_ini,
                    script_thunk_alloc("SetNumericIniSetting", cmd_set_numeric_ini_setting),
                    parse_fn, 0u, 0u);
    registered++;

    static const NativeParamDesc p_printc[10] = {
        {"format", PARAM_STRING, 0},
        {"var1", PARAM_FLOAT, 1}, {"var2", PARAM_FLOAT, 1}, {"var3", PARAM_FLOAT, 1},
        {"var4", PARAM_FLOAT, 1}, {"var5", PARAM_FLOAT, 1}, {"var6", PARAM_FLOAT, 1},
        {"var7", PARAM_FLOAT, 1}, {"var8", PARAM_FLOAT, 1}, {"var9", PARAM_FLOAT, 1},
    };
    write_cmd_entry(ext_table, 0x14A0u, "PrintToConsole", "PrintC", "prints a formatted string to console",
                    0, 10, p_printc,
                    script_thunk_alloc("PrintToConsole", cmd_print_to_console),
                    parse_fn, 0u, 0u);
    registered++;

    static const NativeParamDesc p_build_ref[2] = {
        {"modIndex", PARAM_INT, 0},
        {"baseFormID", PARAM_INT, 0},
    };
    write_cmd_entry(ext_table, 0x14D9u, "BuildRef", "", "builds and resolves a FormID from mod index and base ID",
                    0, 2, p_build_ref,
                    script_thunk_alloc("BuildRef", cmd_build_ref),
                    parse_fn, 0u, 0u);
    registered++;

    host_script_cmd_base = ext_table;
    host_script_cmd_count = EXT_TABLE_COUNT;
    host_script_cmd_max_opcode = FNV_OPCODE_BASE + EXT_TABLE_COUNT;

    fprintf(stderr,
            "[nvse-lite] relocated ScriptCommands -> %#x (%u slots, %u native commands registered, version=%.0f.%.0f.%.0f)\n",
            host_script_cmd_base, EXT_TABLE_COUNT, registered,
            env_double("FNV_NVSE_VERSION", 1.0),
            env_double("FNV_NVSE_REVISION", 0.0),
            env_double("FNV_NVSE_BETA", 0.0));
}

void script_ext_init(void) {
#if defined(FNV_SCRIPT_EXT_PATCHED) && !defined(FNV_GAME_SKYRIM) && !defined(FNV_GAME_FALLOUT3)
    script_ext_set_fnv_extras(FNV_INPUT_GLOBALS_PTR,
                              FNV_INI_GET_FN,
                              FNV_INI_PREF_GET_FN,
                              FNV_SETTING_LOOKUP_FN);
    script_ext_init_table(FNV_VANILLA_SCRIPT_BASE,
                          FNV_VANILLA_CONSOLE_BASE,
                          FNV_VANILLA_CONSOLE_COUNT,
                          FNV_DEFAULT_PARSE_FN,
                          FNV_EXTRACT_ARGS_FN,
                          FNV_CONSOLE_PRINT_FN,
                          FNV_LOOKUP_FORM_FN);
#endif
}
