# World Restructure: New York, Countryside and Player Mansions (Phase A)

Status: **plan for approval**. Nothing in the running game has changed. The
current province stays live until Phase B is approved.

| Artefact | Path |
|---|---|
| Revised top-down blueprint | `docs/geography/world_restructure_plan.png` |
| Estate regions, sampled plots, capacity | `data/world/estate_plan.json` (not read by the game yet) |
| Generator | `tools/geography/region_plan.py` |

## 1. Audit: what we keep, what we replace

| System | Verdict |
|---|---|
| Deterministic simulation, commands/events, saves (v3 with world id and migration) | **Keep.** Mansions and estates are new state alongside it. |
| Road graph (position-keyed nodes, A*, speed per edge, long-edge overflow fixed) | **Keep.** It already routes 10 k nodes across bridges in < 50 ms. |
| Convoy movement (route points, cost-timed, LanePath presentation) | **Keep.** Convoys simply start and end at estate gates. |
| Streaming tiers (overview MultiMesh, mid massing, threaded detail) | **Keep.** Countryside adds a terrain/vegetation tier. |
| Coastlines, boroughs, bridges, landmarks (`nyc_1977.json`) | **Keep** as the city core; extend the frame. |
| Little Italy (381 lots, IDs, businesses) | **Keep** unchanged. |
| District lattices + overlaid arterials (grid-first) | **Replace.** It is the cause of the double roads, stubs and empty paved areas. |
| Modular towers, facade textures, block interiors (branch `world-quality-wip`) | **Reuse** as building/parcel content in the new pipeline. |

## 2. Revised world

A 27 x 24 km frame (playable ~24 x 20 km) around the approved compressed city.

| Ring | Areas | Content |
|---|---|---|
| **City core** | Manhattan, Downtown & North Brooklyn, Long Island City & Astoria, South Bronx | Dense 1977 architecture; businesses, territory, operations. |
| **Outskirts** | Flatbush/Canarsie/Bay Ridge, Central Queens, North Bronx, Nassau suburbs, Hudson County & Fort Lee | Brownstones to detached houses, rail yards, industrial estates, parks, tree-lined roads. Density falls with distance from the core. |
| **Estate regions** | Staten Island (Todt Hill), Riverdale, Palisades, Westchester, Gold Coast, South Shore, Bergen Hills | Rolling terrain, woodland, lakes, farms, villages, winding lanes, gated estate plots. |
| **Scenery** | Long Island beyond the frame, Hudson Highlands, the Atlantic | Low-cost terrain, woodland cards and water to the horizon. |

These are the places where 1970s New York families actually lived. They are
connected by the period routes: the Verrazzano, Throgs Neck, Whitestone,
George Washington and Goethals bridges, the LIE, the Northern and Southern
State and Belt parkways, the Palisades, Saw Mill and Hutchinson parkways and
the Staten Island Expressway.

**Why this size.** Convoys average 15–19 m/s on parkways. The outer estates
sit 15–22 km by road from Little Italy (about 15–20 minutes of game time),
prime estates 5–8 km (5–8 minutes). That is a real strategic trade-off
without making city operations tedious. The frame is 2.4x the current area,
but the dense, costly part shrinks: only the core is fully built.

## 3. Estate plots and capacity

- **Plot:** 140 x 140 m. Mansion, grounds, garage block, gatehouse and a
  driveway to a lane. Large enough for the mansion to read from the strategic
  camera.
- **Spacing:** at least 230 m centre to centre. Placement is Poisson-disc
  sampled over estate land, off lakes, at least 160 m from highways, and
  leaves woodland gaps so plots never read as a grid.
- **Identity:** plot IDs `estate:<region>:<n>` are generated from the world
  seed and stay stable.

| Tier | Plots | Typical road distance to Little Italy |
|---|---|---|
| Prime (Staten Island, Riverdale) | 208 | 5–8 km |
| Suburban (Palisades, Westchester, Gold Coast) | 872 | 9–15 km |
| Outer (South Shore, Bergen Hills) | 937 | 15–22 km |
| **Total** | **2,017** | |

**Recommended server population: up to ~1,500 estates per world.** That keeps
about 25 % of plots free for new players and relocation. A larger population
means another world shard (same map, separate server), not more plots on this
one. The count is finite and explicit; the server refuses claims when a tier
is full.

## 4. Little Italy HQ vs. the family mansion

- **The mansion is the family's primary headquarters.** The existing
  `HeadquartersState` (level, facilities) moves to the estate, so there is one
  HQ, one level, one set of upgrades and no duplicate income.
- **The Marino Social Club stays** as the family's city front and story
  location. It becomes a **staging point** where crews can be stationed for
  short city operations, with no level, income or upgrades of its own.
- **Save migration (v4):**
  - HQ level and facilities become mansion level and facilities.
  - The player is assigned a prime plot (the Marino estate on Staten Island).
  - Crews keep their current positions as "deployed" and get the estate as
    `home`.
  - Nothing is lost or duplicated.

## 5. Mansions: data and rules (server-authoritative)

```
EstateState  { id (plot id), owner_faction, level, buildings{}, gate_node_key,
               garage_slots, protection_until_ms, relocate_ready_ms, status }
PlotRegistry { plot_id -> owner_faction }   # server-owned occupancy
```

- Every player owns exactly one primary estate. Claims, relocation and
  release are **commands** validated in `SimWorld`, like every other change.
- The estate's gate is a road-graph node joined to a lane by its driveway, so
  the plot is part of the road network.
- On the world map the estate is drawn from its level (mansion model tier,
  walls, garage). It shows the family name, level and status (shielded,
  under attack, reinforced). It can be inspected, and later scouted,
  attacked and reinforced.
- Offline players stay on the map. Attacks on offline players follow
  protection rules:
  - new-player shield (for example 72 h, broken by attacking);
  - a cooldown between attacks on the same estate;
  - power-band limits against bullying.

## 6. Convoys start and end at estates

Each `CrewState` gains `home_estate`, plus a status of `home`, `deployed` or
`moving`. An order such as attack, reinforce or move then works like this:

1. It routes from the crew's actual location: the estate gate if at home,
   otherwise where it is deployed.
2. It spawns at the gate or garage and joins the public road.
3. It travels on real roads and is visible to other players.
4. Combat and reinforcement happen at the persistent world coordinates.
5. "Return" routes back to the home gate.

This uses the same deterministic route/cost/timestamp model as today. No
vehicle appears mid-road.

## 7. Relocation (designed now, interface later)

- Target must be a free plot in an allowed tier.
- Cost scales with tier. A cooldown applies (for example 7 days). Prime plots
  trade shorter journeys for higher upkeep and visibility.
- **Blocked** while:
  - any of the player's convoys is moving;
  - the estate is under attack or has incoming reinforcements;
  - within 1 h of combat.
  This prevents escape and teleport exploits.
- **Atomic server step:**
  1. Reserve the target plot.
  2. Move the estate data with level, buildings, resources and troops.
  3. Re-home crews: crews at home move with the estate; deployed crews keep
     their position, and their home updates.
  4. Release the old plot.

## 8. The mansion scene

- Selecting your own estate and choosing *Enter* runs a camera zoom to the
  gate, fades and loads `scenes/estate/estate.tscn`. The scene is built from
  the same `EstateState`.
- While inside, the world streamer and traffic are suspended, but the
  simulation (`Game`) keeps ticking, so income, convoys and AI continue.
- *Exit* restores the camera to the exact map position.
- First pass (Phase C): mansion, garage, gatehouse, grounds and a working
  transition both ways. Upgrade buildings come later, as data.

## 9. Streets-first generation (Phase B)

1. **Terrain and water.** A low-res heightfield, rolling only outside the
   core. Coasts, rivers, lakes and streams come from polygons.
2. **One road network.** It is built as a single graph:
   - highways and parkways;
   - bridges;
   - the city grids, with avenues as grid lines and Broadway as a true
     diagonal (no overlays);
   - suburban streets;
   - country lanes that follow terrain contours.
   Lower Manhattan and Brooklyn street patterns are traced from the reference
   GLB and compressed. The GLB stays reference-only.
3. **Blocks and plots from road faces.** Every block is a face of the planar
   road graph. Estate plots sit on lanes with driveways.
4. **Parcels and buildings per ring.** The core uses the existing catalogue,
   modular towers and interiors; the outskirts use lower density; the
   countryside gets villages, farms and estates.
5. **Ground surfaces.** Ground follows the face type: pavement, yards,
   fields, lawns, woodland.
6. **Distance tiers.** The current detail / mid / overview tiers, plus
   terrain chunks and instanced tree clusters with impostor cards in the
   distance.

Road continuity is guaranteed by construction, because every street is an
edge of the same graph. Regression tests will check graph faces, parcel
containment, driveways and chunk-boundary continuity.

## 10. Performance plan (mobile, unverified on devices)

- **Countryside:** terrain chunks of about 2 k triangles each, plus instanced
  tree clusters with three LODs:
  - mesh at close range;
  - cross-card at mid range;
  - baked canopy colour in the terrain far away.
  No grass blades; grass is a material.
- **Close-zoom cost:** the cost is the detail chunks (0.45 M triangles and
  20–25 MB of buffers each in Little Italy). Phase B adds:
  - per-building LODs;
  - props merged into lower-LOD sets;
  - shadows limited to buildings.
  The aim is under 1 M primitives at close zoom.
- **Targets:** 30 fps on low-end devices, 60 fps on capable ones. This can
  only be confirmed on real hardware (Android SDK and export templates still
  need installing).

## 11. Risks

- Tracing the reference GLB's road layer into a compressed graph needs
  cleanup tooling (it has about 400 k road triangles at real scale).
- Terrain under roads and buildings must stay flat. Plan: flatten corridors
  and plots in the heightfield.
- The larger map increases overview memory. Countryside must stay
  instanced and low-cost.
- The relocation and attack rules need balance testing once combat exists.

## Phases

| Phase | Scope | Status |
|---|---|---|
| A | This plan | **Awaiting approval** |
| B | Streets-first foundation in one representative region (Lower Manhattan to Brooklyn to the Staten Island estates) | |
| C | Mansion vertical slice: Marino estate and a rival estate, a convoy from the gate, the estate scene and return | |
| D | Validation: tests, screenshots at all zooms and inside the mansion, performance | |
