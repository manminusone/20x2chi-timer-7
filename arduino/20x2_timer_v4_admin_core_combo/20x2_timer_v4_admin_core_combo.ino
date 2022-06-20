/***********************************************
 * 
 * 20x2 timer v.4 admin code for M5Stack Core/Core2
 * 
 * This is a probject to get an admin interface
 * running on both the M5Stack Core and Core2
 * machines. Each one has similar architectures
 * but slightly different interfaces.
 * 
 ***********************************************/

// #define DEBUG 1

#include <esp_http_client.h>

#if defined(ARDUINO_M5Stack_Core_ESP32) || defined(ARDUINO_M5STACK_Core_ESP32)
#include <M5Stack.h>
#include <utility/Power.h>

#include "secret.h"

void batteryInit() { M5.Power.begin(); }
bool charging()    { return M5.Power.isCharging(); }
int batPercent()   { return M5.Power.getBatteryLevel(); }

#elif defined(ARDUINO_M5Stack_Core2) || defined(ARDUINO_M5STACK_Core2)
#include <M5Core2.h>
#include <AXP192.h>

AXP192 axp192;
void batteryInit() { axp192.begin(); }
bool charging()    { return axp192.isCharging(); }
int batPercent()   { return (int) axp192.GetBatteryLevel(); }

#else
#error "Need to run on a M5Stack board."
#endif

#include <WiFi.h>
#include <DigiFont.h>

#define RGBto565(r,g,b) ((((r) & 0xF8) << 8) | (((g) & 0xFC) << 3) | ((b) >> 3)) 

/*************************************************************************
 * 
 * common variables
 * 
 *************************************************************************/

const int NOVAL = 9999; // out of range integer that can be used to indicate no value was read


extern unsigned char splashJpg[];

#define STAT_OFF  1
#define STAT_RUN  2

int timeval = 120, sgn = 1;
int timer_status = STAT_OFF;
int old_timeval = 0;

#ifdef  DEBUG

char retstr[32];
char *serverIP() {
  IPAddress serverIP;
  if (WiFi.hostByName("20x2chi-timer.local",serverIP)) {
    Serial.println(">>> IP received");
    serverIP.toString().toCharArray(retstr,32);
    return retstr;
  }
  Serial.println(">>> Didn't get IP");
  return NULL;
}

#else
char *serverIP() {
  return (char *)"192.168.4.1";
}

#endif

char TIMERURL[100], TIMERSTART[100], TIMERSTOP[100];

// definitions for DigiFont
void customLineH(int x0,int x1, int y, int c) { M5.Lcd.drawLine(x0,y,x1,y, c); }
void customLineV(int x, int y0,int y1, int c) { M5.Lcd.drawLine(x,y0, x,y1, c); } 
void customRect(int x, int y,int w,int h, int c) { M5.Lcd.fillRect(x,y,w,h, c); } 
DigiFont dfont(customLineH,customLineV,customRect);


/*************************************************************************
 * 
 * UI stuff here
 * 
 *************************************************************************/

uint8_t brightness = 127;

/* Draw an arrow indicating outgoing wifi data */
void draw_wifi_up(bool is_on) {
  M5.Lcd.fillTriangle(200,18, 208,2, 216,18, is_on ? WHITE : BLUE);
}

/* draw an arrow indicating incoming wifi data */ 
void draw_wifi_down(bool is_on) {
  M5.Lcd.fillTriangle(220,2, 236,2, 228,18, is_on ? WHITE : BLUE);
}


/* draw the battery icon with percentage and optional charging symbol */
void draw_battery(int percentage, bool is_charging) {
  int startx = 280, starty = 5;
  M5.Lcd.drawLine(startx,starty, startx+19,starty, WHITE);
  M5.Lcd.drawLine(startx,starty+9, startx+19,starty+9, WHITE);
  M5.Lcd.drawLine(startx+19,starty, startx+19,starty+9,WHITE);
  M5.Lcd.drawLine(startx,starty, startx,starty+9,WHITE);
  M5.Lcd.fillRect(startx+20,starty+2, 4,6,WHITE);

  if (percentage > 10)
    for (int i = 1; i <= 8; ++i) 
      M5.Lcd.drawLine(startx,starty+i, startx + ceil(percentage * 0.2), starty+i, WHITE);

  if (is_charging) {
    //int whiteVal[] = { 8,14, 8,14, 7,14, 7,14, 6,13, 6,13, 6,11, 5,11, 5,9, 5,9 };
    //int blackVal[] = { -1,-1, 9,13, 9,13, 8,12, 8,12, 7,10, 7,10, 6,9, 6,8, -1,-1 };
    int blueVal[] = { 6,8, 6,8, 5,8, 4,8, 3,8, 3,7, 2,7, 2,12, 1,12, 0,12, 0,11, 0,10, 5,10, 5,9, 4,8, 4,8, 4,7, 4,6, 4,6 };
    int whiteVal[] = { -1,-1, 7,7, 7,7, 6,7, 5,6, 5,6, 4,6, 3,6, 3,11, 2,10, 1,9, 6,9, 6,8, 6,7, 6,7, 5,6, 5,5, 5,5, 5,5, -1,-1 };
    for (int i = 0; i < 19; ++i) {
      Serial.printf(".. %d\n", i);
      M5.Lcd.drawLine(startx+blueVal[i * 2] + 5, starty + i-4, startx+blueVal[i * 2 + 1] + 5,starty + i-4, BLUE);
      if (whiteVal[i * 2] != -1) 
        M5.Lcd.drawLine(startx+whiteVal[i * 2]+5, starty + i-4, startx+whiteVal[i * 2 + 1] + 5,starty+i-4, WHITE);
    }
    Serial.println("done with battery");
  }
}

/* just draw everything in the header */
void draw_header() {
  M5.Lcd.fillRect(0,0,320,20,BLUE);
  M5.Lcd.setTextSize(2);
  M5.Lcd.setTextColor(WHITE);
  M5.Lcd.setCursor(10,3);
  M5.Lcd.print("20x2 TIMER");

  draw_battery(batPercent(), charging());
}

/* draw the colorful labels for the buttons */
void draw_buttons() {
  M5.Lcd.fillRect(0,200,100,40,   0x000f);
  M5.Lcd.fillRect(220,200,100,40, 0x03E0);
  M5.Lcd.setTextSize(2);
  M5.Lcd.setCursor(20, 215);
  M5.Lcd.print("START");

  // brightness icon
  M5.Lcd.fillTriangle(150,210, 150,230, 170,230, WHITE);
  M5.Lcd.drawLine(150,210, 170,210, WHITE);
  M5.Lcd.drawLine(170,210, 170,230, WHITE);
  
  M5.Lcd.setCursor(240, 215);
  M5.Lcd.print("RESET");
}
/* draw the screen apart from the clock */
void draw_screen() {
  M5.Lcd.setBrightness(brightness);
  M5.Lcd.fillScreen(BLACK);
  Serial.println("Drawing hdr");
  draw_header();
  Serial.println("Drawing buttons");
  draw_buttons();
  Serial.println("Drawing done");
}

/**************************************************************************
 * 
 * connect_to_wifi - do the old wifi connection thing with status msg
 * 
 **************************************************************************/

 bool connect_to_wifi() {
  unsigned long startTime = millis();
  int16_t cx;
  String dotData = "  .  ";
  int dotPtr = 2,yValue = 220;
  char *wifistat[] = { "WL_IDLE_STATUS", "WL_NO_SSID_AVAIL", "WL_SCAN_COMPLETED", "WL_CONNECTED", "WL_CONNECT_FAILED", "WL_CONNECTION_LOST", "WL_DISCONNECTED" };
  
  M5.Lcd.fillRect(0,yValue,320,40, BLACK);
  M5.Lcd.setTextColor(YELLOW,BLACK);
  M5.Lcd.setTextSize(2);
  M5.Lcd.setCursor(10,yValue);
  M5.Lcd.print("connecting to wifi");
  Serial.printf("ssid %s, pwd %s\n",WIFI_SSID, WIFI_PWD);
  cx = M5.Lcd.getCursorX();
  WiFi.begin(WIFI_SSID,WIFI_PWD);
  while (WiFi.status() != WL_CONNECTED && (millis() - startTime < 15000)) {
    Serial.print("wifi status = "); Serial.println(wifistat[WiFi.status()]);
    M5.Lcd.setCursor(cx,yValue);
    M5.Lcd.print(dotData.substring(dotPtr,dotPtr+3));
    --dotPtr;
    if (dotPtr < 0) { dotPtr = 2; }
    delay(250);
  }
  M5.Lcd.setCursor(10,yValue);
  if (WiFi.status() == WL_CONNECTED) {
    M5.Lcd.print("CONNECTED            ");
  } else {
    M5.Lcd.print("TIMED OUT            ");
  }
  delay(1000);
  return WiFi.status() == WL_CONNECTED;
}

/*************************************************************************
 * 
 * ESP client functions
 * 
 *************************************************************************/

esp_http_client_handle_t http_client;

/* callback function for handling HTTP data */
esp_err_t data_handler(esp_http_client_event_t* evt) {
  int i;
  // draw_wifi_up(false);
  // draw_wifi_down(true);
  switch (evt->event_id) {
    case HTTP_EVENT_ON_DATA: 
    { // this superfluous block fixes compiler complaint about timeval change
      // printf("DATA > len = %d\r\n", evt->data_len);
      char *cp = (char *) evt->data;

      // handle possible 'OK' string
      if (!strcmp(cp, "OK")) {
        // draw_wifi_down(false);
        return ESP_OK;
      }

      for (i = 0; i < evt->data_len; ++i) {
        char c = cp[i];
        if (c == '-') { sgn = -1; }
        if (isdigit(c)) {
          timeval = timeval * 10 + (c - '0');
        }
      }
      break; 
    }
    case HTTP_EVENT_ERROR:
      printf("HTTP EVENT ERROR\r\n");
      timeval = NOVAL;
      break;
  }
  // draw_wifi_down(false);
  return ESP_OK;
}

 void client_init() {
  esp_http_client_config_t config_client = {0};

  Serial.println("Fetching ip");
  char *ipaddr = serverIP();
  if (ipaddr != NULL) {
    Serial.printf("Found IP: %s\n", ipaddr);
    sprintf(TIMERURL,   "http://%s/time", ipaddr);
    sprintf(TIMERSTART, "http://%s/time/start", ipaddr);
    sprintf(TIMERSTOP,  "http://%s/time/stop", ipaddr);

    config_client.url           = TIMERURL;
    config_client.event_handler = data_handler;
    config_client.method        = HTTP_METHOD_GET;
    http_client = esp_http_client_init(&config_client);

  } else {
    Serial.println("*** IP ADDRESS NOT RECEIVED");
    while (true) { delay(1000); } // FIXME - ?
  }
}


/*************************************************************************
 * 
 * timer functions
 * 
 *************************************************************************/

esp_err_t timer_start() { 
  esp_err_t err = esp_http_client_set_url(http_client, TIMERSTART);
  // draw_wifi_up(true);
  err = esp_http_client_perform(http_client);
  if (err == ESP_OK) {
    // timer started!
    Serial.println("* GOT CONFIRMATION");
    timer_status = STAT_RUN;
  }
  return err;
}

esp_err_t timer_stop() {
  esp_err_t err = esp_http_client_set_url(http_client, TIMERSTOP);
  // draw_wifi_up(true);
  err = esp_http_client_perform(http_client);
  if (err == ESP_OK) {
    // timer stopped!
    Serial.println("* GOT CONFIRMATION");
    timer_status = STAT_OFF;
  }
  return err;
}

esp_err_t timer_check() {
  old_timeval = timeval * sgn;
  timeval = 0; sgn = 1;

  // init the type of request
  esp_err_t err = esp_http_client_set_url(http_client, TIMERURL);
  // draw_wifi_up(true);
  err = esp_http_client_perform(http_client);
  if (err == ESP_OK) {
    Serial.printf("time = %d\r\n", timeval * sgn);
  } else {
    Serial.printf("ERROR %d\n", err);
  }
  return err;
}

/* display the time in DigiFont */
void timer_show() {
  int numThk = 11, SCR_HT = 240, SCR_WD = 320;
  int colonThk=4,colonSpc=8;
  int secs = timeval * sgn;
  int d1 = timeval/60,
      d2 = (timeval % 60) / 10,
      d3 = (timeval % 10);
  char sign = (secs < 0 ? '-' : ' ');

  // TODO - implement blinking
  if (timer_status == STAT_OFF) {  // timer off colors
    dfont.setColors(RGBto565(0,125,0),RGBto565(0,90,0),RGBto565(0,20,0));
  } else {
    if (secs > 15) { // green
      dfont.setColors(RGBto565(0,250,0),RGBto565(0,180,0),RGBto565(0,40,0));
    } else if (secs > 0) { // amber
      dfont.setColors(RGBto565(250,250,0),RGBto565(180,180,0),RGBto565(40,40,0));
    } else { // red
      dfont.setColors(RGBto565(250,0,0),RGBto565(180,0,0),RGBto565(40,0,0));
    }
  }
  int w=(SCR_HT-numThk-colonSpc*2)/4;
  int leftSpace = (SCR_WD - (4*w+2*colonSpc-colonThk)) / 2;
  dfont.setSize2(w-colonThk,w*2,numThk);
  int y=(SCR_HT-w*2)/2;
  dfont.drawDigit2c(sign, leftSpace + 0*w,y);
  dfont.drawDigit2c(d1, leftSpace + 1*w,y);
  dfont.drawDigit2c(':', leftSpace + 2*w+colonSpc-colonThk,y);
  dfont.drawDigit2c(d2, leftSpace + numThk+2*colonSpc-colonThk+2*w,y);
  dfont.drawDigit2c(d3, leftSpace + numThk+2*colonSpc-colonThk+3*w,y);  
}

/*************************************************************************
 * 
 * main loops here
 * 
 *************************************************************************/
void setup() {
  Serial.begin(115200);
  M5.begin();
  batteryInit();

  M5.Lcd.fillScreen(BLACK); // clearing the screen appears to make the drawJpg run faster
  M5.Lcd.drawJpg(splashJpg, 19405, 0,0);


  Serial.println("Starting wifi connect");
  if (connect_to_wifi()) {
    draw_screen();
    Serial.println("Attempting to init client");
    client_init();
    Serial.println("Completed");
  } else { Serial.println("no connect to wifi"); while (true) { delay(1000); } } // just do nothing
}

void loop() {

  if (WiFi.status() == WL_CONNECTED) {
    M5.update();

    printf("[%s] [%s] [%s]\n", (M5.BtnA.isPressed() ? "A" : " "),(M5.BtnB.isPressed() ? "B" : " "),(M5.BtnC.isPressed() ? "C" : " "));
    printf("STATUS = %s\n", timer_status == STAT_RUN ? "STAT_RUN" : timer_status == STAT_OFF ? "STAT_OFF" : "unknown");

    if (timer_status == STAT_OFF && M5.BtnA.isPressed()) {
      Serial.println("Starting timer");
      timer_start();
    }
    if (M5.BtnB.isPressed()) {
      Serial.print("Brightness: "); Serial.println(brightness);
      brightness += 32;
      if (brightness >= 256) brightness -= 256;
      M5.Lcd.setBrightness(brightness);
    }
    if (timer_status == STAT_RUN && M5.BtnC.isPressed()) {
      Serial.println("Stopping timer");
      timer_stop();
    }

    esp_err_t errval = timer_check();

    if (errval > ESP_ERR_HTTP_BASE) {
      M5.Lcd.setCursor(20,20);
      switch (errval) {
        case ESP_ERR_HTTP_MAX_REDIRECT:
          M5.Lcd.println("MAX REDIRECT ERR");
          break;
        case ESP_ERR_HTTP_CONNECT:
          M5.Lcd.println("HTTP CONNECT ERR");
          break;
        case ESP_ERR_HTTP_WRITE_DATA:
          M5.Lcd.println("WRITE DATA ERR");
          break;
        case ESP_ERR_HTTP_FETCH_HEADER:
          M5.Lcd.println("FETCH HDR ERR");
          break;
        case ESP_ERR_HTTP_INVALID_TRANSPORT:
          M5.Lcd.println("INVALID TRANSPORT ERR");
          break;
        case ESP_ERR_HTTP_CONNECTING:
          M5.Lcd.println("HTTP CONNECTING ERR");
          break;
        default:
          M5.Lcd.println("HTTP ERROR");
      }

    } else {
      if (timer_status == STAT_OFF && old_timeval == 120 && (timeval*sgn) < 120) {
        Serial.println("Detected run");
        timer_status = STAT_RUN;
      } else if (timer_status == STAT_RUN && old_timeval < 120 && (timeval*sgn) == 120) {
        Serial.println("Detected stop");
        timer_status = STAT_OFF;
      }
  
      timer_show();
    }
  }

  delay(200);
}
