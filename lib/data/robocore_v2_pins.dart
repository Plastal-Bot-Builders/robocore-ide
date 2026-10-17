// GENERATED from firmware/RoboCore/src/RoboCoreV2Pins.h by tools/gen_pins.py.
// Do not edit: change the header and run `python3 tools/gen_pins.py`.

/// RoboCore V2 (Rev 2.0) pin map, shared with the RoboCore Arduino library.
class RoboCoreV2Pins {
  RoboCoreV2Pins._();

  static const motor1In1 = 11; // RC_PIN_MOTOR1_IN1
  static const motor1In2 = 12; // RC_PIN_MOTOR1_IN2
  static const motor2In1 = 13; // RC_PIN_MOTOR2_IN1
  static const motor2In2 = 14; // RC_PIN_MOTOR2_IN2
  static const motorNfault = 21; // RC_PIN_MOTOR_NFAULT
  static const motor1Isense = 5; // RC_PIN_MOTOR1_ISENSE
  static const motor2Isense = 6; // RC_PIN_MOTOR2_ISENSE
  static const enc1A = 15; // RC_PIN_ENC1_A
  static const enc1B = 16; // RC_PIN_ENC1_B
  static const enc2A = 17; // RC_PIN_ENC2_A
  static const enc2B = 18; // RC_PIN_ENC2_B
  static const sonarTrig = 40; // RC_PIN_SONAR_TRIG
  static const sonarEcho = 41; // RC_PIN_SONAR_ECHO
  static const lineLeft = 7; // RC_PIN_LINE_LEFT
  static const lineCentre = 10; // RC_PIN_LINE_CENTRE
  static const lineRight = 2; // RC_PIN_LINE_RIGHT
  static const i2cSda = 8; // RC_PIN_I2C_SDA
  static const i2cScl = 9; // RC_PIN_I2C_SCL
  static const imuInt1 = 1; // RC_PIN_IMU_INT1
  static const imuI2cAddr = 106; // RC_IMU_I2C_ADDR
  static const batterySense = 4; // RC_PIN_BATTERY_SENSE
  static const servo1 = 38; // RC_PIN_SERVO1
  static const servo2 = 39; // RC_PIN_SERVO2
  static const servo3 = 35; // RC_PIN_SERVO3
  static const servo4 = 36; // RC_PIN_SERVO4
  static const userButton = 42; // RC_PIN_USER_BUTTON
  static const bootButton = 0; // RC_PIN_BOOT_BUTTON
  static const buzzer = 47; // RC_PIN_BUZZER
  static const rgbLed = 48; // RC_PIN_RGB_LED
  static const expIo3 = 3; // RC_PIN_EXP_IO3
  static const expIo37 = 37; // RC_PIN_EXP_IO37
  static const uartTx = 43; // RC_PIN_UART_TX
  static const uartRx = 44; // RC_PIN_UART_RX
  static const batteryDivider = 2.0; // RC_BATTERY_DIVIDER
  static const motorMvPerAmp = 3300.0; // RC_MOTOR_MV_PER_AMP
  static const motorCurrentLimitA = 1.0; // RC_MOTOR_CURRENT_LIMIT_A
  static const freePins = <int>[3, 37, 43, 44, 38, 39, 35, 36]; // RC_FREE_PINS

  /// The same values under their C++ names, for the IDE's sketch checker and simulator.
  static const byCName = <String, num>{
    'RC_PIN_MOTOR1_IN1': 11,
    'RC_PIN_MOTOR1_IN2': 12,
    'RC_PIN_MOTOR2_IN1': 13,
    'RC_PIN_MOTOR2_IN2': 14,
    'RC_PIN_MOTOR_NFAULT': 21,
    'RC_PIN_MOTOR1_ISENSE': 5,
    'RC_PIN_MOTOR2_ISENSE': 6,
    'RC_PIN_ENC1_A': 15,
    'RC_PIN_ENC1_B': 16,
    'RC_PIN_ENC2_A': 17,
    'RC_PIN_ENC2_B': 18,
    'RC_PIN_SONAR_TRIG': 40,
    'RC_PIN_SONAR_ECHO': 41,
    'RC_PIN_LINE_LEFT': 7,
    'RC_PIN_LINE_CENTRE': 10,
    'RC_PIN_LINE_RIGHT': 2,
    'RC_PIN_I2C_SDA': 8,
    'RC_PIN_I2C_SCL': 9,
    'RC_PIN_IMU_INT1': 1,
    'RC_IMU_I2C_ADDR': 106,
    'RC_PIN_BATTERY_SENSE': 4,
    'RC_PIN_SERVO1': 38,
    'RC_PIN_SERVO2': 39,
    'RC_PIN_SERVO3': 35,
    'RC_PIN_SERVO4': 36,
    'RC_PIN_USER_BUTTON': 42,
    'RC_PIN_BOOT_BUTTON': 0,
    'RC_PIN_BUZZER': 47,
    'RC_PIN_RGB_LED': 48,
    'RC_PIN_EXP_IO3': 3,
    'RC_PIN_EXP_IO37': 37,
    'RC_PIN_UART_TX': 43,
    'RC_PIN_UART_RX': 44,
    'RC_BATTERY_DIVIDER': 2.0,
    'RC_MOTOR_MV_PER_AMP': 3300.0,
    'RC_MOTOR_CURRENT_LIMIT_A': 1.0,
  };
}
