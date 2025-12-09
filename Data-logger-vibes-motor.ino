#include <Arduino.h>
#include <Wire.h>
#include <SPI.h>
#include <SD.h>

#include <TinyGPSPlus.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>

#include <WiFi.h>
#include <esp_wifi.h>
#include "esp_bt.h"

// ===================== PINES =====================
// I2C MPU6050 (lado IZQUIERDO)
#define I2C_SDA_PIN   25   // D25
#define I2C_SCL_PIN   26   // D26

// UART GPS (lado DERECHO)
#define GPS_RX_PIN    16   // RX2
#define GPS_TX_PIN    17   // TX2

// SD (VSPI, lado DERECHO)
#define SD_CS_PIN      5   // D5 (CS)
#define SD_MOSI_PIN   23   // D23 (MOSI)
#define SD_MISO_PIN   19   // D19 (MISO)
#define SD_SCK_PIN    18   // D18 (CLK)

// Botón de evento
#define BUTTON_PIN    15   // D15 (botón entre D15 y GND)

// LEDs estado GPS
#define LED_RED_PIN   32   // sin fix
#define LED_GREEN_PIN 33   // con fix

// ===================== OBJETOS GLOBALES =====================
HardwareSerial GPS_Serial(2);   // UART2
TinyGPSPlus gps;
Adafruit_MPU6050 mpu;
File logFile;

bool sdOk   = false;
bool mpuOk  = false;

String logFilename;             // nombre del fichero de log actual

// Muestreo
const unsigned long SAMPLE_INTERVAL_MS = 20; // ~50 Hz
unsigned long lastSampleTime = 0;

// Flush SD
const unsigned long FLUSH_INTERVAL_MS = 500; // cada 0,5 s
unsigned long lastFlushTime = 0;

// Botón
int lastButtonState = HIGH;

// Offsets de acelerómetro
float offsetAx = 0.0f;
float offsetAy = 0.0f;
float offsetAz = 0.0f;
bool offsetsCalc = false;

// Última orientación válida
float lastOrientationDeg = 0.0f;

// ===================== FUNCIONES AUXILIARES =====================

void disableRadios() {
  WiFi.mode(WIFI_OFF);
  WiFi.disconnect(true);
  esp_wifi_stop();
  esp_bt_controller_disable();
}

// Ahora getGPSData mantiene la última orientación válida en lastOrientationDeg
void getGPSData(String &dateStr, String &timeStr,
                double &lat, double &lon,
                double &speedKmh, int &sats,
                float &orientationDeg) {
  if (gps.date.isValid() && gps.time.isValid()) {
    char bufDate[11];
    snprintf(bufDate, sizeof(bufDate), "%04d-%02d-%02d",
             gps.date.year(), gps.date.month(), gps.date.day());
    dateStr = String(bufDate);

    char bufTime[9];
    snprintf(bufTime, sizeof(bufTime), "%02d:%02d:%02d",
             gps.time.hour(), gps.time.minute(), gps.time.second());
    timeStr = String(bufTime);
  } else {
    dateStr = "0000-00-00";
    timeStr = "00:00:00";
  }

  if (gps.location.isValid()) {
    lat = gps.location.lat();
    lon = gps.location.lng();
  } else {
    lat = 0.0;
    lon = 0.0;
  }

  if (gps.speed.isValid()) {
    speedKmh = gps.speed.kmph();
  } else {
    speedKmh = -1.0;
  }

  if (gps.satellites.isValid()) {
    sats = gps.satellites.value();
  } else {
    sats = 0;
  }

  // Orientación (rumbo) desde el GPS:
  // si el curso es válido, actualizamos lastOrientationDeg;
  // si no, reutilizamos la última orientación válida.
  if (gps.course.isValid()) {
    lastOrientationDeg = gps.course.deg();
  }
  orientationDeg = lastOrientationDeg;
}

// Siguiente nombre de fichero disponible: log_001.csv, log_002.csv, ...
String getNextLogFilename() {
  char filename[32];
  for (int i = 1; i <= 999; i++) {
    snprintf(filename, sizeof(filename), "/log_%03d.csv", i);
    if (!SD.exists(filename)) {
      return String(filename);
    }
  }
  // Si se llenan 999 ficheros, reutiliza el último
  return String("/log_999.csv");
}

bool initSD() {
  SPI.begin(SD_SCK_PIN, SD_MISO_PIN, SD_MOSI_PIN, SD_CS_PIN);

  if (!SD.begin(SD_CS_PIN)) {
    Serial.println("SD no detectada (modulo o tarjeta ausentes). Se continua sin SD.");
    return false;
  }

  logFilename = getNextLogFilename();
  Serial.print("Usando fichero de log: ");
  Serial.println(logFilename);

  logFile = SD.open(logFilename, FILE_WRITE);
  if (!logFile) {
    Serial.println("No se pudo abrir/crear el fichero de log. Se continua sin SD.");
    return false;
  }

  // Cabecera (con event, fix y orientation)
  logFile.println("millis,gps_date,gps_time,lat,lon,speed_kmh,sats,ax_g,ay_g,az_g,event,fix,orientation");
  logFile.flush();

  Serial.println("SD inicializada correctamente.");
  lastFlushTime = millis();
  return true;
}

bool initMPU() {
  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);

  if (!mpu.begin(0x68)) {
    Serial.println("ERROR: MPU6050 no detectado en 0x68.");
    mpuOk = false;
    return false;
  }

  Serial.println("MPU6050 detectado correctamente.");

  mpu.setAccelerometerRange(MPU6050_RANGE_4_G);
  mpu.setGyroRange(MPU6050_RANGE_250_DEG);
  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);

  mpuOk = true;
  return true;
}

void calibrateMPUOffsets() {
  if (!mpuOk) {
    Serial.println("Saltando calibracion: MPU no OK.");
    return;
  }

  Serial.println("Calibrando offsets de acelerometro (mantener la caja quieta)...");
  const int N = 200;
  double sx = 0.0, sy = 0.0, sz = 0.0;
  const float g_const = 9.80665f;

  for (int i = 0; i < N; ++i) {
    sensors_event_t a, g, temp;
    mpu.getEvent(&a, &g, &temp);

    sx += a.acceleration.x / g_const;
    sy += a.acceleration.y / g_const;
    sz += a.acceleration.z / g_const;
    delay(10);
  }

  offsetAx = sx / N;
  offsetAy = sy / N;
  offsetAz = (sz / N) - 1.0f; // esperamos ~1g en Z

  offsetsCalc = true;

  Serial.print("Offset Ax: "); Serial.println(offsetAx, 4);
  Serial.print("Offset Ay: "); Serial.println(offsetAy, 4);
  Serial.print("Offset Az: "); Serial.println(offsetAz, 4);
}

// ===================== SETUP =====================

void setup() {
  Serial.begin(115200);
  delay(2000);

  Serial.println("Iniciando registrador (GPS + MPU6050)...");

  disableRadios();

  pinMode(BUTTON_PIN, INPUT_PULLUP);
  pinMode(LED_RED_PIN, OUTPUT);
  pinMode(LED_GREEN_PIN, OUTPUT);

  digitalWrite(LED_RED_PIN, HIGH);
  digitalWrite(LED_GREEN_PIN, LOW);

  // GPS
  GPS_Serial.begin(9600, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);

  // SD y MPU
  sdOk  = initSD();
  mpuOk = initMPU();

  calibrateMPUOffsets();

  lastSampleTime = millis();
}

// ===================== LOOP =====================

void loop() {
  // Actualizar GPS
  while (GPS_Serial.available() > 0) {
    gps.encode(GPS_Serial.read());
  }

  // LEDs según fix GPS
  bool fix = gps.location.isValid();
  if (fix) {
    digitalWrite(LED_RED_PIN, LOW);
    digitalWrite(LED_GREEN_PIN, HIGH);
  } else {
    digitalWrite(LED_RED_PIN, HIGH);
    digitalWrite(LED_GREEN_PIN, LOW);
  }

  unsigned long now = millis();
  if (now - lastSampleTime >= SAMPLE_INTERVAL_MS) {
    lastSampleTime = now;

    float ax_g = 0.0f, ay_g = 0.0f, az_g = 0.0f;

    if (mpuOk) {
      sensors_event_t a, g, temp;
      mpu.getEvent(&a, &g, &temp);

      const float g_const = 9.80665f;
      ax_g = a.acceleration.x / g_const;
      ay_g = a.acceleration.y / g_const;
      az_g = a.acceleration.z / g_const;

      if (offsetsCalc) {
        ax_g -= offsetAx;
        ay_g -= offsetAy;
        az_g -= offsetAz;
      }
    }

    // --- GPS + orientación ---
    String dateStr, timeStr;
    double lat, lon, speedKmh;
    int sats;
    float orientation;
    getGPSData(dateStr, timeStr, lat, lon, speedKmh, sats, orientation);

    // --- Botón ---
    int buttonState = digitalRead(BUTTON_PIN);
    int eventFlag = 0;
    if (lastButtonState == HIGH && buttonState == LOW) {
      eventFlag = 1;
      Serial.println("EVENTO DE BOTON");
    }
    lastButtonState = buttonState;

    // --- fix flag (0/1) ---
    int fixFlag = fix ? 1 : 0;

    // Construir línea CSV
    char line[260];
    snprintf(line, sizeof(line),
             "%lu,%s,%s,%.6f,%.6f,%.2f,%d,%.4f,%.4f,%.4f,%d,%d,%.2f",
             (unsigned long)now,
             dateStr.c_str(),
             timeStr.c_str(),
             lat,
             lon,
             speedKmh,
             sats,
             ax_g,
             ay_g,
             az_g,
             eventFlag,
             fixFlag,
             orientation);

    if (sdOk && logFile) {
      logFile.println(line);

      unsigned long tNow = millis();
      if (tNow - lastFlushTime >= FLUSH_INTERVAL_MS) {
        logFile.flush();
        lastFlushTime = tNow;
      }
    }

    Serial.println(line);
  }
}
