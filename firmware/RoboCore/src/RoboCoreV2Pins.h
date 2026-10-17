// RoboCore V2 (Rev 2.0) pin map.
// Source: hardware/RoboCore_V2_schematic_rev2.0.pdf. Keep hardware/pinout.md in step.
// The RoboCore IDE reads these values too (its CI checks that they match).
#pragma once
#include <stdint.h>

#define ROBOCORE_V2 1
#define ROBOCORE_BOARD_REV "2.0"

// Motors (DRV8411A dual H-bridge). Motor 1 = left, motor 2 = right.
constexpr uint8_t RC_PIN_MOTOR1_IN1 = 11;
constexpr uint8_t RC_PIN_MOTOR1_IN2 = 12;
constexpr uint8_t RC_PIN_MOTOR2_IN1 = 13;
constexpr uint8_t RC_PIN_MOTOR2_IN2 = 14;
constexpr uint8_t RC_PIN_MOTOR_NFAULT = 21;    // LOW = driver fault
constexpr uint8_t RC_PIN_MOTOR1_ISENSE = 5;    // ADC1, 3.3 V per amp
constexpr uint8_t RC_PIN_MOTOR2_ISENSE = 6;    // ADC1, 3.3 V per amp

// Encoders (XRP motors, 10k pull-ups to 3.3 V)
constexpr uint8_t RC_PIN_ENC1_A = 15;
constexpr uint8_t RC_PIN_ENC1_B = 16;
constexpr uint8_t RC_PIN_ENC2_A = 17;
constexpr uint8_t RC_PIN_ENC2_B = 18;

// Sensors
constexpr uint8_t RC_PIN_SONAR_TRIG = 40;
constexpr uint8_t RC_PIN_SONAR_ECHO = 41;
constexpr uint8_t RC_PIN_LINE_LEFT = 7;        // ADC1
constexpr uint8_t RC_PIN_LINE_CENTRE = 10;     // ADC1
constexpr uint8_t RC_PIN_LINE_RIGHT = 2;       // ADC1
constexpr uint8_t RC_PIN_I2C_SDA = 8;
constexpr uint8_t RC_PIN_I2C_SCL = 9;
constexpr uint8_t RC_PIN_IMU_INT1 = 1;
constexpr uint8_t RC_IMU_I2C_ADDR = 0x6A;      // LSM6DSOX, SA0 = GND
constexpr uint8_t RC_PIN_BATTERY_SENSE = 4;    // ADC1, battery / 2

// Servos (signal pins; power is VMOT 5.5 V)
constexpr uint8_t RC_PIN_SERVO1 = 38;
constexpr uint8_t RC_PIN_SERVO2 = 39;
constexpr uint8_t RC_PIN_SERVO3 = 35;
constexpr uint8_t RC_PIN_SERVO4 = 36;

// User interface
constexpr uint8_t RC_PIN_USER_BUTTON = 42;     // LOW when pressed, 10k pull-up on the board
constexpr uint8_t RC_PIN_BOOT_BUTTON = 0;      // LOW when pressed
constexpr uint8_t RC_PIN_BUZZER = 47;          // use tone()
constexpr uint8_t RC_PIN_RGB_LED = 48;         // WS2812B; the core also calls it RGB_BUILTIN

// Expansion header pins that are free for sketches
constexpr uint8_t RC_PIN_EXP_IO3 = 3;          // strapping pin: keep it unloaded at boot
constexpr uint8_t RC_PIN_EXP_IO37 = 37;
constexpr uint8_t RC_PIN_UART_TX = 43;
constexpr uint8_t RC_PIN_UART_RX = 44;

// Pins a sketch (or the IDE's "set pin" block) may use freely on the V2.
// Every other GPIO already drives a motor, reads a sensor or carries USB / I2C.
constexpr uint8_t RC_FREE_PINS[] = {3, 37, 43, 44, 38, 39, 35, 36};

// Scales
constexpr float RC_BATTERY_DIVIDER = 2.0f;     // 100k / 100k
constexpr float RC_MOTOR_MV_PER_AMP = 3300.0f; // IPROPI 200 uA/A into 16.5k
constexpr float RC_MOTOR_CURRENT_LIMIT_A = 1.0f;
