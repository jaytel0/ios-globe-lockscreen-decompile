# Tools

Roughly the order the pipeline runs in.

## Reading the IPSW over the network
- `ipsw_peek.py <url>` — read the ZIP central directory via HTTP range requests,
  list all members, write `members.json`
- `grab.py <url> <member>...` — range-fetch and inflate individual members

## Unwrapping Apple's containers
- `unlzfse.py` — strip an Image4 wrapper and LZFSE-decompress (`bvx2`)
- `unpbze.py` — decode the `pbze` chunked container (used by `.mtree`)
- `unstream.py` — streaming libcompression decode; kept for reference
- `fcs_unwrap.py`, `fcs_gcm.py` — attempts at deriving the AEA key by hand.
  **Both fail.** Kept as a record of what not to try; use `ipsw fw aea --key`.

## Filesystem
- `mtree_paths.py <mtree.txt> <out>` — reconstruct full paths from the BSD mtree

## Textures
- `art_ident.py <file>...` — identify `.art` payload format by size matching
- `art_mip.py` / `art_decode.py` — decode an ASTC `.art` tile to an image
- `build_faces.py <layer> <mip>` — assemble the 24 tiles into 6 cube faces
- `cube_to_equirect.py <layer> <mip> <out>` — unwrap to a world map to verify
  orientation by eye
- `make_assets.py` — export the final cube faces into `app/Resources/`

## Simulator
- `run.sh <shot> [secs]` — build, install, launch, screenshot. UDID is hardcoded.
- `gesture.sh drag fx1 fy1 fx2 fy2` / `gesture.sh pinch out|in` — drive the
  simulator with cliclick, looking the window position up each time
- `drag.sh` — earlier fixed-coordinate version, superseded by `gesture.sh`

Python deps: `pillow`, `numpy`, `texture2ddecoder`, `cryptography`.
