# iOS validation

This is the device and simulator validation record, with a dated log, of the
Halo: Combat Evolved iPhone and iPad app. It applies to `main` of
`bmanturner/halo-ce-universal`: version 0.2.0 (15), synced with OpenCE `main`
`9da2a45f` (build 177). Updated 2026-10-10.
Reports of gameplay on the original iOS fork are not validation of this code.

## Current status

Verified on hardware:

- 0.2.0 (15): a signed build of commit `8a2ae846` launched on an iPad Pro 11"
  (4th gen, M2): 219 guest imports resolved (0 unavailable), Metal (ANGLE)
  renderer, main menu, audio output active ("Release — 0.2.0 (15)").
- A network co-op host on `a10` loaded, passed the cutscene skip vote and
  played with the touch controls on the iPad ("Upstream merge — main
  `f479e349`").
- Server-browser joins of public servers work on the iPad, including after a
  background and device lock of about 4 minutes ("Background resume and
  internet joins"; "Client-side additions").
- A DualSense on the iPad: its touchpad held shows the scoreboard; an Xbox
  Series X controller works on an iPhone ("Client-side additions"; "Menu and
  controller follow-up").
- Frame Rate (30 CLASSIC, 60, DISPLAY) measured on the iPad in both Low Power
  Mode states, with and without MetalFX ("Frame rate setting").
- Render height, MetalFX and Custom Edition maps on the iPad
  ("Client-side additions"); earlier iPhone 13 Pro and iPhone 15 Pro device
  checks are in the older entries.

## Open items

Not yet verified. Items the log shows as done are not listed.

- Sustained play on hardware (matches, extended campaign, split-screen co-op):
  movement and fire replication, scores, player identity and checkpoint
  continuity.
- Latency and memory on hardware; extended-play frame time on every supported
  device (frame time was measured on the iPad Pro M2 only). Frame rate: the
  on-screen cadence and battery use.
- Sound at the 1024-frame audio buffer by ear (output was active in 0.2.0).
- Upstream's FOV AND VIEWMODELS and GRAPHICS screens, in-game settings from
  the campaign pause menu, and controller removal on a device.
- Online split screen with several controllers; browser rooms.
- Voice chat on iOS: capture on a device, VOICE CHAT and VOICE VOLUME in
  Settings > Audio, push to talk with a hardware keyboard's V (there is no
  touch or controller talk button, and no echo cancellation).
- Controllers: rumble on iOS by feel; Backbone and other PlayStation hardware
  (a DualSense is verified).
- Game Mode turning on (Control Center shows the game's Game Overlay) and its
  effect on controller latency; the on-screen cadence at FRAME RATE 60 since
  the wait moved after the present.
- Hosting after a background resume; a game under way across a background
  shorter than 20 seconds; other platforms' behavior after a long `select` gap
  (the STUN and broker refresh is shared code); WebKit process termination
  recovery.
- Browser crossplay, host migration and reconnect paths on hardware with
  matching browser maps, including cold-restart admission: a restarted iOS host
  could not rejoin its former match after the browser took over, because the
  browser server rejected its selected machine slot.
- Separate internet connections and TURN-only connectivity for the optional
  WebRTC transport.
- The two Mac mission visual bugs from 0.1.5 (a transparent floor panel and the
  escape pod front, and escape-pod jitter in the ending cinematic); the macOS
  app's interactive controller, menu and crossplay coverage, launching it on
  the current build, and a separate native macOS renderer.
- Physical shake input for the debug panel; AirDrop delivery of shader reports.
- The web page in a browser, and Linux and Windows builds.

## Reproduce

```sh
python3 tools/ios_test.py
node --test tools/tests/*.test.cjs
python3 tools/ios_build.py --unsigned --ipa dist/Halo-CE-iOS-unsigned.ipa
python3 tools/ios_build.py --simulator
```

Optional real-network transport test on an Apple Silicon Mac with a GUI session:

```sh
npm install --prefix build/network-test playwright
build/network-test/node_modules/.bin/playwright install chromium
node tools/test_ios_webrtc.cjs
```

This creates a random isolated room on the public signaling services, starts
Chromium and a native WebKit probe, and checks datagrams and reliable streams.
It needs internet access but no game assets or signing account. It is not run
by default CI, because external signaling and GUI availability are variable.

## Log

### Frame pacing after the present, and Game Mode — 2026-10-10

FRAME RATE 60 used to draw a frame, wait for its slot, then present it, so the
controls the frame read were older by the wait. `halo_graphics_pace_frame` now
runs right after the present (`host_sdl.c` swap, `host_metalfx.m` present, the
latter only when MetalFX presented), so the wait falls before the next frame
reads the controls. `Info.plist` declares `LSSupportsGameMode` and the games
category (`public.app-category.games`).

Observed on the iPad Pro 11" (4th gen, M2), Low Power Mode off, the user's
settings (render height 1080, MSAA 2x, MetalFX off), frames counted from
`debug.gpu_stats`:

| Scene | FRAME RATE | fps | Slowest 1 s window |
| --- | --- | --- | --- |
| Main menu | 60 | 60.0 | 59.8 |
| Main menu | DISPLAY | 120.0 | 116.0 |
| Blood Gulch hosted, `look:1`, after the load | 60 | 60.0 | 59.9 |

The map load's window was 44 fps. A throwaway probe in the pacer measured the
wait now taken before the frame instead of before its present: 11.0 to
11.8 ms of each 16.67 ms frame in Blood Gulch, which is how much sooner a
frame is presented after it reads the controls. Not measured: the on-screen
cadence (ANGLE reports no presentation times; the present time now varies with
the frame's drawing time), the MetalFX path at 60, and whether Game Mode
turned on.

### Release — 0.2.0 (15), 2026-10-10

Published as GitHub release `apple-v0.2.0`
(https://github.com/bmanturner/halo-ce-universal/releases/tag/apple-v0.2.0)
with one unsigned IPA for iPhone and iPad, `Halo-CE-iOS-unsigned.ipa` (iOS 16+,
SHA-256 `0c796fa673f3a2ef86a90e2f3fa9c2eafa2fd85014f28821260cac6f4ae58ae7`),
built from commit `8a2ae846`, which has OpenCE `main` `9da2a45f` (build 177)
merged.

Observed: a signed build of that commit was installed on an iPad Pro 11"
(4th gen, M2) and launched. 219 guest imports resolved (0 unavailable), the
renderer was Metal (ANGLE), the main menu appeared and audio output was
active. This is a launch check, not sustained play or a listening test.

### Upstream merge — main `9da2a45f`, 2026-10-10

Merged 97 upstream commits: upstream's split of `HALO_ANDROID` into
`HALO_ARM64_GUEST` (the guest's ABI), `HALO_GLES` (the ES renderer) and
`HALO_ANDROID` (the app); field of view and viewmodel settings
(`view_fov.c`, the FOV AND VIEWMODELS and GRAPHICS screens); in-game
settings in the campaign; high-res controller buttons and reticles; a
profiling build; network version 25 (units' integrated lights); any
controller drives the menus while one person plays; saved profiles' controls
applied; the frame throttle sleeps; gamepad and render-target leaks; and
many decompilation fixes. Apple-specific integration:

- `HALO_ILP32` is retired. The iOS guest defines `HALO_ARM64_GUEST` and
  `HALO_GLES` (with `HALO_IOS`); the web build `HALO_ANDROID`,
  `HALO_ARM64_GUEST`, `HALO_GLES` and `HALO_WEB`. The fork's guards were
  mapped so that every build compiles what it did before:
  `HALO_ILP32 && !HALO_IOS` became `HALO_ANDROID`, `!HALO_ILP32 || HALO_IOS`
  `!HALO_ANDROID`, and shared mobile behaviour `HALO_ANDROID || HALO_IOS`.
  The texture upload's BGRA swizzle stays off on iOS (`HALO_GLES &&
  !HALO_IOS`), which uploads converted texels as RGBA itself.
- Upstream code now also built for the iOS guest: the screen fade scripts'
  argument fix for the ARM64 guest (`hs.c`) and 1024-frame audio callbacks
  (`dsound_sdl.c`, 512 before).
- The fork's `display.field_of_view` is removed in favour of upstream's
  `display.fov`, `display.viewmodel_fov` and `display.viewmodel_visible`.
  The settings screens were written again from `tools/port_settings.py`;
  Video Settings keeps one place per row (no per-platform packing), since the
  menu platforms cannot pack the iOS touch layout apart from Android's.
- `SDL_CloseGamepad`, which the platform layer now calls when a controller
  goes: the Apple guest calls the new `host_sdl_close_gamepad` import, which
  releases the guest's handle and SDL's reference; the web build's is a
  no-op over its fixed table.
- `tools/tests/web-memory.test.cjs` takes `enum render_target_kind` from
  `d3d8_gl.c` for upstream's render-target eviction.

Observed:

- Unsigned IPA and simulator app built. `tools/ios_test.py`, the 132
  `tools/tests/*.test.cjs` checks, the two `.mjs` browser suites, the web
  workflow's nine Python harnesses and four C regressions,
  `tools/test_touch_menu.py`, `tools/test_touch_layout.py`,
  `tools/test_cache_file_formats.py` and `tools/test_bmp_files.py` pass.
  `tools/test_linux_port.py`'s three Linux-toolchain checks and
  `tools/test_profile.py`'s two (32-bit headers, LeakSanitizer) fail on macOS;
  `tools/harness` and `tools/test_light_storage.py` need a 32-bit Linux
  toolchain, as before the merge.
- `ninja web` with Emscripten 6.0.10 links. `tools/ci_build.py android debug`
  builds the APK.
- Not verified here: sound at the new buffer size, the FOV screens and
  controller removal on a device, Linux and Windows builds.

### Frame rate setting — 2026-10-10

`display.frame_rate` (iOS): Video Settings' FRAME RATE row (30 CLASSIC, 60,
DISPLAY) in SMOOTH MOTION's place on the touch layout (menu platform
`!ios` for SMOOTH MOTION). 30 is the Xbox's path; above 30 is Smooth Motion
capped by the host (`halo_graphics_pace_frame`, before the ANGLE swap and the
MetalFX present), skipped while the panel refreshes no faster than the cap.

Why this design (measured with throwaway probes on the iPad Pro 11", M2):
ANGLE Metal ignores `eglSwapInterval` 0 and 2; `CADisplayLink`
`preferredFrameRateRange` (60,60,60), even with SDL's (80,120,120) link
lowered too, left presents at 120 fps; a deadline limiter before the present
gave 60.0 fps with every interval 14-19 ms. With Low Power Mode the panel
refreshes at 60 Hz (a display link's `targetTimestamp - timestamp` is
16.67 ms, 8.34 ms otherwise), the game already presents 60.0 fps, and the same
limiter made it stutter (53-56 fps, about 8% of frames 33 ms or longer), hence
the check.

Results (Blood Gulch hosted by `debug.network_test`, `look:1`, MSAA 2x,
render height 1440; frames counted from `debug.gpu_stats`):

| Setting | Low Power Mode | fps | Slowest 1 s window |
| --- | --- | --- | --- |
| DISPLAY | on | 60.0 | 59.8 |
| 60 | on | 60.0 | 59.8 |
| 30 CLASSIC | on | 30.0 | 30.0 |
| 60, MetalFX | on | 60.0 | 59.9 |
| DISPLAY | off | 119.9 | 116.0 |
| 60 | off | 59.7 | 56.5 |
| 30 CLASSIC | off | 30.0 | 30.0 |
| 60, MetalFX | off | 59.9 | 58.6 |
| DISPLAY, MetalFX | off | 119.8 | 116.1 |

Changing the row in the menu applied at once: the log showed
`frame rate: at most 60 a second` and `frame rate: the display's`, and the
menu ran at 120, then 60, then 120 fps. Not measured: the on-screen cadence
(ANGLE reports no presentation times) and battery use.

### Upstream merge — main `6a74eab5`, 2026-10-09

Merged 27 upstream commits: Android touch menus (`touch_input.c`,
`touch_menu.c`, `ui_widget.c`'s tap targets, `debug.touch_targets`), Android's
on-screen game controls (Java overlay, `host_touch.c`, `touch_game.c`, touch
aiming in `player_control.c`/`input_abstraction.c`), and libtiff left out of
every build. Apple-specific integration:

- iOS keeps its own touch overlay (`host_touch.m`) and the mouse pointer path
  behind `HALO_DESKTOP_INPUT`: upstream's touch pointer is the `#else` of the
  fork's `!HALO_ILP32 || HALO_IOS` block in `sdl_platform.c`, so only Android
  and the web build take it. Finger events reach `touch_input.c` only under
  `HALO_ANDROID`, so the unguarded tap-to-skip in `XInputGetState` never fires
  on iOS. The iOS guest needs no new imports (no new SDL calls; the
  `host_touch_*` calls are Android-only).
- `input.touch_controls` and `input.touch_aim_assist` use the fork's
  `_platform_mobile` (upstream's `_platform_android`) inside `#ifdef
  HALO_ANDROID`, so iOS's `config.toml` does not list them. The fork's 1–100
  mouse sensitivity (default 0.1) is kept.
- Web (`HALO_ANDROID`): `port/web/src/web_stubs.c` gives the Android host's
  six touch services as idle; the page's own controls (`site/input.js`) stay
  a virtual controller. Without them `wasm-ld` reports `host_touch_*`
  undefined (reproduced).

Observed:

- Unsigned IPA and simulator app built (the guest compiles upstream's touch
  units and `tiff_file.c`, without libtiff). `tools/ios_test.py`, the 132
  `tools/tests/*.test.cjs` checks, `tools/test_touch_menu.py` and
  `tools/test_touch_layout.py` pass. `tools/test_linux_port.py`: 8 pass; the
  three Linux-toolchain checks fail on macOS as before.
- `ninja web` with Emscripten 6.0.10 links. `tools/ci_build.py android debug`
  builds the APK.
- Not verified: the app on a device after this merge, Android touch controls
  on a device, the page in a browser, Linux and Windows builds.

### Client-side additions — 2026-10-09

Device: iPad Pro 11" (4th gen, M2, 2388x1668 at 120 Hz), DualSense, ANGLE
Metal (OpenGL ES 3.0, ANGLE 2.1.28252). Timings come from a throwaway probe
(not committed) in the host's swap: frames per second, the render thread's CPU
time per frame, GPU time per frame from `GL_EXT_disjoint_timer_query`, and
memory-watch write faults. Scene: `debug.network_test = "host:bloodgulch"`
with `debug.test_input = "look:1"`, medians of 34 one-second samples after the
game starts. All runs held 120 fps (vsync), so CPU and GPU time are the
comparison.

| Build and settings | CPU ms/frame | GPU ms/frame |
| --- | --- | --- |
| Before, MSAA 4x, shadows 1024, per-pixel lighting | 3.17 | 4.51 |
| Before, anti-aliasing off | 3.17 | 2.89 |
| Before, `display.render_height = 1080` (MSAA 4x) | 3.24 | 2.37 |
| Before, PGO only, MSAA 4x | 3.17 | 4.49 |
| After, MSAA 4x | 3.13 | 4.53 |
| After, anti-aliasing off | 3.00 | 2.95 |
| After, `display.render_height = 1080` (MSAA 4x) | 3.31 | 1.99 |

Write faults stayed at 0 per second in steady play on both builds.

- **Vertex and index mirror** (`d3d8_gl.c`): ANGLE exposes
  `GL_EXT_draw_elements_base_vertex` on its ES 3.0 context, so the iOS guest
  now uses the mirror that was limited to ES 3.2; the iOS bridge calls the EXT
  entry point. The log line ends with `base vertex 1`. About 5% less CPU per
  frame with anti-aliasing off; within noise with MSAA.
- **PGO**: the committed Linux profile builds into the guest, after the
  converter's branch-range fix (it failed with "fixup value out of range" in
  `cache_file_formats.o` without it). No measurable change in this scene.
- **Cheaper MSAA: not achieved.** A `GL_EXT_multisampled_render_to_texture`
  path cut MSAA's GPU cost from 1.6 to 0.8 ms, but ANGLE accepts that colour
  attachment only with an implicit-resolve depth renderbuffer, whose samples it
  discards at every render-pass break. Halo's environment and model shaders are
  multi-pass and test depth EQUAL against the first pass, so while textures
  still uploaded mid-frame after a map load, the BSP and objects drew flat and
  washed out for several seconds (seen on the device; fine with anti-aliasing
  off, fine on the old build). The path was removed. Invalidating the
  multisample depth before the present-time resolve gave no measurable gain
  (4.53 against 4.51 ms) and was removed too. MSAA keeps the renderbuffer path.
- **MetalFX**: `MetalFX configured: input 1546x1080, output 2388x1668, GPU
  hand-off shared event` with `display.render_height = 1080`, and input
  1031x720 with it at 0; the scaler writes the drawable directly; about 118 fps
  from the guest's frame counter. The display capture
  (`xcrun devicectl device capture screenshot`) showed a correct upscaled
  picture. The probe does not time MetalFX frames (ANGLE's swap is skipped).
- **Render height**: the Video Settings row (iOS only) and
  `display.render_height = 1080` give `iOS render target: 1546x1080`.
- **Field of view**: frames at 70, 90 and 110 show the wider views; at 110
  the first-person weapon is smaller and part of an arm shows at the bottom
  edge, as the weapon is drawn with the same camera.
- **Custom Edition**: the "cannot reserve the Custom Edition tag cache" line is
  gone; with Halo PC's `bitmaps.map`, `sounds.map` and `loc.map` in
  `Documents/CustomEdition/maps`, `deathisland` (in the game's `custom_maps`,
  for the network test's path) hosted and played ("Halo Custom Edition: using
  the install at .../Documents/CustomEdition").
- **Touchpad scoreboard**: holding the DualSense touchpad showed the
  scoreboard in a game; a touchpad click in the pause menu did nothing.
- **Multiplayer**: the final build joined a public server through the server
  browser, with correct textures at load and the touchpad scoreboard working.

Gates: `tools/ios_test.py` passes (the memory probe covers the Custom Edition
range), `node --test tools/tests/*.test.cjs` passes (132), and
`tools/test_linux_port.py`'s menu tests pass; its three Linux-toolchain tests
fail on macOS before and after. The device, Simulator and macOS apps build.

### Background resume and internet joins — 2026-10-09

Symptom: on the iPad, server browser joins failed with "could not reach"
after the app had been in the background. A fresh launch joined.

Cause, from the device console (`xcrun devicectl device process launch
--console`): iOS defuncts a suspended app's sockets. The internet play
tunnel's UDP socket read `ENOTCONN` (Winsock 10057) after the background,
and so did the game's own server browser socket (UDP 5151), so a host's
reply through a working tunnel never reached the game. The broker TCP
connections were dead too, and they reconnected only after their retry and
silence timers, past the browser's 30-second join limit.

Fix:

- `port/ios/host/posix_net.c` records each UDP socket's protocol, options and
  bound address (with the port the system chose). A socket that fails with
  `ENOTCONN`/`EPIPE` and peeks `ENOTCONN` is recreated in place with `dup2`,
  then given the same options and bound to the same port. Each revival is
  logged to `ios-runtime.log`.
- `p2p.c`: if `select` returns `PEER_TIMEOUT` past its wait, the p2p thread was
  suspended. It asks STUN for the public address again and calls the new
  `p2p_signal_reconnect()`, which reconnects every broker at once.

Observed on iPad Pro 11" (4th gen): join a public v24 server, leave, background
and lock the device for about 4 minutes, return, then join the same server.
This failed three times before the fix (a tunnel-only reopen and a broker
reconnect each fixed one layer). With both changes it succeeded: the console
showed sockets 17 and 18 recreated on their ports (the tunnel's 58275 and
5151), the same STUN mapping, and a connected host after a 307-second stop.
The native network probe passes when built with `tools/ios_test.py`'s flags.

Not verified: hosting after a resume, a game under way across a background
shorter than 20 seconds, and other platforms' behavior after a long
`select` gap (the STUN and broker refresh is shared code).

### Upstream merge — main `f479e349`, 2026-10-09

Merged 390 upstream commits (online co-op, online split screen, voice chat,
Custom Edition maps, renderer/audio work, hardening; network version 11 → 24).
Apple-specific integration in the merge:

- The browser-only `_distributed_message_migration_checkpoint` moved from
  after `batch` (where it shifted upstream's `notice`, `client_identity` and
  `pings` numbers by one) to 83, past upstream's kinds.
- The ILP32 guests keep the 128 MB contiguous window and the Xbox's texture
  and sound caches: upstream's 512 MB desktop window would overlap the guest
  image at `0x88000000`. Upstream's new ES-only `HALO_ANDROID` renderer and
  post-processing guards now use `HALO_ILP32`.
- Guest runtime: 8-byte `memcmp`, callback-less SDL audio streams for voice
  capture, `host_gl_read_buffer`; Opus and zlib compiled into the guest.
  `NSMicrophoneUsageDescription` added; `brokers.txt` bundled; Lucide's ISC
  notice (voice speaker icons) bundled with Opus's and zlib's.
- Web build: zlib, Opus and the port's game headers wired into
  `tools/web_build.py` as on the other ports; `posix_trace_marker.c` excluded;
  `memory_watch_begin_frame` and the SDL audio stream calls voice chat links
  against added to the web layer (the page records no audio); texture swizzle
  state skipped on WebGL 2, which has none.
- Scoreboards: the voice speaker is placed after the browser builds'
  " (HOST)" mark, and the split-screen score's ping column falls back to the
  host's measurement outside browser rooms.
- Regression harnesses that extract production functions were updated for
  upstream's code: the render-target cache and multisampled framebuffers
  (`web-memory.test.cjs`), the host's vehicle carry in the client tick, and
  upstream's solo-host lobby gate (`server_alone`: one player may start any
  game) in `test_web_server_policy.py`.

Observed:

- Apple guest, signed iPad app (Release, team build), unsigned IPA, simulator
  app and macOS app built. `tools/ios_test.py`, the 132
  `tools/tests/*.test.cjs` checks, the web workflow's nine Python harnesses
  and its four C regressions pass. Eight applicable `tools/test_linux_port.py`
  checks pass; the same three Linux-toolchain checks fail on macOS as before.
  `tools/harness` and `port/relay` tests need Linux and were not run.
- `ninja web` with Emscripten 6.0.10 links; the page loads its capability
  checks and room UI (game data import and play not exercised).
  `tools/ci_build.py android debug` builds the APK on this Mac. Linux and
  Windows builds were not run here.
- iPad Pro 11" (4th gen, M2): the user's NTSC-US image imported from a loose
  Documents copy; 216 guest imports resolved, Metal (ANGLE) renderer, main
  menu with music. A network co-op host on `a10` (`debug.network_test =
  "host:a10:coop"`) loaded, the cutscene skip vote passed, and gameplay
  rendered with the touch controls (device screenshot inspected). The final
  build reopened to the main menu.
- Not verified: joining a v24 public server, online split screen with
  multiple controllers, voice chat capture on device, browser rooms, and
  launching the macOS app.

### Main refresh — 0.1.9 (13), 2026-10-04

Integrated upstream main `193cbf59` and retained PR #12 head `eaa82e68` (no
newer WASM commits were available). This replaces the default native list
with upstream's in-game PC menus/browser, retaining Apple rendering, imports,
controller handling and the optional WebRTC transport. Expat and SDL key-name
bridges are included; Apple embeds 204 menu files, zero HUD replacements and
zero replacement fonts. Original logos, map pictures and other game assets
continue to come from the user's image.

- Both Release Apple apps build. Signed 0.1.9 installed and launched normally
  on iPhone 15 Pro (A17 Pro); Metal, cached shaders, touch controls and audio
  start successfully. Physical phone main-menu screenshot inspected.
- Mac displayed live signed listings and their focused row, reached the
  selected host and displayed the game-lobby preview. Created a saved profile
  through the actual menus, then joined `the BIG CTF`: admitted as machine 22,
  player added, Blood Gulch loaded and client entered the ongoing game. Own
  framebuffer captured; timed test exited cleanly. This is a smoke test, not
  sustained play validation. One earlier test run overlapped another local
  client and failed to bind its port; the successful run had no competing app.
- `tools/ios_test.py` passes (including 16 XISO cases and native socket and
  quick-play tests). The 132 `tools/tests/*.test.cjs` checks pass. Production
  player rejoin/ownership, client lifecycle and four checkpoint runtime tests
  pass under their sanitizer harnesses; fixtures now cover main's reusable
  quit-player slots and the new picked-up-weapon callback.
- Eight applicable `tools/test_linux_port.py` checks pass, including menu XML
  and setting validation. Three Linux ABI/link/listing checks require a Linux
  toolchain/sysroot and do not run successfully on this macOS host.
- Browser host policy, solo-host/end-game, migration-manager, connection-idle,
  player-name and pending-rejoin harnesses also pass. A regression caught the
  solo-host early return bypassing main's new time limit; the updated predicate
  keeps solo hosts open only while respecting the configured time limit.
- Device signature and app bundle exclusions checked. No new Mac notarization
  or MacBook delivery was performed for this revision.
- Sustained iOS matches, split-screen co-op, every new in-game setting and
  browser crossplay/migration remain unverified in this revision. Published
  PR #12 web demos were protocol 6 at the last check; native protocol remains
  11. This refresh does not claim to resolve that incompatibility.

### Observed locally

- Unsigned ARM64 iPhone/iPad app and IPA built with Xcode 27 and LLVM/LLD 23.1.2.
- ARM64 iOS simulator app compiled and linked, installed and launched on the
  iPhone 18 Pro / iOS 27 simulator. With the user's NTSC-US v5 maps
  (`01.10.12.2276`), the native main menu and Beaver Creek gameplay rendered;
  the audio callback reported active PCM output. This is simulator evidence,
  not physical-device performance or a listening test.
- The full-disc ISO uses partition offset `0x18300000`. Native extraction and
  the inspection helper produced byte-identical results for all 24 maps
  (1,860,638,720 bytes); SHA-256 hashes were compared locally. The helper now
  recognizes that offset, which the native and browser importers already used.
- Real game crossplay with Chromium's WASM build from CI revision `221ba03e`:
  the browser joined the native host's running match at tick 2991, then the
  native client joined a fresh browser-hosted match at tick 592. Both rendered
  Beaver Creek and the host logs confirmed the remote player finished loading.
  Both processes ran on the same Mac, using public signaling and WebRTC.
- Host departure worked in both directions: after terminating iOS, Chromium
  adopted the live match at tick 4542 / epoch 1; after closing the browser host,
  iOS adopted the live match at tick 1279 / epoch 1. The engine logged preserved
  match state. Score, movement/fire replication and extended continuity have
  not yet been systematically verified.
- A cold restart of the original iOS host could not join its former match
  after the browser took over: the browser server rejected the new connection
  because its selected machine slot was occupied. This is a known failing
  scenario, distinct from live-client host migration and fresh-room joining.
- Signed native ILP32 execution probe passed: layout, global/stack access,
  indirect calls, atomics and pointer zero-extension.
- Concurrent memory protection/tracking and zeroed reused mappings passed.
- Audio handoff passed 100 real SDL callbacks and 134,144 exact PCM samples.
- Display sizing and sixteen synthetic XISO regressions passed under sanitizers.
- Native virtual sockets passed packet framing, ring/counter wraparound,
  backpressure and ordered control-queue tests under ASan/UBSan.
- JavaScript suite: all 132 tests passed, including six new native adapter
  tests, including delayed acknowledgements, all 128 ping rows and migration/reconnect callbacks.
- A real macOS WebKit-to-Chromium WebRTC connection carried 4,096 exact datagram
  bytes and 262,144 exact ordered reliable-stream bytes from native virtual
  sockets and back through PR #12's transport.
  This tests the network bridge, not the game or an iPhone.

All three CI workflows passed at `221ba03e`: browser/relay/tests, iOS unsigned
IPA/simulator/probes, and Android/Linux/Windows builds. See the fork
[Actions runs](https://github.com/AttilaTheFun/halo-ce-universal/actions)
for revision-specific results. The asset-based simulator tests above used the
same engine with simulator-only launch settings added to bypass the chooser;
those settings do not affect device builds. Local host migration tests also
pass with the `HALO_IOS_BROWSER` feature guard and reject original failure cases.

### Menu and controller follow-up

- Normal launch now opens Halo's main menu. The signed update was installed on
  the designated iPhone 13 Pro (iOS 26.7.1); its screenshot confirms the menu,
  and its log reports 194 resolved imports and active PCM output.
- System Link's menu handler now opens the room chooser after startup. The
  native form uses the keyboard layout guide and a scrollable field area;
  a landscape simulator screenshot with the keyboard visible confirms the
  code field and both action buttons remain on screen.
- The real quick-play state machine passes deferred-start and repeat-start
  tests; stale packet/control/ping state is cleared between room selections.
  A simulator room launch still reaches Beaver Creek gameplay.
- SDL hardware-controller routing retains the connected primary gamepad,
  balances its owned open/close reference, logs changes and automatically
  hides/restores touch controls. The simulator's gamepad triggers hiding;
  the user subsequently confirmed an Xbox Series X controller works on the
  phone. Backbone/PlayStation hardware behavior remains unverified. The touch
  visibility toggle now hides along with the controls while connected.
- The iPhone 15 Pro is excluded from further device testing at the user's
  request. Physical-device tests now target only the iPhone 13 Pro.

### Graphics diagnostics (2026-10-03)

- Fixed GLES water draws losing their destination framebuffer after ripple
  mipmap blits. A/B simulator runs of `levels\b30\b30` show a flat dark water
  surface with the old ordering and ripples after restoring targets/raster
  state following texture preparation. Other existing simulator scene artifacts
  remain; this is not a claim of complete rendering correctness.
- iPhone 13 Pro executed MetalFX spatial scaling from 1558×720 to 2532×1170.
  The menu rendered with the Metal-backed presentation path. This establishes
  execution, not a sustained-performance improvement.
- Simulator debug panel and system share sheet rendered in landscape.
  After dismissal the controls regain first-responder status; injecting the
  UIKit shake event reopens the debug panel. Physical shake input remains a
  user check.
  An exported report parsed successfully with 57 source records and 44
  first-use draw waits; every event source reference resolved. The simulator
  correctly disables MetalFX. Actual AirDrop delivery requires user selection
  on the phone and has not been tested by automation.
- Runtime ABI, memory, audio, display sizing, 16 XISO tests, and room bridge
  regression checks pass. Full signed-device and simulator host builds pass.
- macOS menu routing and a separate native macOS renderer remain unvalidated.

### Persisted renderer selection (2026-10-03)

- Default startup selects ANGLE's Metal backend. Simulator logs identify its
  Metal renderer; iPhone 13 Pro logs identify the Apple A15 Metal GPU. The
  alternative path uses Apple's EAGL/OpenGL ES driver, with separate symbol
  dispatch throughout guest rendering, shader diagnostics, and presentation.
- MetalFX runs on the iPhone 13 Pro using an ANGLE IOSurface → MetalFX handoff
  at 1558×720 → 2532×1170. It is unavailable in OpenGL mode and in the simulator.
- Normalize decoded texture uploads to RGBA on iOS. This fixes the red/blue
  reversal seen with texture swizzling in the ANGLE simulator. Silent
  Cartographer now shows blue sky, textured geometry and water ripples.
- Simulator UI control actions save OpenGL and remove the MetalFX row; the
  following launch logs OpenGL. Metal selection restores the row and the next launch logs Metal; it is saved
  independently of the upscaling preference. Changes apply on relaunch.
- Signed device, simulator, and unsigned IPA builds pass. The public IPA
  contains unsigned embedded framework copies and bundled license notices.
  Native runtime/layout, memory, audio, display, XISO and room checks pass.
- A Metal shader-report export identifies the ANGLE backend and validates
  all source references (13 shader sources, 7 recorded events in the menu run).
- This adds a Metal backend via ANGLE, not a handwritten Metal renderer.
  Extended campaign/crossplay performance and all-device coverage remain open.

### Private-image storage and native Mac target (2026-10-03)

- Removed the touch visibility toggle; iPhone controls remain automatic and
  the native AppKit target creates no touch overlay.
- Imported the user's full 7,825,162,240-byte disc through the shared private
  storage transaction. SHA-256 readback matched; all original maps validated.
- Six synthetic storage tests pass: retained image and restart without source,
  cancellation preserving current data, corrupt import preserving current data,
  truncated stored image rejection, pointer traversal rejection, and cleanup
  restricted to owned unpublished generations. Existing 16 XISO parser tests
  and ABI/memory/audio/display/room tests also pass.
- iPhone 13 Pro: native first-launch import screen observed; a verified private
  image generation was then transferred to its container for migration testing.
  Relaunch reached Metal main menu with 198 resolved imports, touch controls
  visible, and no hide/show toggle. The full Files-picker import transaction
  was exercised in the shared native importer, not driven end-to-end by taps
  on this phone. iPhone 15 Pro was not used.
- Mac: native main-menu and Silent Cartographer framebuffers captured, with
  audio. Developer ID/hardened-runtime app launched successfully inside its
  sandbox using its private Application Support generation. Initial MetalFX
  testing found an inactive-window lookup; using the SDL Cocoa window fixed
  that, with scaler execution confirmed. Performance and interactive controller,
  menu, and crossplay coverage remain outstanding.
- Simulator build passes, but this session's simulator launch service stalled;
  the device checks above replace that attempted UI smoke test, not a claimed
  simulator pass.
- Unsigned IPA and signed DMG contain no user disc image or maps. Replacement
  HUD/title/font payloads are disabled in Apple guest builds, and the app icon
  is original geometric art. Signing does not establish legal clearance.
- The ring-artwork Mac release built from `55bbbf7e` was accepted by Apple
  on 2026-10-03. App submission: `2ee63744-83dd-4188-8f02-3c3b74697397`;
  DMG submission: `890c6e2f-6bdb-4678-883f-e5b452746859`. Both tickets were
  stapled and validated. Gatekeeper accepted the final DMG and the app mounted
  from it as `Notarized Developer ID`. The final package was also checked for
  accidental game/private data. Actual AirDrop delivery remains unverified.

### Settings and menu audio update (0.1.4 / 8)

- macOS Settings is a reusable separate window under the application menu
  (⌘,); iOS retains its shake-presented modal, now titled Settings.
- Reproduced music starvation in a real eight-second native menu tracking
  session: servicing DirectSound completions alone drained to zero PCM.
  Servicing the guarded sound streaming update on the guest main thread kept
  PCM active throughout two subsequent eight-second menu sessions and after
  closing. The SDL worker never invokes the game's completion callbacks.
- Fixed black generated icon assets by replacing offscreen AppKit drawing
  with CoreGraphics resizing. Visually inspected the regenerated ring icon;
  both Mac ICNS and iOS catalog now use the correct bitmap.
- Native ABI, memory, audio callback/deadlock, display sizing, 16 XISO cases
  and room bridge tests pass. Both physical-device and Mac release builds pass.
- At the user's updated request, installed 0.1.4 (8) on iPhone 15 Pro
  (`iPhone16,1`, A17 Pro, iOS 27.0.1) and copied the verified private disc/map
  generation into its app container. Normal launch reached the main menu,
  with 199 resolved imports, Metal rendering, active PCM output and touch
  controls. Existing saves were preserved. No controller was connected during
  this smoke test; the earlier iPhone 13 Pro controller evidence is unchanged.
- The Mac app from `37ccd843` was accepted by Apple (submission
  `a0576c71-190f-47fd-9982-698422a89e1a`). Its ticket was stapled and validated;
  Gatekeeper accepted it as Notarized Developer ID. Packaged the stapled app
  as `HaloCE-0.1.4-AppleSilicon.zip` and successfully sent it to the user's
  MacBook through Taildrop. No DMG is required for this local test release.

### First-mission feedback / 0.1.5 (9)

- User completed the first mission on Mac and reported compilation hitches,
  two transparent surfaces (floor panel and escape-pod front), escape-pod
  jitter in the ending cinematic, and nonfunctional Dock Quit.
- The received report identified build 7 / `55bbbf7e`, ANGLE Metal on M4 Max,
  158 sources, zero timing events and zero dropped events. Replaying all 158
  shader sources with the bundled ANGLE driver on M6 compiled successfully.
  This does not rule out link, texture, material, draw-state or geometry bugs
  on the reported M4 Max. The two visual bugs are still unresolved; no
  speculative rendering or animation patch has been applied.
- Fixed AppKit creation order: initializing SDL video first installs
  SDL3Application and its standard app menu. Before this, pre-creating
  NSApplication skipped both menu setup and the terminate-to-quit bridge.
  Reuses SDL’s Settings placeholder to avoid AppKit stealing Cmd+, from a
  duplicate menu item. Real application-menu Quit and the Dock termination selector both produce
  a guest quit event and exit 0. Settings is tested through the actual menu.
- Added a bounded, GPU/OS/driver-scoped persistent ANGLE blob cache. A fresh
  launch loaded a compiled blob from disk. Callback tests cover disk reload,
  small/negative output buffer sizes, concurrent writes and 64 MiB eviction.
  First-use Metal pipeline specialization can still hitch; no frame-time
  performance claim is made from cache hits alone.
- Schema 2 shader reports record compile/link stalls even with optional GPU
  recording off, and include program/source associations. A real menu run
  exported a valid report with 11 programs / 13 sources, all references
  resolved, and a timing event while first-use GPU recording was false.
- The signed sandboxed 0.1.5 app launched with its private image store,
  populated its shader cache, opened Settings through the application menu,
  and exited 0 through Quit. Native menu audio remained active through an
  8.24-second tracking session. Mac and iOS device builds and runtime/cache
  probes passed; this update was not installed on an iPhone.
- Apple accepted the app from `1235f980` (submission
  `47e2d143-3182-4e31-aa4b-43bdd1e69ff3`); its ticket was stapled and Gatekeeper
  accepted it as Notarized Developer ID. Sent `HaloCE-0.1.5-AppleSilicon.zip`
  to the user's MacBook via Taildrop. The visual mission bugs above remain
  open pending a reproducible scene/checkpoint or clip.

### Application naming / 0.1.6 (10)

- Distributed Mac bundle: `Halo: Combat Evolved.app`. Menu heading and SDL
  application metadata use the full title; localized InfoPlist strings give
  Finder/Dock the short label `Halo`. The native Foundation display-name
  lookup on the built, correctly named bundle returns `Halo`; localized
  CFBundleName remains `Halo: Combat Evolved`. iOS CFBundleDisplayName is
  `Halo`. Bundle identifiers and the private data locations are unchanged.
- Installed and launched on iPhone 15 Pro; CoreDevice lists `Halo`, 0.1.6
  (10). Mac Settings/Quit smoke checks pass. Apple accepted the app from
  `2e6febc6` (submission `1c361f6d-56c2-4aab-8dce-7628b6fc5232`); stapling
  and Gatekeeper checks pass. After extracting the final ZIP, the raw bundle
  name, full application name and short localized icon label still match.
  Sent `Halo-0.1.6-AppleSilicon.zip` to the MacBook using Taildrop.

### Public servers — 0.1.7 (11), 2026-10-04

- Signed iPhone 15 Pro build installed as `com.LoganShire.HaloCE`, preserving
  imported game data and saves. Native networking is now the default.
- Physical phone discovered 14 signed protocol-11 public listings. An initial
  join investigation exposed the missing Darwin `recvmsg` sockaddr conversion;
  the new native TCP/UDP sanitizer test reproduces that defect and passes with
  the fix. This is separate from the earlier public-WASM protocol-6 mismatch.
- Real Mac ARM64 client joined `[D] Slayer` through public MQTT discovery and
  the native internet tunnel; the game logged successful machine admission,
  player registration and `Multiplayer playing: Multiplayer is ready.` No
  local fixture or WebRTC relay was used. This is a join/load smoke test,
  not a sustained match or movement/fire replication test.
- The first native join exposed upstream's protocol-11 settings extension
  (13,092 to 13,120 bytes). Imported the PC game-rule extension from `c9ee319a`
  and its client gameplay handling. Older incoming records expand to default
  rules; Apple browser-room hosting emits the old settings layout. Browser
  crossplay and mixed-version checkpoint migration need fresh validation;
  the historical results above do not establish those for 0.1.7.
- Quick-play timing regression: selecting a room/server inside the native
  command pump advances the clock. Refreshing `now` after pumping avoids an
  unsigned-wrap timeout immediately after selection. The production state
  machine test covers this and passes with sanitizers.
- `python3 tools/ios_test.py` passed: guest ABI/memory, audio, display, 16 XISO
  tests, virtual room queues/sockets, shader cache, real Darwin TCP/UDP and
  quick-play lifecycle. Both Apple release targets compiled successfully.
- Server UI is an Apple presentation of upstream `c04765d7` P2P discovery,
  not PR #69's optional HTTP list. Native automatic UPnP and hosting UI are
  outside this change; NAT reachability is not guaranteed for every server.

Developer-only launch variables: `HALO_NATIVE_TEST_BROWSER=1` opens the browser
20 seconds after game event pumping starts; optional `HALO_NATIVE_TEST_JOIN`
selects exactly one named server once. Neither is set in ordinary launches.

### Visible join progress — 0.1.8 (12), 2026-10-04

- The reported phone join to MassiveFlagWar was accepted by the server and
  reached player setup; no rejection was logged before event processing stopped.
  The old UI exposed the main menu while asynchronous setup continued.
- Keep a native progress window over the menus while the game continues its
  normal frame/network loop. Restore SDL keyboard focus, show engine setup
  phases, allow cancellation, and dismiss only for gameplay or a terminal
  result. Early termination now produces a visible explanation.
- The updated Mac client late-joined MassiveFlagWar with 35 players and
  reached gameplay. The iPhone 15 Pro then joined with 36 players: native
  progress appeared, machine/player admission completed, Blood Gulch loaded,
  and `Multiplayer playing` dismissed progress. A screenshot verified the
  landscape progress presentation and Cancel control.
- Found a test-only interference: the delayed automatic browser launch fired
  at 20 seconds after the user had already manually joined at 17 seconds. It
  disposed the live client, reopened the browser, and caused a client assertion.
  Manual browser/room opening now consumes that scheduled test navigation.
  Final signed installation was launched WITHOUT automatic navigation/join
  environment variables. This smoke test is not sustained gameplay validation.
- Both Apple release builds pass, the device signature verifies, and the full
  `tools/ios_test.py` suite passes. Existing campaign rendering issues and
  browser/WebRTC interoperability limitations are unchanged.


### Merge of OpenCE `e0b581b1` (build 188) — 2026-10-11

- Integration: OpenCE main `e0b581b1` (build 188), network version 26.
  Removed from the fork: browser rooms in the Apple apps (WKWebView, `room.js`,
  the room bridge), quick play, host migration, the browser scoreboard ping,
  the fork's own web port and its relay, and the native server-list window
  (it joined through quick play); the in-game server browser is used. Added:
  the Apple hosts build upstream's `posix_dtls.c` with Mbed TLS
  (`port/apple/dtls.cmake`), so the Apple apps accept browsers' WebRTC. Menus:
  `ios` is a fourth `platform` place; settings have a `_platform_ios` bit.
- Builds (this Mac, Homebrew clang 21, so without PGO): signed iPad app
  (Release, team build), macOS app, Apple TV app (ANGLE, maps embedded,
  installed), and from the same tree upstream's web build (`ninja web`) and
  `ninja android`.
- Gates: `tools/ios_test.py` passes (guest ABI/memory including the Custom
  Edition range, audio, display, XISO, shader cache, native TCP/UDP). pytest:
  test_touch_menu, test_cache_file_formats, test_bmp_files and test_web_build
  pass, except `test_the_sockets_inside_the_page`, which fails on macOS on
  upstream's own tree too. test_profile's two failures are the platform's (ASan
  leak detection is unsupported on macOS; the iOS-configured build.ninja's
  `-mcpu=apple-m4`). `node --test` on port/web/tests sw/xiso: 13 pass.
  `tools/test_touch_layout.py` passes. `tools/test_linux_port.py`: 18 pass; its
  Linux-toolchain checks fail on macOS as on upstream (xdk headers, weak
  references, system link bots, p2p signatures). `tools/harness` needs a 32-bit
  host and does not run on Apple silicon.
- Devices: iPad Pro 11-inch (4th generation, iPad14,3, iPadOS 27.0, 24A435);
  Apple TV 4K (3rd generation, AppleTV14,1, tvOS 27.0, 24J361).
- iPad hosting Blood Gulch (`debug.network_test host:bloodgulch`, 75 s):
  internet play invite and STUN mapping, the game ran, exit 0.
- Browser to native over WebRTC: a headless Chromium running upstream's web
  build joined the iPad's game by its invite (`?join=`). The iPad logged
  "WebRTC connected to player …'s browser" and both logged players 0 and 1
  playing. The same with the Apple TV hosting. Repeated on the final build for
  the iPad.
- Apple TV to a native upstream host: in a server-browser test (`browse`) the
  Apple TV joined a public dedicated game ("[D] Big Team", Beaver Creek)
  instead of the test's own, reached it over internet play, loaded the map and
  spawned (about 18 seconds, 1081 packets sent, 1137 received) before it was
  stopped.
- Screenshots (`xcrun devicectl device capture screenshot`): in a game on both
  devices the HUD numbers, shield and health meters, motion tracker and weapon
  draw correctly. Video Setup shows V-SYNC, RENDER HEIGHT, FRAME RATE,
  GRAPHICS and FOV AND VIEWMODELS on both; the iPad's FOV AND VIEWMODELS screen
  shows upstream's ARM SHIELDS, LEGS and SHIELD COLOR.
- Existing installs: config.toml files from earlier versions say
  `network.online = false`; the Apple host still sets `HALO_NET_ONLINE=1`, so
  internet play stays on after an update.
- Not verified: system link on the local network between the iPad and the
  Apple TV (the Apple TV kept "searching for games"; never verified before);
  an invite join between two Apple devices; rumble/remote; the Mac app was
  built but not run.
