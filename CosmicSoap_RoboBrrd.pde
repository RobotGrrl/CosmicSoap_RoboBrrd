/*

Cosmic Soap!
a crazy fluids+physics+fft+robot+thingspeak sketch
------------

robotgrrl.com
Aug 27, 2011

Cosmic Soap is licensed under the BSD 3-Clause License! :)
http://www.opensource.org/licenses/BSD-3-Clause
 
Copyright (c) 2011, RobotGrrl.com
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, 
are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, 
  this list of conditions and the following disclaimer.
  
* Redistributions in binary form must reproduce the above copyright notice, 
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.
  
* Neither the name of the RobotGrrl.com nor the names of its contributors
  may be used to endorse or promote products derived from this software
  without specific prior written permission.
  
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY 
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT 
SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED 
TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN 
ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH 
DAMAGE.

*/


// ------------- L I B S ------------- //
import traer.physics.*;
import msafluid.*;
import processing.opengl.*;
import javax.media.opengl.*;
import processing.serial.*;
import ddf.minim.analysis.*;
import ddf.minim.*;
import processing.net.*;

// ------------- T H I N G S P E A K ------------- //
String APIKEY = "";
String LDRL_FIELD = "LDR_L";
String LDRR_FIELD = "LDR_R";
String PIR_FIELD = "PIR";
Client c;
String data;

// ------------- A U D I O ------------- //
Minim minim;
AudioPlayer jingle;
AudioInput input;
FFT fftLog;
int lastPosition;
float fftAvg;
boolean mic = true;

// ------------- D I S P L A Y ------------- //
float invWidth, invHeight;
float aspectRatio, aspectRatio2;

// ------------- F L U I D S ------------- //
// you can change how many particles are in the fluid sim in ParticleSystem
MSAFluidSolver2D fluidSolver;
MSAParticleSystem particleSystem;
final float FLUID_WIDTH = 150;
PImage imgFluid;
boolean drawFluid = true;
float fadeSpeed = 0.01; // a number that controls how long the colours are shown on the screen- the fft changes this
float spray = 0.08;

// ------------- P H Y S I C S ------------- //
final int NUM_PARTICLES = 10; // make this 200 for more awesome
Particle[] particles = new Particle[NUM_PARTICLES];
Particle mouse;
ParticleSystem physics;
float gravy = 0.0f;
float gravx = 0.0f;
float mouseVelX;
float mouseVelY;
float t;
float mouseVelMag;

// ------------- S E R I A L ------------- //
Serial myPort;
int ldrL = 0;
int ldrR = 0;
int pir = 0;
float lastFlip = 0.0f;
float lastUpdate = 0.0f;
int ldrLow = 500;
int ldrHigh = 1023;
final int l = 15; // make this 2 times the length of one packet plus 1 (explanation later on in the code)
char[] in = new char[l];


void setup() {
  
    // ------------- D I S P L A Y ------------- //
    //size(960, 640, OPENGL);    // use OPENGL rendering for bilinear filtering on texture
    size(1500, 1000, OPENGL);
    //size(screen.width, screen.height, OPENGL);
    hint( ENABLE_OPENGL_4X_SMOOTH );    // Turn on 4X antialiasing
    
    invWidth = 1.0f/width; // opengl makes positioning things on the canvas weird, so we have to multiply by the inverse
    invHeight = 1.0f/height;
    aspectRatio = width * invHeight;
    aspectRatio2 = aspectRatio * aspectRatio;
    
    smooth();
    noCursor();


    // ------------- S O U N D ------------- //
    minim = new Minim(this);
    if(mic) {
      input = minim.getLineIn(Minim.STEREO, 2048);
      fftLog = new FFT(input.bufferSize(), input.sampleRate());
    } else {
      jingle = minim.loadFile("tron.mp3"); // use your own mp3 here :)
      jingle.loop();
      jingle.mute();
      fftLog = new FFT(jingle.bufferSize(), jingle.sampleRate());
    }
    
    fftLog.logAverages(22, 3);
    fftLog.window(FFT.HAMMING);


    // ------------- S E R I A L ------------- //
    println(Serial.list());
    
    int xbee = 99; // crazy value so we know that if it is not set, then it is not connected
    
    for(int i=0; i<Serial.list().length; i++) {
      if(Serial.list()[0].equals("/dev/tty.usbserial-FTE0U1GP")) { // hardcode in here your xbee or arduino, so that way it is easier to connect in the future
        xbee = i;
        println("Choosing #" + xbee);
        break;
      }
    }
    
    if(xbee != 99) {
      myPort = new Serial(this, Serial.list()[xbee], 9600);
      println("Connected!");
    } else {
      println("Xbee not connected!"); 
    }
    
    
    // ------------- F L U I D S ------------- //
    // create fluid and set options
    fluidSolver = new MSAFluidSolver2D((int)(FLUID_WIDTH), (int)(FLUID_WIDTH * height/width));
    fluidSolver.enableRGB(true).setFadeSpeed(fadeSpeed).setDeltaT(0.5).setVisc(0.0005);
    // create image to hold fluid picture
    imgFluid = createImage(fluidSolver.getWidth(), fluidSolver.getHeight(), RGB);
    // create particle system
    particleSystem = new MSAParticleSystem();
    
    
    // ------------- P H Y S I C S ------------- //
    physics = new ParticleSystem();
    mouse = physics.makeParticle();
    mouse.makeFixed();
    // every particle is attracted to the mouse particle, and also to its neighbour
    for(int i=0; i<NUM_PARTICLES; i++) {
      particles[i] = physics.makeParticle(1.0, random(0,width)*invWidth, random(0, height)*invHeight, 0.0);
      physics.makeAttraction(particles[i], mouse, random(10000, 100000), 100);
      if(i>0) physics.makeAttraction(particles[i-1], particles[i], random(10000, 100000), 100);
    }
    
    
    // ------------- T H I N G S P E A K ------------- //
    //c = new Client(this, "api.thingspeak.com", 80); // Connect to server on port 80
   
}


void draw() {

    // ------------- S E R I A L ------------- // 
    /*
    notes: the packet structure for the xbee-arduino/robobrrd comm is like this:
    #R0000!, where the # is the beginning delim, and the ! is the end delim
    the R just says what sensor it is for, and there are always 4 places in the reading
    (this is preformatted for us from the arduino/robobrrd side)
    
    the arduino/robobbrrd sends two packets per cycle. it then iterates through for which
    packets it sends first, so that way each sensor has a chance of being sent first,
    entailing that it would be read first
    
    the reason why two data packets are sent is because if you send only one, the serial
    buffer can easily become confused, and now all of a sudden when you are counting
    your chars, then it could be offset- throwing everything off. at least if we send two,
    then we have the chance that there is enough "space" for there to be at least one good
    packet in the data.
    
    this is why the in buffer char array has to be twice the size of the packet. we also add
    one for good measure, in case anything unforseeable happens with our code, resulting in
    an extra char.
    */
    if(myPort.available() > 0) {
      
      // put all 15 of the chars in an array first (if there are 15)
      for(int j=0; j<l; j++) {
        if(myPort.available() > 0) in[j] = myPort.readChar();
        //println("["+j+"]: " + in[j]);
      }
      
      // now we go through all 15...
      for(int j=0; j<l; j++) {
        
        // look for the first delimiter
        if(in[j] == '#') {
          
          // have to make sure that this is long enough to be a complete message, and that there is a complete message in the serial
          if(l-j > 6 && myPort.available() > 6) {
            
            char sensor = in[j+1];
            
            // here is where we do things for whichever specific sensor it is
            switch(sensor) {
              case 'L': {
                ldrL = (((int)in[j+2]-48)*1000) + (((int)in[j+3]-48)*100) + (((int)in[j+4]-48)*10) + ((int)in[j+5]-48); // changing a char to an int
                gravx = map(ldrL, ldrLow, ldrHigh, -6.0f, 6.0f);
                physics.setGravity(gravx, gravy, 0.0);
                println("LDR L: " + ldrL);
                break;
              }
              case 'R': {
                ldrR = (((int)in[j+2]-48)*1000) + (((int)in[j+3]-48)*100) + (((int)in[j+4]-48)*10) + ((int)in[j+5]-48);
                gravy = map(ldrR, ldrLow, ldrHigh, -6.0f, 6.0f);
                physics.setGravity(gravx, gravy, 0.0);
                //println("LDR R: " + ldrR);
                break;
              }
              case 'P': {
                pir = (((int)in[j+2]-48)*1000) + (((int)in[j+3]-48)*100) + (((int)in[j+4]-48)*10) + ((int)in[j+5]-48);
                if(pir > 500 && millis() > (lastFlip+1000)) {
                  println("flip!");
                 for(int i=0; i<(NUM_PARTICLES*2)-1; i++) {
                   physics.getAttraction(i).setStrength(-1* (physics.getAttraction(i).getStrength()) );
                 } 
                 lastFlip = millis();
                }
                break;
              }
            }
            
          }
        }
        in[j] = '-'; // reset the in buffer as we go
      }
      
      myPort.clear();
      
    }
    
    
    // ------------- T H I N G S P E A K ------------- //
    /*
    if(second() > (lastUpdate+15)) {
      updateThingSpeak();
      lastUpdate = second();
    }
    */
    
    
    // ------------- F F T ------------- //
    if(mic) {
      fftLog.forward(input.mix);
    } else {
      fftLog.forward(jingle.mix);
    }
    
    fftAvg = 0.0f;
    for(int i=0; i<fftLog.avgSize(); i++) {
      fftAvg += fftLog.getAvg(i);
    }
    fftAvg/=fftLog.avgSize();
    //println("FFT Avg: " + fftAvg);
    
    
    // ------------- P H Y S I C S ------------- //
    mouse.position().set( mouseX, mouseY, 0 );
    physics.tick();
    
    mouseVelX = ((mouseX - pmouseX) * invWidth)+1*10;
    mouseVelY = ((mouseY - pmouseY) * invHeight)+1*10;
    
    mouseVelMag = sqrt( ((mouseX - pmouseX)*(mouseX - pmouseX)) + ((mouseY - pmouseY)*(mouseY - pmouseY)) );
    
    // this is communicating back to robobrrd
    if(mouseVelMag > 20) {
      myPort.write("B");
    }
    
    t = millis()/1000.0f;
    addForce(mouseX*invWidth, mouseY*invHeight, 0.5*cos(t), 0.5*sin(t));
    
    for(int i=0; i<NUM_PARTICLES; i++) {
      handleBoundaryCollisions(particles[i]);
      float p_x = particles[i].position().x()*invWidth;
      float p_y = particles[i].position().y()*invHeight;
      float p_vx = particles[i].velocity().x()/100;
      float p_vy = particles[i].velocity().y()/100;
      addForce(p_x, p_y, p_vx, p_vy);
    }
    
    
    // ------------- F L U I D S ------------- //
    /*
    // these are just some extra sprays in the corner
    addForce(0, 0, spray*cos(second()), spray);
    addForce(width, 0, -spray, spray*cos(second()));
    addForce(width, height, -spray, -spray*cos(second()));
    addForce(0, height, spray*cos(second()), -spray);
    */
    
    fluidSolver.update();

    if(drawFluid) {
      
        float et = 1.5; // et is how intense the colours are. the greater it is, the more white
        float w = 0.0f; // gives a base white colour (used for mic input)

        if(mic) {
          w = map(fftAvg, 0.0f, 10.0f, -0.5, 1.0);
        } else {
          et = map(fftAvg, 0.0f, 10.0f, -0.5, 1.0); 
        }
      
        for(int i=0; i<fluidSolver.getNumCells(); i++) {
          float r = fluidSolver.r[i];
          float g = fluidSolver.g[i];
          float b = fluidSolver.b[i];
          imgFluid.pixels[i] = color((r * et)+w, (g * et)+w, (b * et)+w);
        }
        
        imgFluid.updatePixels();
        image(imgFluid, 0, 0, width, height);
    } 

    particleSystem.updateAndDraw();    
    
}



// ------------- C O M P U T E R ------------- //

void mouseMoved() {
    float mouseNormX = mouseX * invWidth;
    float mouseNormY = mouseY * invHeight;
    float mouseVelX = (mouseX - pmouseX) * invWidth *10;
    float mouseVelY = (mouseY - pmouseY) * invHeight *10;
    addForce(mouseNormX, mouseNormY, mouseVelX*10, mouseVelY*10);
}

void mousePressed() {
  // mute/unmute the music
  if(!mic) {
    if(jingle.isMuted()) {
      jingle.unmute();
    } else {
      jingle.mute(); 
    }
  }
}

// using keys are great for testing variables out
void keyPressed() {
    switch(key) {
    case 'r': 
        renderUsingVA ^= true; 
        println("renderUsingVA: " + renderUsingVA);
        break;
    case 'a': // flip attraction
      for(int i=0; i<(NUM_PARTICLES*2)-1; i++) {
        physics.getAttraction(i).setStrength(-1* (physics.getAttraction(i).getStrength()) );
      }
      break;
    case 'f': // less fade (white)
      fadeSpeed /= 2;
      fluidSolver.setFadeSpeed(fadeSpeed);
      break;
    case 'g': // more fade (black)
      fadeSpeed *= 2;
      fluidSolver.setFadeSpeed(fadeSpeed);
      break;
    case 'm': // more mass
      for(int i=0; i<NUM_PARTICLES; i++) {
        particles[i].setMass(particles[i].mass()+0.1);
      }
      break;
    case 'n': // less mass
      for(int i=0; i<NUM_PARTICLES; i++) {
        if(particles[i].mass() > 0.1) particles[i].setMass(particles[i].mass()-0.1);
      }
      break;
    case 'y': // random attraction!
      float r = random(-10000, 10000);
      for(int i=0; i<(NUM_PARTICLES*2)-1; i++) {
        physics.getAttraction(i).setStrength(r);
      }
      break;
    case 's': // save!
      save("spacey-" + day() + "-" + hour() + ":" + minute() + ":" + second() + ":" + millis() + ".png");
      break;
    case 'v': // more viscous!
      fluidSolver.setVisc(fluidSolver.getVisc()+0.01);
      break;
    case 'c': // less viscous!
      fluidSolver.setVisc(fluidSolver.getVisc()-0.01);
      break;
    case '[': // less y gravity!
      if(gravy > -6.0f) gravy -= 0.5;
      physics.setGravity(gravx, gravy, 0.0);
      break;
    case ']': // more y gravity!
      if(gravy < 6.0f) gravy += 0.5;
      physics.setGravity(gravx, gravy, 0.0);
      break;
    case '9': // less x grav
      if(gravx > -6.0f) gravx -= 0.5;
      physics.setGravity(gravx, gravy, 0.0);
      break;
    case '0': // more x grav
      if(gravx < 6.0f) gravx += 0.5;
      physics.setGravity(gravx, gravy, 0.0);
      break;
    }
    println(frameRate);
}

/*
note: this function is really important. if you don't have it, stuff messes up really badly.
for example, when developing and not closing the serial port, librxtx would crash, which would
mean my bt mouse&keyboard wouldn't work, which would mean me eventually having to reboot. blech!
also, this is pretty much the same with the mic, except with less insane consequences.
*/
void stop() {
  myPort.stop();
  
  if(mic) {
    input.close();
  } else {
    jingle.close();
  }
  
  super.stop(); 
}



// ------------- F L U I D S ------------- //
// add force and dye to fluid, and create particles
void addForce(float x, float y, float dx, float dy) {
    float speed = dx * dx  + dy * dy * aspectRatio2;    // balance the x and y components of speed with the screen aspect ratio

    if(speed > 0) {
        if(x<0) x = 0; 
        else if(x>1) x = 1;
        if(y<0) y = 0; 
        else if(y>1) y = 1;

        float colorMult = 5;
        float velocityMult = 30.0f;

        int index = fluidSolver.getIndexForNormalizedPosition(x, y);

        color drawColor;

        colorMode(HSB, 360, 1, 1);
        float hue = ((x + y) * 180 + frameCount) % 360;
        drawColor = color(hue, 1, 1);
        colorMode(RGB, 1);  

        fluidSolver.rOld[index]  += red(drawColor) * colorMult;
        fluidSolver.gOld[index]  += green(drawColor) * colorMult;
        fluidSolver.bOld[index]  += blue(drawColor) * colorMult;

        particleSystem.addParticles(x * width, y * height, 10);
        fluidSolver.uOld[index] += dx * velocityMult;
        fluidSolver.vOld[index] += dy * velocityMult;
    }
}



// ------------- P H Y S I C S ------------- //
// really basic collision strategy:
// sides of the window are walls
// if it hits a wall pull it outside the wall and flip the direction of the velocity
// the collisions aren't perfect so we take them down a notch too
void handleBoundaryCollisions( Particle p )
{
  if ( p.position().x() < 0 || p.position().x() > width )
    p.velocity().set( -0.9*p.velocity().x(), p.velocity().y(), 0 );
  if ( p.position().y() < 0 || p.position().y() > height )
    p.velocity().set( p.velocity().x(), -0.9*p.velocity().y(), 0 );
  p.position().set( constrain( p.position().x(), 0, width ), constrain( p.position().y(), 0, height ), 0 ); 
}



// ------------- T H I N G S P E A K ------------- //
/*
note: this actually never successfully worked for me, but maybe you will have more
luck. in my testing, this would cause quite a slowdown every 15s when trying to send
some data. plus, thingspeak would never receive the data (prob cause the url is messed up below :P).
*/
void updateThingSpeak() {
  println("Updated ThingSpeak");
  c.write("GET /update?key="+APIKEY+"&field1="+ldrL+"&field2="+ldrR+"&field3="+pir + " HTTP/1.1\n");
  c.write("Host: robotgrrl.com\n\n");
}

