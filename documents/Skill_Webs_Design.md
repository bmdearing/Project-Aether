# Skill Webs

Every spell gets its own passive tree, in the spirit of Last Epoch's skill trees. Levelling a spell (gold plus Crystallized Aether, levels 1 to 20) earns a point that can only be spent in that spell's web. Gear's "+N to level of Spells" raises damage as before but doesn't add web points, so a respec never depends on what you're wearing.

## Rules

- **Points.** One per level above 1, so up to 19 at level 20. A web has about 20 nodes and around 30 points of capacity, so a full web can't be bought: you choose.
- **Nodes.** Each node takes 1 to 5 points. Multi-point nodes scale per point; most one-point nodes change how the spell behaves.
- **Connections.** A node unlocks once any node it's linked from has at least one point. The spell's icon sits at the centre, and the inner ring is always available.
- **Exclusive pairs.** Some twists pull in opposite directions (Spark: faster or slower). Taking one locks the other.
- **Respec.** Right-click takes a point back, as long as no node that depends on it still has points. "Refund all" clears the web for free; respecs are free while the system settles.
- **Saved per spell**, in the save file next to spell levels.

## Node types

Most nodes are shared building blocks, tuned per spell so every web has a solid backbone:

| Building block | Per point | Applies to |
|---|---|---|
| Potency | +6% more damage | damaging spells |
| Efficiency | -6% Mana cost | all |
| Swiftness | +5% cooldown recovery, or cast speed for cast-time spells | all |
| Reach | +8% area | Area spells |
| Velocity | +8% projectile speed | Projectile spells |
| Endurance | +8% duration | Duration spells |
| Precision | +3% base critical strike chance | damaging spells |
| Affliction | +6% chance for the spell's own ailment | spells with an ailment |
| Legion | +1 to the active limit | Limit spells |

The twists are what make each web its own. These are the starting set; the first three spells are the ones you described.

## Twists by spell

**Comet** (Meteor is removed and becomes Comet's fire twist)
- *Molten Core:* Comet becomes Fire. It burns instead of chilling, and its bonus applies against Ignited enemies instead of Chilled ones.
- *Meteor Shower:* the strike splits into 3 smaller comets around the target, each with 45% damage and 60% area.
- *Crater:* the impact leaves a patch that Chills (or Ignites, with Molten Core) for 3 seconds.
- *Heavy Mass:* +60% damage, but the comet falls 50% slower.

**Spark**
- *Static Swarm (3 points):* +1 spark per point.
- *Overcharge* (exclusive with Stalking Spark): sparks move 70% faster and hit 30% harder but last half as long.
- *Stalking Spark* (exclusive with Overcharge): sparks move 40% slower and last twice as long, and each re-hit on the same enemy deals 10% more.
- *Chain Reaction:* a spark that kills an enemy splits into two.

**Ice Pulse**
- *Shard Volley:* the pulse becomes 5 icicle projectiles fired forward; +1 per point in *Splinters* (up to +4).
- *Frozen Nova* (needs Shard Volley): the icicles fire in a full ring around you instead.
- *Deep Freeze:* hits on Chilled enemies Freeze them.
- *Second Pulse:* a weaker pulse follows 0.4 seconds later.

**Thunder Javelin**
- *Forked Bolt:* splits into 3 on the first hit.
- *Storm Spear:* no longer pierces; explodes on impact in a small area.
- *Recall:* returns to you after its range, hitting again on the way back.

**Cinder Lance**
- *Smouldering Trail:* leaves a burning line along its path.
- *Twin Lances:* fires two in a narrow V.
- *Overheat:* each consecutive cast within 2 seconds deals 15% more, up to 5 stacks.

**Inferno**
- *Eternal Flame:* the column lingers for 3 seconds, burning anything inside.
- *Wandering Pyre:* the column drifts toward the nearest enemy.
- *Firestorm:* calls 3 small columns at random spots in the area instead of one.

**Flame Wall**
- *Ring of Fire:* forms a circle around the target instead of a line.
- *Advancing Wall:* the wall slowly pushes away from you.
- *Fuel:* enemies that die in the wall extend its duration.

**Flame Jets**
- *Blue Flame:* +40% damage, but costs Mana twice as fast.
- *Wide Spray:* the cone is 50% wider and 30% shorter.
- *Walking Fire:* no movement slow while channelling.

**Winter's Eye**
- *Blizzard Orb:* the orb stops at the target and fires icicles in place for its whole duration.
- *Split Eye:* the orb splits into two orbs that drift apart.
- *Shatterpoint:* the final detonation is twice as large.

**Stormcall**
- *Thunderhead:* the strike repeats twice more at the same spot, 0.5 seconds apart.
- *Lightning Rod:* forks prefer Shocked enemies and deal 30% more to them.
- *Overload:* every fork that hits adds a fork to the next cast, up to +5.

**Static Discharge**
- *Capacitor:* stores a charge each second (up to 5); each charge adds a chain.
- *Arc Field:* leaves an electrified ring that shocks enemies crossing it.
- *Grounded:* half the radius, but double damage and guaranteed Shock.

**Thunder Sweep**
- *Spiral:* the bolts curve outward in a spiral.
- *Echo:* the sweep repeats 0.6 seconds later, rotated.
- *Focused Sweep:* bolts fire only in a forward cone, but twice as many.

**Entropic Decay**
- *Lingering Rot:* leaves a decaying field for 4 seconds.
- *Contagion:* enemies that die while Unravelled spread Unravelling to those nearby.
- *Collapse:* the field pulls enemies slightly inward.

**Black Hole**
- *Event Horizon:* collapses at the end, dealing heavy Entropic damage.
- *Singularity:* smaller, but pulls far harder.
- *Wandering Void:* drifts slowly toward the densest group of enemies.

**Tornado**
- *Twin Funnels:* each cast summons two smaller tornadoes.
- *Firestorm:* the tornado deals Fire instead and Ignites.
- *Eye of the Storm:* you take 15% less damage while standing inside one.

**Caltrops**
- *Barbed:* inflict Bleed.
- *Scatter Shot:* thrown as a cone in front of you instead of a targeted patch.
- *Tripwire:* the first enemy to step on them is briefly rooted.

**Frost Armor**
- *Glacial Shell:* also grants Ward equal to 10% of max Life while active.
- *Shatter:* when it ends, it explodes for Cold damage around you.
- *Rime:* melee attackers are Chilled.

**Booming Blade**
- *Thunderclap:* bolts end in a small explosion.
- *Arc Blade:* bolts fork once, in a V.
- *Resonance:* each consecutive swing within 1 second adds +1 bolt, up to +3.

**Blink**
- *Afterimage:* leaves a decoy that enemies attack for 2 seconds.
- *Static Step:* deals Lightning damage where you arrive.
- *Double Blink:* stores 2 charges.

**Battle Cry / Intimidating Shout / Seismic Cry**
- *Rallying Cry:* also restores 5% of max Life.
- *Terrify:* enemies flee for 1 second.
- *Aftershock:* Seismic Cry's slam repeats once, half strength.

**Purge**
- *Cleansing Wave:* also removes buffs from nearby enemies.
- *Absolution:* each debuff removed restores 3% of max Mana.

## New spells

**Reap** (Aetheric, Area). A spectral scythe sweeps a 110° cone in front of you for heavy damage.
- *Harvest:* each enemy hit restores 1% of max Life.
- *Wide Arc:* a 180° cone with 25% less damage.
- *Second Swing:* sweeps back the other way for 50% damage.

**Wraith** (Aetheric, Minion). Spends all of your Ward to summon a wraith that fights beside you. It gains damage for every 7 Ward consumed. You can't recover Ward while it lives.
- *Bound Soul:* the wraith lasts 50% longer.
- *Ward Feast:* every 4 Ward consumed adds damage, instead of every 7.
- *Spectral Host:* summons two wraiths that split the Ward.

## Minions

Wraith brings a new tag, **Minion**, with gear and Slate modifiers to match: increased minion damage, minion attack speed, minion life, and minion duration. There's also a new **Minion Brand** for crafting toward minion modifiers.

## Build order

1. The framework: web data per spell, points from level, allocation and respec, saving, and the web view on the Spells screen.
2. Building-block nodes for every spell, wired into the spell's stats.
3. Twists: Comet (with Meteor removed), Spark and Ice Pulse first, then spell by spell.
4. Reap, Wraith and the Minion tag, modifiers and Brand.
