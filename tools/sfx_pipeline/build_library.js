// Writes data/sound/sound_library.tres from assets/sfx/: each SoundLibrary
// slot gets every file matching its pattern (Array slots) or one file.
// Run after process_sfx.js: node tools/sfx_pipeline/build_library.js
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '../..');
const SFX = path.join(ROOT, 'assets/sfx');

// slot -> glob-ish prefix under assets/sfx (Array slots), or [file] for single.
const ARRAYS = {
	pistol_fire: 'weapon/pistol_shot_', revolver_fire: 'weapon/revolver_shot_', shotgun_fire: 'weapon/shotgun_shot_',
	rifle_fire: 'weapon/rifle_shot', automatic_fire: 'weapon/auto_shot_',
	impact_flesh: 'combat/gore_splat_', impact_metal: 'impact/ricochet_', impact_stone: 'impact/ricochet_', impact_wood: 'impact/wood_',
	hit_flesh: 'combat/melee_flesh_hit_', hit_armor: 'combat/shield_block_', parry: 'combat/shield_block_',
	shield_block: 'combat/shield_block_', hit_critical: 'combat/bone_break_', explosion: 'spells/explosion',
	enemy_death: 'combat/body_fall_', item_drop: 'world/item_drop_',
};
const SINGLES = {
	dry_click: 'ui/tick.ogg', pistol_reload: 'weapon/mag_insert_01.ogg', revolver_reload: 'weapon/mag_insert_05.ogg',
	rifle_reload: 'weapon/mag_insert_03.ogg', bolt_cycle: 'ui/mechanism.ogg', lever_cycle: 'ui/mechanism.ogg',
	item_pickup: 'ui/mechanism.ogg', item_equip: 'combat/blade_scrape_03.ogg', brand_use: 'ui/mechanism_long.ogg',
	craft_apply: 'ui/mechanism.ogg', ui_click: 'ui/click.ogg',
};

const files = [];
const walk = (d) => fs.readdirSync(d, { withFileTypes: true }).forEach(e => e.isDirectory() ? walk(path.join(d, e.name)) : e.name.endsWith('.ogg') && files.push(path.relative(SFX, path.join(d, e.name)).split(path.sep).join('/')));
walk(SFX);
files.sort();

const ids = new Map();
const ext = (f) => { if (!ids.has(f)) ids.set(f, ids.size + 2); return `ExtResource("${ids.get(f)}")`; };
const lines = [];
for (const [slot, prefix] of Object.entries(ARRAYS)) {
	const hits = files.filter(f => f.startsWith(prefix));
	if (!hits.length) throw new Error('no files for ' + slot);
	lines.push(`${slot} = Array[AudioStream]([${hits.map(ext).join(', ')}])`);
}
for (const [slot, f] of Object.entries(SINGLES)) {
	if (!files.includes(f)) throw new Error('missing ' + f);
	lines.push(`${slot} = ${ext(f)}`);
}
const head = [`[gd_resource type="Resource" script_class="SoundLibrary" load_steps=${ids.size + 2} format=3]`, '',
	'[ext_resource type="Script" path="res://data/sound/SoundLibrary.gd" id="1"]'];
for (const [f, id] of ids) head.push(`[ext_resource type="AudioStream" path="res://assets/sfx/${f}" id="${id}"]`);
const out = [...head, '', '[resource]', 'script = ExtResource("1")', ...lines, ''].join('\n');
fs.writeFileSync(path.join(ROOT, 'data/sound/sound_library.tres'), out);
console.log(`sound_library.tres: ${Object.keys(ARRAYS).length + Object.keys(SINGLES).length} slots, ${ids.size} files`);
