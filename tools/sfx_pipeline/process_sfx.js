// Cuts the raw library in assets/sound/ (kept out of git and Godot) into
// game-ready Ogg files in assets/sfx/.
//   One-shots: split on silence, each cut trimmed, faded, mono (3D) and peak
//              normalised.
//   Loops:     a window of an ambience, loudness matched, with its end
//              crossfaded into its start so it loops seamlessly.
// Run: node tools/sfx_pipeline/process_sfx.js   (needs ffmpeg on PATH)
const { execFileSync, spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');
const RAW = path.join(ROOT, 'assets/sound');
const OUT = path.join(ROOT, 'assets/sfx');

// src: raw file; out: output stem (numbered when several); merge: gaps shorter
// than this join two sounds; min/max: cut length limits; skip: indices to
// drop; take: cap on cuts; pitch: playback-rate factor; stereo: keep both
// channels (2D sounds); peak: target peak dBFS; tail: seconds kept after the
// sound falls below the silence threshold; threshold: silence level in dB;
// cuts: explicit [start, length] pairs instead of silence detection.
const ONE_SHOTS = [
	{ src: 'combat/GOREBone_Bone Breaks Celery 01_JSE_GMP.wav', out: 'combat/bone_break', merge: 0.3 },
	{ src: 'combat/GOREFlsh_Flesh Drops on Floor 03_JSE_GMP.wav', out: 'combat/body_fall', merge: 0.3, min: 0.4, max: 1.3 },
	{ src: 'combat/GORESplt_Gore Splatter 01_JSE_GMP.wav', out: 'combat/gore_splat', merge: 0.3 },
	{ src: 'weapon/WEAPAxe_Long Two-Handed Axe Flesh Hit_JSE_MW.wav', out: 'combat/melee_flesh_hit', merge: 0.3 },
	{ src: 'weapon/WEAPArmr_Metal Shield Block Hits_JSE_MW.wav', out: 'combat/shield_block', merge: 0.3 },
	{ src: 'weapon/WEAPSwrd_Weapon 03 Slow Scrapes_JSE_MW.wav', out: 'combat/blade_scrape', merge: 0.3 },
	{ src: 'weapon/WEAPAxe_One-Handed Axe Drops_JSE_MW.wav', out: 'world/item_drop', merge: 0.15 },
	{ src: 'environment/MECHMisc_Ricochet Hits 01_JSE_SG.wav', out: 'impact/ricochet', merge: 0.2, skip: [4] },
	{ src: 'environment/WOODBrk_Snap09_InMotionAudio_Wood.wav', out: 'impact/wood', merge: 0.1 },
	{ src: 'environment/AIRBrst_Steam Release Short 03_JSE_SG_Mono.wav', out: 'world/steam_burst', merge: 0.3 },
	{ src: 'spells/EXPLReal_Medium Realistic Explosion 15_DDUMAIS_NONE.wav', out: 'spells/explosion', merge: 1.0 },
	{ src: 'weapon/GUNRif_SVD Dragunov 7.62×54R SOURCE Single Shots 30m Front MikroUsi_DRCA_DRAG_AB.wav', out: 'weapon/rifle_shot', merge: 0.3, tail: 0.25 },
	// Pitched down and longer, the rifle stands in for shotguns.
	{ src: 'weapon/GUNRif_SVD Dragunov 7.62×54R SOURCE Single Shots 30m Front MikroUsi_DRCA_DRAG_AB.wav', out: 'weapon/shotgun_shot', merge: 0.3, tail: 0.35, pitch: 0.8, take: 5 },
	{ src: 'weapon/GUNRif_SVD Dragunov 7.62×54R DESIGNED Single Shot Core Long_DRCA_DRAG_Stereo_05.wav', out: 'weapon/rifle_shot_heavy', merge: 1.0 },
	{ src: 'weapon/Dan Wesson 445 - FIRING - Take 2 - 1m Above - MKH8060.wav', out: 'weapon/revolver_shot', merge: 0.6, tail: 0.2 },
	// The same revolver, pitched up and cut short, stands in for pistols.
	{ src: 'weapon/Dan Wesson 445 - FIRING - Take 2 - 1m Above - MKH8060.wav', out: 'weapon/pistol_shot', merge: 0.6, tail: 0.1, pitch: 1.22, max: 0.9 },
	{ src: 'weapon/Ak 5 - FIRING - Hit Metal Armor Plate - Single Shots 2 - HANDHELD NEAR SHOOTER - MS - 418-S.wav', out: 'weapon/auto_shot',
		cuts: [0.78, 7.57, 13.94, 19.70, 25.59, 30.75, 35.59, 40.95].map(t => [t - 0.03, 0.75]) },
	{ src: 'weapon/GUNMech_SVD Dragunov 7.62×54R SOURCE Magazine Insert Slow_DRCA_DRAG_CO-100K.wav', out: 'weapon/mag_insert', merge: 0.5, min: 0.3 },
	{ src: 'ui/mainMenu/UIClick_UI Click 33_CB Sounddesign_ACTIVATION2.wav', out: 'ui/click', stereo: true, peak: -3, merge: 1.0, threshold: -60 },
	{ src: 'ui/mainMenu/Bluezone_BC0301_tiny_gears_small_mechanism_click_003.wav', out: 'ui/tick', stereo: true, peak: -3, merge: 1.0, threshold: -60 },
	{ src: 'ui/mainMenu/Bluezone_BC0301_tiny_gears_small_mechanism_click_complex_011.wav', out: 'ui/mechanism', stereo: true, peak: -3, merge: 1.0, threshold: -60 },
	{ src: 'ui/mainMenu/Bluezone_BC0301_tiny_gears_small_mechanism_sequence_045.wav', out: 'ui/mechanism_long', stereo: true, peak: -3, merge: 1.0, threshold: -60 },
	{ src: 'environment/MECHGear_Tiny Rotation 01_JSE_SG_Stereo.wav', out: 'ui/gear_turn', stereo: true, peak: -3, merge: 0.3, min: 0.3, take: 4 },
];

// start/length in seconds; lufs: target integrated loudness.
const LOOPS = [
	{ src: 'ui/mainMenu/RAIN_Rain at Night Slow Crescendo Calm Suburban_BOLT_BackyardRain_UsiPro.wav', out: 'ambience/rain', start: 180, length: 90 },
	{ src: 'environment/AMBDsgn_Factory Hall with Large Steam Mashines 02_JSE_SG.wav', out: 'ambience/factory_hall', start: 5, length: 75 },
	{ src: 'environment/DSGNErie_EerieBoilerRoom06_InMotionAudio_Sinister Textures Volume 1.wav', out: 'ambience/boiler_room', start: 5, length: 75 },
	{ src: 'environment/DSGNErie_EerieSubway01_InMotionAudio_Sinister Textures Volume 1.wav', out: 'ambience/eerie_tunnel', start: 20, length: 90 },
	{ src: 'environment/Wind - Aspen - Gusts - Close - Inside Canopy - XY - MKH8060.wav', out: 'ambience/wind_gusts', start: 10, length: 90 },
	{ src: 'environment/Wind - Oak - Calm - Close - Inside Canopy - XY - MKH8060.wav', out: 'ambience/wind_calm', start: 90, length: 90 },
	{ src: 'environment/AMBForst_Forest04_InMotionAudio_TheForestSamples.wav', out: 'ambience/forest', start: 2, length: 70 },
	{ src: 'environment/Calm_River_02.wav', out: 'ambience/river', start: 10, length: 60 },
];
const LOOP_LUFS = -24;
const LOOP_FADE = 3.0;
// Quiet recordings aren't pushed past this, so their hiss stays down.
const LOOP_MAX_GAIN = 12;

// Thunder claps cut from the storm recording: [start, end] seconds.
const THUNDER_SRC = 'ui/mainMenu/RAIN_Distant Thunder and Rain Long Thunderstorm C_BOLT_BackyardRain_UsiPro.wav';
const THUNDER = [[2.5, 11.5], [38.5, 44.5], [61.0, 67.0], [74.5, 85.0], [107.0, 117.0]];

const ff = (args) => execFileSync('ffmpeg', ['-hide_banner', '-nostats', '-y', ...args], { stdio: ['ignore', 'pipe', 'pipe'] });
const ffErr = (args) => spawnSync('ffmpeg', ['-hide_banner', '-nostats', ...args], { maxBuffer: 1 << 26 }).stderr.toString();
const duration = (file) => parseFloat(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', file]).toString());

function segments(file, threshold, merge) {
	const total = duration(file);
	const log = ffErr(['-i', file, '-af', `silencedetect=noise=${threshold}dB:d=0.05`, '-f', 'null', '-']);
	const starts = [...log.matchAll(/silence_start: (-?[0-9.]+)/g)].map(m => parseFloat(m[1]));
	const ends = [...log.matchAll(/silence_end: ([0-9.]+)/g)].map(m => parseFloat(m[1]));
	// Sound runs from each silence end (or 0) to the next silence start (or the end).
	const sounds = [];
	let cursor = 0;
	for (let i = 0; i < starts.length; i++) {
		const s = Math.max(starts[i], 0);
		if (s > cursor + 0.005) sounds.push([cursor, s]);
		cursor = i < ends.length ? ends[i] : total;
	}
	if (cursor < total - 0.01) sounds.push([cursor, total]);
	const merged = [];
	for (const seg of sounds) {
		const last = merged[merged.length - 1];
		if (last && seg[0] - last[1] < merge) last[1] = seg[1];
		else merged.push([...seg]);
	}
	return { merged, total };
}

function peakDb(file, start, len) {
	const log = ffErr(['-ss', `${start}`, '-t', `${len}`, '-i', file, '-af', 'volumedetect', '-f', 'null', '-']);
	const m = log.match(/max_volume: (-?[0-9.]+) dB/);
	return m ? parseFloat(m[1]) : 0;
}

function oneShot(cfg) {
	const file = path.join(RAW, cfg.src);
	const threshold = cfg.threshold ?? -50;
	const { merged, total } = segments(file, threshold, cfg.merge ?? 0.2);
	const tail = cfg.tail ?? 0.12;
	let cuts = cfg.cuts ? cfg.cuts.map(([a, l]) => [a, a + l]) : merged
		.map(([a, b]) => [Math.max(a - 0.004, 0), Math.min(b + tail, total)])
		.filter(([a, b]) => b - a >= (cfg.min ?? 0.03));
	if (cfg.skip) cuts = cuts.filter((_, i) => !cfg.skip.includes(i));
	if (cfg.take) cuts = cuts.slice(0, cfg.take);
	const outputs = [];
	cuts.forEach(([a, b], i) => {
		let len = b - a;
		if (cfg.max) len = Math.min(len, cfg.max * (cfg.pitch ?? 1));
		const gain = (cfg.peak ?? -1) - peakDb(file, a, len);
		const outLen = len / (cfg.pitch ?? 1);
		const fadeOut = Math.min(0.08, outLen * 0.3);
		const filters = [];
		if (cfg.pitch) filters.push(`asetrate=48000*${cfg.pitch}`);
		filters.push('aresample=48000');
		if (!cfg.stereo) filters.push('pan=mono|c0=0.5*c0+0.5*c1');
		// Drops any lead-in more than 30 dB under the peak, so the sound plays on time;
		// the fade-out is applied reversed so it lands on the trimmed end.
		filters.push(`volume=${gain.toFixed(2)}dB`, 'silenceremove=start_periods=1:start_threshold=-30dB:start_silence=0.004', 'afade=t=in:d=0.003',
			'areverse', `afade=t=in:d=${fadeOut.toFixed(3)}`, 'areverse');
		const name = cuts.length > 1 ? `${cfg.out}_${String(i + 1).padStart(2, '0')}.ogg` : `${cfg.out}.ogg`;
		const out = path.join(OUT, name);
		fs.mkdirSync(path.dirname(out), { recursive: true });
		// Mono sources have no c1; pan then needs the single channel only.
		const channels = parseInt(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'stream=channels', '-of', 'csv=p=0', file]).toString());
		const af = filters.map(f => (channels === 1 && f.startsWith('pan=')) ? 'pan=mono|c0=c0' : f).join(',');
		ff(['-ss', `${a}`, '-t', `${len}`, '-i', file, '-af', af, '-c:a', 'libvorbis', '-q:a', '5', out]);
		outputs.push(`${name} (${outLen.toFixed(2)}s)`);
	});
	console.log(`${cfg.out}: ${outputs.length} cut(s)\n  ${outputs.join('\n  ')}`);
}

function loudness(file, start, len) {
	const log = ffErr(['-ss', `${start}`, '-t', `${len}`, '-i', file, '-af', 'ebur128', '-f', 'null', '-']);
	const m = [...log.matchAll(/I:\s+(-?[0-9.]+) LUFS/g)];
	return m.length ? parseFloat(m[m.length - 1][1]) : LOOP_LUFS;
}

// out = x[0:L] with its first F seconds crossfaded with x[L:L+F], so the
// wrap from L back to 0 continues the recording.
function loop(cfg) {
	const file = path.join(RAW, cfg.src);
	const L = cfg.length, F = LOOP_FADE;
	const gain = Math.min(LOOP_LUFS - loudness(file, cfg.start, L + F), LOOP_MAX_GAIN);
	const out = path.join(OUT, `${cfg.out}.ogg`);
	fs.mkdirSync(path.dirname(out), { recursive: true });
	const graph = [
		`[0]aresample=44100,volume=${gain.toFixed(2)}dB,alimiter=limit=0.89,asplit=3[x1][x2][x3]`,
		`[x1]atrim=0:${F},asetpts=PTS-STARTPTS,afade=t=in:d=${F}:curve=qsin[a]`,
		`[x2]atrim=${L}:${L + F},asetpts=PTS-STARTPTS,afade=t=out:d=${F}:curve=qsin[b]`,
		`[a][b]amix=inputs=2:normalize=0[head]`,
		`[x3]atrim=${F}:${L},asetpts=PTS-STARTPTS[body]`,
		`[head][body]concat=n=2:v=0:a=1[o]`,
	].join(';');
	ff(['-ss', `${cfg.start}`, '-t', `${L + F}`, '-i', file, '-filter_complex', graph, '-map', '[o]', '-c:a', 'libvorbis', '-q:a', '4', out]);
	console.log(`${cfg.out}.ogg: ${L}s loop, ${gain >= 0 ? '+' : ''}${gain.toFixed(1)} dB`);
}

function thunder() {
	const file = path.join(RAW, THUNDER_SRC);
	THUNDER.forEach(([a, b], i) => {
		const len = b - a;
		const gain = -3 - peakDb(file, a, len);
		const name = `ambience/thunder_${String(i + 1).padStart(2, '0')}.ogg`;
		ff(['-ss', `${a}`, '-t', `${len}`, '-i', file, '-af', `aresample=44100,volume=${gain.toFixed(2)}dB,afade=t=in:d=0.4,afade=t=out:st=${len - 2}:d=2`, '-c:a', 'libvorbis', '-q:a', '4', path.join(OUT, name)]);
		console.log(`${name} (${len.toFixed(1)}s)`);
	});
}

const only = process.argv[2];
for (const cfg of ONE_SHOTS) if (!only || cfg.out.includes(only)) oneShot(cfg);
for (const cfg of LOOPS) if (!only || cfg.out.includes(only)) loop(cfg);
if (!only || 'thunder'.includes(only)) thunder();
