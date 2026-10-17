// Serial echo
// Replies to each line you send from the Serial Monitor.

void setup() {
  Serial.begin(115200);
  pinMode(LED_BUILTIN, OUTPUT);
  Serial.println("Type something and press Send");
}

void loop() {
  if (Serial.available() > 0) {
    String msg = Serial.readStringUntil('\n');
    msg.trim();
    Serial.print("You said: ");
    Serial.println(msg);
    if (msg == "led on") {
      digitalWrite(LED_BUILTIN, HIGH);
    }
    if (msg == "led off") {
      digitalWrite(LED_BUILTIN, LOW);
    }
  }
  delay(20);
}
