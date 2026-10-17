#!/usr/bin/env node
// Stands in for arduino-cli in the server tests. Behaves like `arduino-cli compile --format json`:
//   sketch contains MAKE_ERROR  -> compile error on line 3 (exit 1)
//   sketch contains MAKE_LINK   -> missing loop() link error (exit 1)
//   sketch contains MAKE_SLOW   -> hangs (to test the timeout)
//   otherwise                   -> writes the build files and reports success
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
if (args[0] === 'version') {
  console.log(JSON.stringify({ VersionString: 'fake-1.0' }));
  process.exit(0);
}
if (args[0] === 'core') {
  console.log(JSON.stringify({ platforms: [{ id: 'esp32:esp32', installed_version: '0.0.0' }] }));
  process.exit(0);
}
const opt = (name) => args[args.indexOf(name) + 1];
const fqbn = opt('--fqbn');
const build = opt('--build-path');
const sketchDir = args[args.length - 1];
const main = `${path.basename(sketchDir)}.ino`;
const src = readFileSync(path.join(sketchDir, main), 'utf8');
const files = readdirSync(sketchDir);

if (src.includes('MAKE_SLOW')) setTimeout(() => {}, 60_000);
else if (src.includes('MAKE_ERROR')) {
  const p = path.join(sketchDir, main);
  console.log(JSON.stringify({
    compiler_out: '',
    compiler_err: `${p}: In function 'void loop()':\n${p}:3:5: error: 'foo' was not declared in this scope\n    3 |     foo();\n      |     ^~~\n`,
    builder_result: {
      build_path: build,
      diagnostics: [{ severity: 'ERROR', message: "'foo' was not declared in this scope", file: p, line: 3, column: 5 }],
    },
    success: false,
    error: 'exit status 1',
  }));
  process.exit(1);
} else if (src.includes('MAKE_LINK')) {
  console.log(JSON.stringify({
    compiler_out: '',
    compiler_err: `/home/builder/.arduino15/packages/esp32/hardware/esp32/3.3.12/cores/esp32/main.cpp:60: undefined reference to \`loop()'\ncollect2: error: ld returned 1 exit status\n`,
    builder_result: { build_path: build },
    success: false,
    error: 'exit status 1',
  }));
  process.exit(1);
} else {
  if (fqbn.startsWith('arduino:avr')) {
    writeFileSync(path.join(build, `${main}.hex`), ':100000000C945C000C946E000C946E000C946E00CA\n:00000001FF\n');
  } else {
    writeFileSync(path.join(build, `${main}.bootloader.bin`), Buffer.from([0xe9, 1, 2, 3]));
    writeFileSync(path.join(build, `${main}.partitions.bin`), Buffer.from([0xaa, 0x50]));
    writeFileSync(path.join(build, `${main}.bin`), Buffer.from([0xe9, 9, 9, 9, 9]));
  }
  console.log('some progress text first');
  console.log(JSON.stringify({
    compiler_out: `Sketch uses 289306 bytes (9%) of program storage space. Maximum is 3145728 bytes.\nGlobal variables use 20118 bytes (6%) of dynamic memory, leaving 307562 bytes for local variables. Maximum is 327680 bytes.\n`,
    compiler_err: '',
    builder_result: {
      build_path: build,
      executable_sections_size: [{ name: 'text', size: 289306, max_size: 3145728 }, { name: 'data', size: 20118, max_size: 327680 }],
      fake_files: files,
    },
    success: true,
  }));
}
