extends RefCounted
class_name SkillWeb
## Each spell's passive web (documents/Skill_Webs_Design.md). A spell earns
## one point per level above 1, spent only in its own web. Nodes are either
## shared building blocks (more damage, cheaper, wider...) chosen by the
## spell's tags, or the spell's own twists that change how it behaves.
## Ability.web_points holds what's allocated; Ability.web_value() and
## has_twist() read it, and the spell code applies it.
##
## Layout: the spell sits at the centre; ring 1 is open from the start, each
## outer node needs a point in a node it links from (`requires`).

## Effect keys read by Ability / PlayerAbilityCast.
const MORE_DAMAGE := &"more_damage"        # % more damage per point
const MANA_COST := &"mana_cost"            # % less Mana cost
const COOLDOWN := &"cooldown"              # % cooldown recovery
const AREA := &"area"                      # % increased area
const PROJECTILE_SPEED := &"projectile_speed"
const DURATION := &"duration"
const CRIT := &"crit"                      # + base crit chance, percentage points
const STATUS_CHANCE := &"status_chance"    # + chance for the spell's own ailments, percentage points
const LIMIT := &"limit"
const PROJECTILES := &"projectiles"        # + projectiles (spell decides what that means)
const TWIST := &"twist"                    # behaviour switch, read with has_twist(id)
const CURSE_STRENGTH := &"curse_strength"  # % more curse strength (PlayerAbilityCast.curse_strength())
const MAX_RESISTANCE := &"max_resistance"  # + maximum Resistance, percentage points (Triangulation, Dark Arts)

class WebNode:
	var id: String
	var name: String
	var description: String
	var max_points: int = 1
	var effect: StringName
	var per_point: float = 0.0
	var requires: Array[String] = []
	var exclusive_with: String = ""
	## One of the spell's own nodes (TWISTS), laid out on the twist side even
	## when it adds a value rather than switching behaviour.
	var from_spell := false
	## Placed in a gap of the first ring and opened by the nodes either side.
	var auto_link := false
	## Polar layout: ring (1 = innermost) and angle in degrees.
	var ring: int = 1
	var angle: float = 0.0

	func _init(fields: Dictionary) -> void:
		for key in fields:
			set(key, fields[key])

	func is_twist() -> bool:
		return effect == TWIST

static var _cache: Dictionary = {}  # ability_id -> Array[WebNode]

## Building blocks: [id, name, description template, max, effect, per point,
## predicate key, ring]. Ring 2 blocks need their ring 1 tier.
const BLOCKS := [
	["potency", "Potency", "+%s%% more damage per point.", 3, MORE_DAMAGE, 6.0, "damage", 1],
	["efficiency", "Efficiency", "%s%% less Mana cost per point.", 3, MANA_COST, 6.0, "always", 1],
	["swiftness", "Swiftness", "+%s%% cooldown recovery and cast speed per point.", 3, COOLDOWN, 6.0, "cooldown", 1],
	["reach", "Reach", "+%s%% area per point.", 3, AREA, 8.0, "area", 1],
	["velocity", "Velocity", "+%s%% projectile speed per point.", 3, PROJECTILE_SPEED, 8.0, "projectile", 1],
	["endurance", "Endurance", "+%s%% duration per point.", 3, DURATION, 8.0, "duration", 1],
	["precision", "Precision", "+%s%% critical strike chance per point.", 3, CRIT, 3.0, "damage", 2],
	["affliction", "Affliction", "+%s%% chance to inflict this spell's ailments per point.", 3, STATUS_CHANCE, 6.0, "status", 2],
	["legion", "Legion", "+%s to how many can be active at once per point.", 2, LIMIT, 1.0, "limit", 2],
	["potency_2", "Greater Potency", "+%s%% more damage per point.", 3, MORE_DAMAGE, 6.0, "damage", 3],
	["reach_2", "Greater Reach", "+%s%% area per point.", 3, AREA, 8.0, "area", 3],
	["efficiency_2", "Thrift", "%s%% less Mana cost per point.", 2, MANA_COST, 8.0, "always", 3],
]
## Ring 2/3 blocks hang off these ring 1 blocks (else potency).
const BLOCK_PARENT := {"precision": "potency", "affliction": "potency", "legion": "efficiency",
	"potency_2": "precision", "reach_2": "reach", "efficiency_2": "efficiency"}

## Spell twists: id -> node fields (requires defaults to the first ring 1
## block). Only twists the spell code applies are listed; more come in with
## their spells (documents/Skill_Webs_Design.md).
## Shared by the area curses (Meager, Fracturing, Decompose, Elemental Fragility).
const CURSE_TWISTS := [
	{"id": "hex_potency", "name": "Hex Potency", "description": "+8% curse strength per point.", "ring": 2, "max_points": 3, "effect": CURSE_STRENGTH, "per_point": 8.0},
	{"id": "lingering_hex", "name": "Lingering Hex", "description": "The curse lasts 50% longer.", "ring": 2},
	{"id": "hex_aura", "name": "Hex Aura", "description": "The curse becomes an aura: cast it to switch it on, and every enemy near you stays cursed, 25% stronger, while it drains 8% of your maximum Mana per second. Cast again to switch it off; it ends when your Mana runs dry.", "ring": 3, "requires": ["hex_potency"]},
	{"id": "contagious_hex", "name": "Contagious Hex", "description": "A cursed enemy that dies passes the curse to the nearest enemy.", "ring": 3, "requires": ["lingering_hex"]},
]

const TWISTS := {
	"comet": [
		{"id": "gravity_well", "name": "Gravity Well", "description": "Just before the comet lands, enemies around the spot are dragged toward it.", "ring": 3, "requires": ["reach_2"]},
		{"id": "scorched_earth", "name": "Scorched Earth", "description": "The crater burns for 3 seconds, Igniting enemies who stand in it.", "ring": 2},
		{"id": "molten_core", "name": "Molten Core", "description": "Comet becomes Fire: it burns instead of chilling, and deals its bonus damage to Ignited enemies instead of Chilled ones.", "ring": 2},
		{"id": "meteor_shower", "name": "Meteor Shower", "description": "The strike splits into 3 smaller comets around the target, each dealing 45% damage over 60% of the area.", "ring": 3, "requires": ["molten_core", "reach_2"]},
		{"id": "heavy_mass", "name": "Heavy Mass", "description": "+60% more damage, but the comet falls 50% slower.", "ring": 3, "requires": ["potency_2"]},
	],
	"spark": [
		{"id": "ball_lightning", "name": "Ball Lightning", "description": "The sparks merge into one big, slow ball dealing 80% of all their damage.", "ring": 3, "requires": ["conductor"]},
		{"id": "conductor", "name": "Conductor", "description": "Each spark hit jumps to the nearest other enemy for 50% damage.", "ring": 2},
		{"id": "static_swarm", "name": "Static Swarm", "description": "+1 spark per point.", "ring": 2, "max_points": 3, "effect": PROJECTILES, "per_point": 1.0, "requires": ["velocity"]},
		{"id": "overcharge", "name": "Overcharge", "description": "Sparks move 70% faster and deal 30% more damage, but last half as long.", "ring": 3, "requires": ["static_swarm"], "exclusive_with": "stalking_spark"},
		{"id": "stalking_spark", "name": "Stalking Spark", "description": "Sparks move 40% slower and last twice as long.", "ring": 3, "requires": ["static_swarm"], "exclusive_with": "overcharge"},
	],
	"ice_pulse": [
		{"id": "permafrost", "name": "Permafrost", "description": "The pulse leaves ice on the ground that slows enemies for 3 seconds.", "ring": 2},
		{"id": "shard_volley", "name": "Shard Volley", "description": "The pulse becomes 5 icicles fired ahead of you.", "ring": 2, "exclusive_with": "second_pulse"},
		{"id": "splinters", "name": "Splinters", "description": "+1 icicle per point (Shard Volley).", "ring": 3, "max_points": 4, "effect": PROJECTILES, "per_point": 1.0, "requires": ["shard_volley"]},
		{"id": "frozen_nova", "name": "Frozen Nova", "description": "Icicles fire in a full ring around you instead (Shard Volley).", "ring": 3, "requires": ["shard_volley"]},
		{"id": "second_pulse", "name": "Second Pulse", "description": "A second pulse follows 0.4 seconds later at half damage.", "ring": 2, "exclusive_with": "shard_volley"},
		{"id": "deep_freeze", "name": "Deep Freeze", "description": "Hits on Chilled enemies Freeze them.", "ring": 3, "requires": ["second_pulse", "shard_volley"]},
	],
	"thunder_javelin": [
		{"id": "lightning_rod", "name": "Lightning Rod", "description": "A second after the javelin lands, lightning strikes there for 80% damage.", "ring": 2},
		{"id": "frost_javelin", "name": "Frost Javelin", "description": "The javelin is Cold instead of Lightning and Chills.", "ring": 2},
		{"id": "javelin_volley", "name": "Javelin Volley", "description": "Throws 3 javelins in a fan, each dealing 60% damage.", "ring": 2},
	],
	"cinder_lance": [
		{"id": "ember_trail", "name": "Ember Trail", "description": "The lance leaves a burning line along its whole path for 2 seconds.", "ring": 3, "requires": ["kindling", "potency_2"]},
		{"id": "kindling", "name": "Kindling", "description": "Each enemy the lance passes through makes it 15% stronger and bigger.", "ring": 2},
		{"id": "storm_lance", "name": "Storm Lance", "description": "The lance is Lightning instead of Fire and Shocks.", "ring": 2},
		{"id": "twin_lances", "name": "Twin Lances", "description": "Hurls a second lance in a V, each dealing 75% damage.", "ring": 2},
	],
	"inferno": [
		{"id": "heat_shimmer", "name": "Heat Shimmer", "description": "For 4 seconds after the pillar, you have 25% more Evasion.", "ring": 3, "requires": ["backdraft"]},
		{"id": "backdraft", "name": "Backdraft", "description": "+50% more damage to Ignited enemies.", "ring": 2},
		{"id": "inferno_firestorm", "name": "Firestorm", "description": "Three smaller columns erupt across the area instead of one, each with 50% damage and half the area.", "ring": 2},
		{"id": "conflagration", "name": "Conflagration", "description": "Every hit Ignites.", "ring": 3, "requires": ["inferno_firestorm", "potency_2"]},
	],
	"flame_wall": [
		{"id": "searing_gate", "name": "Searing Gate", "description": "Your projectiles that pass through the wall deal 30% more damage.", "ring": 3, "requires": ["firebreak"]},
		{"id": "firebreak", "name": "Firebreak", "description": "Enemy projectiles that cross the wall burn up.", "ring": 2},
		{"id": "frost_wall", "name": "Frost Wall", "description": "The wall is Cold instead of Fire and Chills instead of igniting.", "ring": 2},
	],
	"flame_jets": [
		{"id": "pressure_valve", "name": "Pressure Valve", "description": "Every 2 seconds of channelling fires a large fireball down the stream for 200% damage.", "ring": 3, "requires": ["afterburn", "potency_2"]},
		{"id": "afterburn", "name": "Afterburn", "description": "Every enemy the jets touch is Ignited, so it keeps burning after leaving the cone.", "ring": 2},
		{"id": "walking_fire", "name": "Walking Fire", "description": "No longer slows you while channelling.", "ring": 2},
		{"id": "blue_flame", "name": "Blue Flame", "description": "+40% more damage, but drains Mana twice as fast.", "ring": 3, "requires": ["walking_fire", "potency_2"]},
	],
	"winters_eye": [
		{"id": "watchful_eye", "name": "Watchful Eye", "description": "The eye turns to follow the nearest enemy.", "ring": 2},
		{"id": "twin_eyes", "name": "Twin Eyes", "description": "Launches two orbs either side of the target, each dealing 60% damage.", "ring": 2},
	],
	"stormcall": [
		{"id": "ground_strike", "name": "Ground Strike", "description": "A second bolt falls on another enemy in range for full damage.", "ring": 2},
		{"id": "hellfire_call", "name": "Hellfire Call", "description": "The strike is Fire instead of Lightning and Ignites.", "ring": 2},
		{"id": "thunderhead", "name": "Thunderhead", "description": "The strike repeats twice more at the same spot, 0.5 seconds apart, at 60% damage.", "ring": 2},
	],
	"static_discharge": [
		{"id": "capacitor", "name": "Capacitor", "description": "Charge builds between casts: up to double damage once 4 seconds have passed since the last.", "ring": 2},
		{"id": "grounded", "name": "Grounded", "description": "Half the radius, double the damage, and every hit Shocks.", "ring": 2, "exclusive_with": "chain_lightning"},
		{"id": "chain_lightning", "name": "Chain Lightning", "description": "Each arc jumps on to up to 3 enemies instead of 1.", "ring": 2, "exclusive_with": "grounded"},
	],
	"thunder_sweep": [
		{"id": "static_field", "name": "Static Field", "description": "Everything the sweep passes through is Shocked.", "ring": 2},
		{"id": "focused_sweep", "name": "Focused Sweep", "description": "Twice the bolts, all fired across the front half.", "ring": 2},
		{"id": "echo_sweep", "name": "Echo", "description": "The sweep repeats 0.6 seconds later, turned half a step, at 70% damage.", "ring": 3, "requires": ["focused_sweep", "potency_2"]},
	],
	"meager": CURSE_TWISTS,
	"fracturing": CURSE_TWISTS,
	"decompose": CURSE_TWISTS,
	"elemental_fragility": CURSE_TWISTS,
	"linger": [
		{"id": "haunting", "name": "Haunting", "description": "An enemy that dies with Linger bursts, dealing 25% of Linger's total damage as Pale to enemies around it.", "ring": 2},
		{"id": "contagion", "name": "Contagion", "description": "When the afflicted enemy dies, Linger moves to the 3 nearest enemies instead of 2.", "ring": 2},
	],
	"pale_thread": [
		{"id": "tether", "name": "Tether", "description": "The threaded enemy can't move more than 6 metres from where it was caught.", "ring": 2},
		{"id": "long_thread", "name": "Long Thread", "description": "The thread holds out to 26 metres instead of 18.", "ring": 2},
	],
	"death_shroud": [
		{"id": "cold_comfort", "name": "Cold Comfort", "description": "Each enemy that dies in the shroud restores 2% of your maximum Ward.", "ring": 2},
		{"id": "grave_chill", "name": "Grave Chill", "description": "Enemies inside the shroud are also Slowed (35% slower).", "ring": 2},
		{"id": "pale_pyre", "name": "Pale Pyre", "description": "Enemies inside the shroud take Pale damage per second equal to 70% of your maximum Life and Ward, scaled by your spell damage. You burn for the same 70% yourself (reduced by Esoteric Resistance and Resilience).", "ring": 2},
	],
	"entropic_decay": [
		{"id": "rot_spreads", "name": "Rot Spreads", "description": "An enemy that dies within 4 seconds of the decay passes it to the nearest enemy for 50% damage.", "ring": 2},
		{"id": "pale_decay", "name": "Pale Decay", "description": "The decay is Pale instead of Entropic and leaves enemies Pallid (they deal less damage).", "ring": 2},
		{"id": "lingering_rot", "name": "Lingering Rot", "description": "The decay spreads out again 1 second later at 60% damage.", "ring": 2},
	],
	"black_hole": [
		{"id": "white_hole", "name": "White Hole", "description": "The collapse throws every enemy outward for 200% damage instead of firing back swallowed shots.", "ring": 3, "requires": ["spaghettify"]},
		{"id": "spaghettify", "name": "Spaghettify", "description": "Damage grows the closer an enemy is pulled in, up to double at the centre.", "ring": 2},
		{"id": "event_horizon", "name": "Event Horizon", "description": "Collapses at the end in a blast of Entropic damage (300%).", "ring": 2},
	],
	"tornado": [
		{"id": "debris", "name": "Debris", "description": "The tornado flings rocks at enemies just outside it for Kinetic damage.", "ring": 2},
		{"id": "firestorm", "name": "Firestorm", "description": "The tornado is Fire and Ignites.", "ring": 2},
		{"id": "twin_funnels", "name": "Twin Funnels", "description": "Summons two smaller tornadoes, each dealing 60% damage.", "ring": 3, "requires": ["firestorm", "legion"]},
	],
	"caltrops": [
		{"id": "barbed_wire", "name": "Barbed Wire", "description": "Enemies that stop on the caltrops are caught for half a second.", "ring": 2},
		{"id": "barbed", "name": "Barbed", "description": "Caltrops inflict Bleed.", "ring": 2},
	],
	"frost_armor": [
		{"id": "cold_snap", "name": "Cold Snap", "description": "Blocking or parrying while the armour holds Chills every enemy around you.", "ring": 2},
		{"id": "rime", "name": "Rime", "description": "Its retaliation always Chills.", "ring": 2},
		{"id": "frost_shatter", "name": "Shatter", "description": "When the armour ends it bursts for 150% Cold damage over a wider area.", "ring": 3, "requires": ["rime", "potency_2"]},
	],
	"booming_blade": [
		{"id": "thunderclap", "name": "Thunderclap", "description": "Every fourth trigger is free and sends twice the bolts.", "ring": 3, "requires": ["resonant_edge"]},
		{"id": "resonant_edge", "name": "Resonant Edge", "description": "The bolts deal 40% more damage to Shocked enemies.", "ring": 2},
		{"id": "arc_blade", "name": "Arc Blade", "description": "Two more bolts, fanned wide.", "ring": 2},
	],
	"blink": [
		{"id": "afterimage", "name": "Afterimage", "description": "Enemies within 5 metres of where you left are dazed for 1 second (not bosses).", "ring": 2},
		{"id": "long_step", "name": "Long Step", "description": "Teleport 60% further.", "ring": 2},
		{"id": "purging_step", "name": "Purging Step", "description": "Blinking removes every debuff on you.", "ring": 2},
	],
	"battle_cry": [
		{"id": "war_drums", "name": "War Drums", "description": "Each enemy within the cry adds 1 second to it, up to 5.", "ring": 2},
		{"id": "rallying_cry", "name": "Rallying Cry", "description": "Also restores 5% of your maximum Life.", "ring": 2},
	],
	"intimidating_shout": [
		{"id": "war_drums", "name": "War Drums", "description": "Each enemy within the shout adds 1 second to it, up to 5.", "ring": 2},
		{"id": "echoing_shout", "name": "Echoing Shout", "description": "The shout rings out again 2 seconds later.", "ring": 2},
	],
	"seismic_cry": [
		{"id": "war_drums", "name": "War Drums", "description": "Each enemy within the cry adds 10% more damage to it, up to 50%.", "ring": 2},
		{"id": "aftershock", "name": "Aftershock", "description": "The slam repeats 0.8 seconds later at half strength.", "ring": 2},
	],
	"reap": [
		{"id": "deaths_tithe", "name": "Death's Tithe", "description": "Each kill with Reap refunds 25% of its Mana cost.", "ring": 2},
		{"id": "withering_scythe", "name": "Withering Scythe", "description": "The scythe is Entropic instead of Aetheric and Unravels.", "ring": 2},
		{"id": "harvest", "name": "Harvest", "description": "Each enemy the scythe hits restores 1% of your maximum Life.", "ring": 2},
		{"id": "wide_arc", "name": "Wide Arc", "description": "The sweep covers 180 degrees, but deals 25% less damage.", "ring": 2},
		{"id": "second_swing", "name": "Second Swing", "description": "The scythe sweeps back again for 50% damage.", "ring": 3, "requires": ["harvest", "wide_arc", "potency_2"]},
	],
	"wraith": [
		{"id": "possession", "name": "Possession", "description": "The first enemy a wraith kills rises as a wraith for 6 seconds, at 60% damage.", "ring": 3, "requires": ["bound_soul"]},
		{"id": "bound_soul", "name": "Bound Soul", "description": "The wraith lasts 50% longer.", "ring": 2},
		{"id": "ward_feast", "name": "Ward Feast", "description": "Every 4 Ward consumed adds damage, instead of every 7.", "ring": 2},
		{"id": "spectral_host", "name": "Spectral Host", "description": "Summons two wraiths that split the Ward between them.", "ring": 3, "requires": ["bound_soul", "ward_feast"]},
	],
	"shatter": [
		{"id": "lingering_frost", "name": "Lingering Frost", "description": "A broken Freeze leaves the enemy Chilled again.", "ring": 3, "requires": ["fault_lines"]},
		{"id": "fault_lines", "name": "Fault Lines", "description": "Also breaks the ailments of every enemy within the spell's area around the target.", "ring": 2},
		{"id": "resonance", "name": "Resonance", "description": "Each ailment broken on an enemy beyond the first adds 25% to all of its bursts.", "ring": 2},
		{"id": "splinter", "name": "Splinter", "description": "Every burst also hits enemies within 3 metres for 40% of its damage.", "ring": 3, "requires": ["resonance", "potency_2"]},
	],
	"purge": [
		{"id": "cleansing_fire", "name": "Cleansing Fire", "description": "Each ailment removed bursts in its element around you for 20% of your maximum Life.", "ring": 2},
		{"id": "second_wind", "name": "Second Wind", "description": "Also restores 10% of your maximum Life.", "ring": 2},
	],
	"thunderstorm": [
		{"id": "downpour", "name": "Downpour", "description": "Enemies under the cloud are slowed as well as Drenched.", "ring": 3, "requires": ["eye_of_the_cloud"]},
		{"id": "eye_of_the_cloud", "name": "Eye of the Cloud", "description": "The enemy at your crosshair is struck twice each round.", "ring": 2},
		{"id": "storm_front", "name": "Storm Front", "description": "The bolts strike every 1.5 seconds instead of every 2.", "ring": 2},
	],
	"nova": [
		{"id": "implosion", "name": "Implosion", "description": "The nova drags enemies toward its centre.", "ring": 3, "requires": ["double_nova"]},
		{"id": "double_nova", "name": "Double Nova", "description": "A second nova bursts 0.5 seconds later for 50% damage.", "ring": 2},
	],
	"puncture": [
		{"id": "riposte_point", "name": "Riposte Point", "description": "Puncture deals double damage to Staggered enemies.", "ring": 3, "requires": ["hemorrhage"]},
		{"id": "hemorrhage", "name": "Hemorrhage", "description": "Puncture always inflicts Bleed.", "ring": 2},
		{"id": "skewer", "name": "Skewer", "description": "The spike also runs through the next enemy in reach.", "ring": 2},
	],
	"invocation_of_arach": [
		{"id": "venom", "name": "Venom", "description": "Spider bites inflict Unraveling and sting for 30% more as Entropic damage.", "ring": 2},
		{"id": "brood", "name": "Brood", "description": "A marked kill raises two spiders.", "ring": 2},
	],
	"inner_power": [
		{"id": "overflow", "name": "Overflow", "description": "While on and at full Life, half your Life regeneration restores Ward.", "ring": 3, "requires": ["focused_mind"]},
		{"id": "focused_mind", "name": "Focused Mind", "description": "You regenerate three times your Mana regeneration as Life, instead of twice.", "ring": 2},
		{"id": "still_waters", "name": "Still Waters", "description": "Inner Power grants 20% more Aetheric damage instead of 10%.", "ring": 2},
	],
	"manasaber": [
		{"id": "echo_of_will", "name": "Echo of Will", "description": "A fainter slash follows 0.3 seconds later for 40% damage.", "ring": 2},
		{"id": "twin_blade", "name": "Twin Blade", "description": "The blade sweeps back again for 50% damage.", "ring": 2},
	],
	"blizzard": [
		{"id": "hailstones", "name": "Hailstones", "description": "Every fifth icicle is a hailstone that Freezes.", "ring": 3, "requires": ["whiteout"]},
		{"id": "eye_of_the_storm", "name": "Eye of the Storm", "description": "You take 15% less damage while standing in your own Blizzard.", "ring": 2},
		{"id": "whiteout", "name": "Whiteout", "description": "Icicles also Chill every enemy within 1.5m of where they land.", "ring": 2},
	],
	"triangulation": [
		{"id": "absorption", "name": "Absorption", "description": "While on, 5% of the Elemental damage your Resistances stop is restored as Mana.", "ring": 2},
		{"id": "high_ground", "name": "High Ground", "description": "+1% to maximum Fire, Cold and Lightning Resistance per point while it is on.", "ring": 2, "max_points": 3, "effect": MAX_RESISTANCE, "per_point": 1.0},
		{"id": "summit", "name": "Summit", "description": "+1% to maximum Fire, Cold and Lightning Resistance per point while it is on.", "ring": 3, "max_points": 2, "effect": MAX_RESISTANCE, "per_point": 1.0, "requires": ["high_ground"]},
	],
	"dark_arts": [
		{"id": "absorption", "name": "Absorption", "description": "While on, 5% of the Esoteric damage your Resistances stop is restored as Mana.", "ring": 2},
		{"id": "forbidden_ground", "name": "Forbidden Ground", "description": "+1% to maximum Esoteric Resistance per point while it is on.", "ring": 2, "max_points": 3, "effect": MAX_RESISTANCE, "per_point": 1.0},
		{"id": "black_summit", "name": "Black Summit", "description": "+1% to maximum Esoteric Resistance per point while it is on.", "ring": 3, "max_points": 2, "effect": MAX_RESISTANCE, "per_point": 1.0, "requires": ["forbidden_ground"]},
	],
	"enchantment": [
		{"id": "kindle_on_crit", "name": "Kindle on Crit", "description": "While on, your critical strikes always inflict the converted element's ailment.", "ring": 3, "requires": ["tempered_edge"]},
		{"id": "tempered_edge", "name": "Tempered Edge", "description": "While on, +10% more damage of the element(s) it converts to.", "ring": 2},
		{"id": "frost_enchant", "name": "Frost Enchant", "description": "Half of the converted damage becomes Cold instead of Fire.", "ring": 2, "exclusive_with": "storm_enchant"},
		{"id": "storm_enchant", "name": "Storm Enchant", "description": "Half of the converted damage becomes Lightning instead of Fire.", "ring": 2, "exclusive_with": "frost_enchant"},
	],
	"innervate": [
		{"id": "wellspring", "name": "Wellspring", "description": "While on, Spells cost 10% less Mana.", "ring": 2},
		{"id": "surge", "name": "Surge", "description": "Switching it off restores 20% of your maximum Mana, once every 30 seconds.", "ring": 3, "requires": ["wellspring"]},
	],
	"charged_reflexes": [
		{"id": "hair_trigger", "name": "Hair Trigger", "description": "While on, the first shot after a reload is always a critical strike.", "ring": 2},
		{"id": "overclock", "name": "Overclock", "description": "45% faster attacks instead of 30%, but each shot drains twice the Mana.", "ring": 2},
		{"id": "steady_hands", "name": "Steady Hands", "description": "Reloads are 70% faster instead of 40%.", "ring": 2},
	],
}

## The web for a spell: its building blocks, then its twists.
static func nodes_for(ability: Ability) -> Array:
	if ability == null:
		return []
	if _cache.has(ability.ability_id):
		return _cache[ability.ability_id]
	var nodes: Array = []
	var present := {}
	for b in BLOCKS:
		if not _applies(ability, b[6]):
			continue
		var node := WebNode.new({"id": b[0], "name": b[1], "description": b[2] % _num(b[5]), "max_points": b[3], "effect": b[4], "per_point": b[5], "ring": b[7]})
		present[node.id] = node
		nodes.append(node)
	for node: WebNode in nodes:
		if node.ring > 1:
			var parent: String = BLOCK_PARENT.get(node.id, "potency")
			if not present.has(parent):
				parent = "potency" if present.has("potency") else "efficiency"
			node.requires.assign([parent])
	var twists: Array = TWISTS.get(ability.ability_id, [])
	var twist_ids := twists.map(func(t): return t["id"])
	var twist_nodes: Array = []
	for fields in twists:
		var f: Dictionary = fields.duplicate()
		if not f.has("effect"):
			f["effect"] = TWIST
		var req: Array[String] = []
		req.assign(f.get("requires", []))
		f.erase("requires")
		var node := WebNode.new(f)
		node.from_spell = true
		node.requires.assign(req.filter(func(id): return present.has(id) or twist_ids.has(id)))
		# A twist that builds on another twist hangs off twists only, so its
		# links stay on the twist side of the web.
		var from_twists := node.requires.filter(func(id): return twist_ids.has(id))
		if not from_twists.is_empty():
			node.requires.assign(from_twists)
		# Otherwise _lay_out() links it to the two first-ring nodes beside it.
		if node.requires.is_empty():
			node.auto_link = true
		present[node.id] = node
		twist_nodes.append(node)
	nodes.append_array(twist_nodes)
	_lay_out(nodes, present)
	_cache[ability.ability_id] = nodes
	return nodes

static func _applies(ability: Ability, key: String) -> bool:
	match key:
		"always": return true
		"damage": return ability.deals_damage()
		"cooldown": return ability.cooldown_seconds > 0.0 or ability.base_cast_time > 0.0
		"area": return ability.has_tag(Ability.TAG_AREA)
		"projectile": return ability.has_tag(Ability.TAG_PROJECTILE)
		"duration": return ability.has_tag(Ability.TAG_DURATION)
		"status": return not ability.applies_status_effects.is_empty()
		"limit": return ability.has_tag(Ability.TAG_LIMIT)
	return false

static func _num(v: float) -> String:
	return str(int(v)) if v == roundf(v) else str(v)

static func find(ability: Ability, node_id: String) -> WebNode:
	for node: WebNode in nodes_for(ability):
		if node.id == node_id:
			return node
	return null

## ---- Points ------------------------------------------------------------------

static func points_available(ability: Ability) -> int:
	return maxi(ability.level - 1, 0)

static func points_spent(ability: Ability) -> int:
	var total := 0
	for id in ability.web_points:
		total += int(ability.web_points[id])
	return total

static func points_left(ability: Ability) -> int:
	return points_available(ability) - points_spent(ability)

static func points_in(ability: Ability, node_id: String) -> int:
	return int(ability.web_points.get(node_id, 0))

## "" when a point can go into node_id, else why not.
static func why_not_allocate(ability: Ability, node_id: String) -> String:
	var node := find(ability, node_id)
	if node == null:
		return "Unknown node."
	if points_left(ability) <= 0:
		return "No points left. Level the spell up for more."
	if points_in(ability, node_id) >= node.max_points:
		return "Already maxed."
	if node.exclusive_with != "" and points_in(ability, node.exclusive_with) > 0:
		return "Can't be taken with %s." % find(ability, node.exclusive_with).name
	if node.ring > 1 and not node.requires.any(func(id): return points_in(ability, id) > 0):
		return "Needs a point in a connected node first."
	return ""

static func allocate(ability: Ability, node_id: String) -> bool:
	if why_not_allocate(ability, node_id) != "":
		return false
	ability.web_points[node_id] = points_in(ability, node_id) + 1
	return true

## Takes one point back, unless a node that depends on this one would be
## left without a connection.
static func refund(ability: Ability, node_id: String) -> bool:
	var have := points_in(ability, node_id)
	if have <= 0:
		return false
	if have == 1:
		for node: WebNode in nodes_for(ability):
			if points_in(ability, node.id) > 0 and node.ring > 1 and node.requires.has(node_id):
				if not node.requires.any(func(id): return id != node_id and points_in(ability, id) > 0):
					return false
	if have == 1:
		ability.web_points.erase(node_id)
	else:
		ability.web_points[node_id] = have - 1
	return true

static func refund_all(ability: Ability) -> void:
	ability.web_points.clear()

## Points the spell no longer has (its level went down): dropped from the
## outermost nodes first.
static func trim_to_available(ability: Ability) -> void:
	var nodes := nodes_for(ability).duplicate()
	nodes.sort_custom(func(a: WebNode, b: WebNode): return a.ring > b.ring)
	for node: WebNode in nodes:
		while points_left(ability) < 0 and points_in(ability, node.id) > 0:
			if points_in(ability, node.id) == 1:
				ability.web_points.erase(node.id)
			else:
				ability.web_points[node.id] = points_in(ability, node.id) - 1

## ---- Layout ------------------------------------------------------------------

## Least angle between neighbours on a ring (outer rings are longer).
const RING_SPACING := {1: 40.0, 2: 30.0, 3: 24.0}

## Angles are degrees clockwise from the top. The first ring's blocks go
## evenly round the whole circle (Potency on top). The spell's twists sit
## in the gaps between them, all the way round, each opened by the two
## blocks beside it, so every branch leads somewhere different. Everything
## else sits near what opens it, then each ring is spaced out.
static func _lay_out(nodes: Array, by_id: Dictionary) -> void:
	var ring1: Array = nodes.filter(func(n: WebNode): return n.ring == 1 and not n.from_spell)
	ring1.sort_custom(func(a: WebNode, b: WebNode): return a.id == "potency" and b.id != "potency")
	for i in ring1.size():
		(ring1[i] as WebNode).angle = 360.0 * i / ring1.size()
	var auto: Array = nodes.filter(func(n: WebNode): return n.auto_link)
	for j in auto.size():
		var node: WebNode = auto[j]
		# The middle of a gap between first-ring blocks, gaps shared out evenly.
		var gaps := maxi(ring1.size(), 1)
		var gap := floori((j + 0.5) * gaps / float(auto.size()))
		var slot := 360.0 * (gap + 0.5) / gaps
		node.angle = slot
		if node.ring == 1:
			continue
		# The two first-ring blocks either side of the slot open it.
		var by_gap := ring1.duplicate()
		by_gap.sort_custom(func(a: WebNode, b: WebNode): return absf(angle_difference(deg_to_rad(a.angle), deg_to_rad(slot))) < absf(angle_difference(deg_to_rad(b.angle), deg_to_rad(slot))))
		node.requires.assign(by_gap.slice(0, mini(2, by_gap.size())).map(func(b: WebNode): return b.id))
	for ring in [2, 3]:
		var group: Array = nodes.filter(func(n: WebNode): return n.ring == ring)
		for node: WebNode in group:
			if node.auto_link:
				continue
			var parents: Array = node.requires.filter(func(id): return by_id.has(id) and by_id[id].ring < ring)
			if parents.is_empty():
				parents = node.requires.filter(func(id): return by_id.has(id) and by_id[id] != node)
			if not parents.is_empty():
				# Parents on opposite sides: hang it off the first, or its links would cross the web.
				if parents.size() > 1 and parents.any(func(id): return absf(angle_difference(deg_to_rad(by_id[id].angle), deg_to_rad(by_id[parents[0]].angle))) > deg_to_rad(120.0)):
					parents = [parents[0]]
					node.requires.assign(parents)
				node.angle = _mean_angle(parents.map(func(id): return by_id[id].angle))
		_space_out(group, RING_SPACING[ring])

## Pushes neighbours on a ring apart until they're `spacing` degrees apart.
static func _space_out(group: Array, spacing: float) -> void:
	var n := group.size()
	if n < 2:
		return
	var sep := minf(spacing, 360.0 / n)
	for _pass in 80:
		group.sort_custom(func(a: WebNode, b: WebNode): return fposmod(a.angle, 360.0) < fposmod(b.angle, 360.0))
		var moved := false
		for i in n:
			var a: WebNode = group[i]
			var b: WebNode = group[(i + 1) % n]
			var gap := fposmod(b.angle - a.angle, 360.0)
			if gap < sep - 0.01:
				var push := (sep - gap) * 0.5
				a.angle -= push
				b.angle += push
				moved = true
		if not moved:
			break
	for node: WebNode in group:
		node.angle = fposmod(node.angle, 360.0)

## Circular mean, in degrees.
static func _mean_angle(angles: Array) -> float:
	var v := Vector2.ZERO
	for a in angles:
		v += Vector2.from_angle(deg_to_rad(a))
	return fposmod(rad_to_deg(v.angle()), 360.0)
