#!/usr/bin/env node
// Writes test/fixtures/geared_ring_spin.json: the master Geared Ring glyph at a few spin angles, as path data.
// test/geared_ring_test.dart checks lib/ui/widgets/geared_ring.dart (the Dart port that animates the icon)
// against it. Run again after copying a new master into this folder:
//   node tools/app_icon/spin_fixture.js
const fs = require('fs');
const path = require('path');
globalThis.IG = require('./geom.js');
const { CONCEPTS } = require('./concepts.js');

const SPINS = [0, -1.25, -7.5, -15, -22.5, -29];
const glyph = CONCEPTS.gearring;
const out = SPINS.map((spin) => ({ spin, d: glyph.glyph({ spin }).map((l) => l.d).join(' ') }));
const file = path.join(__dirname, '..', '..', 'test', 'fixtures', 'geared_ring_spin.json');
fs.mkdirSync(path.dirname(file), { recursive: true });
fs.writeFileSync(file, JSON.stringify(out) + '\n');
console.log('wrote', path.relative(process.cwd(), file), out.length, 'angles');
