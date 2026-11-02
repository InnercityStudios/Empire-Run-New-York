# Empire world rendering proof — unapproved

This is an independent Godot 4.7 project, under the root project's `.gdignore` boundary. It does not load `Game`, `Content`, the UI, economy, crews, saves or province generator. This work is not integrated into the current world.

Open **this folder's `project.godot`**, not the root project's legacy `world_preview.tscn`.

```sh
python3 prepare.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --editor --import
python3 review.py
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

**Tab** switches between Richmond pasture and the Brooklyn waterfront. **1 / 2 / 3** select close, medium and strategic representations. **Right drag** orbits; **wheel** adjusts the selected view.

Capture six actual native Godot Mobile-renderer views and performance samples:

```sh
python3 review.py --capture
```

Outputs belong in `results/captures/`: three PNGs per region plus `capture_report.json` (draw calls, primitives, frame-time percentiles, GPU/render CPU time and VRAM). `visual_review` remains `pending`; producing images is not approval. Inspect all six images before accepting the approach. The runner rejects engine/script/shader errors and missing captures.

In the current automation environment the native window aborts with **SIGABRT / exit -6** in macOS AppKit/HIServices initialization. **No new Godot screenshots or GPU measurements were produced.** See `results/capture_status.json`. Headless topology/coverage checks pass, but they do not prove visual quality, Mobile shader output or phone performance.

`data/geography.json` is the sole spatial contract for these two samples. Its metre coordinates, explicit lake Bézier controls/sample points, land polygons, road endpoint IDs, road widths, field outlines and asset placements drive all tiers. No blueprint PNG is read. `approved` is deliberately false. The source authoring script is deterministic; the retained estate ID/centre/gate are copied verbatim from the existing reservation export. This is a draft sample geometry, not a surveyed or approved replacement province.

`ConformingMesh` clips each mesh cell to vector land and water before triangulation. Interior spacing is 4 / 8 / 32 m, but shorelines remain constrained by the same vector edges. Every tier preserves the same 4 m tile-border knots and normals. A coarse cell containing a closed water hole is subdivided until the land is triangulatable without filling that hole. The adversarial half-metre lake test is in `src/checks.gd`.

Buildings retain full imported scene transforms and shared textured materials. Medium LOD uses their imported mesh LODs. Strategic geometry comes from those same assets' upward-facing surfaces at the same placements, including tree canopies; it does not substitute independently populated box blocks. Road paint and kerbs follow the same road topology/perimeter as navigation data. Only these two bounded examples are built, and their geometry is intentionally kept resident for inspection; production province streaming is proposed in the architecture audit, not implemented here.

All staged model/texture sources already existed in the repository. `data/asset_manifest.json` records source model hashes. Licensing is in `ASSET_CREDITS.md`. Source materials are reused; staging imports use mipmaps, mobile compression and 1K texture limits where appropriate.
