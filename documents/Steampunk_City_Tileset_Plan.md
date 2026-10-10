# Steampunk City Tileset Plan

A fifth Figment family, **City**, with five styles: Trainyard, Park, Residence, Downtown and Harbor. This is the plan; nothing is built yet. It follows the pattern the dungeon, desert, snow and forest families use: one doodad kit per family, extracted from the local Warcraft III install (`tools/mdx_pipeline/doodads.json`), and a `MapTileset` per style in `data/tilesets/styles/`.

## What makes it different

The existing layouts are rooms joined by corridors (dungeons) or open fields (desert, snow, forest). A city wants **streets**: a grid of blocks where the buildings are the walls and the streets are where you fight.

**New layout kind: `streets`.** `MapGraph` still decides which cells are connected; each cell becomes a city block.

- **Connected sides open onto the street.** A street 8 to 14 m wide runs along every boundary between connected cells.
- **Unconnected sides are closed off.** Building facades or walls block them, so the graph's dead ends and loops still shape the run.
- **Plazas.** Some cells are open plazas (a fountain, market stalls) instead of solid blocks, like the open rooms in a dungeon.
- **Buildings are walls.** They're placed whole along block edges, facing the street, with collision on their footprint. The navigation mesh (v4.65) treats them as obstacles automatically.
- **Height.** Most buildings are two to three storeys, so the player can't see over them. A city feels enclosed, unlike the fields.

## Styles

| Style | Layout | Feel | Key doodads | Ambience |
|---|---|---|---|---|
| **Trainyard** | streets, long blocks | Rails, cargo, steam. Wide lanes between lines of freight. | rail tracks (procedural: two steel strips plus sleepers), crates, barrels, ammo dumps, power generators, cranes | train station, steam engine |
| **Park** | open field with paths | A walled city park. Lawns, trees, ponds and statues; the least built-up style. | forest-kit trees, flowerbeds, benches, statues, fountains, lantern posts, low hedges | birds (forest loop), distant city |
| **Residence** | streets, small blocks | Narrow winding lanes between houses. Tight corners, lots of cover. | village houses (farm, tavern, grain warehouse), fences, carts, hay, wells | quiet rooms, distant machinery |
| **Downtown** | streets, large blocks, plazas | Grand stone buildings, wide avenues and a central square. | Dalaran/Lordaeron-capital structures, mage tower, arcane observatory, marketplace, banners, crystal lamps, statues | city crowd walla, machinery |
| **Harbor** | streets plus water | Docks and warehouses along a waterfront that bounds one side of the map. | goblin shipyard, piers, crates, ropes, lamps, boats | industrial harbor, water |

**Harbor reuses `WaterBuilder`.** One map edge becomes open water: a wide channel that runs edge to edge with no fords, kept out by the same layer-2 bank walls. Piers stick out into it as walkable platforms.

## Steampunk identity

Warcraft III's human city kit is medieval, so the steampunk flavour has to come from three places:

1. **Goblin and gnomish models.** Goblin shipyard, zeppelin and machinery models, and the power generator, serve as smokestacks and boilers.
2. **Procedural props.** Gear and pipe meshes on facades, steam vents (the `SmokePuff` particle effect with a looping steam-burst sound), rails and cranes.
3. **Lighting and sound.** Warm amber gas lamps against a soot-grey sky, and sound from the bundle's steampunk machine and gadget recordings. Steam bursts (already cut, in `assets/sfx/world/steam_burst_*`) fire from vents.

## Assets to pull (first pass)

Confirmed present in the install:

- **Buildings** (`buildings/other/`): `goblinshipyard`, `powergenerator`, `grainwarehouse`, `tavern`, `marketplace`, `merchant`, `magetower`, `arcaneobservatory`, `dalaranguardtower`, `ammodump`, `barrelsunit`, `cratesunit`, `fruitstand`, `pigfarm`, `elvenfarm`.
- **City props** (`doodads/cityscape/props/`): `lanternpost`, `city_fountain`, `fountainruined`, `citystonebench`, `citywoodbench`, `emptycrates0`, `irongatea`, `irongateb`, `citymaingate`, `knightstatuea`, `city_statue`, `marketstalllarge`, `marketstallsmall`, `banner_long`, `crystallamp`, `tavernsign`.
- **Plants** (`doodads/cityscape/plants/`): `citybush`, `flowerbedangled`, `flowerbedstraight`, `pottedplant`.
- **Ground** (`terrainart/lordaeroncapital/`): `lordc_cobbletiles`, `lordc_bricktiles`, `lordc_squaretiles`, `lordc_dirt`, `lordc_grass`, and the `lordaeroncapitalruins` variants for a run-down quarter.

**Building scale needs checking per model.** The Lordaeron tree models turned out to sit 2.1 m below their origin and to be far too short (the `LordaeronTreeTall*` wrappers fix them). Expect the same with buildings: measure each one's real bounds against the 1.8 m player and add inherited wrapper scenes where needed.

## Gameplay notes

- **Spawns.** Packs stand in streets and plazas, never inside building footprints. Use the dresser's reservation rects the way water does.
- **Chests.** They go in alleys and dead ends, which the streets layout produces naturally.
- **Line of sight.** Buildings block it, so ranged enemies path around corners to get a shot (v4.65 behaviour).
- **Boss vault.** The final block is a walled courtyard. In Downtown, a plaza with a grand building behind the altar.
- **Performance.** Buildings are big meshes; give them draw distances to match and count draw calls. A city of 25 blocks with 4 to 6 buildings each is about 120 large models.

## Build order

1. The `streets` layout in `MapLayout` and a `StreetBuilder`: blocks, streets, plazas, building placement on block edges.
2. Extract the city kit, measure building scales, and add wrapper fixes.
3. Residence first (small blocks, fewest unique assets), then Downtown, Trainyard (rails), Park (reuses the forest kit) and Harbor (water edge plus piers).
4. Cut the city ambiences (train station, harbor, crowd, machinery) with `tools/sfx_pipeline`.
5. Capture each style with `tests/ui_capture/capture_map.tscn` (`spawn`, `aerial`) and review.
