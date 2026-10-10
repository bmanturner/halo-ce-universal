#!/usr/bin/env python3
"""Build ANGLE's libEGL and libGLESv2 frameworks for the Apple TV (tvOS device, arm64).

The prebuilt ANGLE package used by the iPhone/iPad app has no tvOS slice, so
the frameworks are built from the same ANGLE revision (ios_angle.REVISION).
Everything lives under build/third_party/angle-tvos/: depot_tools, the ANGLE
checkout, and dist/ with EGL.xcframework and GLESv2.xcframework.

The first run downloads about 7 GB of sources and toolchains (clang, rust) and
compiles about 1300 files, roughly 10 minutes on a recent Apple Silicon Mac.
Later runs return at once while dist/BUILD_INFO.txt matches the revision and
the gn arguments. Needs full Xcode, git and network access.

    python3 tools/tvos_angle.py [--jobs N]

tools/tvos_build.py runs this itself before building the app.
"""
import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ios_angle import REVISION  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'build/third_party/angle-tvos'
DEPOT_TOOLS = BASE / 'depot_tools'
ANGLE = BASE / 'angle'
DIST = BASE / 'dist'
GCLIENT_FILE = BASE / '.gclient'
SYNC_STAMP = BASE / 'sync-stamp'
OUT = 'out/tvos-device'
FRAMEWORKS = [('libEGL', 'EGL'), ('libGLESv2', 'GLESv2')]

DEPOT_TOOLS_URL = 'https://chromium.googlesource.com/chromium/tools/depot_tools'
DEPOT_TOOLS_REVISION = 'a03dfbf7f2d1cefa2795d81d59ca4f16c8616a8f'
ANGLE_URL = 'https://chromium.googlesource.com/angle/angle'

# use_blink is required: build/config/apple/mobile_config.gni asserts it for tvOS.
GN_ARGS = [
    'target_os="ios"',
    'target_platform="tvos"',
    'target_cpu="arm64"',
    'target_environment="device"',
    'use_blink=true',
    'ios_enable_code_signing=false',
    'ios_deployment_target="17.0"',
    'ios_app_bundle_id_prefix="org.haloce.angle"',
    'is_debug=false',
    'is_component_build=false',
    'angle_enable_metal=true',
    'angle_enable_vulkan=false',
    'angle_enable_gl_desktop_backend=false',
    'angle_enable_gl=false',
    'angle_has_frame_capture=false',
    'treat_warnings_as_errors=false',
]

# Test-only dependencies skipped to save about 6 GB. third_party/catapult stays:
# gn gen fails without catapult/tracing/BUILD.gn (//testing/BUILD.gn, gni/angle.gni).
GCLIENT = f'''solutions = [
  {{
    "name": "angle",
    "url": "{ANGLE_URL}.git@{REVISION}",
    "deps_file": "DEPS",
    "managed": False,
    "custom_deps": {{
      "angle/third_party/VK-GL-CTS/src": None,
      "angle/third_party/SwiftShader": None,
    }},
    "custom_vars": {{
      "checkout_angle_cl_deps": False,
    }},
  }},
]
target_os = ["ios"]
'''


def run(*args, cwd=ROOT, env=None):
    print('+', ' '.join(str(a) for a in args), flush=True)
    subprocess.run([str(a) for a in args], cwd=cwd, env=env, check=True)


def output(*args, cwd=ROOT):
    return subprocess.run([str(a) for a in args], cwd=cwd, check=True,
                          capture_output=True, text=True).stdout.strip()


def build_info_header():
    return f'revision: {REVISION}\ngn args: {" ".join(GN_ARGS)}\n'


def is_current():
    """True when dist was built from this revision and these gn arguments."""
    info = DIST / 'BUILD_INFO.txt'
    if not info.is_file() or not info.read_text().startswith(build_info_header()):
        return False
    return all((DIST / f'{xc}.xcframework/tvos-arm64/{lib}.framework/{lib}').is_file()
               for lib, xc in FRAMEWORKS)


def tool_env():
    env = dict(os.environ)
    env['PATH'] = f'{DEPOT_TOOLS}{os.pathsep}{env["PATH"]}'
    env['DEPOT_TOOLS_UPDATE'] = '0'
    env['DEPOT_TOOLS_METRICS'] = '0'
    # Xcode's python3 shim sets LIBRARY_PATH/CPATH/SDKROOT; ANGLE's toolchain chooses its own SDK and links with -fatal_warnings
    for var in ('LIBRARY_PATH', 'CPATH', 'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH', 'OBJC_INCLUDE_PATH',
                'SDKROOT', 'LDFLAGS', 'CFLAGS', 'CXXFLAGS', 'CPPFLAGS'):
        env.pop(var, None)
    return env


def prepare_depot_tools():
    """depot_tools at its pinned commit, bootstrapped so the gn wrapper works."""
    DEPOT_TOOLS.mkdir(parents=True, exist_ok=True)
    if not (DEPOT_TOOLS / '.git').exists():
        run('git', 'init', '-q', DEPOT_TOOLS)
    head = subprocess.run(['git', 'rev-parse', '-q', '--verify', 'HEAD'], cwd=DEPOT_TOOLS,
                          capture_output=True, text=True).stdout.strip()
    if head != DEPOT_TOOLS_REVISION:
        print('Fetching depot_tools', flush=True)
        run('git', 'fetch', '-q', '--depth', '1', DEPOT_TOOLS_URL, DEPOT_TOOLS_REVISION, cwd=DEPOT_TOOLS)
        run('git', 'checkout', '-q', '--force', 'FETCH_HEAD', cwd=DEPOT_TOOLS)
    if not (DEPOT_TOOLS / 'python3_bin_reldir.txt').exists():
        run(DEPOT_TOOLS / 'ensure_bootstrap', cwd=DEPOT_TOOLS, env=tool_env())


def prepare_angle_root():
    """Blobless clone with full history, so ANGLE reports its real version, at REVISION."""
    if not (ANGLE / '.git').exists():
        if ANGLE.exists():
            shutil.rmtree(ANGLE)
        print('Cloning ANGLE (history only, about 1 minute)', flush=True)
        run('git', 'clone', '-q', '--filter=blob:none', '--no-checkout', ANGLE_URL, ANGLE)
    head = subprocess.run(['git', 'rev-parse', '-q', '--verify', 'HEAD'], cwd=ANGLE,
                          capture_output=True, text=True).stdout.strip()
    if head != REVISION:
        run('git', 'checkout', '-q', '--force', '--detach', REVISION, cwd=ANGLE)


def sync_stamp_value():
    return hashlib.sha256(f'{REVISION}\n{GCLIENT}'.encode()).hexdigest()


def sync_sources(jobs):
    """gclient sync and hooks (toolchains, flex/bison); skipped once done for this revision."""
    if GCLIENT_FILE.exists() and GCLIENT_FILE.read_text() != GCLIENT:
        SYNC_STAMP.unlink(missing_ok=True)
    GCLIENT_FILE.write_text(GCLIENT)
    if SYNC_STAMP.exists() and SYNC_STAMP.read_text().strip() == sync_stamp_value():
        return
    SYNC_STAMP.unlink(missing_ok=True)
    prepare_angle_root()
    env = tool_env()
    print('Syncing ANGLE dependencies (about 2 minutes, about 7 GB)', flush=True)
    # gclient merges its previous entries with the new ones, so a dependency that
    # custom_deps now skips is listed twice, which depot_tools' gn wrapper cannot
    # parse; the sync writes the file again
    (BASE / '.gclient_entries').unlink(missing_ok=True)
    run('gclient', 'sync', '--no-history', '--shallow', '--nohooks', '-j', jobs, cwd=BASE, env=env)
    run('gclient', 'runhooks', cwd=BASE, env=env)
    # gclient does not remove a checkout that custom_deps later skips
    for skipped in ('third_party/VK-GL-CTS', 'third_party/SwiftShader'):
        if (ANGLE / skipped).exists():
            shutil.rmtree(ANGLE / skipped)
    SYNC_STAMP.write_text(sync_stamp_value() + '\n')


def ninja_binary():
    bundled = ANGLE / 'third_party/ninja/ninja'
    return str(bundled) if bundled.exists() else 'ninja'


def compile_frameworks(jobs):
    env = tool_env()
    print('Compiling ANGLE for tvOS (about 4 minutes)', flush=True)
    run('gn', 'gen', OUT, '--args=' + ' '.join(GN_ARGS), cwd=ANGLE, env=env)
    run(ninja_binary(), '-C', OUT, '-j', jobs, *(lib for lib, _ in FRAMEWORKS), cwd=ANGLE, env=env)


def check_tvos_arm64(binary):
    """Raise unless the binary is an arm64 Mach-O built for tvOS (LC_BUILD_VERSION platform 3)."""
    archs = output('lipo', '-archs', binary).split()
    if archs != ['arm64']:
        raise RuntimeError(f'{binary}: expected arm64 only, found {archs}')
    lines = output('otool', '-l', binary).splitlines()
    for i, line in enumerate(lines):
        if line.strip() == 'cmd LC_BUILD_VERSION':
            platform = next((l.split()[1] for l in lines[i + 1:i + 6] if l.split()[:1] == ['platform']), None)
            if platform == '3':
                return
            raise RuntimeError(f'{binary}: built for platform {platform}, expected 3 (tvOS)')
    raise RuntimeError(f'{binary}: no LC_BUILD_VERSION load command, not a tvOS binary')


def angle_version():
    """ANGLE's version (2.1.<commit position>) from the header the build generates, or unknown."""
    try:
        header = (ANGLE / OUT / 'gen/angle/angle_commit.h').read_text()
    except OSError:
        return 'unknown'
    position = re.search(r'#define ANGLE_COMMIT_POSITION (\d+)', header)
    return f'2.1.{position.group(1)}' if position else 'unknown'


def assemble():
    """Build dist in a temporary folder, then move it into place."""
    built = ANGLE / OUT
    for lib, _ in FRAMEWORKS:
        check_tvos_arm64(built / f'{lib}.framework' / lib)
    staging = BASE / 'dist.tmp'
    if staging.exists():
        shutil.rmtree(staging)
    slice_dir = staging / 'slice'
    slice_dir.mkdir(parents=True)
    try:
        for lib, xc in FRAMEWORKS:
            framework = slice_dir / f'{lib}.framework'
            shutil.copytree(built / f'{lib}.framework', framework, symlinks=True)
            run('xcodebuild', '-create-xcframework', '-framework', framework,
                '-output', staging / f'{xc}.xcframework')
            check_tvos_arm64(staging / f'{xc}.xcframework/tvos-arm64/{lib}.framework/{lib}')
        shutil.rmtree(slice_dir)
        version = angle_version()
        (staging / 'BUILD_INFO.txt').write_text(build_info_header() + f'version: {version}\n')
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    if DIST.exists():
        shutil.rmtree(DIST)
    os.replace(staging, DIST)


def prepare(jobs):
    """Build ANGLE for tvOS if dist is missing or stale; return the dist directory."""
    if is_current():
        print(f'ANGLE for tvOS is up to date: {DIST}')
        return DIST
    BASE.mkdir(parents=True, exist_ok=True)
    prepare_depot_tools()
    sync_sources(jobs)
    compile_frameworks(jobs)
    assemble()
    print(f'ANGLE for tvOS built: {DIST}')
    return DIST


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--jobs', type=int, default=min(12, os.cpu_count() or 4))
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error('--jobs must be positive')
    prepare(args.jobs)


if __name__ == '__main__':
    main()
