#!/usr/bin/env python3
"""Build the Apple TV app from source on an Apple Silicon Mac.

The Xbox maps (and optionally Custom Edition maps) are copied into the app
bundle, so the app is a personal build, not for distribution.
"""
import argparse
import os
import platform
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SDL_SOURCE = ROOT / 'build/third_party/SDL3'
SDL_TVOS = ROOT / 'build/third_party/SDL3-tvos'
STAMP = '.halo-source-revision'
# SDL 3 turns OpenGL ES off on tvOS by default; the port draws through Apple's OpenGL ES there.
GLES_LINE = 'dep_option(SDL_OPENGLES            "Include OpenGL ES support" ON "SDL_VIDEO;NOT VISIONOS;NOT TVOS;NOT WATCHOS" OFF)'
GLES_FIXED = GLES_LINE.replace('NOT TVOS;', '')


def run(*args):
    print('+', ' '.join(str(a) for a in args), flush=True)
    subprocess.run([str(a) for a in args], cwd=ROOT, check=True)


def prepare_sdl():
    """SDL copy without .git whose OpenGL ES option is available on tvOS."""
    if not (SDL_SOURCE / 'CMakeLists.txt').exists():
        sys.exit(f'{SDL_SOURCE} is missing; run tools/ios_build.py --guest-only first')
    revision = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=SDL_SOURCE, check=True,
                              capture_output=True, text=True).stdout.strip()
    stamp = SDL_TVOS / STAMP
    if stamp.exists() and stamp.read_text().strip() == revision:
        return
    if SDL_TVOS.exists():
        shutil.rmtree(SDL_TVOS)
    shutil.copytree(SDL_SOURCE, SDL_TVOS, symlinks=True, ignore=shutil.ignore_patterns('.git'))
    cmake = SDL_TVOS / 'CMakeLists.txt'
    text = cmake.read_text()
    if text.count(GLES_LINE) != 1:
        shutil.rmtree(SDL_TVOS)
        sys.exit(f'{cmake}: expected exactly one SDL_OPENGLES dep_option line, found {text.count(GLES_LINE)}; '
                 'SDL changed, update tools/tvos_build.py')
    cmake.write_text(text.replace(GLES_LINE, GLES_FIXED))
    stamp.write_text(revision + '\n')


def map_folder(parser, option, value, required_map=None):
    folder = Path(value).expanduser().resolve()
    if not folder.is_dir():
        parser.error(f'{option}: {folder} is not a folder')
    if required_map and not (folder / required_map).is_file():
        parser.error(f'{option}: {folder} has no {required_map}')
    return folder


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--team', required=True, help='Apple development team ID for signing')
    parser.add_argument('--bundle-id', default='org.haloce.tv', help='bundle identifier covered by your signing profile (default org.haloce.tv)')
    parser.add_argument('--icloud-container', default='', help='iCloud container for save mirroring, e.g. iCloud.com.example.halo (default: none)')
    parser.add_argument('--game-data', required=True, help='folder with the Xbox *.map files (must hold ui.map)')
    parser.add_argument('--custom-edition', help='folder with Custom Edition *.map files, including bitmaps.map, sounds.map and loc.map')
    parser.add_argument('--install', metavar='DEVICE', help='build for and install on this Apple TV (its identifier from xcrun devicectl list devices)')
    parser.add_argument('--jobs', type=int, default=min(12, os.cpu_count() or 4))
    args = parser.parse_args()
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        parser.error('an Apple Silicon Mac with full Xcode is required')
    if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', args.bundle_id):
        parser.error('--bundle-id must be a reverse-DNS identifier (e.g. com.example.halo)')
    if args.icloud_container and not re.fullmatch(r'iCloud\.[A-Za-z0-9.-]+', args.icloud_container):
        parser.error('--icloud-container must look like iCloud.com.example.halo')
    if args.jobs < 1:
        parser.error('--jobs must be positive')
    game_data = map_folder(parser, '--game-data', args.game_data, 'ui.map')
    custom = map_folder(parser, '--custom-edition', args.custom_edition) if args.custom_edition else None
    run(sys.executable, 'tools/ios_build.py', '--guest-only')
    prepare_sdl()
    build = ROOT / 'build/tvos/app'
    run('cmake', '-S', 'port/tvos', '-B', build, '-G', 'Xcode', '-DCMAKE_SYSTEM_NAME=tvOS',
        '-DCMAKE_OSX_SYSROOT=appletvos', '-DCMAKE_OSX_ARCHITECTURES=arm64', '-DCMAKE_OSX_DEPLOYMENT_TARGET=17.0',
        f'-DHALO_BUNDLE_IDENTIFIER={args.bundle_id}', f'-DHALO_DEVELOPMENT_TEAM={args.team}',
        f'-DHALO_ICLOUD_CONTAINER={args.icloud_container}', f'-DHALO_GAME_DATA={game_data}',
        f'-DHALO_CUSTOM_EDITION_DATA={custom or ""}')
    if args.install:
        # Building for the paired Apple TV lets automatic signing register it
        # with the team; a generic build only finds an already registered one.
        run('xcodebuild', '-project', build/'HaloCE.xcodeproj', '-scheme', 'HaloCE', '-configuration', 'Release',
            '-destination', f'id={args.install}', '-jobs', args.jobs, '-quiet',
            '-allowProvisioningUpdates', '-allowProvisioningDeviceRegistration', 'build')
    else:
        run('cmake', '--build', build, '--config', 'Release', '--target', 'HaloCE', '-j', args.jobs, '--',
            '-quiet', '-allowProvisioningUpdates', '-allowProvisioningDeviceRegistration')
    app = build / 'Release-appletvos/HaloCE.app'
    print(f'App: {app}')
    if args.install:
        run('xcrun', 'devicectl', 'device', 'install', 'app', '--device', args.install, app)


if __name__ == '__main__':
    main()
