# Claude Code Brief — Crafting Rev 3: Residue & the Siphon

**Project:** Project Aether · Godot 4.7.1 · GDScript
**Replaces:** Crafting & Inventory Rev 2 (Orbs, Brands, Edicts, Aether Tolerance). The grid inventory, stash and portals from Rev 2 stay as they are.

Work in three phases. Finish and report each one before starting the next.

---

## Design intent (read first)

Killing enemies fills **residue pools**. At the Hub, the player puts an item into the **Siphon** and spends residue on crafts.

- **Where you hunt decides what you can craft.** An enemy's damage category decides which pool it fills. Typed crafts (Fire, Pale, Armour…) need the matching pool.
- **Generic crafts take any pool.** That covers generic modifiers and mechanics (Mana, Speed, sockets, anchoring and so on). Residue you don't need is never wasted.
- **There's no hard limit per item.** Instead, every craft on an item costs more than the last, up to a cap. No craft can ever become impossible.
- **Only two physical crafting items remain:** Tempering and the Shard of Tharsis.

"Aether" is already the spell-upgrade currency (`Ability.AETHER_CURRENCY`). Never name residue or anything else in this system "Aether". All player-facing names below are placeholders and live only in the text data file.

---

## 0. Before you start

1. Read `CraftingResolver`, `CraftTarget`, `CraftPreview`, `CraftResult`, `CraftingSystem`, `ActiveBrands`, `BrandCombinationResolver` and `CurrencyBag`. Also read `GearModifierPool`, `SlateModifierPool`, `SlateRecombinator`, `CorruptionSystem`, `Enemy._on_died()` / `_roll_drop()`, `GameState`, `SaveManager`, `item_serializer`, `CurrencyShop`, the `SlateStation` / `SlateBenchScreen` pattern, and the inventory crafting flow (`ItemCard.craft_preview_for`).
2. Report what you'll reuse, what you'll remove and anything here that conflicts with the code. If a conflict changes behaviour, stop and report it. Don't resolve it silently.
3. **Reuse, don't rebuild.** Keep the candidate filter, tier rolling, `_describe`, the pool building and the no-side-effects `preview()`. Refactor `CraftingResolver` in place, or rename it `SiphonResolver`. Use whichever leaves less dead code.

**Code style:** match the existing conventions. Use typed GDScript. Keep comments minimal, only where intent isn't obvious. Every stable ID is a `StringName`. Display names, descriptions and errors go in `data/crafting/currency_text.tres`. All numbers are placeholders in `Constants`.

---

# Phase 1 — Residue pools

## 1.1 Pools

| Pool ID | Filled by |
|---|---|
| `residue_physical` | Kills whose damage type is Physical (Kinetic, Piercing, Explosive) |
| `residue_elemental` | Kills whose damage type is Elemental (Fire, Cold, Lightning) |
| `residue_esoteric` | Kills whose damage type is Esoteric (Aetheric, Entropic, Pale) |
| `residue_boss` | `EnemyRank.BOSS` kills only. One shared pool for every boss. |

- Use the existing `Constants.DAMAGE_TYPE_CATEGORY`. If an enemy has no damage type, use its attack's damage type. If it still has none, use Physical.
- Pools are numbers on `GameState`, the same as ammo, and take no grid space. Save them through `SaveManager`. A fresh game starts every pool at 0.
- Every pool has a cap (`RESIDUE_POOL_CAP`, `RESIDUE_BOSS_POOL_CAP`). Any gain above the cap is lost.

## 1.2 Gain on kill

When the player gets credit for a kill (the same place XP is granted in `_on_died()`):

```
amount = RESIDUE_PER_KILL[archetype_category] × RESIDUE_RARITY_MULT[enemy rarity] × _reward_mult("currency")
```

- A boss-rank kill adds this amount to its category pool, and also adds `RESIDUE_BOSS_PER_KILL` to `residue_boss`.
- Record each boss the player has killed, by definition file name. Use an existing record if there is one; otherwise add one to `GameState` and save it. `vestige_add` uses this record.
- Bosses with several damage types (for example the Lord of the Elements) use the category those types share. If the types span more than one category, report it.
- Round to an int, with a minimum of 1.
- Add `EventBus.residue_changed(pool_id: StringName, delta: int, total: int)`.

## 1.3 Constants (placeholders)

```
RESIDUE_PER_KILL := {light: 1, standard: 2, heavy: 3, elite: 5, boss: 40}
RESIDUE_RARITY_MULT := {NORMAL: 1.0, ELITE: 2.0, CHAMPION: 4.0, ASCENDANT: 8.0}
RESIDUE_BOSS_PER_KILL := 10
RESIDUE_POOL_CAP := 8000
RESIDUE_BOSS_POOL_CAP := 2000
```

## 1.4 Phase 1 tests (headless)

- Each category fills the right pool. A boss fills both its category pool and `residue_boss`, and is added to the killed-bosses record.
- Rarity and the reward multiplier scale the amount.
- Caps hold.
- Pools survive a save and load. An old save with no pools loads with every pool at 0.

---

# Phase 2 — Siphon crafting core

## 2.1 Families

A craft can target a **family**, which is a modifier tag. The family decides which pool pays.

| Family tags | Pays from |
|---|---|
| `kinetic`, `piercing`, `explosive`, `armor` | `residue_physical` |
| `fire`, `cold`, `lightning`, `evasion` | `residue_elemental` |
| `aetheric`, `entropic`, `pale`, `ward` | `residue_esoteric` |
| `life`, `mana`, `speed`, `attack`, `spell`, `critical`, `minion`, `dot`, `resistance`, `resilience` | Any regular pool |
| `&""` (unfocused) | Any regular pool |

- Store this as a data table (`CRAFT_FAMILIES`), not as logic. The tag names are the ones the Brands use today.
- A modifier is in a family if it carries that tag (use the existing `affix_tags()`).
- On a Slate, a typed family must match one of the Slate's tags, as the old Category Brands did. If it doesn't, the craft returns `NO_VALID_OUTCOME`.

## 2.2 Crafts

| ID | Family | Effect | Pays from |
|---|---|---|---|
| `add` | optional | Add 1 modifier from the family. If the new set needs a higher rarity, raise the rarity (Common → Uncommon → Rare, using the existing limits). | Family pool |
| `recast` | optional | Remove 1 random non-anchored modifier in the family, then add 1 from the family | Family pool |
| `bleed` | optional | Remove 1 random non-anchored modifier in the family. Rarity is unchanged. | Family pool |
| `absolve` | none | Remove every non-anchored modifier. Rarity drops to the lowest that fits (the existing `_fitting_rarity`). | Any |
| `settle` | optional | Reroll the value of each modifier in the family within its tier. Unfocused also rerolls a Lens's radius. | Family pool |
| `anchor` | none | Anchor **one modifier the player chooses**. The item needs at least `ANCHORING_MIN_MODIFIERS` explicits, and only `MAX_ANCHORED_MODIFIERS` can be anchored. | Any |
| `sockets` | none | Roll sockets from 1 to `max_sockets`. Can be repeated. Refused on Slates, Jewels, items with `fixed_sockets()`, and items that have jewels socketed (remove them first). | Any |
| `retype` | damage type | Change a weapon's `infused_damage_type` to the chosen type, which can't be its current type. Refused on Unique/Mythic items and `NO_INFUSION` items. | That type's pool |
| `restore_type` | none | Clear `infused_damage_type` back to the native type | Any |
| `vestige_add` | boss id | Add 1 modifier from pool `vestige_<id>`. Only bosses in the killed-bosses record can be chosen. | `residue_boss` |

**Removal rules:**
- Anchored modifiers are never removed, replaced or rerolled.
- Unique and Mythic items accept only `sockets`.
- Corrupted items accept only `sockets`.
- `sockets_rolled` no longer limits anything.

## 2.3 Cost and the per-item multiplier

```
cost = ceil(CRAFT_BASE_COST[craft_id] × min(CRAFT_COST_GROWTH ^ craft_count, CRAFT_COST_MULT_CAP))
```

- Add `craft_count: int` to `Item` and `Slate`, and serialize it. Old items load with 0.
- **Every** resolved Siphon craft adds 1 to `craft_count`, including `sockets`, `anchor` and `retype`. A craft that fails validation changes nothing.
- The count never resets. `absolve` does not reset it.
- Tempering and the Shard are not Siphon crafts and don't touch the count.
- Remove Aether Tolerance completely, from Slates too. Leave the `tolerance` fields readable so old saves load, but nothing uses them.
- **Invariant:** for every regular craft, `CRAFT_BASE_COST × CRAFT_COST_MULT_CAP × (1 + FORESIGHT_EXTRA_COST × (FORESIGHT_MAX_OUTCOMES − 1)) ≤ RESIDUE_POOL_CAP`. For boss crafts, the same check uses `RESIDUE_BOSS_POOL_CAP`. Assert this in a test. It's what guarantees no craft, even a full-foresight one, can ever be out of reach.

```
CRAFT_COST_GROWTH := 1.12
CRAFT_COST_MULT_CAP := 10.0
CRAFT_BASE_COST := {add: 20, recast: 30, bleed: 15, absolve: 10, settle: 25,
                    anchor: 120, sockets: 40, retype: 60, restore_type: 20, vestige_add: 10}
```

## 2.4 Payment

- `payment: Dictionary` maps pool IDs to amounts and must add up exactly to the cost.
  - **Typed crafts** pay everything from the family's pool.
  - **Any-pool crafts** can split the cost across the three regular pools. `residue_boss` is never accepted here.
  - **`vestige_add`** pays only from `residue_boss`.
- `auto_payment(cost) -> Dictionary` takes from the fullest regular pool first. The UI can use it as the default.
- If the payment is invalid or can't be afforded, return the failure with **nothing spent**.

## 2.5 Sessions (roll / commit) and foresight

Split rolling from committing, so foresight works without rework. Paying happens up front, so seeing an outcome is never free.

```
preview(item, craft_id, family) -> CraftPreview              # pure: odds + current cost
cost_of(item, craft_id, family, outcomes := 1) -> int
begin(item, craft_id, family, payment, outcomes := 1) -> CraftSession
CraftSession.outcomes: Array[CraftOutcome]                   # simulated, item untouched
CraftSession.choose(index) -> CraftResult
CraftSession.decline() -> CraftResult
```

**`begin`:**
1. Validate the item, the craft and the payment. On any failure, nothing is spent.
2. Spend the residue and add 1 to `craft_count`.
3. Simulate `outcomes` independent results from the current item state.

**Committing:**
- `choose` applies one outcome.
- `decline` leaves the item unchanged. The residue and the count stay spent.
- A normal craft is `begin(..., 1)` followed by `choose(0)`.
- An abandoned session counts as declined.

**Foresight:**
- `GameState.foresight_outcomes` defaults to 0 (off). The player can't access it yet; it's set from a dev toggle only.
- When it's on, the player sees `n` outcomes, where `n` is 1–4 (`FORESIGHT_MAX_OUTCOMES := 4`).
- A foresight craft costs `cost × (1 + FORESIGHT_EXTRA_COST × (n − 1))`, with `FORESIGHT_EXTRA_COST := 0.25`.
- It counts as one craft.

**Events:** keep `craft_completed` and `craft_failed`. Add `EventBus.residue_spent(payment: Dictionary)`.

## 2.6 Tempering (physical item)

- Keep the ID `tempering`, so existing stacks survive. It becomes a crafting consumable next to `shard_of_tharsis`, and drops from that roll.
- **Targets:** every `Weapon` (melee, ranged, throwing and conduits) and every `Armor` piece, including shields. It does not apply to jewellery, belts, quivers, pouches, Jewels or Slates.
- +`TEMPERING_QUALITY_GAIN` per use, up to `get_quality_cap()` (the existing cap, 25).
- **Quality effect:**
  - On a weapon, it's 1% more weapon damage per point, which already exists. Check that ranged, throwing and conduit damage all use `get_quality_multiplier()`, and wire in any that don't.
  - On armour, it's **1% more base defences per point** (Armour, Evasion or Ward, whichever the base has). Wire this in if it doesn't exist.
- It works on corrupted, Unique and Mythic items.
- The art and the final name are out of scope. Use a placeholder icon.

## 2.7 Remove

Remove the following, and list everything removed in your report:
- the Orbs, apart from `tempering`
- Brands, Edicts (including item-level Edicts), `ActiveBrands` and `BrandCombinationResolver`
- Infusion and Shrivening Stones (`retype` and `restore_type` replace them)
- Aether Tolerance
- `ORB_IDS`
- the Orb/Brand/Edict entries in `CURRENCY_DROP_WEIGHTS`, and the `CURRENCY_DROP_CHANCE` drop roll
- their data files and text entries

`CRAFTING_CONSUMABLE_IDS` becomes `[tempering, shard_of_tharsis]`. Drop `test_level_edicts`, and update every other test that used the removed systems.

## 2.8 Figments, Lenses and Slates

- **Figments:** `CraftingSystem.craft_figment()` uses Orb IDs today. Move it to the Siphon as unfocused `add` / `recast` / `bleed` / `absolve` / `settle` at any-pool cost, using the same `craft_count` rules. Empowering stays Gold-priced.
- **Lenses:** the Lenscrafter's Gold services stay as they are. Lenses are also Siphon targets, the same as Jewels.
- **Slates:**
  - A Recombinator result takes the higher `craft_count` of its two inputs.
  - Both Splitter halves inherit the parent's `craft_count`.

## 2.9 Old saves

When loading:
- Every legacy Orb (except Tempering), Brand, Edict, Infusion Stone and Shrivening Stone in the inventory or stash is removed. Each one refunds `LEGACY_CURRENCY_REFUND := 5` to **each** regular pool, up to the cap.
- `active_edict` on items is cleared.
- Saved active Brands are dropped.
- Report how many of each were converted in a test.

## 2.10 Phase 2 tests (headless)

Use a seeded RNG, test content with about 20 gear modifiers, about 10 Slate modifiers and one `vestige_test` pool.

- **Families and payment:**
  - A typed `add` only adds modifiers with that tag, and pays only from the matching pool.
  - An any-pool craft accepts a split payment and rejects `residue_boss`.
  - `vestige_add` pays from `residue_boss` and refuses a boss that isn't in the killed-bosses record.
  - An off-tag family on a Slate fails, and a Hybrid Slate accepts either of its tags.
- **Rarity:** `add` raises rarity only when needed, `bleed` leaves rarity unchanged, and `absolve` drops it to fit.
- **Anchoring:** the chosen modifier is anchored, and survives `recast`, `bleed`, `absolve` and `settle`. The craft fails below the minimum modifier count and above the maximum anchored count.
- **Cost:** it follows the growth curve, holds flat once it reaches the cap, and doesn't reset after `absolve`. The invariant holds for every craft.
- **Failures:** a failed validation spends nothing and doesn't change the count. An unaffordable craft fails the same way.
- **Sockets** reroll repeatedly, and refuse Slates, Jewels, fixed-socket Uniques and items with jewels socketed.
- **Damage type:** `retype` only accepts a damage type other than the current one and pays from that type's pool. `restore_type` clears the infusion.
- **Item restrictions:** corrupted, Unique and Mythic items accept only `sockets`.
- **Sessions:**
  - A declined session spends the residue, increments the count and leaves the item unchanged.
  - Every outcome of a 4-outcome session is valid, and its cost is ×1.75.
  - `preview` probabilities sum to 1.0.
- **Tempering:** caps at 25, applies to ranged weapons and armour, raises armour defences, and refuses jewellery.
- **Figment crafts** work at the Siphon.
- **Legacy migration** converts correctly.

---

# Phase 3 — The Siphon station and UI

- **Siphon:** a Hub interactable. Follow the `SlateStation` / `SlateBenchScreen` pattern: one item box, with the inventory and stash on the side. The screen shows:
  - the three regular pool meters, plus the boss pool once the player has killed a boss
  - the list of crafts, with a family picker on crafts that take one
  - the cost of the next craft and the item's current multiplier
  - the odds from `preview` (reuse `ItemCard.craft_preview_for`)
  - a payment allocator for any-pool crafts, defaulting to `auto_payment`
  - an anchor picker that lets the player click the modifier to anchor
- **Inventory:**
  - Show the pool meters under the grid.
  - The right-click crafting flow now handles only Tempering and the Shard.
  - Remove Brand activation.
- **Currency Exchange (dev convenience):** sell only Tempering and the Shard, and add a "+500 to each regular pool" action.
- **Docs:** update the crafting sections of `DEVELOPMENT.md` (including its flagged gaps) and add a `PATCH_NOTES.md` entry, following the repo's existing conventions.
- **Tests:** a UI capture of the Siphon screen, following the `ui_capture` pattern.

---

## Out of scope

- The rebuild/contribution system and built bases
- How foresight is unlocked, and the foresight UI. Only the engine and the dev toggle are in scope.
- Vestige pool content beyond the single test pool
- Faction-specific crafts, paying in instalments, and prefix/suffix targeting
- Final names and art for Tempering, the Shard, the Siphon and residue
- Balance and drop tuning. Every number is a placeholder.

## Open questions

Use the default and flag it in your report.

1. **Defence families.** Default: Armour → Physical, Evasion → Elemental, Ward → Esoteric, matching the damage categories each one mitigates.
2. **Resistance and Resilience.** Default: generic, so they can be paid from any pool.
3. **Anchoring.** Default: the player chooses the modifier. Rev 2 picked one at random.
4. **Which Vestige pools boss residue can buy from.** Default: any boss the player has killed at least once.
5. **Residue gain scaling with Area Level.** Default: none, so it's flat.
6. **Refund for legacy currency.** Default: 5 per item to each regular pool.

## Report back

For each phase, report:
- files created, modified and removed
- test results, including the existing suites you touched
- defaults used for open questions
- conflicts found
