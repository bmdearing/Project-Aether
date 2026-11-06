# Claude Code Brief — Crafting Rev 3 Addendum: Perks, Monster Infrequents & the 4-Line Cap

**Project:** Project Aether · Godot 4.7.1 · GDScript
**Extends:** `Aether_Crafting_Rev3_ClaudeCode_Brief.md` (Residue & the Siphon). Nothing here changes Rev 3's residue, costs or Siphon crafts unless it says so.

Work in four phases. Finish and report each one before starting the next. Phase A should land together with Rev 3 Phase 2, because both change the same limit and rarity rules.

---

## Design intent (read first)

Loot is the weakest part of the game. Stat lines are numbers you can't feel in first person, and the Siphon can build any stat line from any base, so no drop is ever exciting. This addendum gives each layer one job:

- **Drops give you behaviour.** Monster Infrequents (MIs) drop only from specific enemies and carry one **perk**: an effect that changes how you play ("kills reload your weapon", "landing from a jump sends out a shockwave"). The Siphon can't create perks.
- **The Recombinator gets you to two perks.** It's a gamble that destroys items: two items go in, one comes out, and perks can be lost. It's the only way to get a second perk on an item.
- **The Siphon does the numbers.** Rev 3 is unchanged: residue, escalating costs, nothing ever locked.
- **There are fewer stat lines.** Items max out at 4 (2 prefixes and 2 suffixes) and jewels at 2, so each line means more and the item card is easier to read.

Rules that must hold:
- Perks never transfer cleanly. No extraction, no Codex, no unlocking a perk permanently. A perk exists only on the item it dropped on, or on a Recombinator result built from that item.
- Perks change behaviour. They aren't big damage multipliers: "every 3rd shot chains" is a perk, "+80% more damage" is not.
- Uniques and Mythics stay at the top. They never get perks and can't be recombined.

All player-facing names below are placeholders and live only in the text data files.

---

## 0. Before you start

1. Read `Item` (`MAX_PREFIXES`/`MAX_SUFFIXES`), `Constants.AFFIX_LIMITS_GEAR`/`AFFIX_LIMITS_JEWEL`, `ItemRoller`, `JewelRoller`, `GearModifierPool`, `JewelModifierPool`, the Rev 3 Siphon resolver, `SlateRecombinator` and the Recombinator station and screen, `UniqueEffects` (the pattern for gear-driven behaviour), `Enemy._on_died()`/`_roll_drop()`, `Loot`, `LootPickup`, `LootLookCard`, `ItemCard`, `item_serializer`, `SaveManager` and `WikiCatalog`.
2. Report what you'll reuse and anything that conflicts with Rev 3 or the code. If a conflict changes behaviour, stop and report it.
3. **Reuse, don't rebuild.** Perk effects follow the `UniqueEffects` pattern: gear keys summed on equip, with behaviour hooked off `EventBus`. Gear recombining extends `SlateRecombinator` and its station rather than adding a second station.

**Code style:** the same as Rev 3. Use typed GDScript, minimal comments and `StringName` IDs. Names go in text data and numbers go in `Constants` as placeholders.

---

# Phase A — 4-line cap

## A.1 Limits

| | Uncommon | Rare |
|---|---|---|
| Gear (`AFFIX_LIMITS_GEAR`) | 1 prefix / 1 suffix | 2 prefixes / 2 suffixes (3–4 lines) |
| Jewels (`AFFIX_LIMITS_JEWEL`) | 1 line total | 1 prefix / 1 suffix |

- `Item.MAX_PREFIXES` and `MAX_SUFFIXES` become 2.
- Jewels need a total-line cap per rarity, because "1 line, either kind" can't be expressed as a prefix/suffix pair. Add `AFFIX_TOTAL_LIMITS_JEWEL := {UNCOMMON: 1, RARE: 2}` and make `_fitting_rarity`, the Siphon's `add` and `JewelRoller` respect it.
- Rare drops roll 3–4 lines (`ItemRoller`), and Rare jewels always roll 2.
- Slates and Figments are unchanged.
- Perks (Phase B) don't count toward any of these limits.

## A.2 Value rescale

Removing 2 lines from every slot cuts about a third of gear stats. To compensate:
- Multiply every rolling gear explicit's tier values by `STAT_LINE_RESCALE := 1.4`. This means the explicit tables in `ItemRoller.AFFIX_POOL` and the weapon library, not implicits and not jewels.
- Jewel lines get `JEWEL_LINE_RESCALE := 1.3`.
- Skip binary mods (no `%d`) and mods with a hard design cap, such as move speed's 35% at T1. List every skipped mod in your report.
- Rerun `tests/balance/probe_archetypes` and `probe_power_curve` before and after the change, and report both.

## A.3 Old items

- Items and jewels that are already over the new limits keep every line and still work.
- The Siphon's `add` refuses them until they're at or under the limit (a new `OVER_LINE_LIMIT` error). `recast`, `bleed`, `settle`, `absolve`, `anchor` and `sockets` still work. Since `bleed` and `absolve` bring an item under the limit, no item is ever stuck.
- Old values are **not** rescaled. Only new rolls use the new tables.

## A.4 Phase A tests

- Limits hold for drops, the Siphon's `add` and rarity fitting, including the jewel total cap.
- A 6-line legacy item loads unchanged, refuses `add`, and accepts it again after `bleed` takes it to 4 lines.
- A rescaled tier value comes out at about 1.4× the old one. The skip list is honoured.

---

# Phase B — Perks and Monster Infrequents

## B.1 Data

- `PerkDef` resource (`data/perks/<id>.tres`), with these fields:
  - `id: StringName`
  - `slots: Array[int]` (the `EquipmentSlot` values it can roll on)
  - `weapon_kinds: Array[StringName]` (optional: `melee`/`ranged`/`throwing`/`conduit`)
  - `sources: Array[StringName]` (enemy definition file names)
  - `value_min`/`value_max: float` (one rolled number per perk, which can be 0 for binary perks)
  - `effect_key: StringName`
  - `boss: bool`
- Name and description live in `data/perks/perk_text.tres`. The description uses `%d` for the rolled value.
- Each item gets a new `perks: Array[ItemPerk]` field (`id` + `value`). It's kept separate from `affixes` so perks never meet the prefix/suffix, anchoring or Siphon logic. Serialize it, and load old items with an empty list.
- Each item can hold at most `MAX_PERKS := 2` perks.

## B.2 Behaviour

- `PerkEffects`, modelled on `UniqueEffects`: when equipment changes, it collects each equipped item's perks by `effect_key` and runs their behaviour off `EventBus` (kills, hits, landings, blocks, reloads, casts).
- When two copies of the same perk are equipped, they don't stack: the best roll counts.
- Perk text shows on the item card in its own section under the stat lines, styled apart from them.

## B.3 Drops

An MI is an ordinary **Uncommon or Rare** item that also carries one perk. It isn't a separate rarity.

When an enemy that's listed as a source for at least one perk dies, roll:

```
chance = MI_DROP_CHANCE[archetype_category] × MI_RARITY_MULT[enemy rarity] × _reward_mult("gear")
```

If the roll succeeds, the enemy drops one MI:
1. Pick one of the enemy's perks, by equal weight.
2. Pick a base that fits the perk's slots and weapon kinds, at the area's item level, using the normal base rules.
3. Roll the base as Uncommon (`MI_UNCOMMON_WEIGHT`) or Rare (`MI_RARE_WEIGHT`), using the normal affix rolling.
4. Add the perk with its value rolled between `value_min` and `value_max`.
5. Name the item `"<Source>'s <Base name>"` (text data), for example "Hollowed Shambler's Iron Gauntlets".

This roll is separate from the normal gear roll. A kill can drop both.

```
MI_DROP_CHANCE := {light: 0.004, standard: 0.006, heavy: 0.012, elite: 0.04, boss: 0.5}
MI_RARITY_MULT := {NORMAL: 1.0, ELITE: 2.0, CHAMPION: 4.0, ASCENDANT: 8.0}
MI_UNCOMMON_WEIGHT := 3.0
MI_RARE_WEIGHT := 1.0
```

## B.4 Siphon and other crafting

- No Siphon craft adds, removes, rerolls or reads perks. `absolve` leaves them alone.
- The Shard of Tharsis leaves perks alone. A bricked result keeps its perk.
- Perks don't change `craft_count`.

## B.5 Starter perks (placeholders)

All are placeholders for the user to replace. One per source enemy to start, and 20 in total. Before building each one, check that the mechanic it relies on exists. If it doesn't, swap in another perk and say so. Blind and War Cry don't exist; Curses, Marks, knockback and Battle Cry do.

| Source | Slot | Perk |
|---|---|---|
| Unchartered Brigand | ranged weapon | Kills have a (15–25)% chance to fully reload your weapon |
| Unchartered Cutthroat | gloves | Your first hit after (3–2) s without attacking is a Critical Strike |
| Unchartered Javelineer | throwing weapon | Thrown weapons ricochet to (1–2) more enemies |
| Unchartered Enforcer | melee weapon | Heavy melee hits knock enemies back |
| Unchartered Chieftain | amulet | Killing an Elite or stronger triggers Battle Cry |
| Directorate Soldier | ranged weapon | The last round in a magazine deals (60–100)% more damage |
| Directorate Adjudicator | gloves | Hits Mark enemies; your next spell deals (20–35)% more damage to a Marked enemy |
| Legion Dreadknight | shield | Blocking sends out a shockwave that knocks enemies back |
| Legion Threshold Knight | boots | Landing from a jump or ledge climb deals (40–70) Physical damage around you |
| Synod Ember Golem | boots | Sprinting leaves burning ground behind you |
| Synod Aether Golem | conduit / amulet | Every (6–4)th spell you cast is free |
| Synod Warden Golem | body armour | When a hit takes over 20% of your Life, gain Ward equal to (30–50)% of it |
| Synod Exarch | amulet | Kills while airborne restore (8–15) Mana |
| Synod Vindicator | melee weapon | Melee hits on Ignited enemies spread the Ignite to one nearby enemy |
| Veilborne Cantor | gloves | Curses you apply spread to one nearby enemy when the Cursed enemy dies |
| Veilborne Mindbender | helmet | Enemies killed under a control Ailment explode for (5–10)% of their Life as Esoteric damage |
| Hollowed Shambler | helmet | Enemies you kill have a (10–20)% chance to rise and fight for you for 8 s (max 2) |
| Elemental Orb | ring | Your elemental hits cycle Fire → Cold → Lightning, with (20–30)% increased Ailment chance for the current element |
| Sand Globe | belt | Kills release a sand burst that Slows nearby enemies for 2 s |
| Fire Golem | gloves | Igniting an enemy that's already Ignited makes it erupt for (50–80)% of the Ignite's damage |

Boss perks (`boss: true`) are out of scope beyond one test perk. They're meant to be the rare, strong ones.

## B.6 Phase B tests

- An MI only drops from its listed sources, on a base that fits the perk's slots, as an Uncommon or Rare, with the perk value in range.
- Perks survive a save and load, and an old item loads with no perks.
- No Siphon craft or Shard outcome changes perks.
- Two equipped copies of the same perk count once, at the best value.
- For each starter perk, one behaviour check (headless, seeded) that its effect fires.

---

# Phase C — Recombinator for gear

Extend the existing Recombinator station and `SlateRecombinator` (or rename it `Recombinator`) with a gear mode.

## C.1 Rules

- **Inputs:** a **base item** and a **donor item** of the same item type (two rings, two pistols, two helmets). The player chooses which is the base.
- **Refused:**
  - Unique and Mythic items
  - corrupted items
  - items with jewels socketed (take them out first)
  - pairs that have no perks between them
- **Result:** a copy of the base item. Its stat lines, implicits, sockets, quality and anchors are unchanged. The donor gives perks only. This keeps the jobs separate: the Recombinator handles perks, the Siphon handles numbers.
- **Perks:** each perk on either item survives independently with `PERK_KEEP_CHANCE := 0.65`.
  - If both items have the same perk, it's one perk that keeps the better roll and rolls once.
  - If more than `MAX_PERKS` survive, keep 2 at random.
  - If none survive, one random perk from the inputs is kept. The result never has zero perks.
- **Both inputs are consumed.**
- **`craft_count`:** the result takes the higher of the two inputs' counts, the same as Rev 3's Slate rule. A recombine doesn't add to the count.
- **Cost:** `GEAR_RECOMBINE_COST := 100` Gold (placeholder), matching the Slate recombine.
- **Preview** shows each perk's survival chance before the player confirms. The roll is seeded, so reopening the screen can't reroll the result.

## C.2 Phase C tests

- The result keeps the base's lines exactly, and both inputs are gone.
- Perk survival matches 0.65 over a seeded batch. The cap of 2 holds, at least 1 perk always survives, and duplicate perks merge to the better roll.
- Refusals: mismatched types, Unique/Mythic, corrupted, socketed jewels, no perks.
- `craft_count` takes the higher input.

---

# Phase D — Presentation and the Wiki

- **Drop:** an MI gets its own beam colour and drop sound, and stands out from a normal Rare at a distance.
- **Look card (`LootLookCard`)** shows the perk and its source enemy before pickup.
- **Item card:** a perk section with its own accent, under the stat lines.
- **Wiki:** a Monster Infrequents tab listing every perk with its source enemies, slots and value range, so players can farm what they want.
- **Docs:** update `DEVELOPMENT.md` (crafting and loot sections) and add a `PATCH_NOTES.md` entry.
- **Tests:** a UI capture of an MI item card and the Recombinator gear mode, following the `ui_capture` pattern.

---

## Out of scope

- Boss perk content beyond one test perk
- Perk tiers and upgrading a perk by combining two copies (see open question 1)
- Drop table tuning outside MIs: fewer Commons, gear drop rate (see open question 5)
- Final names, art, sounds and beam colours
- Balance: every number is a placeholder

## Open questions

Use the default and flag it in your report.

1. **Combining two copies of the same perk.** Default: they merge to the better roll, with no upgrade. Tiers would give a reason to keep farming one monster, but would roughly double the perk design work.
2. **Which base the Recombinator keeps.** Default: the player chooses it, and the donor gives perks only. The alternative is a 50/50 pick like Slates, with lines pooled from both items.
3. **Guaranteed perk survival.** Default: at least 1 perk always survives. Without this rule, a recombine can wipe out every perk.
4. **MI rarity.** Default: Uncommon or Rare (3:1). An Uncommon MI is a good base to finish with the Siphon.
5. **Common drops.** Default: unchanged here. The loot pass that cuts Common weight (currently 72%) is still separate.
6. **Rescale factors.** Default: ×1.4 for gear lines and ×1.3 for jewel lines, to be checked with the probes.

## Report back

For each phase, report:
- files created, modified and removed
- test results, including the existing suites you touched
- defaults used for open questions
- conflicts found, especially with Rev 3
