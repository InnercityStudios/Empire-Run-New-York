# World landscape implementation audit — 1 November 2026

Implemented in the working tree on `phase-b-slice`. **Phase 1 is not visually signed off:** this environment can run headless Godot but cannot capture a graphical viewport. Mobile GPU performance, shader appearance and the requested seven screenshots remain unverified. No phone FPS target is claimed.

## Root causes found

- `GeoShellBuilder._land()` painted **every landmass with the road material**, making any unfilled block an asphalt void. `_quays()` extruded vertical walls along every coast, including natural countryside. Both paths have been removed from the geography renderer.
- `GeographyBuilder` ignored the existing, uncommitted `networks` and `estate_regions` blueprint fields. The authored Bay Ridge/Grasmere streets, country roads, lakes and plot reservations were not consumed. Baseline tests: **45 passed, 1 failed**, with the Verrazzano approaches missing.
- The legacy generator fitted rectangular blocks before emitting their bounding lattice roads, independently from arterials. Its rectangular rendering assumptions also affected pavements and distant building massing. The new representative city/suburban pipeline derives parcels from bounded street faces and respects those polygons at all three building tiers.
- Island stitching searched only the original connected nodes. Newly connected roads never entered its spatial search, so valid roads further out were discarded. Stitching now propagates through newly connected components and checks entire connectors for dry land.
- `estate_plan.json` was a planning estimate based on centres, not buildable footprints, terrain, final road access or driveway clearance. Its 2,017 figure was not verified capacity.

## Implemented

`LandscapeBlueprint` applies a separate, reproducible 27 × 24 km outer geography layer to the existing city definition. It retains Little Italy, city/business IDs, world ID and metre/centimetre coordinate conventions. No save format or coordinate migration was introduced. Existing uncommitted art, scene, catalogue and geography work was preserved; no branch was merged or reset.

`TerrainField` supplies a common continuous height function for meshes, natural banks, vegetation and estate validation. Broad low relief surrounds flat estate fields. Rivers/ponds descend below the shared water datum; roads retain their established y=0 datum with blended verges. Estate clearance uses smooth circular field blending rather than square pads.

`TerrainStreamer` keeps coarse 128 m samples resident and streams 16 m samples on 1,024 m tiles. It uses two bounded worker tasks, one terrain upload per frame, unload hysteresis and fallback coverage. Terrain vertices are local to each tile; authoritative positions remain in world coordinates. Shared border positions/normals are tested; skirts cover mixed-resolution boundaries. Existing city overview, mid and detail streaming remain active.

Ground blends the existing grass, soil, sand, mud and rock assets with shared world UVs, bank masks and broad colour variation. Terrain texture imports now use mipmaps and mobile compression. Water uses quieter normal ripples, shoreline proximity colour and the existing sky environment, without screen-space depth/refraction or fluid simulation. Vegetation reuses the existing lean authored oak, birch, maple, rock, shrub and reed assets; placement excludes estate clearance discs and road verges. No additional high-poly city or tree model was imported.

The authored street network now drives both visible road pieces and navigation. Crossroads, snapped T-junctions and collinear overlaps are resolved before face extraction. Polygon parcel building footprints are contained and collision checked. Non-bridge authored carriageways are clipped clear of water; country roads are 7–9 m wide. The existing core lattice is retained outside the representative streets-first districts; converting every historical district to authored faces remains a later visual iteration, not a claimed completed rewrite.

`world-quality-wip` was inspected for its modular tower, facade and interior changes; its removals and unfinished gameplay/UI changes were not merged. The existing ~52 MB lower Manhattan/Brooklyn reference GLB was inspected as source reference and remains outside runtime assets. The compressed authored city geography remains the coordinate reference.

## Estate validation

The final runtime field generates and independently audits **2,034** reservations, above the provisional 2,017 target:

| Tier | Validated plots |
|---|---:|
| Prime | 109 |
| Suburban | 1,005 |
| Outer | 920 |

- Plot footprint: 140 × 140 m; complete footprint diagonal radius ~99 m lies inside a 115 m exclusion radius.
- Minimum measured centre spacing: **231.2147 m** (requirement: 230 m).
- Whole exclusion disc is checked against region boundaries, water and public road clearance. The public-road clearance includes the road half-width and a 10 m verge outside the exclusion disc.
- Future driveway gate, road point, road identity, orientation and elevation are stored. Access is on the final connected graph. Pond-edge intersections and neighbouring exclusion discs are checked; future driveway width allowance is 6 m.
- Independent audit: **0** water violations, **0** road-access violations, **0** driveway conflicts, **0** wet driveway samples. Exclusion-disc elevation error is below floating-point tolerance.
- Existing mansion GLB full mesh footprints were inspected: L1 ~31.6 × 25.4 m; L2 ~59.2 × 25.4 m; L3 ~59.2 × 28.9 m. They fit inside 140 m plots with space for a future compound. This does not certify an as-yet unauthored complete mansion layout.

`data/world/estate_reservations.json` records the actual IDs, positions, access data, source hashes and audit report. It is an export of the runtime blueprint, not ownership/save state. The original planning-only `estate_plan.json` is retained for history. No mansion construction, ownership, combat or networking was added.

## Validation and limits

- Godot **4.7.2** headless suite: **53 passed, 0 failed**, exit 0. Includes original gameplay/economy/save migrations, unchanged Little Italy fingerprint `381:708f77ce754b9eda`, borough/bridge connectivity, plus terrain seams, footprint/driveway clearance, planar street topology, parcel containment and visible-road/navigation agreement.
- Actual main-scene smoke test: **PASS**, exit 0. Panned through Little Italy, Bergen fields, Silver Lake, Westchester and strategic zoom. Observed 14–16 detailed terrain tiles near those views, maximum 2 terrain tasks; strategic zoom released all detailed terrain and vegetation. There are 662 resident coarse tiles. These are CPU/state checks, not rendered visual checks.
- Python generator/capture script syntax and `git diff --check` pass. Detailed logs are in `docs/validation/`. Baseline and final headless suites both emit shutdown resource-cache leak diagnostics; macOS certificate access and editor-settings writes are also restricted in this sandbox. Test assertions and exit status are reported separately from those environment/cache diagnostics.
- Graphical Godot launched through the shell exits immediately (SIGABRT). Computer Use returned “Computer Use was not approved to use Godot.” Godot's local help lists the headless display driver as **dummy rendering only**, so headless screenshots would not validate the Mobile renderer. No concept images, fabricated captures or Blender previews have been substituted.

The whole map has the new foundation in code/data, but premium visual quality, absence of visible mixed-LOD artefacts, and device budgets require actual graphical review before Phase 1 can be declared complete. The next gate is to capture and inspect the seven game views, then tune/expand urban authoring from that evidence.

## Reproduce

```sh
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
python3 tools/geography/build_landscape.py
python3 tools/geography/build_water_mask.py
$GODOT --headless --path . --import
$GODOT --headless --path . -s tests/run_tests.gd
$GODOT --headless --path . -s tests/tools_landscape_audit.gd
$GODOT --headless --path . -s tests/tools_landscape_streaming.gd -- --new-game --no-save
python3 tools/geography/capture_landscape.py --godot "$GODOT"
```

The capture tool requests dense/medium New York, city/suburb transition, open countryside, natural lake banks, mansion-ready fields and the whole world at strategic zoom. It writes actual viewport images, statistics and a manifest under `docs/geography/phase1_captures/`, and fails if Godot cannot produce a capture. Capture runs skip save writes; the full-world zoom override applies only to the capture.
