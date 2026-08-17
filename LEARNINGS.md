# Learnings

Everything non-obvious discovered along the way, including the things that cost
time and the one bug still open.

---

## 1. Getting inside an IPSW without downloading it

Apple publishes beta firmware on an open CDN (`updates.cdn-apple.com`) — no
developer account, you just need the URL. AppleDB indexes them
(`https://api.appledb.dev/ios/iOS;<build>.json`). `api.ipsw.me` only carries public
releases, not betas.

An IPSW is a ZIP, and the CDN honours HTTP range requests. Read the End of Central
Directory from the last 128 KB, parse the central directory, and you have every
member's offset and size. Pulling the full contents list of a 12.3 GB image cost
about 24 MB of traffic. `tools/ipsw_peek.py`, `tools/grab.py`.

**The `.mtree` member is the cheat code.** `Firmware/<fs>.dmg.aea.mtree` is a
complete index of every path in the encrypted filesystem — 39 MB instead of 8.9 GB.
You can locate a file before deciding whether decrypting is worth it.

## 2. Apple's nested container formats

Three layers, each needing different handling:

- **Image4 (`IM4P`)** wraps most firmware payloads. Skip the ASN.1 header to the
  compression magic.
- **`bvx2`** = LZFSE. `compression_decode_buffer` from `/usr/lib/libcompression.dylib`
  via ctypes handles it in one shot (`tools/unlzfse.py`).
- **`pbze`** = a `pbzx`-style chunked container: magic, `u64be` chunk size, then
  repeating (`u64be` raw size, `u64be` compressed size, LZFSE payload). One-shot and
  streaming decode both fail on it; you must walk the chunks (`tools/unpbze.py`).
  LZBITMAP (`0x702`) is **not** exposed by libcompression on macOS 26 — probing
  `compression_stream_init` confirms it returns unsupported.
- The decoded mtree is an **Apple Archive (`AA01`)**, which `/usr/bin/aa` reads
  natively — it contains `mtree.txt`, a BSD mtree.

## 3. The encrypted root filesystem is openly decryptable

Since iOS 18 the root filesystem ships as `.aea` (Apple Encrypted Archive). The AEA
header contains `com.apple.wkms.fcs-key-url` pointing at **`wkms-public.apple.com`**,
which serves the unwrapping private key to anyone. So "encrypted" here means
"encrypted at rest with a published key", not "locked".

Deriving the symmetric key from it is *not* a plain ECDH + X9.63 + RFC 3394 unwrap —
I tried the obvious combinations and every one failed its integrity check. Don't
burn time on it: `blacktop/ipsw` implements the real derivation.

```bash
ipsw fw aea --key --pem fcs_key.pem rootfs.dmg.aea    # -> base64:...
aea decrypt -i rootfs.dmg.aea -o rootfs.dmg -key-value base64:...
hdiutil attach -readonly -nobrowse -mountpoint ./rootfs rootfs.dmg
```

Decryption of 8.9 GB takes about 4 seconds (it is multithreaded). macOS mounts the
resulting APFS image directly.

**Framework binaries are not in the root filesystem.** Since iOS 17 the dyld shared
cache lives in a separate OS cryptex — a second, smaller `.aea` (2.35 GB here).
`/System/Library/PrivateFrameworks/Foo.framework/` on the rootfs contains only
resources; the executable is in the cache. Extract with
`ipsw dyld extract <cache> <path>` and class-dump with `ipsw class-dump`.

## 4. Finding a feature when nothing is named after it

Grepping for "astronomy" across the filesystem found only watch faces. Apple names
poster extensions after gods and flowers:

| Codename | What it is |
|---|---|
| **Aegir** | Astronomy (Earth / Moon / Mars) — Norse sea god |
| Celosia | iOS 27 default wallpaper |
| Space | iOS 26 default wallpaper |
| Fluidity | iOS 18 default wallpaper |
| Calliope | the fuller solar-system renderer |
| Mercury | the poster extension bundling the OS-branded defaults |
| Extragalactic | part of the Black Unity series, *not* astronomy |

What actually worked: search every `.loctable` and `.strings` file for the
user-visible name. Localisation tables are where the human-readable labels live, and
there are few enough to grep exhaustively. `AegirPoster.appex/InfoPlist.loctable`
→ `CFBundleDisplayName = "Astronomy"`. Done.

Second useful signal: a bundle registered in `/System/Library/LocationBundles/`
is location-aware. That is how a wallpaper gives itself away as one that knows
where you are.

## 5. Decoding Apple's `.art` textures

8-byte header, little-endian `uint16`s: `[0:2]` format, `[2:4]` flags, `[4:6]` width,
`[6:8]` height. Then a raw payload.

Identify the payload by **matching file size against ASTC mip-chain totals** — there
is exactly one footprint that fits. A 626,296-byte file with a 1024×1024 header is
ASTC 6×6 with 11 mip levels (626,288 bytes) plus the 8-byte header, exactly.
`tools/art_ident.py` brute-forces this.

Decoding: the pip package `texture2ddecoder` handles ASTC. There is no Homebrew
`astcenc` formula. Note the decoder returns **BGRA**, not RGBA.

The `classic` variants are uncompressed — `c1d-classic.art` is 64×64 RGBA8 × 6 faces,
i.e. a cube map, which is the hint that the whole system is cube-mapped.

## 6. Working out the cube-map orientation

Don't guess — unwrap it and look. `tools/cube_to_equirect.py` renders the six
assembled faces to an equirectangular world map, which is instantly verifiable by
eye. The mapping came out right first try:

- Assembled face order is 4 equatorial faces then 2 poles.
- Metal slice order (+X, −X, +Y, −Y, +Z, −Z) = assembled faces `[1, 0, 4, 5, 2, 3]`.
- No per-face rotation needed, with the convention lon 0 → +Z, lon +90 → +X, +Y north.
- Tiles are row-major within each face (`i0 i1 / i2 i3`).

## 7. The emissive texture is packed

RGB is city lights **in colour** (sodium-orange vs LED-white read differently).
Alpha is a completely separate channel: a water mask with river networks drawn in
(1 = water). That is what lets the shader tint land and sea independently —
`continentDayColor`, `continentNightColor`, `oceanDayColor`, `oceanNightColor`.

Practical trap: do **not** load this as a single RGBA texture through CoreGraphics.
The only 8-bit RGBA context modes are premultiplied, which zeroes the city lights
everywhere the mask is 0. Split into two textures at export time.

## 8. The lighting model, recovered

`NUNIAegirPipelineConstants` is 35 floats and reads like a lighting rig: sun distance
/ radius / glow / colour; `earthLightPower`, `earthSpecular{Power,Strength,Breakup}`
(breakup stops the ocean acting as a perfect mirror), `earthIllumination*` for the
night side, `earthCloudShadow{Strength,EaseFrom,EaseTo}`, `earthAtmosphere*` with a
terminator ease, and bloom radius/strength/threshold. The full field list is in
`findings/nanouniverse_classdump.txt`.

## 9. Rendering notes from rebuilding it

- **The sun must be fixed in the globe's frame, not the world's.** The sub-solar
  point is a latitude/longitude, so rotate it into world space with the model matrix.
  Get this wrong and spinning the globe drags geography through a stationary
  terminator — Tokyo changes time of day because you looked at it. One line:
  `u.lightDirection = rotation.modelMatrix * sunModel`.
- **Soft terminators matter more than anything else for realism.** Both the surface
  *and* the clouds need the ramp. Clouds clipping at `saturate(ndl)` produce a hard
  diagonal line across the planet that reads instantly as fake.
- **Keep one texture-coordinate convention through every pass.** Flipping `ndc.y` in
  the scene pass while sampling with an unflipped `uv` in the post pass cancels out
  for the scene but leaves the *bloom* vertically mirrored — subtle enough to miss.
  Set `uv.y = 1 - p.y` in the vertex shader so v=0 is the top everywhere.
- **Weight ambient toward the night side.** A fullscreen globe whose dark half is
  pure black just looks like a broken screen.
- Xcode 26 no longer bundles the Metal compiler: `xcodebuild -downloadComponent
  MetalToolchain` (688 MB).
- xcodegen **generates over** whatever you point `info.path` at. Hand-writing an
  Info.plist and then referencing it silently destroys it — put the keys in
  `info.properties` instead. This cost real time.

## 10. Testing on the simulator

- Drive the simulator with `cliclick`, but the whole drag must be **one invocation**
  (`dd:` … `dm:` … `du:`). Separate processes lose the mouse-down state.
- Never hardcode window coordinates — the Simulator window moves. Look it up each
  time via System Events (`tools/gesture.sh`).
- Several simulators can share the name "iPhone 17 Pro" across runtimes. Pin the
  UDID everywhere or `xcodebuild` and `simctl` will target different devices.
- Do not infer "the app crashed" from screenshot brightness. A fullscreen daylit
  Earth has almost exactly the same mean brightness as the iOS home screen; that
  false signal sent me chasing a launch failure that never happened.
- `print()` over `simctl launch --console-pty` proved unreliable. Writing to a file
  in the app container and reading it with `simctl get_app_container` always works.

---

## Open bug: touches never reach the Metal view

**Symptom.** Dragging does nothing. Confirmed both by automation and by hand.

**Evidence.** `app/Sources/DebugLog.swift` appends to `Documents/touch.log` from
`touchesBegan` / `touchesMoved` / `touchesCancelled` in `TouchMTKView`. After a drag
across the globe the log contains only `app start` — **the touch methods are never
invoked at all.** This is a delivery problem, not a maths problem: the rotation model
and the renderer are fine.

**Ruled out.**
- Not the `UIPinchGestureRecognizer` — removing it left the drag equally dead.
- Not the automation. The same synthetic drags do reach the simulator; a bottom-edge
  swipe performs the system home gesture and backgrounds the app.
- Not a crash or a failed launch. The app renders continuously and the beacon pulses.
- Not the renderer. An earlier build of this same code **did** spin correctly
  (`findings/images/demo-spin-before-after.png` shows South America rotating round
  to Australia with inertia). The regression came in with the fullscreen/zoom/
  Info.plist changes.

**Leading hypotheses, in order.**
1. `UIRequiresFullScreen` / the regenerated Info.plist changed how the hosting
   controller lays out, leaving the `MTKView` with zero-size `bounds` — hit testing
   then rejects every touch while the drawable still renders at full size. Log
   `view.bounds` at `layoutSubviews` first; this is the cheapest check and fits the
   evidence best.
2. Something in the SwiftUI hierarchy is swallowing touches above the representable —
   `ZStack { Color.black; GlobeView() }` plus `.ignoresSafeArea()`,
   `.statusBarHidden()`, `.persistentSystemOverlays(.hidden)`. Bisect by removing
   the modifiers one at a time.
3. The representable is being recreated on every `LocationProvider` publish, so the
   view receiving touches is not the view on screen. Log the `ObjectIdentifier` of
   the `MTKView` in `updateUIView`.

**Suggested fix regardless of cause.** Drop the raw `touches*` overrides and drive
rotation from a SwiftUI `DragGesture` + `MagnifyGesture` attached to the
representable, reading `value.translation` and `value.velocity`. That removes the
UIKit hosting question entirely and keeps throw velocity (`DragGesture.Value` exposes
it directly). Keep `RotationModel` exactly as is — it is correct and tested.
