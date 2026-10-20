#pragma once
// Minimal stand-in for arduino-esp32 3.3.12 so the library can be checked on a PC.
// Signatures are copied from the real core headers.
#include <cstdint>
#include <cstring>
#include <cmath>
#include <cstddef>
#include <algorithm>
#include <string>
#include <initializer_list>
#include <cstdlib>
#define CONFIG_IDF_TARGET_ESP32S3 1
using std::min; using std::max;
#define HIGH 1
#define LOW 0
#define INPUT 0x01
#define OUTPUT 0x03
#define RISING 0x01
#define FALLING 0x02
#define CHANGE 0x03
#define HEX 16
#define IRAM_ATTR
#define constrain(amt, low, high) ((amt) < (low) ? (low) : ((amt) > (high) ? (high) : (amt)))
static const uint8_t LED_BUILTIN = 49 + 48;
#define LED_BUILTIN LED_BUILTIN
#define RGB_BUILTIN LED_BUILTIN
typedef enum { ADC_0db, ADC_2_5db, ADC_6db, ADC_11db } adc_attenuation_t;
class String { std::string s; public:
 String(const char*c=""):s(c){} String(int v,unsigned char b=10):s(std::to_string(v)){(void)b;} String(long v):s(std::to_string(v)){}
 String(unsigned char v,unsigned char b):s(std::to_string(v)){(void)b;} String(float v,unsigned int d):s(std::to_string(v)){(void)d;}
 const char*c_str()const{return s.c_str();} void trim(){} bool operator==(const char*o)const{return s==o;}
 friend String operator+(const String&a,const String&b){String r(a);r.s+=b.s;return r;}
 friend String operator+(const String&a,const char*b){String r(a);r.s+=b;return r;}
 friend String operator+(const String&a,int b){return a+String(b);} friend String operator+(const String&a,long b){return a+String(b);}
};
struct Print { size_t print(const char*){return 0;} size_t print(int){return 0;} size_t print(unsigned long){return 0;} size_t print(double,int=2){return 0;}
 size_t println(const char*){return 0;} size_t println(int){return 0;} size_t println(long){return 0;} size_t println(double,int=2){return 0;} size_t println(const String&){return 0;} size_t print(const String&){return 0;}
 int printf(const char*,...)__attribute__((format(printf,2,3))){return 0;} };
struct HWCDC: Print{ void begin(unsigned long){} explicit operator bool(){return true;} int available(){return 0;} String readStringUntil(char){return String();} };
extern HWCDC Serial;
struct EspClass{ const char*getChipModel(){return "";} uint8_t getChipRevision(){return 0;} uint8_t getChipCores(){return 2;} uint32_t getFlashChipSize(){return 0;} uint32_t getPsramSize(){return 0;} };
extern EspClass ESP;
void pinMode(uint8_t,uint8_t); void digitalWrite(uint8_t,uint8_t); int digitalRead(uint8_t);
void delay(uint32_t); void delayMicroseconds(uint32_t); unsigned long millis(); unsigned long micros();
unsigned long pulseIn(uint8_t pin, uint8_t state, unsigned long timeout = 1000000L);
uint16_t analogRead(uint8_t); uint32_t analogReadMilliVolts(uint8_t pin); void analogReadResolution(uint8_t bits);
void analogSetAttenuation(adc_attenuation_t); void analogSetPinAttenuation(uint8_t pin, adc_attenuation_t attenuation);
bool ledcAttach(uint8_t pin, uint32_t freq, uint8_t resolution); bool ledcWrite(uint8_t pin, uint32_t duty); bool ledcDetach(uint8_t pin);
void tone(uint8_t _pin, unsigned int frequency, unsigned long duration = 0); void noTone(uint8_t);
void rgbLedWrite(uint8_t pin, uint8_t red_val, uint8_t green_val, uint8_t blue_val);
void attachInterrupt(uint8_t pin, void (*)(void), int mode); int digitalPinToInterrupt(int);
void noInterrupts(); void interrupts(); long random(long,long);
