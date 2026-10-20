// The names the code editor knows (Arduino core + RoboCore library): suggestions, parameter hints and hovers.
// The RoboCore part follows firmware/RoboCore/src (RoboCore.h, RoboCoreMotors.h, RoboCoreSensors.h).

class ApiEntry {
  const ApiEntry(this.name, this.params, this.doc, [this.ref]);

  /// As written in code: `digitalWrite`, `motors.drive`, `RoboCore::rgb`, `HIGH`.
  final String name;

  /// `(pin, value)` for a function, empty for a constant.
  final String params;

  /// One short sentence, for students.
  final String doc;

  /// The Arduino language reference page under functions/, e.g. `digital-io/digitalwrite`. The site's
  /// spelling varies (pinMode, but digitalwrite): each one here was checked to open.
  final String? ref;

  String? get url => ref == null ? null : 'https://docs.arduino.cc/language-reference/en/functions/$ref/';
}

const kApi = <ApiEntry>[
  // ---- Arduino core
  ApiEntry('pinMode', '(pin, mode)', 'Sets a pin as INPUT, OUTPUT or INPUT_PULLUP. Call it in setup().', 'digital-io/pinMode'),
  ApiEntry('digitalWrite', '(pin, value)', 'Switches an output pin HIGH (on) or LOW (off).', 'digital-io/digitalwrite'),
  ApiEntry('digitalRead', '(pin)', 'Reads a pin: HIGH or LOW.', 'digital-io/digitalread'),
  ApiEntry('analogRead', '(pin)', 'Reads the voltage on a pin as a number: 0 to 4095 on ESP32 boards, 0 to 1023 on the Uno.', 'analog-io/analogRead'),
  ApiEntry('analogWrite', '(pin, value)', 'Sets a PWM output from 0 (off) to 255 (fully on), e.g. to dim an LED.', 'analog-io/analogWrite'),
  ApiEntry('delay', '(ms)', 'Waits this many milliseconds. 1000 ms is one second.', 'time/delay'),
  ApiEntry('delayMicroseconds', '(us)', 'Waits this many microseconds (millionths of a second).', 'time/delayMicroseconds'),
  ApiEntry('millis', '()', 'Milliseconds since the board started. Good for timing without delay().', 'time/millis'),
  ApiEntry('micros', '()', 'Microseconds since the board started.', 'time/micros'),
  ApiEntry('Serial.begin', '(baud)', 'Starts the serial port at this speed. RoboCore uses 115200.', 'communication/serial/begin'),
  ApiEntry('Serial.print', '(value)', 'Sends text or a number to the Serial Monitor, on the same line.', 'communication/serial/print'),
  ApiEntry('Serial.println', '(value)', 'Sends text or a number to the Serial Monitor, then starts a new line.', 'communication/serial/println'),
  ApiEntry('Serial.available', '()', 'How many characters are waiting to be read from the Serial Monitor.', 'communication/serial/available'),
  ApiEntry('Serial.read', '()', 'Reads one character, or -1 when none is waiting.', 'communication/serial/read'),
  ApiEntry('Serial.readStringUntil', '(char)', 'Reads text up to this character, for example \'\\n\' for a whole line.', 'communication/serial/readStringUntil'),
  ApiEntry('tone', '(pin, frequency, ms)', 'Plays a note of this frequency (Hz) on a buzzer for ms milliseconds.', 'advanced-io/tone'),
  ApiEntry('noTone', '(pin)', 'Stops the note playing on that pin.', 'advanced-io/noTone'),
  ApiEntry('random', '(min, max)', 'A random whole number from min up to max − 1.', 'random-numbers/random'),
  ApiEntry('map', '(value, fromLow, fromHigh, toLow, toHigh)', 'Rescales a number from one range to another.', 'math/map'),
  ApiEntry('constrain', '(value, low, high)', 'Keeps a number between low and high.', 'math/constrain'),
  ApiEntry('rgbLedWrite', '(pin, red, green, blue)', 'Sets an RGB LED on an ESP32 board, 0–255 each. On RoboCore V2, RoboCore::rgb does the same.'),
  ApiEntry('HIGH', '', 'On: the pin is at 3.3 V (5 V on the Uno).'),
  ApiEntry('LOW', '', 'Off: the pin is at 0 V.'),
  ApiEntry('INPUT', '', 'pinMode: the pin reads a signal.'),
  ApiEntry('OUTPUT', '', 'pinMode: the pin drives an LED, buzzer or other part.'),
  ApiEntry('INPUT_PULLUP', '', 'pinMode: an input that reads HIGH until a button pulls it LOW.'),
  ApiEntry('LED_BUILTIN', '', 'The board’s own LED. On RoboCore V2 it is the RGB LED.'),
  ApiEntry('RGB_BUILTIN', '', 'The board’s RGB LED (ESP32 boards).'),
  // ---- RoboCore library: board helpers (RoboCore.h)
  ApiEntry('RoboCore::rgb', '(red, green, blue)', 'Sets the RGB LED, 0–255 each.'),
  ApiEntry('RoboCore::beep', '(frequencyHz, ms)', 'A short beep on the buzzer (2000 Hz for 80 ms if you leave them out).'),
  ApiEntry('RoboCore::userPressed', '()', 'true while the USER button is held down.'),
  ApiEntry('RoboCore::waitForUser', '(timeoutMs)', 'Waits until USER is pressed and released. false if timeoutMs passes first (0 = wait forever).'),
  ApiEntry('RoboCore::batteryVolts', '()', 'The battery pack’s voltage, about 3.0 (empty) to 4.2 (full).'),
  // ---- motors (RoboCoreMotors motors;)
  ApiEntry('motors.begin', '()', 'Sets up the motors and encoders. drive() calls it for you if you forget.'),
  ApiEntry('motors.drive', '(leftPercent, rightPercent)', 'Speed of each wheel from -100 (full reverse) to 100 (full forward). drive(60, 60) goes forward.'),
  ApiEntry('motors.stop', '()', 'Lets both motors coast to a stop.'),
  ApiEntry('motors.brake', '()', 'Stops both motors quickly.'),
  ApiEntry('motors.leftCount', '()', 'Left wheel encoder count since begin() or resetEncoders(). Positive = forward.'),
  ApiEntry('motors.rightCount', '()', 'Right wheel encoder count since begin() or resetEncoders(). Positive = forward.'),
  ApiEntry('motors.resetEncoders', '()', 'Sets both encoder counts back to 0.'),
  ApiEntry('motors.setReversed', '(left, right)', 'Flips a motor’s direction if a wheel turns the wrong way.'),
  ApiEntry('motors.fault', '()', 'true while the motor driver reports a problem (too much current, too hot, or a flat battery).'),
  // ---- sensors (Sonar sonar; LineSensor line; IMU imu;)
  ApiEntry('sonar.begin', '()', 'Sets up the ultrasonic sensor. The first reading calls it for you if you forget.'),
  ApiEntry('sonar.distanceCm', '()', 'Distance to the nearest object in cm; 400 when nothing echoes back.'),
  ApiEntry('line.begin', '()', 'Sets up the line sensor.'),
  ApiEntry('line.read', '()', 'Where the line is: -1 (under the left sensor), 0 (centred), 1 (right).'),
  ApiEntry('line.left', '()', 'How dark the left sensor sees the floor: 0 (white) to 1 (black).'),
  ApiEntry('line.centre', '()', 'How dark the centre sensor sees the floor: 0 (white) to 1 (black).'),
  ApiEntry('line.right', '()', 'How dark the right sensor sees the floor: 0 (white) to 1 (black).'),
  ApiEntry('imu.begin', '()', 'Starts the IMU (motion sensor). false if it does not answer.'),
  ApiEntry('imu.temperature', '()', 'Board temperature in °C.'),
  ApiEntry('imu.tiltDeg', '()', 'How far the board is tilted from flat, in degrees: 0 flat, 90 on its side.'),
  ApiEntry('imu.accelX', '()', 'Acceleration along X, in g (1 g = gravity).'),
  ApiEntry('imu.accelY', '()', 'Acceleration along Y, in g.'),
  ApiEntry('imu.accelZ', '()', 'Acceleration along Z, in g.'),
  ApiEntry('imu.gyroX', '()', 'Rotation around X, in degrees per second.'),
  ApiEntry('imu.gyroY', '()', 'Rotation around Y, in degrees per second.'),
  ApiEntry('imu.gyroZ', '()', 'Rotation around Z, in degrees per second.'),
];
