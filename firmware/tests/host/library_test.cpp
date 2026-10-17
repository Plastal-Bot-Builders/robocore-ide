// Logic tests for the RoboCore library, run on a PC against a fake board (see run.sh).
// The fake pins, ADC, PWM, I2C and timers record what the library does.
#include "Arduino.h"
#include "Wire.h"
#include <map>
#include <vector>
#include <cstdio>
#include <cassert>
HWCDC Serial; EspClass ESP; TwoWire Wire;
std::map<int,uint32_t> duty; std::map<int,int> adc; std::map<int,int> dig; unsigned long fakeMs=0, echoUs=0; int pulses=0;
std::map<uint8_t,uint8_t> imuRegs;
void pinMode(uint8_t,uint8_t){} void digitalWrite(uint8_t p,uint8_t v){dig[p]=v;} int digitalRead(uint8_t p){return dig.count(p)?dig[p]:HIGH;}
void delay(uint32_t ms){fakeMs+=ms;} void delayMicroseconds(uint32_t){} unsigned long millis(){return fakeMs;}
unsigned long pulseIn(uint8_t,uint8_t,unsigned long t){pulses++; return echoUs>t?0:echoUs;}
uint16_t analogRead(uint8_t p){return adc[p];} uint32_t analogReadMilliVolts(uint8_t p){return adc[p];} void analogReadResolution(uint8_t){}
void analogSetAttenuation(adc_attenuation_t){} void analogSetPinAttenuation(uint8_t, adc_attenuation_t){}
bool ledcAttach(uint8_t,uint32_t,uint8_t){return true;} bool ledcWrite(uint8_t p,uint32_t d){duty[p]=d;return true;} bool ledcDetach(uint8_t){return true;}
void tone(uint8_t,unsigned int,unsigned long){} void noTone(uint8_t){} void rgbLedWrite(uint8_t,uint8_t,uint8_t,uint8_t){}
std::vector<void(*)()> isr; void attachInterrupt(uint8_t,void(*f)(void),int){isr.push_back(f);} int digitalPinToInterrupt(int p){return p;}
void noInterrupts(){} void interrupts(){} long random(long a,long){return a;}
// I2C: register pointer then reads
static uint8_t ptr=0; static bool gotPtr=false;
bool TwoWire::begin(int,int,uint32_t){return true;} void TwoWire::beginTransmission(uint8_t){gotPtr=false;}
size_t TwoWire::write(uint8_t v){ if(!gotPtr){ptr=v;gotPtr=true;} else imuRegs[ptr++]=v; return 1;}
uint8_t TwoWire::endTransmission(bool){return 0;} uint8_t TwoWire::endTransmission(){return 0;}
size_t TwoWire::requestFrom(uint8_t,size_t n){return n;} size_t TwoWire::requestFrom(uint8_t a,size_t n,bool){return requestFrom(a,n);}
int TwoWire::read(){return imuRegs[ptr++];}
#include "RoboCore.h"
static void set16(uint8_t r,int16_t v){imuRegs[r]=v&0xff; imuRegs[r+1]=(v>>8)&0xff;}
int main(){
  RoboCoreMotors m;
  m.drive(60,60);
  // left = motor1 forward on IN1; right motor reversed by default -> motor2 IN2
  printf("drive(60,60): M1 IN1=%u IN2=%u | M2 IN1=%u IN2=%u\n",duty[11],duty[12],duty[13],duty[14]);
  assert(duty[11]==614 && duty[12]==0 && duty[13]==0 && duty[14]==614);
  m.drive(-100,150); assert(duty[12]==1023 && duty[11]==0 && duty[13]==0 && duty[14]==1023); // clamps to 100
  m.drive(NAN,0); assert(duty[11]==0&&duty[12]==0);
  m.stop(); for(int p:{11,12,13,14}) assert(duty[p]==0);
  m.setReversed(false,false); m.drive(30,30); assert(duty[13]>0 && duty[14]==0);
  // encoders: A!=B -> +1 raw; right motor not reversed now
  m.resetEncoders(); dig[15]=1; dig[16]=0; isr[0](); isr[0](); dig[17]=1; dig[18]=1; isr[1]();
  printf("encoders: left %ld right %ld\n", m.leftCount(), m.rightCount()); assert(m.leftCount()==2 && m.rightCount()==-1);
  m.setReversed(false,true); assert(m.rightCount()==1);
  adc[5]=330; printf("current 330 mV -> %.0f mA\n", m.leftCurrentmA()); assert(fabs(m.leftCurrentmA()-100)<0.5);
  dig[21]=LOW; assert(m.fault()); dig[21]=HIGH; assert(!m.fault());

  Sonar s; echoUs=1160; float d=s.distanceCm(); printf("sonar 1160us -> %.1f cm ok=%d\n",d,s.lastEchoOk()); assert(fabs(d-20)<0.01 && s.lastEchoOk());
  echoUs=0; d=s.distanceCm(); assert(d==400 && !s.lastEchoOk());
  unsigned long t0=millis(); s.distanceCm(); assert(millis()-t0>=30); // spacing between pings

  LineSensor L; L.begin();
  // calibrate: white ~300, black ~3300 on all three
  for(int p:{7,10,2}){adc[p]=300;} L.read(); for(int p:{7,10,2}){adc[p]=3300;} L.read();
  adc[7]=300; adc[10]=300; adc[2]=3300; float pr=L.read(); printf("line under right sensor -> %.2f\n",pr); assert(pr>0.9);
  adc[7]=3300; adc[2]=300; float pl=L.read(); assert(pl<-0.9);
  adc[7]=300; adc[10]=3300; float pc=L.read(); assert(fabs(pc)<0.01);
  adc[7]=1800; adc[10]=1800; adc[2]=300; float pm=L.read(); printf("between left and centre -> %.2f\n",pm); assert(pm<-0.4&&pm>-0.6);
  adc[7]=300; adc[10]=300; adc[2]=300; float lost=L.read(); printf("line lost (last seen left) -> %.2f\n",lost); assert(lost==-1.0f);

  IMU imu; imuRegs[0x0F]=0x6C; set16(0x20, 256*5); // 30 C
  set16(0x28,0); set16(0x2A,0); set16(0x2C,16393); // az = 1 g
  assert(imu.begin()); printf("imu ctrl1_xl=0x%02X ctrl2_g=0x%02X ctrl3_c=0x%02X\n",imuRegs[0x10],imuRegs[0x11],imuRegs[0x12]);
  assert(imuRegs[0x10]==0x40 && imuRegs[0x11]==0x40 && imuRegs[0x12]==0x44);
  imuRegs[0x0F]=0x6C; set16(0x20,256*5); set16(0x28,0); set16(0x2A,0); set16(0x2C,16393);
  printf("imu temp %.1f C, tilt flat %.1f deg\n", imu.temperature(), imu.tiltDeg()); assert(fabs(imu.temperature()-30)<0.01 && imu.tiltDeg()<0.5);
  set16(0x28,16393); set16(0x2C,0); printf("imu on its side: tilt %.1f deg\n", imu.tiltDeg()); assert(fabs(imu.tiltDeg()-90)<0.5);
  IMU bad; imuRegs[0x0F]=0x00; assert(!bad.begin()); assert(bad.tiltDeg()==0);

  adc[4]=1900; printf("battery 1900 mV at pin -> %.2f V\n", RoboCore::batteryVolts()); assert(fabs(RoboCore::batteryVolts()-3.8)<0.01);
  dig[42]=LOW; assert(RoboCore::userPressed()); dig[42]=HIGH;
  assert(!RoboCore::waitForUser(100));
  puts("ALL LIBRARY LOGIC TESTS PASSED");
}
