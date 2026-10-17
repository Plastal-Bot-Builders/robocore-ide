// Boards the compile server can build for. Ids match the RoboCore IDE (lib/data/catalog.dart).

export const BOARDS = {
  v2: {
    name: 'RoboCore V2 (ESP32-S3)',
    fqbn: 'esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashSize=8M,PartitionScheme=default_8MB,PSRAM=enabled,CPUFreq=240',
    arch: 'esp32',
    chip: 'esp32s3',
    bootloaderOffset: 0x0,
    flashSize: '8MB',
  },
  devkit: {
    name: 'ESP32 DevKit V1',
    fqbn: 'esp32:esp32:esp32:FlashSize=4M,PartitionScheme=default',
    arch: 'esp32',
    chip: 'esp32',
    bootloaderOffset: 0x1000,
    flashSize: '4MB',
  },
  nodemcu: {
    name: 'NodeMCU-32S',
    fqbn: 'esp32:esp32:nodemcu-32s',
    arch: 'esp32',
    chip: 'esp32',
    bootloaderOffset: 0x1000,
    flashSize: '4MB',
  },
  uno: {
    name: 'Arduino Uno R3',
    fqbn: 'arduino:avr:uno',
    arch: 'avr',
    chip: 'atmega328p',
  },
};

// Where each part of an ESP32 build goes in flash (same as the core's merge-bin step).
export const ESP32_PARTS = (board) => [
  { file: 'bootloader', offset: board.bootloaderOffset },
  { file: 'partitions', offset: 0x8000 },
  { file: 'boot_app0', offset: 0xe000 },
  { file: 'app', offset: 0x10000 },
];
