// Buzzer melody
// Plays a short tune on the buzzer (IO47).
#include <RoboCore.h>

const int BUZZER = RC_PIN_BUZZER;

void note(int freq, int ms) {
  tone(BUZZER, freq, ms);
  delay(ms + 50);
}

void setup() {
  pinMode(BUZZER, OUTPUT);
}

void loop() {
  note(262, 400);
  note(262, 400);
  note(392, 400);
  note(392, 400);
  note(440, 400);
  note(440, 400);
  note(392, 800);
  noTone(BUZZER);
  delay(1500);
}
