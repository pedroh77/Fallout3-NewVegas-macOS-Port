#!/usr/bin/env python3
"""Build a native macOS arm64 .app bundle with Xcode / Command Line Tools."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import sys
import tempfile
from state_probes import normalize, instrument
import script_ext_patches
from native_codecs import validate as validate_codecs
from app_icon import compile_icon

ROOT = Path(__file__).resolve().parents[1]
R = ROOT / 'upstream/recomp'
H = R / 'host'
M = ROOT / 'macos'


def run(cmd):
    subprocess.run(cmd, check=True)


def run_quiet(cmd):
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if res.returncode != 0:
        if res.stdout:
            sys.stderr.write(res.stdout)
        raise subprocess.CalledProcessError(res.returncode, cmd, output=res.stdout)


class _CompileProgress:
    """TTY-aware progress bar matching quick-install.sh's styling."""

    SPIN = ('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    BAR_WIDTH = 24

    def __init__(self, total, label='Compiling'):
        self.total = total
        self.label = label
        self.fancy = sys.stdout.isatty() and os.environ.get('TERM', 'dumb') != 'dumb'
        self.spin_idx = 0
        self._active = False
        if self.fancy:
            term = os.environ.get('TERM', '')
            use_256 = '256color' in term or os.environ.get('COLORTERM') in ('truecolor', '24bit')
            if use_256:
                self.gold = '\033[38;5;220m'
                self.green = '\033[38;5;84m'
                self.red = '\033[38;5;203m'
                self.cyan = '\033[38;5;51m'
            else:
                self.gold = '\033[93m'
                self.green = '\033[92m'
                self.red = '\033[91m'
                self.cyan = '\033[96m'
            self.dim = '\033[2m'
            self.reset = '\033[0m'
        else:
            self.gold = self.green = self.red = self.cyan = self.dim = self.reset = ''

    def _bar(self, done, width):
        pct = min(100, (done * 100) // self.total) if self.total > 0 else 100
        filled = (pct * width) // 100
        return ('█' * filled) + ('░' * (width - filled)), pct

    def _draw(self, glyph, done, reused, compiled, end=''):
        # Never exceed terminal width: wrapping past the right margin breaks \r in-place updates.
        cols = shutil.get_terminal_size((80, 24)).columns
        max_len = max(cols - 1, 20)
        prefix_len = 2 + 1 + 1 + len(self.label) + 1  # "  <glyph> <label> "
        pct_len = 5  # " 100%"

        full_detail = f'{done}/{self.total} ({reused} cached, {compiled} built)'
        short_detail = f'{done}/{self.total}'
        bar_width = self.BAR_WIDTH

        if prefix_len + bar_width + pct_len + 2 + len(full_detail) <= max_len:
            detail = full_detail
        elif prefix_len + bar_width + pct_len + 2 + len(short_detail) <= max_len:
            detail = short_detail
        else:
            detail = short_detail
            bar_width = max(4, max_len - prefix_len - pct_len - 2 - len(detail))

        bar, pct = self._bar(done, bar_width)
        line = (
            f'\r  {glyph} {self.label} {self.gold}{bar}{self.reset} '
            f'{pct:3d}%  {self.dim}{detail}{self.reset}\033[K{end}'
        )
        sys.stdout.write(line)
        sys.stdout.flush()

    def start(self):
        if self.fancy:
            self._active = True
            sys.stdout.write('\033[?25l')
            self._draw(f'{self.cyan}{self.SPIN[0]}{self.reset}', 0, 0, 0)

    def tick(self, done, reused, compiled):
        if self.fancy:
            self.spin_idx = (self.spin_idx + 1) % len(self.SPIN)
            self._draw(f'{self.cyan}{self.SPIN[self.spin_idx]}{self.reset}', done, reused, compiled)

    def finish(self, done, reused, compiled):
        if self.fancy:
            self._draw(f'{self.green}✔{self.reset}', done, reused, compiled, end='\n')
            sys.stdout.write('\033[?25h')
            sys.stdout.flush()
            self._active = False
        else:
            print(f'macOS objects: {reused} reused, {compiled} compiled', flush=True)

    def fail(self):
        if self.fancy and self._active:
            sys.stdout.write(f'\r  {self.red}✘{self.reset} {self.label} failed\033[K\n\033[?25h')
            sys.stdout.flush()
            self._active = False

    def restore_cursor(self):
        if self.fancy and self._active:
            sys.stdout.write('\033[?25h')
            sys.stdout.flush()
            self._active = False


def patch_generated_tu(content):
    """Apply narrow correctness guards for vanilla TESV.exe bugs in translated C units."""
    # 1. Vanilla TESIdleForm::~TESIdleForm (0x55df80) iterates children[0..size-1] via
    #    NiTArray::GetAt (0x4885e0) and unconditionally dereferences the returned pointer at
    #    0x55e05f without checking for NULL. Slots removed via g_55d920 leave NULL holes when not
    #    at the array tail (e.g. Update/DLC plugin loads), causing Quit to Desktop to trap at 0.
    # 2. Vanilla BSAudioManager shutdown (0xb9bbe0) sends a quit message and waits forever on the
    #    LibAudioUpdate thread's exit semaphore [eax+0x34] without checking if the thread was ever
    #    started ([eax+0x24] != 0, skipped at 0xb9f16b when bit 5 / bEnableAudio=0 is set), unlike
    #    0xb9a7a0 which explicitly checks [eax+0x24]. Skip waiting on an unstarted thread.
    guards = [
        (
            b'L_55e05f: /* MOV dword ptr [EAX + 0x24],0x0 */\n',
            b'  if(!eax){RT_BRANCH(0x55e05fu);goto L_55e070;}\n',
        ),
        (
            b'L_b9bbec: /* JZ 0x00b9bc44 */\n',
            b'  if(eax&&!LDM(eax+0x24u,4)){RT_BRANCH(0xb9bbecu);goto L_b9bc44;}\n',
        ),
    ]
    patched = False
    for label, guard in guards:
        if label in content:
            content = content.replace(label, label + guard, 1)
            patched = True
    return content, patched


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def host_deployment_target():
    ver = platform.mac_ver()[0]
    try:
        major = int(ver.split('.')[0])
    except (ValueError, IndexError):
        return '14.0'
    return f'{max(major, 14)}.0'


def find_unicorn(explicit):
    if explicit:
        return explicit
    for candidate in ['/opt/homebrew/opt/unicorn', '/opt/homebrew', '/usr/local/opt/unicorn', '/usr/local']:
        p = Path(candidate)
        if (p / 'include/unicorn/unicorn.h').is_file() and (p / 'lib/libunicorn.a').is_file():
            return p
    return None


def find_ffmpeg():
    """Find FFmpeg headers and dylibs (libavcodec/libswresample/libavutil) for xWMA decoding."""
    for candidate in ['/opt/homebrew/opt/ffmpeg', '/opt/homebrew', '/opt/local', '/usr/local']:
        p = Path(candidate)
        if (p / 'include/libavcodec/avcodec.h').is_file() and (p / 'lib/libavcodec.dylib').is_file():
            return p
    return None


def _macho_deps_and_rpaths(path):
    """Return (install_id, deps, rpaths) parsed from otool for a Mach-O binary."""
    id_lines = subprocess.check_output(['otool', '-D', str(path)], text=True).splitlines()
    install_id = id_lines[1].strip() if len(id_lines) > 1 else None

    l_lines = subprocess.check_output(['otool', '-L', str(path)], text=True).splitlines()
    deps = []
    skipped_self = False
    for line in l_lines[1:]:
        dep = line.strip().split(' (', 1)[0]
        if not dep:
            continue
        if install_id and not skipped_self and dep == install_id:
            skipped_self = True
            continue
        deps.append(dep)

    cmd_lines = subprocess.check_output(['otool', '-l', str(path)], text=True).splitlines()
    rpaths = []
    for i, line in enumerate(cmd_lines):
        if 'cmd LC_RPATH' in line:
            for j in range(i + 1, min(i + 6, len(cmd_lines))):
                if 'path ' in cmd_lines[j]:
                    rp = cmd_lines[j].split('path ', 1)[1].rsplit(' (offset', 1)[0].strip()
                    if rp not in rpaths:
                        rpaths.append(rp)
                    break
    return install_id, deps, rpaths


def _is_system_dylib(dep):
    return dep.startswith('/usr/lib/') or dep.startswith('/System/')


def _resolve_dylib_path(dep, cur_path, cur_real, exe_path, cur_rpaths, search_dirs):
    """Resolve a non-system Mach-O dependency reference to an existing file on disk."""
    candidates = []
    if dep.startswith('@loader_path/'):
        rel = dep[len('@loader_path/'):]
        candidates.extend([cur_real.parent / rel, cur_path.parent / rel])
    elif dep.startswith('@executable_path/'):
        rel = dep[len('@executable_path/'):]
        candidates.append(exe_path.parent / rel)
    elif dep.startswith('@rpath/'):
        rel = dep[len('@rpath/'):]
        for rp in cur_rpaths:
            if rp == '@loader_path':
                candidates.extend([cur_real.parent / rel, cur_path.parent / rel])
            elif rp.startswith('@loader_path/'):
                sub = rp[len('@loader_path/'):]
                candidates.extend([cur_real.parent / sub / rel, cur_path.parent / sub / rel])
            elif rp == '@executable_path':
                candidates.append(exe_path.parent / rel)
            elif rp.startswith('@executable_path/'):
                sub = rp[len('@executable_path/'):]
                candidates.append(exe_path.parent / sub / rel)
            else:
                candidates.append(Path(rp) / rel)
        for sd in [cur_real.parent, cur_path.parent, *search_dirs]:
            candidates.append(Path(sd) / rel)
    else:
        candidates.append(Path(dep))

    for cand in candidates:
        resolved = Path(os.path.normpath(str(cand)))
        if resolved.exists():
            return Path(os.path.realpath(str(resolved)))
    raise RuntimeError(f'Unresolved dylib dependency {dep!r} needed by {cur_path}')


def bundle_dylibs(exe_path, frameworks_dir, extra_search_dirs=()):
    """Copy non-system dylib closure into Frameworks/ and rewrite load paths cleanly."""
    exe_path = Path(exe_path)
    exe_real = Path(os.path.realpath(str(exe_path)))
    frameworks_dir = Path(frameworks_dir)
    frameworks_dir.mkdir(parents=True, exist_ok=True)
    extra_dirs = [Path(d) for d in extra_search_dirs]

    _, exe_deps, exe_rpaths = _macho_deps_and_rpaths(exe_real)
    base_search_dirs = [*extra_dirs]
    for rp in exe_rpaths:
        if not rp.startswith('@'):
            base_search_dirs.append(Path(rp))

    # Map real_path -> bundled basename, and record non-system dependency mappings per binary.
    by_real = {}
    by_name = {}
    dep_map = {}  # binary_real -> list of (orig_dep_str, target_real)
    rpath_map = {}
    queue = []

    exe_changes = []
    for dep in exe_deps:
        if _is_system_dylib(dep):
            continue
        target_real = _resolve_dylib_path(dep, exe_path, exe_real, exe_path, exe_rpaths, base_search_dirs)
        exe_changes.append((dep, target_real))
        if target_real not in by_real:
            name = target_real.name
            if name in by_name and by_name[name] != target_real:
                raise RuntimeError(f'Dylib basename collision for {name}: {by_name[name]} vs {target_real}')
            by_real[target_real] = name
            by_name[name] = target_real
            queue.append(target_real)
    dep_map[exe_real] = exe_changes

    visited_dylibs = set()
    while queue:
        cur_real = queue.pop(0)
        if cur_real in visited_dylibs:
            continue
        visited_dylibs.add(cur_real)
        _, cur_deps, cur_rpaths = _macho_deps_and_rpaths(cur_real)
        rpath_map[cur_real] = cur_rpaths
        cur_changes = []
        for dep in cur_deps:
            if _is_system_dylib(dep):
                continue
            target_real = _resolve_dylib_path(dep, cur_real, cur_real, exe_path, cur_rpaths, base_search_dirs)
            cur_changes.append((dep, target_real))
            if target_real not in by_real:
                name = target_real.name
                if name in by_name and by_name[name] != target_real:
                    raise RuntimeError(f'Dylib basename collision for {name}: {by_name[name]} vs {target_real}')
                by_real[target_real] = name
                by_name[name] = target_real
                queue.append(target_real)
        dep_map[cur_real] = cur_changes

    if not by_real:
        return []

    bundled = []
    for src_real, bundled_name in sorted(by_real.items(), key=lambda item: item[1]):
        dst = frameworks_dir / bundled_name
        shutil.copy2(src_real, dst)
        os.chmod(dst, 0o755)
        cmd = ['install_name_tool', '-id', f'@rpath/{bundled_name}']
        seen_changes = set()
        for orig_dep, target_real in dep_map.get(src_real, []):
            new_ref = f'@loader_path/{by_real[target_real]}'
            if orig_dep != new_ref and (orig_dep, new_ref) not in seen_changes:
                cmd.extend(['-change', orig_dep, new_ref])
                seen_changes.add((orig_dep, new_ref))
        run_quiet(cmd + [str(dst)])
        for rp in rpath_map.get(src_real, []):
            if not rp.startswith('@'):
                run_quiet(['install_name_tool', '-delete_rpath', rp, str(dst)])
        bundled.append(dst)

    seen_exe_changes = set()
    exe_cmd = ['install_name_tool']
    for orig_dep, target_real in dep_map.get(exe_real, []):
        new_ref = f'@executable_path/../Frameworks/{by_real[target_real]}'
        if orig_dep != new_ref and (orig_dep, new_ref) not in seen_exe_changes:
            exe_cmd.extend(['-change', orig_dep, new_ref])
            seen_exe_changes.add((orig_dep, new_ref))
    if len(exe_cmd) > 1:
        run_quiet(exe_cmd + [str(exe_path)])

    # Verify self-containment: no external non-system paths remain in executable or dylibs.
    allowed_prefixes = ('/usr/lib/', '/System/', '@executable_path/../Frameworks/', '@loader_path/')
    for check_bin in [exe_path, *bundled]:
        _, final_deps, _ = _macho_deps_and_rpaths(check_bin)
        bad = [d for d in final_deps if not d.startswith(allowed_prefixes)]
        if bad:
            raise RuntimeError(f'External dylib reference(s) remain in {check_bin}: {bad}')

    for dst in bundled:
        run_quiet(['codesign', '--force', '--sign', '-', str(dst)])

    total_mb = sum(p.stat().st_size for p in bundled) / (1024.0 * 1024.0)
    print(f'Bundled {len(bundled)} FFmpeg dylib(s) into {frameworks_dir.name}/ ({total_mb:.1f} MB)', flush=True)
    return bundled


GAME_PROFILES = {
    'fnv': {
        'app_name': 'Fallout New Vegas',
        'probe_name': 'FNVProbe',
        'exe_name': 'FalloutNewVegas',
        'bundle_prefix': 'dev.fnvmac.',
        'fixed_bundle_id': None,
        'icon': 'AppIcon.png',
        'default_version': '1',
        'steam_appid': '22380',
        'define': None,
        'options_src': 'OptionsFallout.m',
    },
    'fallout3': {
        'app_name': 'Fallout 3',
        'probe_name': 'FNVProbe',
        'exe_name': 'Fallout3',
        'bundle_prefix': 'dev.fallout3mac.',
        # Unique Fallout 3 prefix (matching dev.fnvmac./dev.skyrimmac.); supersedes dev.f3mac.fallout3
        # to guarantee a fresh Game Mode icon cache when AppIcon-Fallout3.png changes (docs/GAME-MODE-ICONS.md).
        'fixed_bundle_id': None,
        'icon': 'AppIcon-Fallout3.png',
        'default_version': '1',
        'steam_appid': '22370',
        'define': '-DFNV_GAME_FALLOUT3',
        'options_src': 'OptionsFallout.m',
    },
    'skyrim': {
        'app_name': 'Skyrim',
        'probe_name': 'SkyrimProbe',
        'exe_name': 'Skyrim',
        'bundle_prefix': 'dev.skyrimmac.',
        'fixed_bundle_id': None,
        'icon': 'AppIcon-Skyrim.png',
        'default_version': '1',
        'steam_appid': '72850',
        'define': '-DFNV_GAME_SKYRIM',
        'options_src': 'OptionsSkyrim.m',
    },
}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('target', choices=['probe', 'game', 'host-check'])
    p.add_argument('--game', choices=['fnv', 'fallout3', 'skyrim'], default='fnv', help='target game profile')
    p.add_argument('--generated', type=Path, help='full-game emit.py output')
    p.add_argument('--exe', type=Path, help='exact executable used to generate these units')
    p.add_argument('--out', type=Path, default=Path('build'))
    p.add_argument('--app-name', default=None, help='bundle display name without .app')
    p.add_argument('--jobs', type=int, default=min(os.cpu_count() or 2, 8))
    p.add_argument('--cache', type=Path, help='object cache keyed by compiler, SDK, flags, headers and content')
    p.add_argument('--state-probes', default='[]', help='bounded numeric entry/receiver-field diagnostic specification')
    p.add_argument('--codec-prefix', type=Path, help='verified pinned macOS Ogg/Vorbis static libraries')
    p.add_argument('--unicorn-prefix', type=Path, help='optional Unicorn engine prefix for fallback interpreter')
    p.add_argument('--no-unicorn', action='store_true', help='disable Unicorn fallback interpreter')
    p.add_argument('--steam-api-dylib', type=Path, help='optional Valve ARM64 libsteam_api.dylib to bundle in Frameworks/')
    p.add_argument('--steam-appid', default=None, help='Steam AppID written to steam_appid.txt when bundling libsteam_api.dylib')
    p.add_argument('--no-call-trace', action='store_true', help='omit per-function diagnostic ring writes')
    p.add_argument('--deployment-target', default=None, help='macOS deployment target (default: host major.0, min 14.0)')
    p.add_argument('--version', default=None, help='positive numeric app build version')
    args = p.parse_args()

    profile = GAME_PROFILES[args.game]
    version = args.version or os.environ.get('GITHUB_RUN_NUMBER') or profile.get('default_version', '1')
    if not version.isdecimal() or not 0 < int(version) <= 2147483647:
        p.error('--version must be a positive 32-bit integer')
    steam_appid = str(args.steam_appid or profile['steam_appid']).strip()
    probes = normalize(args.state_probes)
    matched_probes = set()
    probe = args.target == 'probe'
    host_check = args.target == 'host-check'
    exe_sha = digest(args.exe) if (not probe and args.exe and args.exe.is_file()) else None
    script_ext_active = bool(
        args.game == 'fnv' and not probe and not host_check and exe_sha and script_ext_patches.is_supported(exe_sha)
    )
    codec = validate_codecs(args.codec_prefix, 'macos') if args.codec_prefix else None
    if args.target == 'game' and not codec:
        p.error('game requires --codec-prefix for native sound decoding')
    if args.target == 'game' and not (args.exe and args.exe.is_file() and args.generated and
                                      (args.generated / 'table.c').is_file() and
                                      (args.generated / 'stubs.c').is_file() and
                                      any(args.generated.glob('tu_*.c'))):
        p.error('game requires --exe and --generated with full translated C sources')
    if not shutil.which('xcrun'):
        p.exit(1, 'Apple build required: install Xcode Command Line Tools (xcode-select --install).\n')

    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    cc = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--find', 'clang'], text=True).strip()

    unicorn = None if (probe or args.no_unicorn) else find_unicorn(args.unicorn_prefix)
    if unicorn:
        print(f'  Unicorn fallback enabled: {unicorn}', flush=True)
    ffmpeg = find_ffmpeg() if (args.game == 'skyrim' and not probe) else None
    if ffmpeg:
        print(f'  FFmpeg xWMA decoding enabled: {ffmpeg}', flush=True)

    signature = hashlib.sha256(subprocess.check_output([cc, '--version']) + sdk.encode())
    for header in sorted({hdr for directory in [R, M] for hdr in directory.rglob('*.h')}):
        signature.update(str(header.relative_to(ROOT)).encode() + header.read_bytes())
    config = signature.digest()

    old_manifest = {}
    if args.cache:
        args.cache.mkdir(parents=True, exist_ok=True)
        if (args.cache / 'manifest.json').exists():
            old_manifest = json.loads((args.cache / 'manifest.json').read_text())

    app_name = args.app_name or (profile['probe_name'] if probe else profile['app_name'])
    exe_name = profile['probe_name'] if probe else profile['exe_name']

    sources = [M / 'FNVApp.m', M / 'FNVGameView.m', M / 'FNVPad.c', M / 'FNVDisplay.c', H / 'd3d9_metal.m']
    if probe:
        sources += [M / 'FNVProbe.c', M / 'ProbeRuntime.c']
        sources += [H / (s + '.c') for s in ['d3d9', 'dinput', 'com', 'gheap', 'input', 'sm2msl']]
    else:
        sources += [M / profile['options_src'], M / 'FNVAudioMixer.c', M / 'FNVNativeMedia.m', M / 'FNVNativeVideo.m']
        if args.game == 'skyrim':
            sources.append(M / 'FNVXAudioMixer.c')
        excluded = {'d3d9_null.c', 'fallback.c'}
        excluded.add('shims_xlive.c' if args.game == 'skyrim' else 'xaudio2.c')
        sources += [f for f in H.glob('*.c') if f.name not in excluded]
        if unicorn:
            sources.append(H / 'fallback.c')
        sources += [H / 'dshow.m', R / 'rt_dispatch.c']
        if not host_check:
            sources += [args.generated / 'table.c', args.generated / 'stubs.c']
            sources += sorted(args.generated.glob('tu_*.c'))

    args.out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=args.out) as temp:
        tmp = Path(temp)
        bundle = tmp / (app_name + '.app')
        contents = bundle / 'Contents'
        macos_dir = contents / 'MacOS'
        resources_dir = contents / 'Resources'
        macos_dir.mkdir(parents=True)
        resources_dir.mkdir(parents=True)

        deploy_target = args.deployment_target or host_deployment_target()
        base = [cc, '-target', f'arm64-apple-macos{deploy_target}', '-isysroot', sdk]

        def compile_one(item):
            idx, source = item
            out = tmp / f'{idx}.o'
            content = source.read_bytes()
            matched = set()
            se_matched = set()
            patched = False
            if args.game == 'skyrim' and args.generated and source.parent.resolve() == args.generated.resolve():
                content, patched = patch_generated_tu(content)
            if script_ext_active and args.generated and source.parent.resolve() == args.generated.resolve():
                content, se_matched = script_ext_patches.patch_tu(content, exe_sha)
                patched = patched or bool(se_matched)
            if probes and args.generated and source.parent.resolve() == args.generated.resolve():
                content, matched = instrument(content, probes)
            compiled_source = source
            if patched or matched:
                compiled_source = tmp / ('patched-' + source.name)
                compiled_source.write_bytes(content)
            flags = ['-O1', '-I', str(H), '-I', str(R), '-I', str(M)]
            if profile['define']:
                flags.append(profile['define'])
            if script_ext_active and source.name == 'script_ext.c':
                flags.append('-DFNV_SCRIPT_EXT_PATCHED=1')
            if codec:
                flags += ['-DFNV_HAVE_VORBIS', '-I', str(codec / 'include')]
            if unicorn and source.name == 'fallback.c':
                flags += ['-I', str(unicorn / 'include')]
            if ffmpeg and source.name == 'xaudio2.c':
                flags += ['-DSKYRIM_HAVE_FFMPEG', '-I', str(ffmpeg / 'include')]
            if source.suffix == '.m':
                flags += ['-fobjc-arc', '-Wno-deprecated-declarations']
            if probe:
                flags.append('-DFNV_PROBE')
            elif not host_check and not args.no_call_trace:
                flags.append('-DRT_CALLTRACE')
            key = hashlib.sha256(config + json.dumps(base + flags).encode() + source.name.encode() + content).hexdigest()
            stored = args.cache / (key + '.o') if args.cache else None
            if stored and stored.exists() and digest(stored) == old_manifest.get(stored.name):
                return str(stored), True, matched, se_matched
            cmd = base + flags + ['-c', str(compiled_source), '-o', str(out)]
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            if res.returncode != 0:
                raise subprocess.CalledProcessError(res.returncode, cmd, output=res.stdout)
            if stored:
                os.replace(out, stored)
                out = stored
            return str(out), False, matched, se_matched

        progress = _CompileProgress(len(sources))
        objects = [None] * len(sources)
        matched_se = set()
        reused_count = 0
        built_count = 0
        progress.start()
        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
                future_to_idx = {pool.submit(compile_one, item): item[0] for item in enumerate(sources)}
                pending = set(future_to_idx)
                while pending:
                    done_set, pending = concurrent.futures.wait(
                        pending, timeout=0.1, return_when=concurrent.futures.FIRST_COMPLETED
                    )
                    for fut in done_set:
                        idx = future_to_idx[fut]
                        try:
                            obj_path, reused, m_probe, m_se = fut.result()
                        except BaseException as exc:
                            for rem in pending:
                                rem.cancel()
                            progress.fail()
                            if isinstance(exc, subprocess.CalledProcessError) and exc.output:
                                sys.stderr.write(exc.output)
                            raise
                        objects[idx] = obj_path
                        matched_probes.update(m_probe)
                        matched_se.update(m_se)
                        if reused:
                            reused_count += 1
                        else:
                            built_count += 1
                    progress.tick(reused_count + built_count, reused_count, built_count)
            progress.finish(reused_count + built_count, reused_count, built_count)
        finally:
            progress.restore_cursor()
        if probes and set(probes) != matched_probes:
            raise ValueError('Requested diagnostic entries absent from generated source')
        if script_ext_active:
            expected_se = script_ext_patches.expected_labels(exe_sha)
            if matched_se != expected_se:
                missing_se = sorted(expected_se - matched_se)
                raise ValueError(f'Missing ScriptCommands relocation labels: {missing_se[:10]}')
            print(f'  NVSE-lite: patched {len(matched_se)} ScriptCommands references across generated TUs', flush=True)
        if args.cache:
            (args.cache / 'manifest.json').write_text(json.dumps({Path(path).name: digest(Path(path)) for path in objects}, indent=2))
        if host_check:
            print(f'PASS: compiled {len(objects)} public game-host sources for arm64 macOS; no game inputs')
            return

        frameworks = [
            'Foundation', 'AppKit', 'Metal', 'MetalFX', 'QuartzCore', 'CoreGraphics',
            'AVFoundation', 'CoreVideo', 'CoreMedia', 'ImageIO',
            'UniformTypeIdentifiers', 'GameController', 'CoreHaptics',
        ]
        libraries = [str(codec / 'lib' / ('lib' + n + '.a')) for n in ['vorbisfile', 'vorbis', 'ogg']] if codec else []
        if unicorn:
            libraries.append(str(unicorn / 'lib/libunicorn.a'))

        link_flags = ['-Wl,-stack_size,0x4000000', '-Wl,-headerpad_max_install_names']
        if ffmpeg:
            libraries += ['-L' + str(ffmpeg / 'lib'), '-lavcodec', '-lswresample', '-lavutil']
            link_flags.append('-Wl,-rpath,@executable_path/../Frameworks')
        run(base + objects + libraries + [v for f in frameworks for v in ('-framework', f)] + link_flags + ['-o', str(macos_dir / exe_name)])
        if ffmpeg:
            bundle_dylibs(macos_dir / exe_name, contents / 'Frameworks', extra_search_dirs=[ffmpeg / 'lib'])

        bundle_exe = exe_name
        if codec:
            shutil.copytree(codec / 'licenses', resources_dir / 'Licenses')
        if not probe and args.steam_api_dylib and args.steam_api_dylib.is_file():
            frameworks_dir = contents / 'Frameworks'
            frameworks_dir.mkdir(exist_ok=True)
            steam_dst = frameworks_dir / 'libsteam_api.dylib'
            shutil.copy2(args.steam_api_dylib, steam_dst)
            os.chmod(steam_dst, 0o755)
            run_quiet(['codesign', '--force', '--sign', '-', str(steam_dst)])
            (macos_dir / 'steam_appid.txt').write_text(steam_appid + '\n')
            launcher_name = exe_name + 'Launcher'
            run(base + ['-O2', '-Wall', '-Wextra',
                        '-DFNV_STEAM_GAME_NAME="' + exe_name + '"',
                        '-DFNV_STEAM_DEFAULT_APPID="' + steam_appid + '"',
                        str(M / 'FNVSteamLauncher.c'), '-o', str(macos_dir / launcher_name)])
            bundle_exe = launcher_name

        # Unique per-port bundle ID; see docs/GAME-MODE-ICONS.md for Game Mode icon-cache behavior.
        bundle_id = profile['fixed_bundle_id'] or (profile['bundle_prefix'] + args.target)
        info = dict(
            CFBundleDevelopmentRegion='en',
            CFBundleExecutable=bundle_exe,
            CFBundleName=app_name,
            CFBundleDisplayName=app_name,
            CFBundleIdentifier=bundle_id,
            CFBundlePackageType='APPL',
            CFBundleVersion=version,
            CFBundleShortVersionString='0.1',
            CFBundleInfoDictionaryVersion='6.0',
            LSMinimumSystemVersion=deploy_target,
            LSApplicationCategoryType='public.app-category.games',
            NSHighResolutionCapable=True,
            # Without this key macOS may run the app in camera-housing compatibility mode, which
            # letterboxes native fullscreen below the notch on MacBooks that have one (issue #6).
            # False = never compatibility mode: fullscreen uses the whole panel.
            NSPrefersDisplaySafeAreaCompatibilityMode=False,
            GCSupportedGameControllers=[{'ProfileName': 'ExtendedGamepad'}],
        )
        if not probe:
            info['FNVExecutableSHA256'] = digest(args.exe)
        info['FNVGuestCallTraceEnabled'] = bool(not probe and not args.no_call_trace)
        info['FNVOptimizationLevel'] = 'O1'
        icon_source = M / 'Assets' / profile['icon']
        info.update(compile_icon(tmp, resources_dir, icon_source))
        try:
            info['FNVBuildSourceCommit'] = subprocess.check_output(
                ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True, stderr=subprocess.DEVNULL
            ).strip()
        except (OSError, subprocess.CalledProcessError):
            pass

        (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
        (contents / 'PkgInfo').write_text('APPL????')

        run_quiet(['codesign', '--force', '--deep', '--sign', '-', str(bundle)])

        final_app = args.out / (app_name + '.app')
        if final_app.exists():
            shutil.rmtree(final_app)
        shutil.move(str(bundle), str(final_app))
        print(final_app.resolve())


if __name__ == '__main__':
    main()
