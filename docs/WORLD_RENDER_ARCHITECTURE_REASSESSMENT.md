# World renderer reassessment and isolated proof

Status: **implementation available; visual proof blocked; not approved for expansion**.

Only a new isolated project under `art_source/world_render_poc/` and this audit were added for this task. The existing UI, economy, crews, saves, persistent-coordinate code and live province generation were not edited. Concurrent changes such as the root `terrain_test.tscn` and project settings were left alone. The standalone proof is excluded from the root game's import/export scan by the existing `art_source/.gdignore`.

The screenshots reported by the owner were deleted. The findings below are confirmed from implementation/data; they are not a claim that the deleted camera views were re-inspected. Existing earlier close/medium reference captures were inspected for asset/readability context.

## Precise architectural defects

| Reported defect | Confirmed mechanism | Evidence |
|---|---|---|
| Repetitive box buildings | Medium LOD builds one bounding box per lot; strategic LOD invents 1–4 differently sized boxes per block. These are not reduced meshes of the actual buildings. Full detail stops entirely when camera distance exceeds ~333 m. | `src/world/stream/far_city_builder.gd:build_arrays`; `overview_builder.gd:_build`; `world_streamer.gd:detail_radius` |
| Sudden changes in buildings/plots while zooming | Each tier uses a different population/massing recipe and different footprints. Visibility is selected by chunk and absolute camera distance rather than projected silhouette error. | `OverviewBuilder` versus `BlockFiller` versus `FarCityBuilder` |
| Angular banks, missing narrow water and long shoreline triangles | Terrain uses a regular height grid at 16 or 128 m. The grid is not constrained to coastline or lake edges. A 7 m stream can lie entirely between sample rows; a polygon membership query at vertices cannot prevent a triangle crossing water. Skirts conceal vertical gaps but do not preserve shore geometry or blend the tiers' different normal approximations. | `src/world/terrain/terrain_mesh.gd:arrays`; `terrain_streamer.gd:build/_process` |
| Raised spikes/ledges at road/shore transitions | `_base_height` returns submerged elevation immediately for a negative bank distance, but forces road centres to -0.03 m on the land side. At the shoreline limit, that creates an approximately **1.87 m discontinuity** beside the same y=0 road. | `src/world/terrain/terrain_field.gd:_base_height` |
| Flat procedural countryside | Base relief is a few sine/cosine waves over hundreds of metres. Every reserved estate is flattened to the same 0.12 m datum with 115 m discs/65 m feathers. Vegetation is a second sinusoidal threshold. Broad areas are therefore mathematically flattened, not artist-authored landscapes with field/woodland/shore composition. | `TerrainField._base_height/_flatten_height`; `TerrainStreamer._vegetation` |
| Roads connect in routing but have visible gaps or mismatched junctions | Legacy lattice surfaces are emitted separately from graph lines. `_stitch` adds navigation splits and trimmed connector surfaces without consistently regenerating the receiving road/junction footprint. Authored surfaces also precede later graph edits; `_connect_islands` can prune graph nodes without pruning corresponding rendered surfaces/blocks. A midpoint-near-road assertion does not test surface continuity at junction mouths. | `src/world/geo/geography_builder.gd:_lattice_streets/_stitch/_emit_graph/_connect_islands/_authored_networks` |
| Rectangular lake/park surfaces | Central Park's two lakes are explicitly four-corner approximate rectangles. Park grounds are independent flat polygon overlays, not terrain masks/graded water basins. The **editor preview additionally hardcodes the legacy `greater_new_york` definition**, whose `WorldShellBuilder._park_features` creates lakes directly from `Rect2`; its coasts/ground are also the old rectangular implementation. Preview and runtime are different worlds. | `data/world/nyc_1977.json:parks`; `geo_shell_builder.gd:_grounds/_park_features`; `world_preview.gd:_rebuild`; `world_shell_builder.gd:_park_features` |
| Asset quality lost despite better source models | `AssetLibrary` takes only the first imported MeshInstance's mesh and omits its hierarchy transforms. Chunk merging reconstructs surface arrays without retaining imported mesh LODs. Replacing these merged chunks with boxes cannot recover rooflines, setbacks, cornices or material identity. | `src/world/asset_library.gd:mesh_at/_find_mesh_instance`; `chunk_detail_builder.gd:to_mesh`; `mesh_merger.gd` |
| Streaming does not bound asset residency | All building meshes/materials are prewarmed before chunk visibility is known. Terrain's coarse coverage is selected by landmass bounding-box overlap. Geometry streams, but much of the asset/texture working set is already resident; small surface counts alone do not prove a mobile budget. | `WorldStreamer._prewarm`; `TerrainStreamer.build` |

Read-only source diagnostics found **no proper self-intersections in the input land polygons**. Thus the observed angular errors should not automatically be blamed on invalid input rings; undersampling, discontinuous height rules, independent overlays and preview divergence are concrete causes. Runtime polygon unions also lack a robust outer-ring/hole data model: `LandscapeBlueprint.apply` only treats a one-ring union as merged, while `GeoMap` treats every coast ring as solid land. The new compiler must explicitly retain holes and disconnected islands.

`art_source/world_render_poc/results/current_renderer_audit.json` contains reproducible polygon/park diagnostics. The blueprint PNG was not being parsed by the current runtime; the issue is that sketch-derived coordinates and rendering heuristics were not supported by a coherent topology/representation contract. A more attractive PNG would not fix this.

## One geography contract, three representations

Canonical geography should be versioned vector/height data: world-space metre coordinates; stable road nodes and IDs; directed shoreline rings with holes; explicit water levels and bank profiles; road centreline elevation/width/crossing class; field and region polygons; authored height controls; stable building/parcel instances and estate reservations. Keep simulation coordinates in integer centimetres and convert to local floating-point tile coordinates for rendering. The PNG is generated documentation only.

A deterministic compiler validates topology and emits land/water meshes, unioned road/junction surfaces, parcel boundaries, road navigation input and masks from that contract. No renderer may invent or independently repair roads, coastlines or building placements. Repairs happen in source data, with a revision and diagnostics. The editor preview must load the same compiled definition as the game.

| Representation | Geometry and assets | Streaming/transition rule |
|---|---|---|
| Close 3D | Conforming terrain, shaped banks, full existing textured models, graded roads, kerbs/crossings and nearby vegetation. | Small local tiles, instancing by asset/material and spatial cell; highest detail where projected error is visible. |
| Medium LOD | Reduced meshes of the **same** buildings/trees, retaining roof/footprint silhouettes and materials. Same shoreline/road geometry, coarser terrain interiors; remove tiny furniture. | Imported mesh LOD / authored HLOD, screen-space error with hysteresis. Never repopulate a block as independent boxes. |
| Strategic overview | Batched roof/canopy projections or artist-reviewed cluster impostors derived from the same instances, over simplified vector terrain/road/water coverage. Stable landmark silhouettes and IDs. | Coarse tiles resident, detailed tiles released. No demographic/footprint changes during zoom. |

Godot supplies imported mesh LOD using meshoptimizer and screen-space selection; it does not require inventing a separate box population. See the [official mesh LOD documentation](https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html). For the proof's geographic compiler, polygon clipping is used before triangulation, including explicit handling of returned holes as described by [Godot Geometry2D](https://docs.godotengine.org/en/stable/classes/class_geometry2d.html#class-geometry2d-method-clip-polygons).

Retain the existing worker queue / bounded upload / hysteresis concepts, but feed them immutable precompiled tiles with consistent boundaries. Budget geometry, materials, texture residency, shadow rendering and frame spikes together. The proof intentionally keeps two small samples resident for inspection; it does not claim to demonstrate province streaming, device FPS or final budgets.

## Systems to retain

- **Persistent X/Z coordinates, Little Italy and business IDs:** retain verbatim. The isolated proof does not change their source or persistence code. Render origins are offsets, not migrations.
- **RoadGraph navigation:** retain integer-centimetre node keys, A*, speed/cost handling and convoy interfaces. Feed it the canonical road topology used to build road surfaces; avoid renderer-only connectors. Visual road validation must cover the entire carriageway/junction, not just its midpoint.
- **Estate IDs/centres/exclusion requirements:** retain the existing reservation export as input. The old capacity result belongs to the old terrain/roads and cannot certify the replacement. Revalidate footprints, grade, water, access and exclusions against approved geography without silently moving plots. One exact existing reservation is retained and checked in the proof.
- **Assets/material sharing and instancing:** retain useful licensed/project-authored models and material atlases. Preserve imported scene transforms and useful LODs; replace all-assets startup prewarming with tile/asset residency control when integrating.
- **UI, economy, crews and saves:** retain unchanged. Any later topology change that needs persisted travel/entity migration requires explicit review first. No such migration is implemented here.

## Implemented proof and validation boundary

`art_source/world_render_poc/project.godot` is a separate Mobile-renderer project with no game autoloads. Its unapproved `data/geography.json` explicitly defines:

- A **960 × 704 m Richmond pasture**: curved pond from recorded Bézier controls, gently authored hill controls, a broad unoccupied estate field, three connected country-road edges, two existing farmhouse assets and irregular stands of existing trees/reeds/rocks. Estate `estate:staten:-3430:6572:infill2` keeps centre **[-3508, 6640]** and its original gate/access metadata.
- A **320 × 320 m Brooklyn waterfront sample**: an explicit bulkhead/river boundary, connected Dock/Front/rear streets, pavement and crossing geometry, a shaped green strip, and nine existing building instances including the textured licensed Brooklyn corner model. No proxy building boxes are generated.

Terrain interior spacing is 4 / 8 / 32 m by representation. Each cell is clipped to the same land/water boundaries before triangulation. Every tier retains identical 4 m tile-border knots and analytic normals. Closed holes trigger subdivision instead of being filled as land. Roof/canopy batches derive from placed meshes; the close/medium models retain their full imported hierarchies and automatic LODs. Sources are existing assets; source hashes and credits are staged alongside the proof.

Actual headless Godot checks pass: matching land/water areas across all tiers, **zero shared-boundary mismatches**, identical boundary-knot sets (2,738 country / 373 city), road-connected data, road-clear building bounds, and zero exclusion-disc elevation error for the retained estate. An adversarial **0.5 × 0.5 m lake inside a 32 m terrain cell** is preserved: land 1,023.75 m² plus water 0.25 m². These checks establish topology and data consistency, **not appearance**.

Geometry counts for terrain/road/water/pavement, excluding imported building/vegetation meshes and curb/paint details:

| Sample | Close | Medium | Strategic |
|---|---:|---:|---:|
| Richmond | 87,149 triangles | 25,182 | 6,837 |
| Brooklyn | 17,385 | 5,459 | 1,642 |

No GPU timing, draw-call or mobile performance result is available. Counts alone cannot approve the solution.

## Required visual gate — blocked, not completed

The six-view native Godot capture run was attempted. It aborted with **SIGABRT (subprocess exit -6)** before any viewport image. The local crash report's triggering stack includes **HIServices/AppKit** during native application initialization, not a proof scene/script error. Headless Godot works but uses dummy rendering; it cannot substitute for actual Mobile-renderer screenshots. Blender also cannot start here, so it was not used to fabricate a substitute preview. No new screenshots were produced.

Open the isolated project on a working graphical Godot session, or run:

```sh
python3 art_source/world_render_poc/review.py --capture
```

This captures each region at close, medium and strategic view, plus draw calls, primitives, GPU/render CPU time, frame-time percentiles and VRAM in `results/captures/`. The owner must inspect the images for shoreline continuity, road joins, asset quality, terrain form, scale, LOD popping and lighting. Then profile a supported phone/tablet. The approach stays **unapproved and isolated** until those images are available and accepted. No province expansion or regeneration is authorised by this proof's automated checks.
