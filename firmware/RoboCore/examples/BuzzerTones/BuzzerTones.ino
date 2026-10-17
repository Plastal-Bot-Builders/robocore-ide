// Buzzer tones
// Plays a rising scale on the buzzer (IO47).
#include <RoboCore.h>

const int BUZZER = RC_PIN_BUZZER;

void setup() {
  pinMode(BUZZER, OUTPUT);
}

void loop() {
  tone(BUZZER, 262, 300);   // C4
  delay(350);
  tone(BUZZER, 330, 300);   // E4
  delay(350);
  tone(BUZZER, 392, 300);   // G4
  delay(350);
  tone(BUZZER, 523, 600);   // C5
  delay(650);
  noTone(BUZZER);
  delay(1000);
}
