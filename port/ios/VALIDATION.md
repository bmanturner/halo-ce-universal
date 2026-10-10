# iOS/browser integration validation

This record applies to `apple/ios-upstream-merge` (from
`apple/ios-web-multiplayer`), based on PR #12 at
`eaa82e6803f3d3e67c91d7f2fa2b15ee04e195f5` and the iOS fork at
`3f2c14101d3ae1c7f0c0a11993a43407fadbeb46`. Updated 2026-10-09.
Reports of gameplay on the original iOS fork are not validation of this merge.

## Client-side additions — 2026-10-09

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

## Background resume and internet joins — 2026-10-09

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

## Upstream merge — main `f479e349`, 2026-10-09

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

## Main refresh — 0.1.9 (13), 2026-10-04

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

## Observed locally

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

## Menu and controller follow-up

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

## Required before marking ready

- Install a personally signed build on an iPhone/iPad and import the user's
  original maps. Validate menu, campaign, controls, rendering and audio.
- Repeat the successful simulator join/host/migration tests on hardware with
  matching browser maps. Verify movement/fire replication, scores, player
  identity and checkpoint continuity over extended play.
- Resolve cold-restart admission after host migration; verify reconnect paths.
- Test separate internet connections and TURN-only connectivity.
- Measure frame time, latency, memory and extended play on hardware.
- Exercise app background/resume and WebKit process termination; recovery is
  not yet a validated promise.

The user supplied a compatible original Xbox disc image. Real native/browser
matches now have simulator evidence; physical-device behavior and the remaining
cases above are still unverified. Keep the PR in draft until those checks pass.

## Graphics diagnostics (2026-10-03)

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

## Persisted renderer selection (2026-10-03)

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

## Private-image storage and native Mac target (2026-10-03)

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

## Settings and menu audio update (0.1.4 / 8)

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

## First-mission feedback / 0.1.5 (9)

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

## Application naming / 0.1.6 (10)

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

## Public servers — 0.1.7 (11), 2026-10-04

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

## Visible join progress — 0.1.8 (12), 2026-10-04

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
