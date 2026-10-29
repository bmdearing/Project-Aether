# Ability Node Proposals (2026-10-29)

New web twists, one or two per ability. **All of them were built on 2026-10-29**
(user: "Build them all"); the web text in `data/abilities/skill_web.gd` is the
current wording. Where the code didn't fit the pitch, the built version differs:

- **Inferno** isn't channelled, so *Backdraft* is +50% more damage to Ignited enemies, and *Heat Shimmer* grants 25% more Evasion for 4 s after the pillar.
- **Flame Jets' Afterburn**: every enemy the jets touch is Ignited.
- **Static Discharge's Capacitor** charges with time since the last cast (double at 4 s), not with a held cast.
- **Thunderstorm** already strikes every enemy under it, so *Eye of the Cloud* strikes the crosshair enemy twice.
- **Booming Blade's Resonant Edge**: +40% against Shocked enemies.
- **White Hole** also hits for 200% as it throws.
- **Linger** already jumps on death, so *Haunting* is a Pale burst (25% of Linger's total) around the body.
- **Wraith's Possession**: the first enemy a wraith kills rises as a wraith for 6 s at 60% damage.
- **Arach's Venom**: Unraveling plus a 30% Entropic sting.
- **Puncture's Hemorrhage**: guaranteed Bleed. *Riposte Point*: double damage to Staggered enemies.
- **Blink's Afterimage**: enemies within 5 m of where you left are dazed 1 s (not bosses). A decoy would need enemy AI changes.
- **Shatter's Aftershock** is named *Lingering Frost* (Seismic Cry already has an Aftershock).
- **Seismic Cry's War Drums**: +10% damage per enemy caught, up to 50%.

Ring 2 = early pick, ring 3 = deep pick (needs a ring 1/2 block first).

## Fire
- **Comet**: *Scorched Earth* (r2): the crater burns for 3 s, igniting enemies who walk in. *Gravity Well* (r3): enemies near the target get pulled to the centre just before the comet lands.
- **Cinder Lance**: *Kindling* (r2): each enemy pierced makes the lance 15% bigger and stronger. *Ember Trail* (r3): leaves a burning line along its whole path for 2 s.
- **Inferno**: *Backdraft* (r2): ending the channel early releases a blast scaled by how long you held it. *Heat Shimmer* (r3): standing in your own Inferno grants 20% Evasion.
- **Flame Jets**: *Afterburn* (r2): enemies that leave the cone keep burning 1.5 s. *Pressure Valve* (r3): every 2 s of channel fires one large fireball down the cone.
- **Flame Wall**: *Firebreak* (r2): enemy projectiles that cross the wall are destroyed. *Searing Gate* (r3): your projectiles that pass through the wall gain added Fire damage.
- **Winter's Eye / Hellfire** (as applicable): *Watchful Eye* (r2): the eye turns to track the nearest enemy.
- **Enchantment**: *Tempered Edge* (r2): +10% more damage with the converted element while on. *Kindle on Crit* (r3): crits always inflict the converted element's ailment.

## Cold
- **Ice Pulse**: *Permafrost* (r2): the pulse leaves ice on the ground that slows enemies 30% for 3 s.
- **Blizzard**: *Eye of the Storm* (r2): you take 15% less damage while standing in your Blizzard. *Hailstones* (r3): every fifth icicle is a hailstone that Freezes.
- **Frost Armor**: *Cold Snap* (r2): blocking or parrying while the armour holds sends out a Chill pulse.
- **Shatter**: *Fault Lines* (r2, **built**): also breaks the ailments of every enemy in the area around the target. *Aftershock* (r3): each broken Freeze leaves the target Chilled again.

## Lightning
- **Spark**: *Conductor* (r2): sparks jump to a second enemy when they hit. *Ball Lightning* (r3): one big, slow spark instead of many.
- **Thunder Javelin**: *Lightning Rod* (r2): the javelin sticks where it lands and calls a bolt on enemies near it 1 s later.
- **Thunder Sweep**: *Static Field* (r2): the sweep leaves Shock on everything it passes through.
- **Static Discharge**: *Capacitor* (r2): holding the cast longer stores more charge, up to 2x damage.
- **Stormcall**: *Ground Strike* (r2): the strike also hits a second random enemy within its radius.
- **Thunderstorm**: *Eye of the Cloud* (r2): the cloud's bolts always strike the enemy nearest your crosshair first. *Downpour* (r3): enemies inside the cloud's radius are Drenched *and* slowed 15%.
- **Booming Blade**: *Resonant Edge* (r2): the bolts hit 40% harder against enemies you struck in the last 2 s. *Thunderclap* (r3): every fourth trigger is free and doubles its bolts.

## Esoteric (Aetheric / Entropic / Pale)
- **Black Hole**: *Spaghettify* (r2): enemies caught in the pull take damage that grows the closer they are to the centre. *White Hole* (r3): the collapse throws enemies outward instead of firing the swallowed shots.
- **Entropic Decay**: *Rot Spreads* (r2): an enemy that dies while affected spreads it to the nearest enemy.
- **Linger**: *Haunting* (r2): Linger jumps to a new target when its target dies.
- **Pale Thread**: *Tether* (r2): the threaded enemy can't move more than 6 m from where it was threaded.
- **Reap**: *Death's Tithe* (r2): each kill with Reap refunds 25% of its Mana cost.
- **Wraith**: *Possession* (r3): the wraith can enter a low-Life enemy and fight for you for 6 s.
- **Death Shroud**: *Cold Comfort* (r2): enemies killed in the shroud restore 2% maximum Ward.
- **Dark Arts / Triangulation**: *Absorption* (r2): resisted damage of those types restores Mana (5% of the resisted amount).
- **Invocation of Arach**: *Venom* (r2): spiders' bites apply a stacking Entropic poison.
- **Inner Power**: *Overflow* (r3): Life regeneration above maximum becomes temporary Ward.
- **Innervate** (new): *Wellspring* (r2): while on, spells cost 10% less Mana. *Surge* (r3): switching it off refunds 20% of your maximum Mana once per 30 s.
- **Aether Rebuke**: *Echo of Will* (r2): a second, weaker slash follows 0.3 s later for 40% damage.

## Physical / Utility
- **Puncture**: *Hemorrhage* (r2): Punctured enemies' Bleeds tick 30% faster. *Riposte Point* (r3): Puncture on a staggered enemy counts as a Riposte.
- **Tornado**: *Debris* (r2): the tornado hurls small rocks at enemies near its edge.
- **Caltrops**: *Barbed Wire* (r2): enemies that stop on caltrops are rooted for 0.5 s.
- **Battle Cry / Intimidating Shout / Seismic Cry**: *War Drums* (r2): each enemy hit by the cry adds 1 s to its buff, up to +5 s.
- **Blink**: *Afterimage* (r2): leaves a decoy where you stood that draws enemy attacks for 2 s.
- **Purge**: *Cleansing Fire* (r2): each ailment removed deals a burst of its element around you.
- **Charged Reflexes**: *Hair Trigger* (r2): the first shot after a reload is a guaranteed crit.
- **Nova**: *Implosion* (r3): the nova pulls enemies in instead of pushing outward.
- **Curses (Meager, Fracturing, Decompose, Elemental Fragility)**: *Contagious Hex* (r3): a cursed enemy that dies passes the curse to the nearest enemy.
