// RGB colour cycle
// Steps the on-board RGB LED (IO48) through a few colours.

void setup() {
}

void loop() {
  rgbLedWrite(RGB_BUILTIN, 255, 0, 0);    // red
  delay(500);
  rgbLedWrite(RGB_BUILTIN, 0, 255, 0);    // green
  delay(500);
  rgbLedWrite(RGB_BUILTIN, 0, 0, 255);    // blue
  delay(500);
  rgbLedWrite(RGB_BUILTIN, 255, 160, 0);  // amber
  delay(500);
}
