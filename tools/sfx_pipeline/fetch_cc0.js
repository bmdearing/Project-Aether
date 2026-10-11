// Downloads the CC0 OpenGameArt packs the boss sounds are cut from into
// assets/sound/cc0/<pack>/ (kept out of git with the rest of the raw library).
// Run before process_sfx.js: node tools/sfx_pipeline/fetch_cc0.js
// Needs curl and unzip on PATH, and 7z for the dark magic pack.
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const DEST = path.resolve(__dirname, '../../assets/sound/cc0');
const OGA = 'https://opengameart.org/sites/default/files/';

// pack -> files; every pack is CC0 (opengameart.org/content/<page> in CREDITS.md).
const PACKS = {
	'magic-spell-sfx': ['magical_1_0.ogg', 'magical_2_1.ogg', 'magical_3_1.ogg', 'magical_4_1.ogg', 'magical_5_1.ogg', 'magical_6_0.ogg', 'magical_7_0.ogg'],
	'dark-magic': ['dark_magic.7z'],
	'energy-drain': ['qubodup-PowerDrain.ogg'],
	'ice-spells': ['icespells.zip'],
	'freeze': ['freeze.wav'],
	'ice-shatter': ['IceShatters_0.zip'],
	'sand-spell': ['sand-spell.flac'],
	'earth-spell': ['Earth%20Element%20Magic%20Spell_0.flac'],
	'teleport': ['teleport.wav'],
	'portal': ['PortalSFX.zip'],
	'ufo-beam': ['Beam_0.ogg'],
	'electricity': ['hit.wav', 'groundhit.wav'],
	'ghost-moans': ['qubodup-GhostMoans.zip'],
	'rpg-sfx': ['80-CC0-RPG-SFX_0.zip'],
	'creature2': ['80-CC0-creature-sfx-2.zip'],
	'deep-roar': ['monster_roar.wav'],
	'kenney-scifi': ['sci-fi_sounds.zip'],
	'timehitwind': ['qubodup-timehitwind.zip'],
	'gravity': ['gravity_inverter_0.ogg'],
};

for (const [pack, files] of Object.entries(PACKS)) {
	const dir = path.join(DEST, pack);
	fs.mkdirSync(dir, { recursive: true });
	for (const f of files) {
		const out = path.join(dir, decodeURIComponent(f));
		if (!fs.existsSync(out)) execFileSync('curl', ['-sSfL', '-o', out, OGA + f]);
		if (out.endsWith('.zip')) execFileSync('unzip', ['-o', '-q', out, '-d', dir]);
		if (out.endsWith('.7z')) execFileSync('7z', ['x', '-y', `-o${dir}`, out], { stdio: 'ignore' });
	}
	console.log(`${pack}: ${files.length} file(s)`);
}
