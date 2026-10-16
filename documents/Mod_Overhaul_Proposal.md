# Mod Overhaul Proposal (draft)

Implemented in v5.5 (2026-10-16). Where the code differed from this draft:

- **Weapon `min_item_level` is not a gate.** It sets the item level of a weapon mod's Tier 1, and lower tiers roll from level 1. So the "ilvl gates" change in Part 2 was dropped.
- **Many weapon mods were already off weapons** (`ItemRoller.OFF_WEAPON_AFFIXES`), including typed % damage and every vs-afflicted mod. The weapon cuts were added to that list rather than by deleting files, so existing items keep working. The vs-afflicted buffs were skipped because those mods don't roll on weapons.
- **Stamina (shield Composure) already didn't roll,** so the Composure rename was skipped.
- **Hybrid Life + defence stays one mod.** It adds Life plus 40% of the value as Armour or Evasion (120% as Ward), and its text now says so. It wasn't split into three.
- **skill_level_explosive doesn't roll** until Explosive has a skill. skill_level_all is offered on 35% of amulet drops.
- **Retired gear lines use `no_roll`,** so saved items keep them.


Covers the gear pool (`ItemRoller.AFFIX_POOL`, 125 entries) and the weapon affix library (`data/affixes/weapons/`, 104 `.tres`). Jewels, Lenses, Slates and uniques are out of scope, but they reuse many of these stat keys, so cuts and merges here need a follow-up pass on those pools.

## How to read the ranges

- **Gear:** the range shown is the authored `tier1_min`–`tier1_max`, which is **Tier 2**. Tier 1 is that range ×1.25, and each tier below is ×0.8. Mods marked *(levelled)* use their own table in `LEVELLED_TIERS`, so the full T6→T1 span is shown.
- **Weapons:** the range shown is `value_min`–`value_max` and the item-level gate is `min_item_level`.
- **Verdicts:** **Keep** (unchanged), **Keep\*** (keep with small changes: range, slots or wording), **Rework** (the mod stays but changes meaning or scale), **Merge → X** (removed, and its role moves to X), **Cut** (removed), **New** (added).

Slots: H Helmet, B Body, G Gloves, Bt Boots, S Shield, A Amulet, Be Belt, R Ring, W Weapon, * = every slot.

## The problems, in short

1. **Dilution.** Most rare rolls land on mods nobody wants. The amulet has 22 skill-level mods (9 of them exact duplicates), and gloves can roll 16 ailment-chance or ailment-damage mods. An amulet roll is far more likely to be "+1 Explosive Spells" than anything useful.
2. **Dead mods.** Five "increased X damage" ailment mods (Chill, Shock, Electrocute, Unraveling, Pallid) target ailments that deal no damage. Only Bleed, Ignite and Aetherburn read `_ailment_damage_multiplier()`. Explosive has 0 skills, so "+N to Explosive Skills" does nothing.
3. **Exact duplicates.** In code, `skill_level_spell_X` is identical to `skill_level_X`, and `skill_level_spells` is identical to `skill_level_all` (`StatSheet.get_skill_level_bonus()` adds them all the same way). `skill_cooldown_reduced` is aliased to `cooldown_recovery_rate`. On weapons, 9 of the type families each carry their own copy of "+Intellect/Strength/Agility", and 4 different mods give attack speed.
4. **Mods that are strictly worse.** Magic Find (1 MF = 2% Rarity + 0.5% Quantity) beats Item Rarity on the same 7 slots. Every "damage vs Ignited/Chilled/… enemies" mod (34–40) rolls *lower* than the unconditional "increased Fire/Cold/… damage" mod (46–50).
5. **Scales that don't match.** Cast speed is 26–32 against attack speed's 8–12. Physical damage is 28–34 against Elemental/Esoteric's 16–20. Increased Block is 85–95%, which on its own nearly doubles a shield's block. Move speed is 4–8%, too small to feel in first person.
6. **Weapon item-level gates.** Almost every typed weapon mod needs item level 68–80, so below that a weapon can only roll the generic local mods. Early weapons all feel the same. Tiers already scale with level, so the gates aren't needed.
7. **Binary or negative mods taking up rolls.** "Triggers Retaliation on Block" (on or off) and "reduced Projectile Speed" (a downside).

Net result: **gear pool 125 → 95, weapon library 104 → 72**, with almost no build identity lost.

---

## Part 1: gear pool (`AFFIX_POOL`)

### Attributes and core damage

| Mod | Slots now | Now (T2) | Verdict | Proposed |
|---|---|---|---|---|
| flat_strength | * | 20–25 | Keep | 20–25 |
| flat_agility | * | 20–25 | Keep | 20–25 |
| flat_intellect | * | 20–25 | Keep | 20–25 |
| increased_physical_damage | A R | 28–34 | Keep\* | 24–30 (bring the three damage groups in line) |
| elemental_dmg_increased | A R | 16–20 | Rework | 24–30 (undertuned against Physical) |
| esoteric_dmg_increased | A R | 16–20 | Rework | 24–30 |
| increased_spell_damage | H A R | 34–40 | Keep\* | 24–30 (covers every type, so it shouldn't beat the typed mods) |
| minion_damage | H A R | 28–34 | Keep | 28–34 |
| increased_area_damage | H G | 28–34 | Keep | 24–30 |
| crit_chance_increased | G A R | 28–34 | Keep | 28–34 |
| crit_damage_increased | A R | 38–44 | Keep | 38–44 |
| dot_multiplier | A | 7–20 *(levelled)* | Keep | unchanged |

### Penetration

| Mod | Slots now | Now (T2) | Verdict | Proposed |
|---|---|---|---|---|
| fire_penetration | A R | 18–22 | Keep | 18–22 |
| cold_penetration | A R | 18–22 | Keep | 18–22 |
| lightning_penetration | A R | 18–22 | Keep | 18–22 |
| elemental_penetration | A R | 12–16 | Keep | 12–16 |
| physical_shred | G | 18–22 | Keep | 18–22 |
| **esoteric_penetration** | – | – | **New** | A R, 12–16 (Esoteric builds have no penetration at all right now) |

### Speed, cooldowns and costs

| Mod | Slots now | Now (T2) | Verdict | Proposed |
|---|---|---|---|---|
| attack_speed | G R | 8–12 | Keep\* | 10–14 |
| cast_speed | G A R | 26–32 | Rework | 10–14 (same as attack speed) |
| reload_speed | G R | 20–70 *(levelled)* | Rework | Gloves only. Halve the table to 10–35, since Active Reload already speeds up reloads |
| move_speed | Bt | 4–8 | Rework | *(levelled)* T6→T1: 6–9, 10–14, 15–19, 20–24, 25–29, 30–35 (ilvl 1/21/40/61/72/83). Max 35% at T1, to be judged in play |
| dash_speed | Bt | 28–34 | Keep | 28–34 |
| cooldown_recovery_rate | H A | 18–22 | Keep | 18–22 |
| skill_cooldown_reduced | H | 8–12 | Merge → cooldown_recovery_rate | already aliased to it in `stat_keys.gd`; it's the same stat with different wording |
| mana_cost_reduction | H Be | 12–16 | Keep | 12–16 |
| skill_effect_duration | H A | 28–34 | Keep | 28–34 |
| increased_aoe_radius | H G | 34–40 | Keep | 34–40 |
| reduced_projectile_speed | W | 28–34 | Cut | a downside taking up a roll; better as a unique mechanic if it's ever wanted |

### Ailments (the big consolidation)

There are 8 ailments, each with chance, damage and duration mods: 24 mods, mostly on gloves. Weapons already carry chance and damage mods for each type (Part 2), so gear can move to family-level mods.

| Mod | Slots now | Now (T2) | Verdict | Proposed |
|---|---|---|---|---|
| ailment_chance_bleed / ignite / aetherburn | G | 28–34 each | Merge → **damaging_ailment_chance** | **New**, G: "+X% chance to inflict Bleed, Ignite and Aetherburn", 20–26 |
| ailment_chance_chill / shock / electrocute / unraveling / pallid | G | 28–34 each | Merge → **control_ailment_chance** | **New**, G: "+X% chance to inflict Chill, Shock, Electrocute, Unraveling and Pallid", 20–26 |
| increased_ailment_damage_bleed | H G | 38–44 | Keep | 38–44 |
| increased_ailment_damage_ignite | H G | 38–44 | Keep | 38–44 |
| increased_ailment_damage_aetherburn | H G | 38–44 | Keep | 38–44 |
| increased_ailment_damage_chill / shock / electrocute / unraveling / pallid | H G | 38–44 each | Cut | **do nothing**: these ailments deal no damage (5 dead mods) |
| **ailment_effect** | – | – | **New** | H G: "+X% increased effect of Chill, Shock, Electrocute, Unraveling and Pallid", 20–26. Replaces the 5 dead mods with what they were meant to do |
| increased_ailment_duration_× (all 8) | H A | 38–44 each | Merge → **ailment_duration** | **New**, H A: "+X% increased Ailment duration", 20–26 |
| ailment_tick_rate | G | 28–34 | Keep | 28–34 |
| debuff_effectiveness | H A | 8–12 | Merge → curse_effect | the two overlap; the wording "Debuff Effectiveness" is vague |
| curse_effect | H A | 10–14 | Rework | "+X% increased effect of Curses and Debuffs", 10–14 |
| additional_curses | A | 1 (ilvl 61) | Keep | binary but amulet-only and rare, so it works as a chase mod |

**Resource-on-event mods (moved from weapons to gloves and rings):**

| Mod | Slots | Verdict | Proposed (T2) |
|---|---|---|---|
| mana_on_kill | G R | **New** (replaces entropic_of_dissolution) | "Gain X Mana on kill", 12–16 |
| ward_on_kill | G R | **New** (replaces aetheric_of_the_veil, explosive_of_impact) | "X% of max Ward restored on kill", 3–5 (stacks with the base 5%) |
| mana_on_ailment | G R | **New** (replaces fire_of_the_pyre, lightning_of_conductance) | "Gain X Mana when you inflict an Ailment", 4–6 |
| ward_on_ailment | G R | **New** (replaces cold_of_the_frost, pale_of_the_threshold) | "X% of max Ward restored when you inflict an Ailment", 1–2 |

Result: 33 ailment and curse mods become 10.

### Life, mana and ward

| Mod | Slots now | Now (T2) | Verdict | Proposed |
|---|---|---|---|---|
| flat_life | B H G Bt S A Be R | 82.56–103.2 | Keep\* | 80–100 (round numbers) |
| life_increased | H B G Bt S A Be | 8–12 | Keep | 8–12 |
| life_regen_flat | H B G Bt S A Be | 28–36/s | Keep\* | narrow to B S A Be (it's filler on gloves, boots and helmets) |
| life_regen_increased | same | 44–52 | Cut | a multiplier on a base of 0; dead unless you also stack flat regen |
| flat_mana | H A Be | 68–90 | Keep | 68–90 |
| mana_increased | H A Be | 14–18 | Keep | 14–18 |
| mana_regen | H A Be | 1–2/s | Keep | 1–2/s (base is 5/s, so this is already 20–40%) |
| mana_regen_increased | H A Be | 44–52 | Keep | 44–52 |
| damage_from_mana | H B A | 18–22 | Keep | 18–22 |
| flat_aether | A | 40–55 | Keep | 40–55 |
| flat_ward | H B G Bt S R | 16–20 | Rework | own levelled table, T2 45–52 (see Part 3) |
| increased_ward | H B G Bt S | 28–34 | Keep | 28–34 |
| ward_recovery_increased | H B S A Be | 28–34 | Keep | 28–34 |
| ward_delay_reduction | H B S A Be | 0.8–1.2 s | Keep | base delay is 4 s with a 2 s floor, so this matters |
| ward_on_parry | B S | 8–12 | Keep | 8–12 |

### Armour, evasion and mitigation

| Mod | Slots now | Now (T2) | Verdict | Proposed |
|---|---|---|---|---|
| flat_armor | H B G Bt S R | 120–150 | Rework | new levelled table, T2 15–17 (see Part 3) |
| flat_evasion | H B G Bt S R | 16–20 | Rework | same table as flat_armor, T2 15–17 (see Part 3) |
| flat_resilience | * | 16–20 | Keep\* | 16–20, with the DoT curve changed so a mod gives about 11% (see Part 3) |
| increased_armor | H B G Bt S | 28–34 | Keep | 28–34 |
| increased_evasion | H B G Bt S | 28–34 | Keep | 28–34 |
| hybrid_defense_life | H B G Bt S | 33–41 | Rework | the tooltip says "primary defense". Make it three explicit mods (Armour+Life, Evasion+Life, Ward+Life), each limited to bases of that defence. They count as one entry for weighting |
| armor_to_elemental | B S A | 18–22 | Keep | 18–22 |
| evasion_to_spells | B Bt S | 14–18 | Keep | 14–18 |
| reduced_physical_taken | B S | 9–11 | Keep | 9–11 |
| reduced_elemental_taken | B S | 9–11 | Keep | 9–11 |
| reduced_esoteric_taken | B S | 9–11 | Keep | 9–11 |
| phys_as_fire / phys_as_cold / phys_as_lightning | B S A | 8–12 each | Merge → **phys_as_elemental** | **New**: "X% of Physical Damage taken as Elemental", split evenly. Once all three resistances are capped the three versions are the same mod; 12–16 |
| ailment_ignore_chance | B S Be | 14–18 | Keep | 14–18 |
| stamina | B Bt Be | 20–25 | Rework | it's actually shield **Composure** (`ShieldBlock` reads it). Rename it and limit it to S B, since it does nothing without a shield |

### Resistances

| Mod | Slots now | Now | Verdict | Proposed |
|---|---|---|---|---|
| fire_resistance | * (armour, S, jewellery) | 15–48 *(levelled)* | Keep | unchanged |
| cold_resistance | same | 15–48 *(levelled)* | Keep | unchanged |
| lightning_resistance | same | 15–48 *(levelled)* | Keep | unchanged |
| esoteric_resistance | same | 15–48 *(levelled)* | Keep | unchanged (Esoteric is one resistance) |
| all_elemental_resistance | same | 12–16 | Keep | 12–16 |

### Block, parry, riposte and retaliation

| Mod | Slots now | Now | Verdict | Proposed |
|---|---|---|---|---|
| block_chance_bonus | S | 2–8 *(levelled)* | Keep | unchanged |
| increased_block_chance | S | 30–95 *(levelled)* | Rework | 85–95% nearly doubles a shield's block on its own. Rescale the table to 10–30 |
| parry_window_duration | S | 44–52 | Keep | 44–52 |
| increased_riposte_damage | G | 34–44 | Keep | 34–44 |
| riposte_crit_chance | S | 44–52 | Merge → increased_riposte_damage | two riposte-only mods is too narrow; allow riposte damage on S too |
| increased_retaliation_damage | B G S | 54–64 | Keep | 54–64 |
| retaliate_on_block | S | binary | Rework | "X% chance to Retaliate on Block", 25–35, so it has tiers |

### Loot

| Mod | Slots now | Now (T2) | Verdict | Proposed |
|---|---|---|---|---|
| item_rarity | H B G Bt A Be R | 14–20 | Keep\* | narrow to H Bt A R so armour rolls aren't loot filler |
| magic_find | same | 8–12 | Merge → item_rarity | strictly better than item_rarity on the same slots (10 MF = 20% Rarity + 5% Quantity) |
| item_quantity | A Be R | 4–6 | Keep | 4–6 |

### Skill levels (amulet)

| Mod | Now | Verdict | Proposed |
|---|---|---|---|
| skill_level_all | +1 / +2 (T1, ilvl 80) | Keep | unchanged; make it the rarest amulet mod (weight about a third of the others) |
| skill_level_spells | +1 / +2 | Merge → skill_level_all | identical in code |
| skill_level_× (all 9 types) | +1 / +2 | Keep | per type, as now. A type with no skills yet (Explosive today) gets roll weight 0 until it has one, so it can't land as a dead mod |
| skill_level_spell_× (all 9) | +1 / +2 | Cut | identical in code to the matching skill_level_× |

Result: 22 mods become 10.

---

## Part 2: weapon affix library (`data/affixes/weapons/`)

### Changes across every family

- **Remove the `min_item_level` gates of 68–80** on typed mods (set them to 1) and let tiers handle level scaling, the way the generic local mods already do. This is the biggest early-game fix.
- **"Damage vs afflicted enemies" mods should beat unconditional damage**, because they need setup. Raise them from 34–40 to **55–62** (unconditional stays at 46–50).
- **Cut the 9 type-specific attribute suffixes.** The generic `generic_of_strength/agility/intellect` mods remain.
- **Fold duplicate speed and crit mods into the generic local ones.**
- **Ailment chance goes family-level, like gloves.** The 8 per-type chance mods become two generic local mods (below). A weapon's hits would only inflict the ailments of the damage types they deal, so a Fire sword with "damaging ailment chance" Ignites; it doesn't Bleed.
- **Resource-on-event suffixes are cut from weapons.** Their replacements live on gloves and rings (Part 1, Ailments section).

### Generic and local

| Mod | Now | Verdict | Proposed |
|---|---|---|---|
| local_increased_weapon_damage | levelled 30–225 | Keep | unchanged |
| local_flat_weapon_damage | levelled | Keep | unchanged |
| local_hybrid_weapon_damage | levelled | Keep | unchanged |
| local_increased_attack_speed | 8–18 | Keep | unchanged |
| local_increased_crit_chance | 10–30 | Keep | unchanged |
| local_additional_arrows | 1–3 *(levelled)* | Keep | unchanged |
| projectile_speed | 18–26 | Keep | unchanged |
| riposte_damage | 34–44 | Keep | unchanged |
| generic_of_strength / agility / intellect | 24–30 | Keep | unchanged |
| generic_of_conservation | 12–14 | Keep | unchanged |
| generic_of_the_ward (Ward on hit) | 18–24 | Keep | unchanged |
| generic_relentless (vs <35% Life) | 34–40, ilvl 72 | Keep\* | 55–62, ilvl 1 |
| generic_savage | 34–38, ilvl 80 | Keep\* | the tooltip shows dev text ("does not travel through conversion chains"); change it to "X% increased Damage", ilvl 1 |
| generic_deadly (crit damage) | 38–44, ilvl 78 | Keep\* | ilvl 1 |
| generic_fluid (attack speed) | 14–16, ilvl 74 | Merge → local_increased_attack_speed | duplicate |
| generic_of_the_sharp (+crit chance) | 3.5–4.5 | Keep | the only flat base crit mod |
| **local_damaging_ailment_chance** | – | **New** | "+X% chance to inflict Bleed, Ignite and Aetherburn", 28–34 |
| **local_control_ailment_chance** | – | **New** | "+X% chance to inflict Chill, Shock, Electrocute, Unraveling and Pallid", 28–34 |

### Conduit

| Mod | Now | Verdict | Proposed |
|---|---|---|---|
| local_increased_spell_damage | levelled 30–225 | Keep | unchanged |
| local_increased_cast_speed | 8–18 | Keep | unchanged |
| local_additional_spell_projectiles | 1–3 *(levelled)* | Keep | unchanged |

### Typed families (the same pattern repeats for each)

| Family | Unconditional dmg (46–50) | Ailment chance | Ailment dmg/effect | Vs-afflicted | Other prefix | Suffixes |
|---|---|---|---|---|---|---|
| **Fire** | scorching: Keep\* (ilvl 1) | immolating: **Merge → local_damaging_ailment_chance*** | incendiary: Keep | pyretic: Rework 55–62 | – | kindling (Ignite duration): **Merge → incendiary**. of_conflagration (cast speed): **Merge → local cast speed**. of_the_pyre (Mana on Ignite): **Cut**. of_the_calcine (+Int): **Cut** |
| **Cold** | glacial: Keep\* | freezing: **Merge → local_control_ailment_chance*** | biting (Chill effect): Keep | brittle: Rework 55–62 | crystallising (Freeze threshold): Keep | of_permafrost (Chill duration): Keep. of_the_frost (Ward on Chill): **Cut**. of_the_quench (+Int): **Cut** |
| **Lightning** | arcing: Keep\* | discharging: **Merge → local_control_ailment_chance*** | galvanised (Shock effect): Keep\*, drop "(more effective)" from the text | conducting: Rework 55–62 | – | crackling (Electrocute duration): Keep. of_static (attack speed): **Merge → local AS**. of_conductance (Mana on Electrocute): **Cut**. of_the_galvanic (+Int): **Cut** |
| **Kinetic** | impacting: Keep\* | concussive (Stagger): Keep* (Stagger isn't an ailment, so it stays)* | pulverising (Shred effect): Keep | hammering: Rework 55–62 | – | of_rending (attack speed): **Merge → local AS**. of_the_bruiser (Life on hit): Keep. of_the_ironhand (+Str): **Cut** |
| **Piercing** | lancing: Keep\* | haemorrhaging: **Merge → local_damaging_ailment_chance*** | serrated: Keep | – | penetrating (ignore Armour): Keep | barbed (Bleed duration): **Merge → serrated**. of_the_bleeder (Bleed faster): Keep. of_precision (+crit chance): **Merge → generic_of_the_sharp**. of_the_duelist (+Agi): **Cut** |
| **Explosive** | detonating: Keep\* | incendiary (Ignite on explosion): **Merge → local_damaging_ailment_chance*** | shrapnel (Bleed zone): Keep | – | concussive (AoE): Keep. volatile (Stun): Keep | of_detonation ("reduced skill cooldowns"): **Rework** into "+X% Cooldown Recovery Rate" (same stat as gear). of_impact (Ward on kill): **Cut**. of_the_wrecker (+Str): **Cut** |
| **Aetheric** | aetheric: Keep\* | devouring: **Merge → local_damaging_ailment_chance*** | unmaking: Keep | eroding: Rework 55–62 | consuming (Ward drain): Keep | of_resonance (Aether %): Keep. of_the_veil (Ward on kill): **Cut**. of_the_invoke (+Int): **Cut** |
| **Entropic** | entropic: Keep\* | fraying: **Merge → local_control_ailment_chance*** | unraveling (effect): Keep | decaying: Rework 55–62 | dissolving (enemies deal less): Keep | of_collapse (crit damage): **Merge → generic_deadly**. of_dissolution (Mana on kill): **Cut**. of_efface (+Int): **Cut** |
| **Pale** | pallid: Keep\* | draining: **Merge → local_control_ailment_chance*** | hollowing (effect): Keep | threshold: Rework 55–62 | withering (take more damage): Keep | of_fading (Ward Threshold): Keep. of_the_threshold (Ward on Pallid): **Cut**. of_the_hollow (+Int): **Cut** |

Keep\* in this table means: set `min_item_level` to 1 and keep the range.

**Resource-on-event suffixes** (Mana on Ignite, Ward on Chill, Ward/Mana on kill, and so on) are cut from weapons. Four shared versions with real numbers move to gloves and rings instead (see Part 1).

### Exclusive (weapon-type-locked)

| Mod | Now | Verdict | Proposed |
|---|---|---|---|
| excl_assassins_mark (Dagger, vs unaware) | 64–76 | Keep | unchanged |
| excl_of_the_shadow (Dagger, Stealth duration) | 44–52 | Keep | unchanged |
| excl_marksmans (ranged crit damage) | 54–64 | Keep | unchanged |
| excl_colossus (Mace etc., vs Staggered) | 28–34 | Rework | 55–62. Right now it's weaker than kinetic_hammering, which does the same thing on any weapon |
| excl_shattering (Stagger effect) | 44–52 | Keep | unchanged |
| excl_riposte_edge (Rapier/Saber riposte damage) | 54–64 | Keep | unchanged |
| excl_of_the_counterstrike | 18–22 | Keep | unchanged |
| excl_retaliating (Spiked/Buckler) | 44–52 | Rework | 70–80. Right now it's lower than the gear mod (54–64) despite being exclusive |
| excl_of_steadying (shield block) | 8–10 | Keep\* | the text says "% increased" but the value is flat block; change it to "+X% Chance to Block" |
| excl_channelers (Conduit spell damage) | 34–40 | Cut | weaker than local_increased_spell_damage, which Conduits already roll |
| excl_of_the_weave (Conduit mana cost) | 16–20 | Merge → generic_of_conservation | duplicate |
| excl_resonant (Conduit CRR) | 18–22 | Keep | unchanged |

## Part 3: defences re-crunch

### What the numbers say today

Measured with `tests/balance/probe_map_mobs` on the current build. The player is on-level in rare gear; "hit takes" is one hit after defences as a share of Life+Ward. Your accepted target is 5–8% for a standard monster.

| Area Level | Std raw hit | Armour | Std hit takes | Heavy | Elite |
|---|---|---|---|---|---|
| 1 | 14 | 438 | 2.1% | 4.3% | 8.1% |
| 19 | 25 | 373 | 5.4% | 10.3% | 17.8% |
| 40 | 52 | 856 | 6.6% | 12.7% | 22.2% |
| 67 | 131 | 1323 | 17.7% | 32.3% | 54.8% |
| 79 (T11) | 304 | 1853 | 27.9% | 49.9% | 72.8% |
| 89 (T21) | 635 | 1238 | **61.4%** | **86.9%** | **98.2%** |

The target holds up to about AL40, then falls apart. The cause is that things grow at different rates from item level 1 to 91:

| Thing | Growth, level 1 → 89/91 |
|---|---|
| Monster damage | ×20.6 (×47 at T21, with the 1.04 per Tier) |
| Armour bases | ×11.9 (body 262 → 3,124) |
| Evasion bases | ×8.0 (body 260 → 2,071) |
| Ward bases | ×7.0 (body 106 → 746) |
| Player Life | ×1.7 (no level growth, by design) |

Armour is compared against hit size (`Armour / (Armour + 30 × hit)`), so as hits outgrow Armour bases, its reduction falls. By T21 the probe character's 1,238 Armour stops **6%** of a standard hit. Evasion ignores hit size, so it *gains* strength as its bases grow. The two defences pull in opposite directions.

Other problems found while checking:

- **Evasion and Ward bases are about half of Armour's outside the body slot.** At ilvl 91 the gloves have 1,221 Armour, but only 309 Evasion (15% of the Evasion body) or 125 Ward (17%). The Armour gloves are 39% of the Armour body. Helmets and shields show the same gap. Evasion and Ward builds lose out on four of their five slots.
- **Flat mods don't match the bases.** flat_evasion and flat_ward roll 16–20 at T2, which is about 1–3% of a body base, while flat_armor is about 5%. All three use the standard ×0.8 tier decay, so at ilvl 1 the T6 roll is about as big as the whole base.
- **Resilience does nothing in practice.** DoT mitigation is `R / (R + 2000)` and the mod rolls 16–20, so one mod gives about 1%.
- **Armour reduction has no cap.**

### Proposal (monster damage stays at 1.035 per level and 1.04 per Tier)

Monster damage still grows ×20.6 to AL89 (×47 at T21) and Life doesn't grow. So on-level defences have to get *stronger in percentage terms* as you level, not just keep pace. The proposal does that while bringing the displayed numbers down about 15×.

**1. Armour is compared against the hit's size relative to its level, not its raw size:**

`reduction = Armour / (Armour + 10 × hit ÷ damage_scale(attacker level))`, **capped at 90%**.

`damage_scale` is `AreaLevel.damage_scale()` for the attacking monster's own level. Dividing by it turns a hit back into "level-1 units": a standard hit is about 14 at every Area Level, and an elite slam about 35. So:

- Armour numbers no longer need to grow ×20–47 to keep up. Bases can stay small.
- Hit size still matters: Armour does well against trash and poorly against slams, as in v5.3.2.
- Monsters above your level, and Tier damage, are **not** divided out (`gap_damage_multiplier` and the 1.04 per Tier stay in the hit). They still punch through Armour, so pushing content above your level stays dangerous.

**2. Evasion keeps its current level-independent curves with smaller divisors:** dodge `E / (E + 400)`, deflection chance `E / (E + 246)`, deflection mitigation `E / (E + 1368)` (today's ratios between the three, at the new scale). Caps are unchanged: 65 / 75 / 35%.

**3. Armour and Evasion bases share one curve:** `slot_base × 1.0247^(ilvl − 1)` (×9 from ilvl 1 to 91). Every slot gets the same share for both defences, which fixes the half-size Evasion helmets, gloves and boots:

| Slot (top base line) | ilvl 1 | ilvl 23 | ilvl 45 | ilvl 67 | ilvl 91 | Today at ilvl 91 (A / E) |
|---|---|---|---|---|---|---|
| Body | 19 | 32 | 56 | 95 | 171 | 3,124 / 2,071 |
| Helmet | 9 | 15 | 25 | 43 | 77 | 1,401 / 485 |
| Gloves, Boots | 7 | 11 | 20 | 34 | 60 | 1,221 / 309 |
| Heavy shield (Great, Tower, Pavise) | 14 | 25 | 42 | 72 | 129 | 2,487 (Great) |
| Light shield (Buckler) | 8 | 13 | 23 | 39 | 69 | 342 (Buckler) |

**4. Ward stays a Life-like pool in HP, on its own steeper curve:** `slot_base × 1.03^(ilvl − 1)` (×14 over the game). Ward is the only defence measured in HP, so it has to grow roughly with hits to stay useful. Its growth stays a little behind monster damage, so Ward builds still need some mitigation in the late Tiers.

| Slot (top base line) | ilvl 1 | ilvl 23 | ilvl 45 | ilvl 67 | ilvl 91 | Today at ilvl 91 |
|---|---|---|---|---|---|---|
| Body | 40 | 77 | 147 | 281 | 572 | 746 |
| Helmet | 18 | 34 | 66 | 127 | 257 | 171 |
| Gloves, Boots | 14 | 27 | 51 | 98 | 200 | 125 |
| Heavy shield (Warded Barrier) | 30 | 57 | 110 | 211 | 429 | 166 |
| Light shield (Rune) | 16 | 31 | 59 | 113 | 229 | 125 |

In every slot, the lower base lines keep their current ratio to the top line. Hybrids stay at about 60% of each pure value, as now.

**5. The model:** one dedicated build per defence, wearing that defence on all five slots with about +140% increased from mods, 350 Life, and no other layers (block, parry, reduced damage taken, resistances). "Hit takes" is one on-level hit's share of the pool after defences; your target is 5–8% for a standard monster.

| Area Level | Std raw hit | No defences | **Armour** (rating, reduction) | Std | Elite | **Evasion** (rating, dodge) | Std | Elite | **Ward** (pool) | Std |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 14 | 4.0% | 115, 45% | 2.2% | 7.5% | 115, 22% | 3.0% | 7.5% | 240 | 3.6% |
| 19 | 26 | 7.4% | 179, 56% | 3.3% | 12.3% | 179, 31% | 4.9% | 12.3% | 409 | 4.7% |
| 40 | 54 | 15.3% | 298, 68% | 4.9% | 20.7% | 298, 43% | 7.9% | 19.8% | 760 | 5.9% |
| 67 | 136 | 38.7% | 577, 80% | 7.6% | 36.6% | 577, 59% | 12.6% | 31.5% | 1,688 | 7.4% |
| 79 (T11) | 315 | 90.1% | 773, 78% | 19.7% | 92.6% | 773, 65% | 23.3% | 58.3% | 2,407 | 12.3% |
| 89 (T0) | 289 | 82.6% | 986, 88% | 10.3% | 54.1% | 986, 65% | 21.3% | 53.3% | 3,235 | 8.5% |
| 89 (T21) | 659 | 188% | 986, 76% | 46.0% | 210% | 986, 65% | 48.6% | 122% | 3,235 | 19.5% |

What that gives you:

- **Through the Depths (AL1–67), every single-defence build stays in or under your 5–8% band for standard hits.** Today it's 17.7% at AL67.
- **Armour is the best defence against trash and the worst against big hits. Evasion is the reverse.** At AL67 an Evasion build takes less from an elite slam than an Armour build (31.5% against 36.6%), even though it takes more from standard hits. Each defence has a real identity.
- **The high Tiers still need layered builds.** No single defence survives T21 by itself, because the 1.04 per Tier (×2.3 at T21) sits on top of the level curve and all three defences are capped or near it by then. That fits "crafted endgame builds". For example, Armour plus 20% reduced Physical taken plus a shield at 30% block takes about 25% from a T21 standard hit. If T21 feels too punishing in play, the 1.04 per Tier is the lever to pull, not the level curve.

**6. Flat defence mods** get levelled tables, set to about 15% of the top body base at each tier's level:

| Tier (ilvl) | T6 (1) | T5 (21) | T4 (40) | T3 (61) | T2 (72) | T1 (83) |
|---|---|---|---|---|---|---|
| flat_armor, flat_evasion | 2–3 | 4–5 | 6–8 | 11–13 | 15–17 | 20–23 |
| flat_ward | 5–6 | 10–12 | 17–20 | 32–37 | 45–52 | 62–72 |

increased_armor, increased_evasion and increased_ward (28–34%) stay as they are.

**7. Resilience:** change the DoT curve to `R / (R + 150)` (cap stays 50%), so one T2 mod (16–20) gives about 11% and three give about 28%.

**8. Hybrid bases and the Kite shield** (Armour + Evasion) use the same 60% rule, so a hybrid body at ilvl 91 has about 103 Armour and 103 Evasion.

### Knock-on changes to cover when implementing

- **Enemies share these curves.** `Enemy.gd` calls `physical_mitigation()` and `dodge_chance()` on its own `armor_value` and `evasion_value`. Give the player its own functions so this change doesn't move monster time-to-kill.
- Stone Skin's flat +5,000 Armour gets rescaled, to about +300.
- **armor_to_elemental** ("X% of Armour applies to Elemental") uses the same function, so it moves to the new formula with the player.
- The Wiki Defences tab (`DefenceWiki.gd`) and the Character sheet summary read the formulas directly. The Armour table changes from "raw hit" columns to "standard / heavy / elite hit" columns, since raw hit size no longer means the same thing at every level.
- Saves: base values come from the `.tres` files, so regenerated bases (`tools/generate_base_types.gd`) apply to old items automatically. Rolled flat-defence values on existing items get re-rolled at the same tier and roll position from the new tables.
- After the change, rerun `probe_map_mobs` and `probe_power_curve` to confirm the hit shares match the model.

---

## Totals

| | Before | After |
|---|---|---|
| Gear pool entries | 125 | 95 (93 counting the hybrid trio as one) |
| Weapon affixes | 104 | 72 |
| Dead mods | 5 (+ 11 exact code duplicates) | 0 |
| Typed weapon mods available below ilvl 68 | ~0 | all |

## Decisions (2026-10-15)

1. **Ailment chance goes family-level on gloves and on weapons:** damaging (Bleed, Ignite, Aetherburn) and control (Chill, Shock, Electrocute, Unraveling, Pallid).
2. **Resource-on-event mods are cut from weapons** and move to gloves and rings as four shared mods.
3. **Move speed tops out at 35% at T1.** You'll judge in play whether it's too much.
4. **Skill levels stay per type.** Only the 10 exact code duplicates are cut.
5. **Monster damage growth stays at 1.035 per level and 1.04 per Tier.** Part 3 is built around that. These still need your call:
   - Armour compared against level-relative hit size, with a 90% cap;
   - Armour and Evasion bases at ×1.0247 per item level, and Ward at ×1.03;
   - leaving T21 to layered builds rather than single defences.

## Implementation notes (for later)

- Saves: removed stat keys on existing items need a migration that maps merged keys to their replacements (`stat_keys.gd` already has an alias table) and drops cut ones.
- Jewel, Lens, Slate and unique pools reference several of the cut keys (`increased_ailment_duration_*`, `magic_find` in `JewelModifierPool`, and others). They need the same pass.
- The wiki, StatGlossary and StatSources text update with the pool.
- Shard of Tharsis brand-tag pools change size, so check `_pool_for_brand_tag()` doesn't end up empty for any tag.
