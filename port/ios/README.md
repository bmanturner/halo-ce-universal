# Build and install Halo: CE on iPhone and iPad

This directory builds a native ARM64 iOS app around the existing game's ILP32
runtime. It uses SDL3, OpenGL ES 3, UIKit touch controls, and the user's original
Xbox map files. The game files are separate from the application and are never
included in source control.

The Home Screen name is **Halo**. The portable ILP32 runtime lives in
`port/runtime`; UIKit, Darwin, touch, audio, and the native loader live here.
The existing Android, Linux, Windows and web build targets are retained.

The icon is original abstract ringworld artwork; see [icon notes](ICON.md). Apple builds
exclude the bundled replacement HUD/title/font assets and require a user-owned
disc image. See [distribution status](../apple/DISTRIBUTION.md).

## Build

Use an Apple Silicon Mac with Xcode, its iOS SDK, Python 3, CMake, Ninja, LLVM
and LLD. The validated toolchain is Xcode 27 and Homebrew LLVM/LLD 23.1.2.
The deployment target is iOS 16, but older OS versions have not been validated.
Install dependencies using `brew install cmake ninja llvm lld sdl3 pkgconf`.
Open Xcode once to accept its license and install the iOS platform. Ensure
`xcode-select -p` points into full Xcode, not only Command Line Tools.
For signed device builds, add your Apple account in Xcode Settings > Accounts.
Your provisioning profile must cover the device and chosen bundle identifier.
See [Apple's device setup guide](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).

From the repository root:

```sh
# Native ARM64 simulator app (no signing).
python3 tools/ios_build.py --simulator

# Device app, signed with your Apple development team.
python3 tools/ios_build.py --team YOUR_TEAM_ID --bundle-id com.yourname.haloce

# Unsigned device IPA (no Apple account needed to build).
python3 tools/ios_build.py --unsigned --ipa dist/Halo-CE-iOS-unsigned.ipa
```

The script fetches pinned Khronos headers, SDL release-3.4.16 and musl 1.2.5,
compiles the guest, embeds it into signed application text, and builds the host.
Specify `--llvm` and `--lld` for non-default toolchain locations.
Game assertions remain enabled. An Xcode `Release` host configuration does not
disable the game's assertions. The guest is built with profile-guided
optimisation from the committed Linux profile (`pgo/halo_linux.profdata`; the
`--llvm` clang must be 22 or newer, or it builds without), and without LTO.
Because the assembly converter makes each memory access three instructions,
the guest asks LLVM to relax conditional branches at a quarter of their reach
(`tools/ios_guest_build.py`); otherwise inlining can push one out of range.

Outputs:

- `build/ios/app-device/Release-iphoneos/HaloCE.app`
- `build/ios/app-simulator/Release-iphonesimulator/HaloCE.app`
- `build/ios/app-unsigned/Release-iphoneos/HaloCE.app`
- `dist/Halo-CE-iOS-unsigned.ipa` and its `.sha256` checksum when requested

The default bundle identifier is `org.haloce.ios`. Set `--bundle-id` to one
covered by your signing profile. `--ipa PATH` can also package a signed build;
only unsigned builds are suitable for this project's public release workflow.
Code signing and provisioning must succeed
before installation. No jailbreak, JIT entitlement, or writable executable
memory is used.

## Simulator smoke tests

After installing the simulator app and importing an ISO through the app,
launch it and terminate it between launches:

```sh
xcrun simctl launch SIMULATOR_UDID org.haloce.ios
```

Normal launches open the game menus.

## Install and add game data

The cache validator accepts these exact Xbox v5 cache builds on iOS:

- PAL: `01.01.14.2342`
- NTSC-US: `01.10.12.2276` (experimental compatibility)

### Import on the device

1. Sign/install the IPA with your own account (the unsigned IPA is on the
   project's Releases page), then open **Halo**.
2. Tap **Choose Halo ISO** and select your `.iso` or `.xiso` in Files (On My
   iPhone/iPad, iCloud Drive, or another Files provider). Compressed ZIP/7z
   archives and PC/MCC disc images are not supported.
3. The app copies the image into a private generation, verifies the copy with
   SHA-256 readback, and validates the Xbox filesystem, cache version/build,
   and complete campaign map set during extraction. Cancel safely stops it.
   Once finished, the game starts automatically.

The image is opened through the system document picker with coordinated,
security-scoped access. A cloud image may need to download before extraction.
Leave enough local storage for the retained image plus approximately 1.9 GB
of extracted maps, and any separate source copy already on the phone.
Nothing is fetched from a game-download service, and the source image is never
modified or deleted. Subsequent launches use the private image/map generation
without accessing the original Files location.

You can also copy **one** `.iso` or `.xiso` directly into Halo: CE's Documents
folder using Finder's Files tab or Files > On My iPhone/iPad > Halo: CE, then
launch the app. It detects and imports that image when game data is missing.
If several images are present, choose one with the picker. After a successful
import, the original loose source file can be removed. Keep the retained
`game-UUID/disc.iso` and its map cache; deleting these requires re-import.

Imports run in a private staging directory. Invalid or cancelled imports do
not replace the current game generation. Owned incomplete imports are cleaned
up on next launch. Existing committed generations are preserved. Saves
and profiles stay in `Documents/save` throughout.

### Install a source build

List devices with `xcrun devicectl list devices`. Enable Developer Mode when
iOS requests it, pair/trust the Mac, and keep the device unlocked during
installation. Replace `DEVICE_UDID` and the example bundle identifier with
your device and the ID used for signing.

```sh
xcrun devicectl device install app --device DEVICE_UDID \
  build/ios/app-device/Release-iphoneos/HaloCE.app
xcrun devicectl device process launch --device DEVICE_UDID com.yourname.haloce
```

Downloaded unsigned IPAs (see Releases in [FORK.md](../../FORK.md#releases))
must first be signed with your own Apple account.
Use [`tools/ios_resign.sh`](../../tools/ios_resign.sh) with your local signing
identity and device provisioning profile; see the [re-signing and installation
guide](RESIGNING.md) for the complete setup and commands.
For packaged-IPA signing instructions, see the official
[AltStore Classic setup guide](https://faq.altstore.io/) or
[Sideloadly FAQ](https://sideloadly.io/faq). These signing tools have not been
validated as part of this port; direct Xcode builds have been tested on iPhone 13 Pro. Follow your signing tool's refresh instructions before
the provisioning profile expires. Keep the same account and bundle identifier
when updating to preserve the app's data.

### Optional manual extraction

The Mac helper remains available for inspecting your XISO or preparing maps
manually. It preserves original bytes and records build IDs, sizes and SHA-256
hashes. Existing output files are never replaced.

```sh
python3 tools/ios_extract_assets.py '/path/to/Halo.xiso.iso'
python3 tools/ios_extract_assets.py '/path/to/Halo.xiso.iso' --output assets
```

Manual map extraction is an inspection tool; maps alone no longer satisfy
first-launch setup. Import the image through the app to retain its verified
private copy. `config.toml` and `ios-runtime.log` stay in Documents; the game's
`debug.txt` is in the active `game-UUID` folder. Back up `Documents/save`
before uninstalling or changing bundle IDs.

## Controls

### Resolution

Video Settings > RENDER HEIGHT sets the internal render height: NATIVE (the
default), 1440, 1200, 1080, 900 or 720. It applies after a restart. NATIVE uses
the display's physical resolution with a Retina drawable and matching internal
color/depth targets. The game retains its original logical layout coordinates,
so the HUD and touch controls keep their size. With MetalFX on, MetalFX
upscales from the chosen height (720 if NATIVE).

The row stores `display.render_height` in `Documents/config.toml`; `0` is
NATIVE and the other values match the menu. `display.screen_width = 0` fits
the display; `640` selects original 4:3.

The renderer preserves the selected aspect ratio and caps the render size to
the drawable and GPU texture limit. Existing configuration files without
`render_height` use native resolution. Apple graphics diagnostics
are available from the shake modal or Mac Settings window, as described below.

### Frame rate

`display.frame_rate` (the FRAME RATE row in Video Settings) replaces Smooth
Motion on the touch layout, and `display.interpolation` is not used there. `0`
(DISPLAY) draws a frame for each refresh of the display; `30` (30 CLASSIC) is
the Xbox's 30 frames each second, not blended; above `30` (the menu offers 60)
is Smooth Motion capped at that rate. ANGLE's Metal backend ignores the swap
interval, so the host paces the frames itself: it presents each frame as soon
as it is drawn, then waits for the next frame's slot, so the next frame reads
the controls as late as possible. It does not pace them when the display
already refreshes no faster than the cap, such as in Low Power Mode. The Mac
app keeps the SMOOTH MOTION row.

The app declares Game Mode support (`LSSupportsGameMode` and the games
category in `Info.plist`), so iPadOS and iOS 18 or later turn on Game Mode
while it is full screen: it gets priority on the CPU and GPU, and Bluetooth
controllers and AirPods are polled twice as often. Control Center shows it
under the game's Game Overlay.

### Touch and controller input

The left stick moves and the right stick aims. The four arrows navigate menus.
A selects/jumps; B returns/melees; X reloads/uses; Y changes weapons. Separate
buttons provide fire, grenade, crouch, zoom, flashlight, grenade selection,
and pause. Hold buttons for held actions. Touch controls hide automatically
when a hardware controller connects and return when it disconnects. There is
no hide/show toggle. The native Mac app never creates a touch overlay.
Compatible Backbone, Xbox and PlayStation controllers use SDL's iOS gamepad
backend. Pair Bluetooth controllers in iOS Settings > Bluetooth before or
while the app runs; attach a compatible wired Backbone directly to the phone.
See [Apple's controller pairing guide](https://support.apple.com/en-ie/111099).
The USB-C Backbone requires a compatible USB-C device; it cannot plug directly
into the Lightning iPhone 13 Pro.

The first hardware controller shares player one with the on-screen controls.
Player one's controller stays selected while connected, even if another
controller is attached.

Settings > Gamepads > BUTTON LAYOUT includes BUMPER JUMPER. Click and hold a
DualSense or DualShock 4 touchpad to show the scoreboard; the controller's
Back, Create or Share button also shows it, as in the original game.

| Action | Xbox / standard labels | PlayStation labels |
| --- | --- | --- |
| Select / jump | A | Cross |
| Back / melee | B | Circle |
| Reload / use | X | Square |
| Switch weapon | Y | Triangle |
| Fire / grenade | RT / LT | R2 / L2 |
| Flashlight / switch grenade | RB / LB | R1 / L1 |
| Crouch / zoom | Left / right stick click | L3 / R3 |
| Pause | Menu / Start | Options |
| Scoreboard | Back / View | Share / Create / Touchpad (click and hold) |

The user confirmed an Xbox Series X controller works on the iPhone and a
DualSense on the iPad. Backbone controllers have not been verified. The game
sends basic rumble to the controller; rumble on iOS has not been checked by
feel. Adaptive triggers, the lightbar and gyro are not supported.
Developer console messages, frame counters, profiling text and the menu's build label are omitted
from the game picture. Diagnostic log files remain available in Documents.

The app supports landscape only on iPhone and iPad, including XISO import and
the Files picker. On iPadOS 26 and later it also requests the interface
orientation lock for the full-screen scene; portrait is excluded from the
app's orientation masks. iPadOS controls windowed multitasking and may
letterbox the landscape app when a full-screen orientation lock is unavailable.
Public-server discovery and native UDP/KCP connections are always on in the Apple apps.
Bink intro videos remain unsupported by the upstream port.

## Public server browser

Open **Multiplayer → Join Game → Server Browser** to browse public native
servers using upstream's in-game PC-style menus. Use the controller or the
on-screen controls on iOS; macOS also supports mouse and keyboard. Select a
server, inspect its game details, then join. The list shows maps, game types,
player counts and connection status, with Refresh and Back buttons.
Only listings with this build's network version (`HALO_PORT_NETWORK_VERSION`,
currently 26) are shown, so hosts must run a current upstream build. A
matching map from the user's imported image is required; discovery does not
guarantee reachability. Keep the app in the foreground while connecting and
playing: internet play drops a peer it has not heard from in 20 seconds, so
a game under way does not survive a longer stay in the background.

iOS reclaims a suspended app's sockets. After the app returns, the host
(`host/posix_net.c`) recreates each reclaimed UDP socket in place, at the same
descriptor and port, with its options. Internet play notices that its thread
was stopped longer than a peer lasts, asks STUN for the public address again
and reconnects the MQTT brokers at once (`p2p.c`, `p2p_signal.c`), so the
server browser can join without restarting the app. TCP sockets are not
recreated: a connection open during the suspension is lost.

This integrates OpenCE `main` through `e0b581b1` (OpenCE build 188), including
the in-game server browser, online co-op campaign, online split screen (ADD
PLAYER in the lobby, one extra controller per player), password-protected
lobbies, vote kick, voice chat, field of view and viewmodel settings (Video
Settings > FOV AND VIEWMODELS, with LEGS and ARM SHIELDS), SHIELD COLOR and
SHIELD GLOW settings, a GRAPHICS screen, settings from the campaign's
pause menu, high-resolution controller buttons and weapon reticles, and
upstream's renderer, audio, leak and hardening fixes. Upstream's Android touch
menus and on-screen controls are not used on iOS, which keeps its own overlay
(`host/host_touch.m`). Discovery uses Ed25519 signatures, MQTT brokers (the
bundled `brokers.txt`, copied beside `config.toml` at launch) and invite
joining. Connections use the shared STUN, UDP tunnel and KCP implementation;
automatic router port forwarding is not implemented on Apple. With
`display.menus = "xbox"` the same in-game server browser is used.

Voice chat uses SDL's default input and output: the Apple guest does not
enumerate SDL audio devices. iOS hides the device rows; the Mac app, which
takes the desktop settings rows, lists only SYSTEM DEFAULT in them, and its
desktop display rows (mode, resolution, window size, scaling) do nothing: the
window and display code in `port/linux/src/sdl_platform.c` is compiled out of
the Apple guest by `#if !defined(HALO_ANDROID) && !defined(HALO_IOS)`.
Settings > Audio on iOS shows VOICE CHAT (PUSH TO TALK, OPEN MIC or OFF) and
VOICE VOLUME. iOS asks for microphone access the first time voice opens the
microphone (open mic, or push to talk on a hardware keyboard's V); there is
no touch or controller push-to-talk button. With push to talk the microphone
opens on the first press and stays open until you leave the network game.
There is no echo cancellation, so use headphones with open mic. Voice capture
has not been tested on a device.

Halo Custom Edition maps run on Apple. The guest's 23 MB tag cache has a fixed
address inside the arena's general pool; the host marks those pages used at
start and hands them to the reservation (host_memory.c), so they never go to
another allocation. To play them, copy the Custom Edition maps plus
bitmaps.map, sounds.map and loc.map from a Halo PC / Custom Edition install
into Files > Halo (the app) > CustomEdition > maps (the app creates the
folder, and the same CustomEdition folder in the app's data on the Mac). It
sits beside, not inside, the imported game's folder, so re-importing the game
keeps it. The Xbox-sized texture and sound caches can make very large
community maps draw default textures.

Upstream commit `c9ee319a` added 28 bytes of PC game rules to the settings
record (network version 11). The relevant rule logic and record layout are
included. Receiving older settings records supplies the original default
rules.

### Internet play with browsers

Browsers join through upstream's WebRTC support: the game side is
`port/linux/src/p2p_webrtc.c`, and the DTLS under it is `posix_dtls.c`, linked
into the app's host with the vendored mbedtls (`port/third_party/mbedtls`) like
the other `posix_*.c` files. There is no WebKit or JavaScript in the app and no
separate browser transport. Both players need matching original Xbox maps.

### Provenance and scope

The signed ARM64 ILP32 runtime, memory layout, UIKit input, GLES renderer,
XISO importer, and build tooling are imported/adapted from
[NicholasDominici/halo-ce-ios](https://github.com/NicholasDominici/halo-ce-ios/tree/3f2c14101d3ae1c7f0c0a11993a43407fadbeb46),
branch `ios-port`, on top of OpenCE's game and network source with its musl
math; other platforms are preserved. Apple distribution builds omit the embedded HUD/title/font
replacements. This target builds iPhone/iPad apps; [port/macos](../macos/README.md)
builds the native Mac app and [port/tvos](../tvos/README.md) the Apple TV app.
A dedicated visionOS product remains open.

## How the port works

The game relies on 32-bit pointers in its data structures. Apple's current
ARM64 iOS binaries require their first 4 GB of address space to remain unmapped,
so the game's 32-bit pointers are represented as offsets into an aligned
native arena. This is native compiled code, not an Android emulator.

`tools/ios_asm_convert.py` lifts compiled guest memory accesses and indirect
branches into an aligned 4 GB arena using reserved registers x15 and x27.
Guest pointer values and structure layouts stay 32-bit. PC-relative addresses
are normalized back to guest offsets. A small signed assembly entry switches
to an arena stack; host bridges translate pointers at the ABI boundary.

Guest code is embedded in the app's signed `__TEXT` and aliased into the arena
read/execute with `vm_remap`. Guest data is separately writable. The host
translates Linux/musl calls to Darwin and handles Apple's 16 KB pages. Explicit
Xbox 4 KB read-only regions protect only complete native pages, preserving
writable neighboring buffers. Texture dirty tracking works at 16 KB granularity
and serializes protection changes against concurrent streaming writers.

The generated bridge resolves all guest imports before entering the game.
The portable runtime and assembly conversion tools were derived from the
upstream ARM64 port, with the iOS host and address model imported from NicholasDominici/halo-ce-ios.
SDL/UIKit calls stay on the UI thread; guest workers and audio callbacks run on
arena stacks with the same translation convention.
The audio worker stages mixed PCM for the SDL callback to submit on its own
thread. This avoids taking SDL's stream lock from a worker while the callback
holds that lock and waits for the worker.

## Regression checks

```sh
brew install sdl3 pkgconf  # Native macOS SDL library for the audio regression.
python3 tools/ios_test.py
```

This executes the translated guest on signed native pages and checks 32-bit
structure layout, global/stack access, function pointers, atomic operations,
and zero-extension of addresses. A separate stress test covers concurrent
texture page tracking, fresh zeroed mappings, and the map inflater's writable
4 KB tail beside a read-only buffer.
The SDL regression checks 100 callbacks and 134,144 exact PCM samples,
including reused guest stack buffers and a request larger than 64 KB.
The native XISO importer is tested under AddressSanitizer and UBSan with
synthetic disc images: exact byte preservation, supported builds, invalid
headers, missing maps, truncated extents, cycles, unsafe names, duplicate
files, cancellation/retry, existing files, and malformed directory mutations.

These tests do not replace a device campaign test. See [the validation record](VALIDATION.md)
for observed device/simulator behavior and remaining limitations.

## Simulator

Build with `--simulator`, then select and boot an ARM64 iPhone or iPad simulator
in Xcode. With exactly one simulator booted:

```sh
xcrun simctl install booted build/ios/app-simulator/Release-iphonesimulator/HaloCE.app
HALO_SIM_DATA=$(xcrun simctl get_app_container booted org.haloce.ios data)
cp "/path/to/your/game.xiso" "$HALO_SIM_DATA/Documents/game.xiso"
xcrun simctl launch booted org.haloce.ios
```

Use an explicit simulator ID instead of `booted` when more than one is running.
The app imports the single loose image on first launch. Simulator graphics
are slow; validate performance on a physical device.

## Troubleshooting

- **Signing fails:** check the Apple account in Xcode, team ID, unique bundle
  identifier, device registration, and profile expiration. The script permits
  Xcode provisioning updates; it never supplies somebody else's certificate.
- **App fails to launch:** confirm it was signed for your device, trust the
  developer if requested, and enable Developer Mode. An unsigned IPA will not launch.
- **Menu never appears or maps fail validation:** check `Documents/game-UUID/maps/ui.map`,
  confirm exact original Xbox build IDs above, and inspect `ios-runtime.log`
  and the active generation’s `debug.txt`. Re-import if the retained image or
  validated map cache is incomplete.
- **Changing your bundle ID:** iOS treats this as a separate app/container.
  Keep the same ID when updating and back up `Documents/save` before uninstalling.
- **Audio issues:** share device/OS and output route along with the runtime
  log. The regression suite checks PCM handoff; it does not test every route.

## Graphics debug and shader reports

Shake the iPhone/iPad to open the graphics settings modal. The dedicated
AppKit/macOS target opens a separate **Settings…** window from the application
menu (⌘,). Both retain the graphics options below; the Mac build uses Metal.

- **Renderer** persists the choice between **Metal** (the default) and
  **OpenGL**. Metal uses ANGLE's Metal backend for game rendering; OpenGL
  uses Apple's OpenGL ES driver. Relaunch the app after changing renderers.
  Shader/texture/command translation still starts from the shared GLES API;
  this is not a separate handwritten Metal engine.
- **MetalFX spatial upscaling** is shown only when Metal is selected. It is
  opt-in, requires a supported physical device, and is unavailable in Apple's
  simulator SDK. The switch stores the preference and applies after you relaunch
  the app; the running app keeps the state it launched with, because the game
  sizes its render targets once at startup. When on, the game renders at 720
  lines, or at `display.render_height` when that is set below the display's own
  height, and MetalFX upscales that to the display resolution. It is spatial,
  not temporal, upscaling. ANGLE copies each frame into one of two shared
  IOSurface textures and signals a Metal shared event on the GPU
  (`EGL_ANGLE_metal_shared_event_sync`); the MetalFX command buffer waits for it
  on the GPU, writes straight into the layer's drawable and presents it, so the
  CPU does not wait for each frame (at most two are in flight). The runtime log
  reports the input and output sizes and which hand-off is used; without the
  extension the hand-off falls back to `glFinish`. With MetalFX on, it presents
  once per frame and ANGLE's own swap is skipped. Allocation or command-buffer
  failure stops MetalFX and returns to normal Metal presentation. Enabling it is
  not a guarantee of higher frame rates. OpenGL mode never enables MetalFX.
- **Record shader stalls** records compile/link completion times and each
  program's first draw after recording starts, keeping events ≥ 2 ms and
  compile/link failures. First-use measurements drain earlier GPU work and
  wait for the draw, so recording adds overhead. They can reveal deferred
  compilation but also include drawing cost; they are not isolated compiler
  measurements and do not cover every driver pipeline variant.
- **Share shader report…** opens the system share sheet. Choose AirDrop and
  your Mac. Reports contain generated GLSL, source hashes/stages, program
  combinations, timings, device/OS/GPU and build metadata. They contain no
  game maps or saves. Nothing is sent until you choose a sharing destination.
  Capture retains up to 32 MiB of sources and 4096 events; dropped records are
  counted. The five latest exports are retained in Caches/ShaderReports.

The renderer and both switches persist across launches. For useful reports, enable recording,
restart the app, visit the affected level, then share the report. Turn recording
off again for normal play. Clear resets events and first-use tracking.
Reports provide inputs for future shader warm-up updates; this GLES renderer
currently has no bundled precompiled pipeline catalog. A report is not a
portable Metal binary archive, and cannot guarantee removal of all future
first-use stalls.

For automated diagnostics, launch environments `HALO_IOS_TEST_DEBUG_UI=1`,
`HALO_IOS_TEST_SHADER_CAPTURE=1`, and `HALO_IOS_TEST_METALFX=1` open the panel,
start capture, or request MetalFX respectively, without changing saved settings.

`HALO_IOS_TEST_RENDERER=metal` or `opengl` overrides the renderer for that
launch only. It does not change the user's saved preference.

The game and host are built from source. `tools/ios_angle.py` downloads the
pinned ANGLE runtime frameworks packaged by
[EdgeFirstAI/angle-package](https://github.com/EdgeFirstAI/angle-package),
version `v2.1.28252` / source `c053bf85793bbb83016b1196d04e5df3594b9bcc`.
The archive's SHA-256 is checked before extraction. Device and simulator
slices are embedded separately; device frameworks are signed with the app's
team. Public unsigned IPAs strip the vendor signatures from the embedded
copies. Framework binaries stay in ignored build directories. The package's
build scripts and pinned source revision are available upstream for rebuilding.
