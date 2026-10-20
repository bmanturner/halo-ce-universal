# Credits and third-party notices

This iOS port builds on [cybersecurity/halo-ce-universal](https://github.com/cybersecurity/halo-ce-universal),
the native ports in [bnunu/halo-1](https://github.com/bnunu/halo-1), and the
decompilation work in [punpckhdq/halo](https://github.com/punpckhdq/halo).
The project license is the [AGPL 3.0 or later](../../LICENSE); OpenCE's
commits before its move to the AGPL stay under [CC0 1.0](../../LICENSES/CC0-1.0.txt).

The app includes SDL 3.4.16 (zlib license), portions of musl 1.2.5 (see its
COPYRIGHT for the MIT license and component notices), KCP (MIT), and tomlc17
(MIT), Opus 1.5.2 (BSD 3-clause; voice chat's codec; Licenses/Opus.txt), zlib (zlib license; inflates maps and images; Licenses/zlib.txt), and Expat (MIT; its COPYING is bundled in Licenses/Expat). The native XISO parser adapts upstream extraction code following
extract-xiso (modified BSD; see `port/third_party/extract-xiso/LICENSE.TXT`).
This product includes software developed by in <in@fishtank.com>. Their complete notices are copied into the built app's `Licenses`
directory. Khronos headers retain the notices supplied by their registries.
Other vendored components retain their original notices in the source tree.

Halo, Master Chief, game artwork, and original game assets belong to their
respective rights holders. The project license does not grant rights to those
materials. The icon is original abstract ringworld artwork; see [ICON.md](ICON.md).
Apple builds omit the embedded replacement HUD, title and font assets and
load original game artwork from the user-provided disc image. The new menus
bundle upstream XML layouts and redrawn graphics; see
`port/assets/menus/NON_HANDDRAWN.md` for images sourced at runtime from the
user's map and the remaining placeholders. No game maps, disc images, Microsoft signing material, or
Xbox SDK are distributed in the app. This is an unofficial community port,
unaffiliated with Microsoft, Bungie, or Halo Studios.

## ANGLE Metal backend

The Metal renderer bundles [ANGLE](https://github.com/google/angle) at
`c053bf85793bbb83016b1196d04e5df3594b9bcc` (BSD 3-clause), using the
`v2.1.28252` iOS/device and simulator frameworks published by
[EdgeFirstAI/angle-package](https://github.com/EdgeFirstAI/angle-package).
The download is pinned by SHA-256 in `tools/ios_angle.py`. ANGLE and translator
dependency notices (xxHash, ceval, glslang, SPIR-V headers/tools/cross, Abseil,
and zlib) are copied into the app's `Licenses` directory. ANGLE receives only
native graphics calls; it is not a browser or a WASM runtime.

The Apple TV app builds the same ANGLE revision from source with
`tools/tvos_angle.py` (depot_tools pinned at
`a03dfbf7f2d1cefa2795d81d59ca4f16c8616a8f`), because the package has no tvOS
slice. It ships the same notices.

- Monocypher 4.0.3, vendored from upstream `c04765d7`, implements the signed
  public-server listings. See `port/third_party/monocypher/LICENCE.md`; that
  license is included in both app bundles under Licenses/Monocypher.
- Lucide's `volume-2` and `volume-x` icons (ISC) are rendered into the voice
  chat speaker images in the embedded menus. See
  `port/assets/icons/lucide/LICENSE`; that license is included in both app
  bundles as Licenses/Lucide.txt.
- Mbed TLS 3.6.7 (Apache-2.0 OR GPL-2.0-or-later; used here under
  Apache-2.0), vendored unchanged in `port/third_party/mbedtls`, provides the
  DTLS that internet play uses with browsers (`port/linux/src/posix_dtls.c`,
  linked into the app's host). See `port/third_party/mbedtls/LICENSE`; that
  license is included in the app bundles as Licenses/Mbed-TLS.txt.
