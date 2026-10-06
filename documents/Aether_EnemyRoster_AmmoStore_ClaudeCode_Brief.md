# Claude Code Brief: Enemy Roster v1 + Ammo Store

**Project:** Project Aether · Godot 4.3 · GDScript
**Scope:** Convert the new Warcraft III models, build 10 data-driven units on `EnemyDefinition`, retire the three Trinity playtest units, and add a Hub ammo store.
**Source of truth:** *Project Aether: Enemy Roster & Factions* (the roster doc). The unit data below is copied from it.

---

## 0. Before you start

1. Read `entities/enemies/base/Enemy.gd`, `EnemyAnimationController.gd`, `data/enemies/EnemyDefinition.gd`, `AnimationSet.gd`, `FigmentBoss.gd`, `levels/generated_map/GeneratedMap.gd`, `levels/pinnacle_boss/PinnacleArena.gd`, `systems/items/AmmoInventory.gd`, `entities/interactables/gear_shop/`, and `tools/mdx_pipeline/README.md`.
2. If anything here conflicts with existing code, stop and report it. Don't resolve it silently.
3. Match existing conventions, including how `PATCH_NOTES.md` and `README.md` are updated. Keep comments minimal and use typed GDScript.

---

## 1. Model conversion

Use the existing `tools/mdx_pipeline/mdx_to_gltf.js`. Run `spike.js` on each model first to confirm sequence names and structure.

| Model | Source | Unit |
|---|---|---|
| `banditrouge_dualwield.mdx` | `assets/models/enemies/sampleLegion/Better Bandits/` | Unchartered Cutthroat |
| `banditspearthrower.mdx` | same | Unchartered Javelineer |
| `brigand.mdx` | same | Unchartered Brigand |
| `Enforcer.mdx` | same | Unchartered Enforcer |
| `BanditLord.mdx` | same | Unchartered Chieftain |
| `heropaladin.mdx` | `.../sampleLegion/Omniknight Godhammer/` | Directorate Adjudicator |
| `Arator_Midnights.glb` | already converted | Synod Vindicator |
| `ExarchCandace.mdx` | `.../sampleLegion/Candace Icemoon/Candace Icemoon/` | Synod Exarch |
| `Teron_Gorefiend.mdx` | `.../undead/Teron Gorefiend (Death Knight Hero)/` | Legion Threshold Knight |
| `Progenitor1.mdx` | `.../pinnacle/LordOfTheElements/Progenitor (Sponsored by Missing Shadowsong)/Progenitor/` | Lord of the Elements |

- Calibrate each model's scale against its real mesh bounds, not the declared extents (see the pipeline README). Normal units should read as roughly human-sized next to the 1.8 m player. Elites can be slightly larger, and the Lord of the Elements clearly boss-sized.
- Place each `.glb` next to its source `.mdx`.
- Skip the portrait models, the forest trees and the bushes.
- **Verify visually:** take a windowed screenshot of each imported model, both idle and mid-attack, as was done for Arator.

### 1a. Textures (README "Not yet implemented" item)

Build the material step the pipeline README describes:

- Each exported mesh carries `extras.mdxMaterialId`. Have the converter also write a sidecar JSON per model that maps each geoset to its texture file names (diffuse, normal, ORM, emissive), resolved from `model.Materials` and `model.Textures`.
- Write a Godot tool script that reads the sidecar and builds `ORMMaterial3D` (or `StandardMaterial3D`) resources from the `.dds` files in the model's folder. It then assigns them as surface overrides in each model's wrapper scene (Section 2).
- Apply this to Arator too.
- Some models reference base-game textures that aren't in the folder. The bandits and `heropaladin` are likely cases. Those geosets stay untextured. **List every model and geoset left untextured** in your report.
- Confirm Godot 4.3 imports these `.dds` files correctly, including the normal and ORM maps. If it can't, stop and report.

---

## 2. Model wrapper scenes and animation

`Enemy._apply_model()` drives animation only when the model scene contains an `AnimationTree`. Give each converted model a wrapper scene that follows `UALHumanoidModel.tscn`: the `.glb` plus a `HumanoidAnimTree` instance.

- Add one `AnimationSet` per unit in `data/enemies/animation_sets/`, using the clip map in Section 4. Clip names come from the Hive readmes, so confirm them against the imported `AnimationPlayer`. Use empty strings where a clip doesn't exist.
- Imported clips don't loop. Idle and walk must loop, while attack and death play once. Fix this in one place, in the controller or the wrapper, not per unit.
- Add `model_yaw_offset: float` to `EnemyDefinition` and apply it in `_apply_model()` to `model_forward_yaw_offset`. Arator faces +X and needs `-PI/2`, so measure each model.
- Arator's `Attack 2` bakes identically to `Attack 1` (noted in `FigmentBoss.gd`). Check the other models for the same issue and report any duplicates.

---

## 3. Unit definitions

Create one `EnemyDefinition` `.tres` per unit in `data/enemies/definitions/`. Health and damage come from `archetype_category` + `mob_level` through `Constants.MOB_BASE_*`, so leave `base_health`/`base_damage` at their defaults.

All numbers are placeholders for playtesting.

| File | display_name | faction | category | mob_level | damage_type | attack | move_speed | attack_range | attack_cooldown | stop / retreat | ward_percent | pack |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `unchartered_cutthroat` | Unchartered Cutthroat | `unchartered` | light | 1 | KINETIC | melee | 5.5 | 2.0 | 0.9 | 1.8 / 0 | 0 | 1–3 |
| `unchartered_javelineer` | Unchartered Javelineer | `unchartered` | light | 1 | PIERCING | ranged | 4.5 | 10.0 | 1.6 | 7.0 / 4.5 | 0 | 1–3 |
| `unchartered_brigand` | Unchartered Brigand | `unchartered` | standard | 1 | PIERCING | melee | 3.5 | 2.2 | 1.4 | 2.0 / 0 | 0 | 2–4 |
| `unchartered_enforcer` | Unchartered Enforcer | `unchartered` | heavy | 2 | KINETIC | melee | 2.2 | 2.6 | 2.2 | 2.3 / 0 | 0 | 1–2 |
| `unchartered_chieftain` | Unchartered Chieftain | `unchartered` | elite | 3 | KINETIC | melee | 3.0 | 2.8 | 1.8 | 2.5 / 0 | 0 | 1 |
| `directorate_adjudicator` | Directorate Adjudicator | `directorate` | elite | 3 | KINETIC | melee | 2.6 | 2.8 | 2.0 | 2.5 / 0 | 0.15 | 1 |
| `synod_vindicator` | Synod Vindicator | `synod` | elite | 4 | AETHERIC | melee | 4.5 | 2.4 | 1.2 | 2.1 / 0 | 0.25 | 1 |
| `synod_exarch` | Synod Exarch | `synod` | elite | 4 | COLD | ranged | 3.5 | 14.0 | 2.0 | 9.0 / 6.0 | 0.30 | 1 |
| `legion_threshold_knight` | Legion Threshold Knight | `karvis_legion` | elite | 5 | PALE | melee | 4.0 | 2.6 | 1.5 | 2.3 / 0 | 0.20 | 1 |
| `lord_of_the_elements` | Lord of the Elements | `refined_aetherial` | boss | 10 | FIRE / COLD / LIGHTNING | see §6 | 2.0 | 3.5 | 2.5 | 3.0 / 0 | 0.25 | 1 |

- Fill `lore_description` from the roster doc's **Lore** lines.
- Rarity weights: copy the existing defaults (75 / 20 / 4 / 1). The Lord of the Elements is `EnemyRank.BOSS`, which never auto-rolls.
- Create two generic unit scenes on top of `Enemy.tscn`: `MeleeUnit.tscn` (with an `EnemyMeleeAttack`) and `RangedUnit.tscn` (with an `EnemyRangedAttack`). Units are those scenes plus a `definition`. Set the definition **before** `add_child()`, since `_apply_definition()` runs in `_ready()`.
- Leave `directorate_soldier.tres` and `hollowed_shambler.tres` untouched. They have no models and aren't spawned this pass.

---

## 4. Animation map

`run` uses `Walk 1` for every unit, because no model has a run clip. `stagger` falls back to `hit_reaction` through the existing controller logic.

| Unit | idle | walk | attack_light | attack_heavy | attack_special | hit_reaction | death | death_alt | ability_cast |
|---|---|---|---|---|---|---|---|---|---|
| Cutthroat | Stand 1 | Walk 1 | Attack 1 | Attack 2 | Attack Defend 1 | Stand Hit 1 | Death 1 | Death Fire 1 | — |
| Javelineer | Stand 1 | Walk 1 | Attack 1 | Attack 1 | Attack Defend 1 | Stand Hit 1 | Death 1 | Death Fire 1 | — |
| Brigand | Stand 1 | Walk 1 | Attack 1 | Attack 1 | Attack Defend 1 | Stand Hit 1 | Death 1 | Death Fire 1 | — |
| Enforcer | Stand 1 | Walk 1 | Attack 1 | Attack 2 | Attack Defend 1 | Stand Hit 1 | Death 1 | Death Fire 1 | — |
| Chieftain | Stand 1 | Walk 1 | Attack 1 | Attack 2 | — | — | Death 1 | — | — |
| Adjudicator | unknown, map from `spike.js` output | | | | | | | | |
| Vindicator | Stand 1 | Walk 1 | Attack 1 | Attack 2 | Spell 1 | — | Death 1 | Dissipate | Stand Channel 1 |
| Exarch | Stand 1 | Walk 1 | Attack 1 | Attack 1 | Spell 1 | — | Death 1 | Dissipate | Stand Channel 1 |
| Threshold Knight | Stand 1 | Walk 1 | Attack 1 | Attack 2 | Spell 1 | Stand Hit 1 | Death 1 | Dissipate | Channel |
| Lord of the Elements | Stand 1 | Walk 1 | Attack 1 | Attack 1 | Spell 1 | — | Death 1 | Dissipate | Stand Channel 1 |

The Javelineer's clips are assumed to match the Brigand's, because the readme doesn't list it. Confirm this.

---

## 5. Retire the playtest units

Delete:

- `entities/enemies/glass_cannon/`, `entities/enemies/mobile_bruiser/`, `entities/enemies/heavy_hitter/`
- `data/enemies/definitions/glass_cannon.tres`
- `Constants.EnemyArchetype` and `Enemy.archetype`

Update every reference:

- **`TestArena.tscn`:** replace the three capsules with one instance of each of the 9 non-boss units, spaced in a row.
- **`GeneratedMap.gd`:** replace `ENEMY_SCENES` with pack-based spawning. Each non-start room rolls one pack from a weighted pack table:
  - Normal rooms draw from Unchartered packs, such as Brigand + 1–2 Javelineers, Enforcer + 1–2 Cutthroats, or 2–3 mixed Unchartered.
  - The Vault keeps the FigmentBoss and adds one elite (Chieftain + band, Adjudicator, Vindicator + Exarch, or Threshold Knight).
  - Keep the pack table in data or Constants, not inline in the spawner, following the `ENEMY_RARITY_SPAWN_WEIGHTS` convention.
- **`FigmentBoss`:** it currently uses the Arator model, and Arator now belongs to the Synod Vindicator only. Move FigmentBoss to the **Chieftain model** (`BanditLord.glb`) at boss scale. Its `HEALTH_MULTIPLIER`, `DAMAGE_MULTIPLIER` and `REWARD_MULTIPLIER` are relative to HeavyHitter's hardcoded 220 health and 12 gold. Replace them with values that don't depend on a deleted class, keeping the current effective numbers. Remove its `archetype` line.
- Keep `UALHumanoidModel.tscn`, `HumanoidAnimTree.tscn` and the UAL animation sets, since the new wrappers reuse `HumanoidAnimTree`. Report any UAL resources that end up unreferenced, but don't delete them.

Run a project-wide search afterwards and confirm nothing references the deleted files or enum.

---

## 6. Lord of the Elements in the Pinnacle Arena

- Spawn the Lord of the Elements at `BossSpawnPoint` in `PinnacleArena`, with `rank = BOSS`.
- `EnemyDefinition.damage_type` holds a single type. Give the boss a small boss script, following the `FigmentBoss` convention, that cycles its attack damage type between FIRE, COLD and LIGHTNING. Use one element per attack, in a fixed order, so the pattern is learnable.
- Give its attacks the existing wind-up color flash, tinted with the current element's `Constants.DAMAGE_TYPE_COLOR`.
- Make the arena testable standalone (F6). Spawn the Player at `PlayerSpawnPoint` and add the UI suite, following `GeneratedMap`'s pattern.
- **Out of scope:** how the player reaches the arena, plus the boss's spell, channel and phase mechanics.

---

## 7. Ammo store (Hub)

Add `entities/interactables/ammo_store/AmmoStore.tscn` + `.gd` with the same proximity + `interact` pattern as `GearShop`. Place it in `Hub.tscn` near the Gear and Brand shops.

There is **no menu**. One interact press buys a full resupply:

1. Calculate what's missing:
   - **Reserves:** for each `AmmoType` except ARROW, `max(0, STARTING_AMMO[type] - get_reserve(type))`. Never reduce a reserve that's above the starting amount.
   - **Magazines:** for every ranged weapon in both weapon sets that uses a magazine, `magazine_size - current_magazine`.
2. Cost = sum of missing rounds × a per-`AmmoType` price. Put the prices in a new `Constants.AMMO_ROUND_COST` dict as placeholders. Shotgun and rifle rounds should cost more than pistol and automatic.
3. If nothing is missing, show "Fully stocked" and charge nothing.
4. If `GameState.gold` covers the cost, deduct it, refill the reserves through `AmmoInventory.add()` so `ammo_changed` fires, and fill the magazines. Make sure the HUD updates. Check how the HUD reads the magazine count and emit whatever it listens for.
5. If gold is short, buy nothing and show "Not enough Gold (cost X)". No partial refills.
6. The prompt label shows the live cost while in range, e.g. "Press E to Resupply: 84 Gold".

Cancel any reload in progress when a refill fills that weapon's magazine.

---

## 8. Verification

- A headless test (`godot --headless --script`) that:
  - loads every new definition and checks its health and damage match `Constants.MOB_BASE_*` scaling
  - instantiates both unit scenes with every definition and confirms the model, `AnimationTree` and `AnimationSet` all resolve, with no missing clip names
  - runs `GeneratedMap` generation 20 times without errors, with every spawned enemy coming from the new roster
  - covers the ammo store: a partial refill costs the right amount, a short-gold attempt changes nothing, reserves above the starting amount stay untouched, and a fully stocked press is free
  - confirms no reference remains to `GlassCannon`, `MobileBruiser`, `HeavyHitter` or `EnemyArchetype`
- Windowed screenshots: TestArena showing all 9 units, the Pinnacle Arena with the Lord of the Elements, and the FigmentBoss on its new model.
- Report the files created, modified and deleted, the test results, and the untextured geosets.

---

## 9. Out of scope

- Pack-role logic and every synergy in the roster doc (Hold and pelt, Rattle and rush, Broken band, Sentencing, Chill and close, Ward link, Stabilization)
- Unit kit effects beyond basic attacks: Bleeding, Rattled, Chill on hit, the Brigand's block, and all spells and channels
- The Pale status effect
- Directorate Soldier and Hollowed Shambler models
- Portrait models and dialogue
- A route from the game into the Pinnacle Arena

---

## 10. Open questions

Don't resolve these. Use the default and flag it in your report.

1. **FigmentBoss model.** Default: the **Chieftain model** at boss scale.
2. **Ammo prices.** Default: placeholder `AMMO_ROUND_COST` values.
3. **Refill target.** Default: top up to `STARTING_AMMO`. There's no separate max-reserve cap.
4. **Lord of the Elements element order.** Default: Fire → Cold → Lightning, repeating.
5. **Unit scale.** Default: tune by eye against the player and record each value in the definition's `scale_modifier` or the converter's scale argument, whichever the pipeline already uses.
