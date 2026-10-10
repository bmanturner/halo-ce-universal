# Build and install Halo: CE on Apple TV

This is the Apple TV app. It runs the same signed ARM64 ILP32 guest as the
iPhone and iPad app ([port/ios](../ios/README.md)), with a tvOS host in
`port/tvos`. Network play is the same as on iOS: the native public servers and
internet games, with no change to the network version.

tvOS has no Files app and no document picker, and keeps only purgeable
caches. The app therefore cannot import a disc image. `tools/tvos_build.py`
copies your own maps into the app when it builds it, so an Apple TV build is
a personal build. It contains your game data and must not be distributed
(see [port/apple/DISTRIBUTION.md](../apple/DISTRIBUTION.md)).

## Requirements

- An Apple Silicon Mac with Xcode and the tvOS SDK, and what
  [port/ios/README.md](../ios/README.md) lists for the iOS build (the shared
  guest is built by `tools/ios_build.py --guest-only`).
- An Apple account with a paid developer team, signed in to Xcode >
  Settings > Accounts. The build signs automatically
  (`-allowProvisioningUpdates -allowProvisioningDeviceRegistration`).
- An Apple TV running tvOS 17.0 or later. tvOS has no Developer Mode.
- The Xbox maps of the game, and optionally Custom Edition maps
  (see "Game data").

## Build and install

```sh
python3 tools/tvos_build.py --team TEAM --bundle-id ID --game-data DIR
```

| Option | Meaning |
| --- | --- |
| `--team TEAM` | The developer team ID used to sign |
| `--bundle-id ID` | The app's bundle identifier |
| `--game-data DIR` | A folder holding the Xbox `*.map` files, including `ui.map` |
| `--custom-edition DIR` | A folder with the Custom Edition maps and `bitmaps.map`, `sounds.map`, `loc.map` (optional) |
| `--icloud-container iCloud.ID` | The CloudKit container for iCloud saves (optional) |
| `--install DEVICE` | Build for this Apple TV and install the app on it (optional; the identifier from `xcrun devicectl list devices`). Building for the device lets automatic signing register it with the team, which the first build needs |

The script:

1. runs `tools/ios_build.py --guest-only`, which builds the shared Apple guest;
2. makes `build/third_party/SDL3-tvos`, a copy of SDL 3.4.16 in which the
   OpenGL ES option is allowed on tvOS (SDL turns it off there by default);
3. builds ANGLE for tvOS with `tools/tvos_angle.py` (see below);
4. configures `port/tvos` with Xcode (tvOS 17.0 minimum, Apple TV device
   family) and builds it with automatic signing.

The first run fetches depot_tools and ANGLE's sources and builds ANGLE: about
7 GB under `build/third_party/angle-tvos` and about 10 minutes. Later runs
reuse it.

The output is `build/tvos/app/Release-appletvos/HaloCE.app`. Install it with
`--install DEVICE`, or with:

```sh
xcrun devicectl device install app --device DEVICE build/tvos/app/Release-appletvos/HaloCE.app
```

Pair the Apple TV first: on the Apple TV, Settings > Remotes and Devices >
Remote App and Devices; on the Mac, Xcode > Window > Devices and Simulators.

Each install copies the whole bundle to the Apple TV: about 1.8 GB of Xbox
maps, and about 2.4 GB more with a typical Custom Edition set. Over the local
network the Xbox-only app (1.7 GB) installed in about 35 seconds, the 4.0 GB
one in about 80 seconds including the build.

## Game data

A post-build step copies the maps into the app bundle:

| Option | Folder in the app |
| --- | --- |
| `--game-data` | `GameData/maps` |
| `--custom-edition` | `GameData/CustomEdition/maps` |

At launch the app makes `<Caches>/Halo/game` the game's data folder (the
`d:` drive, which the game writes to) and passes the bundle's
`GameData/maps` as `paths.maps` (`HALO_MAPS_ROOT`), from which the game
reads `d:\maps\`. tvOS does not let the app link to its bundle from Caches.

To get the Xbox maps, either:

- extract them from your own Xbox disc image with
  `tools/ios_extract_assets.py`, or
- copy them from the iOS app's container with
  `xcrun devicectl device copy from --domain-type appDataContainer`, from
  `Documents/game-<UUID>/maps`.

The Custom Edition folder holds the Custom Edition maps together with
`bitmaps.map`, `sounds.map` and `loc.map`.

Writable data (`config.toml`, `ios-runtime.log`, `brokers.txt`, `save/`) is in
`<Caches>/Halo`. tvOS may empty the Caches folder when it needs space; iCloud
saves protect against this.

## iCloud saves

`--icloud-container iCloud.ID` turns on a CloudKit mirror of the saves. It
needs:

- a paid developer team;
- an App ID, for your bundle identifier, with iCloud and CloudKit enabled and
  the container assigned to it;
- Xcode signed in to that account.

The app mirrors `save/` and `config.toml` to the private database: zone
`HaloSaves`, record type `HaloFile`, one LZFSE-compressed asset per file.
`save/z/cacheNNN.map`, the Xbox utility drive's copies of map data (up to
about 290 MB each), are rebuilt by the game and are not mirrored.

- At launch it restores the files that are missing locally, and waits at most
  20 seconds for this. It never overwrites a local file.
- It uploads changed files every 30 seconds and when the app goes to the
  background.
- It never deletes cloud records.
- Development-signed builds use CloudKit's Development environment.
- Without a container or an iCloud account it does nothing, and logs that.
- An error that no retry fixes during a run (the container refuses the app,
  a missing entitlement, no iCloud account) stops the mirror for that run,
  with one log line. Right after the App ID and container were set up, the
  server answered `Invalid bundle ID for container` for about half an hour
  before uploads worked.

## Controls

| Input | What it does |
| --- | --- |
| Game controller (MFi, Xbox, PlayStation) | Passes through SDL as on the other platforms, for menus and play |
| Siri Remote | Reaches the game as keys, not as a player controller: Select is A, Menu is B (back), swipes are the arrow keys. Enough for the menus, not for play |

There are no on-screen controls. While the game runs, Menu does not leave the
app (SDL's controller UI events hint is off); use the TV/Home button.

## What differs from iOS

| | Apple TV |
| --- | --- |
| Renderer | ANGLE's Metal backend (OpenGL ES on Metal), built from source for tvOS by `tools/tvos_angle.py` at the same ANGLE revision as the iOS package (c053bf85, version 2.1.28252) and embedded by `port/tvos/CMakeLists.txt`. `host_graphics.m` picks it when ANGLE's frameworks are in the bundle; Apple's OpenGL ES 3.0 (EAGL) through the SDL copy with OpenGL ES allowed remains the fallback. The ANGLE shader cache works on the Apple TV. It is kept in Caches, so tvOS may empty it, and the first launch after that compiles the shaders again (on the A15 that froze loading for about 2.4 s and the game for about 1.1 s, once). The drawable is 1920x1080 on purpose: the TV scales it to 4K, and a 4K drawable cost about 0.9 ms a frame. MetalFX is not used: on the A15, MetalFX 720p to 1080p cost about 5 ms of GPU time a frame and 720p to 4K 13-15 ms, more than drawing at 720p saved (about 2.2 ms). It does work on tvOS 27.0 (`supportsDevice` is YES on the A15), although Apple's documentation lists tvOS 27.1. ANGLE does not offer S3TC on the A15 Apple TV either (Metal reports no BC texture support), so DXT textures are still decoded on the CPU |
| Render height | 1080 by default (`HaloRenderHeight` in `port/tvos/Info.plist`); the Video Settings row still changes it |
| Display mode | The game draws standard dynamic range and asks tvOS for that mode (`AVDisplayManager.preferredDisplayCriteria`, `host_platform.m`). With Settings > Video and Audio > Match Content > Match Dynamic Range on, the TV switches to SDR while the game is in front, which lets TVs that refuse their game mode in HDR use it, and back for the Home screen and other apps; HDR video elsewhere still plays in HDR. The request names the refresh rate the TV has at launch (the Format setting's), so Match Frame Rate leaves it unchanged, and the game's Frame Rate setting (30 Classic, 60, Display) paces frames within it. Without Match Content tvOS ignores the request and keeps the Format setting's mode. The log says `display: asked for SDR at 60 Hz, the current refresh rate (Match Content on)`, or `off` |
| Game data | Built into the app, not imported |
| Not available | Browser rooms (WebKit), touch controls, ISO import, Files access, joining from a clipboard invite (UIPasteboard), voice chat microphone (you can listen only), the iOS debug settings sheet |

Browser rooms report as unavailable.

## Diagnostics

`host_main.m` forwards these variables from the process environment, on all
Apple apps:

| Variable | Setting | Meaning |
| --- | --- | --- |
| `HALO_MENU_OPEN` | `debug.menu_open` | Start on one menu screen |
| `HALO_EXIT_AFTER` | `debug.exit_after` | Exit after this many seconds |
| `HALO_NETWORK_TEST` | `debug.network_test` | `host:<map>` hosts a game on that map without the menus (`custom_maps\<name>` for a Custom Edition map); `join` joins the first game found |
| `HALO_TEST_INPUT` | `debug.test_input` | `bot:<seed>` plays controller 1 with a pattern; `look:<seed>` only turns and looks up and down |
| `HALO_GPU_STATS` | `debug.gpu_stats` | Logs the renderer's draw counts, with the frame number, once a second |

With `devicectl`, set them as `DEVICECTL_CHILD_<NAME>=value` in the
environment of the command, or pass `--environment-variables`. For example,
Blood Gulch for 100 seconds with the console attached:

```sh
DEVICECTL_CHILD_HALO_NETWORK_TEST=host:bloodgulch DEVICECTL_CHILD_HALO_TEST_INPUT=look:1 \
DEVICECTL_CHILD_HALO_GPU_STATS=1 DEVICECTL_CHILD_HALO_EXIT_AFTER=100 \
  xcrun devicectl device process launch --device DEVICE --terminate-existing --console ID
```

Copy the log with:

```sh
xcrun devicectl device copy from --device DEVICE --domain-type appDataContainer \
  --domain-identifier ID --source Library/Caches/Halo/ios-runtime.log \
  --destination ios-runtime.log
```

## How it works

| File | Contents |
| --- | --- |
| `port/tvos/CMakeLists.txt` | The Xcode project for the app |
| `port/tvos/Info.plist`, `port/tvos/Entitlements.plist` | The app's properties and entitlements |
| `port/tvos/host_platform.m` | The tvOS hooks: no on-screen controls, controllers pass straight through SDL, browser rooms report unavailable, the built-in maps setup |
| `port/tvos/host_cloud_saves.m` | The CloudKit mirror |
| `port/tvos/tvos_host.h` | The header the two host files share |
| `port/tvos/Assets.xcassets` | The brand assets, made by `tools/tvos_icon.py` from `port/apple/RingArtwork.png` |
| `tools/tvos_build.py` | The build, the SDL copy and the install |
| `tools/tvos_angle.py` | Builds ANGLE's `libEGL` and `libGLESv2` frameworks for tvOS |

The rest of the app, the guest, the address arena and the ABI bridges, is
shared with the iOS build. The SDL copy in `build/third_party/SDL3-tvos`
differs from the pinned SDL clone (`build/third_party/SDL3`, made by
`tools/ios_guest_build.py`) only in the OpenGL ES line of its
`CMakeLists.txt`.

## Validation

On an Apple TV 4K (3rd generation, A15, `AppleTV14,1`) with tvOS 27.0
(24J361), 2026-10-10, unattended through `devicectl` with the diagnostics
above. The rows up to Display mode were taken with Apple's OpenGL ES, before
the app drew with ANGLE:

| Check | Result |
| --- | --- |
| Start | The main menu draws at 1920x1080 (logical 852x480) with `OpenGL ES 3.0 Metal - 105 on Apple A15 GPU`; copy image, border clamp, S3TC, sample counting and base vertex are absent, so the renderer's fallbacks run; anisotropy is present |
| Blood Gulch, hosted by `HALO_NETWORK_TEST=host:bloodgulch`, `HALO_TEST_INPUT=look:1` | 59.9 fps for 79 s (frame counter from `HALO_GPU_STATS`); physical footprint 461 MiB (Instruments, Activity Monitor) |
| Icefields, a Custom Edition map (`host:custom_maps\icefields`), in the 4.0 GB build | Loads from `GameData/CustomEdition`; 59.8 fps for 69 s, slowest 1 s window 58.0 |
| iCloud saves | All 32 save and config files uploaded, `savegame.bin` (20 MiB) included; after uninstalling and reinstalling the app, 32 of 32 restored with their SHA-256 matching. The playlists (`blam.lst`) differ afterwards because the game rewrites them at each start |
| DualSense, by hand | SDL reports it as a PlayStation 5 gamepad; the D-pad, the stick, Cross and Circle move through and open the menus. The person holding it found the menus a little delayed. One quick D-pad tap of two never reached SDL, which reads the controller's state once a frame, and the other showed as held for 15 ms. `host_platform.m` now latches every press and passes on a tap that falls between two reads (it logs `controller: a tap between two reads of button N, passed on`); not yet checked by hand |
| Graphics settings | MSAA left the screen black (sound still played): SDL presents the renderbuffer bound at the swap, and the game's multisampled targets had left theirs bound. With the view's renderbuffer bound before the swap, every anti-aliasing mode draws (off, FXAA, SMAA, SSAA 2X, MSAA 2X, 4X, 8X; the GPU allows at most 4 samples, so 8X draws 4X), as do render heights 720 and 1440 and the shadow and per-pixel lighting settings. The drawable is 1920x1080, so render heights above 1080 draw the same as Native. Blood Gulch with MSAA 2X, 512 shadow maps and per-pixel lighting: 59.9 fps over 60 s |
| Display mode | With Match Content on and the Format set to HDR, the TV switched to SDR when the game started and turned on its game mode, which it refuses in HDR (seen at the TV); the log shows `display: mode switch finished` |
| ANGLE | `tools/tvos_angle.py` built the frameworks (LC_BUILD_VERSION platform 3, tvOS 17.0, arm64) and `tools/tvos_build.py` embedded and signed them. The app logs `Renderer: Metal (ANGLE); ANGLE is in this build` and `OpenGL ES 3.0 (ANGLE 2.1.28252 git hash: c053bf85793b)`; of the capabilities only base vertex is added (S3TC, copy image, border clamp and sample counting are still absent); the render target and drawable are 1920x1080; the shader cache loads its blobs on later launches. Blood Gulch (`host:bloodgulch`, `look:1`): 59.9 fps over 60 s, slowest second 58.0, twice |
| ANGLE against Apple's OpenGL ES | In a probe on Blood Gulch (FXAA, 256 shadow maps, per-pixel lighting, both at a 1920x1080 drawable), the GPU work left at each present (`glFinish` wait) was 5.8 ms a frame with ANGLE and 8.3 ms with Apple's OpenGL ES. A 3840x2160 drawable added about 0.9 ms; MetalFX 1280x720 to 1920x1080 cost about 5 ms and to 3840x2160 13-15 ms. A busy 16-player fight was not measured |

Not checked yet: play with a controller beyond the menus (input feel in the
game, rumble), the Siri Remote in the menus, text entry, internet play with
another machine, busy fights with ANGLE, and Apple TV 4K models before the
3rd generation.
