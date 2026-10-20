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
void physics(uint32_t ms);
void delay(uint32_t ms){fakeMs+=ms; physics(ms);} void delayMicroseconds(uint32_t){} unsigned long millis(){return fakeMs;} unsigned long micros(){return fakeMs*1000;}
unsigned long pulseIn(uint8_t,uint8_t,unsigned long t){pulses++; return echoUs>t?0:echoUs;}
uint16_t analogRead(uint8_t p){return adc[p];} uint32_t analogReadMilliVolts(uint8_t p){return adc[p];} void analogReadResolution(uint8_t){}
void analogSetAttenuation(adc_attenuation_t){} void analogSetPinAttenuation(uint8_t, adc_attenuation_t){}
bool ledcAttach(uint8_t,uint32_t,uint8_t){return true;} bool ledcWrite(uint8_t p,uint32_t d){duty[p]=d;return true;} bool ledcDetach(uint8_t){return true;}
int toneHz=0; void tone(uint8_t,unsigned int f,unsigned long){toneHz=f;} void noTone(uint8_t){toneHz=0;}
int rgbOut[3]={0,0,0}; void rgbLedWrite(uint8_t,uint8_t r,uint8_t g,uint8_t b){rgbOut[0]=r;rgbOut[1]=g;rgbOut[2]=b;}
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

// A fake robot for the movement tests: the wheels turn at 1.5 turns a second at full PWM, which ticks the
// encoders (through the library's ISRs) and turns the gyro (15.5 cm between the wheels).
bool physicsOn=false; double encAcc[2]={0,0};
static double rawPct(int in1,int in2){ uint32_t a=duty[in1], b=duty[in2]; if(a==b) return 0; return ((double)a-(double)b)/1023.0*100.0; }
static void tick(int m,int n){ int A=m?17:15, B=m?18:16; for(int i=0;i<std::abs(n);i++){ dig[A]=1; dig[B]=n>0?0:1; isr[m](); } }
void physics(uint32_t ms){
  if(!physicsOn) return;
  double l=rawPct(11,12), r=rawPct(13,14);           // raw motor directions
  for(int m=0;m<2;m++){ encAcc[m]+=(m?r:l)/100.0*1.5*292.5*ms/1000.0; int n=(int)encAcc[m]; encAcc[m]-=n; tick(m,n); }
  double vl=l/100.0*1.5*18.8, vr=-r/100.0*1.5*18.8;  // cm/s in the robot's frame (right motor mirrored)
  double rate=(vl-vr)/15.5*180.0/M_PI;               // deg/s, clockwise positive
  set16(0x26,(int16_t)lround(-rate/0.00875));        // gyro Z: counter-clockwise positive
}
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

  // ---- The helpers behind the IDE's blocks
  physicsOn=true;
  RoboCoreMotors motors; IMU gyro; RoboCoreDrive robot(motors, gyro);
  imuRegs[0x0F]=0x6C; set16(0x28,0); set16(0x2A,0); set16(0x2C,16393); set16(0x26,0);
  assert(gyro.begin());
  motors.resetPosition(LEFT);
  motors.run(LEFT, 1, ROTATIONS);
  printf("run left motor 1 rotation -> %.0f deg, then braked (duty %u/%u)\n", motors.positionDeg(LEFT), duty[11], duty[12]);
  assert(fabs(motors.positionDeg(LEFT)-360)<8 && duty[11]==1023 && duty[12]==1023);
  motors.start(RIGHT, 40); assert(motors.speedPercent(RIGHT)==40 && motors.speedPercent(LEFT)==0); motors.stop(RIGHT);
  robot.resetDistance();
  robot.move(18.8, CM);
  printf("move 18.8 cm -> %.1f cm\n", robot.distanceCm()); assert(fabs(robot.distanceCm()-18.8)<1.0);
  robot.move(-10, CM); printf("then move -10 cm -> %.1f cm\n", robot.distanceCm()); assert(fabs(robot.distanceCm()-8.8)<1.5);
  unsigned long t1=millis(); robot.move(0.5, SECONDS); assert(millis()-t1>=500);
  gyro.resetYaw(); robot.turn(90);
  printf("turn 90 -> yaw %.1f deg\n", gyro.yawDeg()); assert(fabs(gyro.yawDeg()-90)<6);
  robot.turn(-45); printf("turn -45 -> yaw %.1f deg\n", gyro.yawDeg()); assert(fabs(gyro.yawDeg()-45)<8);
  robot.setSpeed(60); robot.steer(50); assert(duty[11]>0 && duty[13]==0 && duty[14]==0); // right wheel stopped
  robot.start(BACKWARD); assert(duty[12]>0 && duty[13]>0); robot.stop(); for(int p:{11,12,13,14}) assert(duty[p]==1023);
  physicsOn=false;

  RoboCoreServos servos; servos.write(1, 90); printf("servo 1 at 90 -> duty %u\n", duty[38]); assert(duty[38]==1188 && servos.angle(1)==90);
  servos.write(4, 400); assert(servos.angle(4)==180); servos.write(7, 90); assert(servos.angle(7)==0);

  RoboCore::resetTimer(); assert(!RoboCore::timerPassed(1)); delay(1000); assert(RoboCore::timerPassed(1)); assert(!RoboCore::timerPassed(1));
  RoboCore::resetTimer(); delay(1100); assert(RoboCore::timerPassed(1)); printf("timer %.1f s\n", RoboCore::timer());
  dig[42]=HIGH; assert(!RoboCore::userJustPressed()); dig[42]=LOW; assert(RoboCore::userJustPressed()); assert(!RoboCore::userJustPressed()); dig[42]=HIGH;
  RoboCoreEdge e; assert(!e.rose(false)); assert(e.rose(true)); assert(!e.rose(true)); assert(!e.rose(false)); assert(e.rose(true));
  unsigned long t2=millis(); RoboCore::melody(MELODY_POWER_UP); printf("power-up tune %lu ms\n", millis()-t2); assert(millis()-t2>=450);
  unsigned long t3=millis(); RoboCore::beep(523,200); assert(millis()-t3>=200);
  adc[4]=1900; printf("battery 3.8 V -> %d %%\n", RoboCore::batteryPercent()); assert(RoboCore::batteryPercent()==59);
  adc[4]=100; assert(RoboCore::batteryPercent()==0);
  RoboCore::rgb(200,100,0); RoboCore::ledBrightness(50); printf("rgb(200,100,0) at 50%% -> %d,%d,%d\n",rgbOut[0],rgbOut[1],rgbOut[2]); assert(rgbOut[0]==100&&rgbOut[1]==50&&rgbOut[2]==0);
  RoboCore::ledBrightness(100);

  Sonar near; echoUs=58*40; assert(!near.justCloserThan(20)); echoUs=58*15; assert(near.justCloserThan(20)); assert(!near.justCloserThan(20));
  echoUs=58*40; near.justCloserThan(20); echoUs=58*10; assert(near.justCloserThan(20));
  LineSensor edge; edge.begin(); for(int p:{7,10,2}){adc[p]=300;} edge.read(); for(int p:{7,10,2}){adc[p]=3300;} edge.read();
  for(int p:{7,10,2}) adc[p]=300; assert(!edge.justFound()); assert(!edge.justLost());
  // As in loop(): both checks run on every pass.
  adc[10]=3300; assert(edge.justFound()); assert(!edge.justLost()); assert(!edge.justFound());
  adc[10]=300; assert(!edge.justFound()); assert(edge.justLost()); assert(!edge.justLost());
  set16(0x28,0); set16(0x2C,16393); assert(gyro.isFlat() && !gyro.justFlat() && !gyro.justTilted());
  set16(0x28,16393); set16(0x2C,0); assert(gyro.isTilted() && gyro.justTilted() && !gyro.justTilted() && !gyro.justFlat());
  set16(0x28,0); set16(0x2C,16393); assert(gyro.justFlat() && !gyro.justTilted());
  set16(0x2C,26000); assert(gyro.isShaken() && gyro.justShaken()); set16(0x2C,16393); // 1.6 g
  set16(0x28,8196); set16(0x2C,14196); printf("pitch %.1f roll %.1f\n", gyro.pitchDeg(), gyro.rollDeg()); assert(fabs(gyro.pitchDeg()+30)<1);

  puts("ALL LIBRARY LOGIC TESTS PASSED");
}
