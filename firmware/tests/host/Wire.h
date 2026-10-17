#pragma once
#include "Arduino.h"
struct TwoWire{ bool begin(int sda, int scl, uint32_t frequency = 0); void beginTransmission(uint8_t address); size_t write(uint8_t);
 uint8_t endTransmission(bool stopBit); uint8_t endTransmission();
 size_t requestFrom(uint8_t address, size_t len, bool stopBit); size_t requestFrom(uint8_t address, size_t len); int read(); };
extern TwoWire Wire;
