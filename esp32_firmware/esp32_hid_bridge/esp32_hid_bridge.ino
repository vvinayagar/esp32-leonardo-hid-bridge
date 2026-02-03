#include <NimBLEDevice.h>

static const char* kDeviceName = "ESP-HID-Bridge";
static const char* kTokenPrefix = "TOKEN=1234;";

static NimBLECharacteristic* gWriteChar = nullptr;
static String gBuffer;

void processLine(const String& line) {
  if (line.startsWith(kTokenPrefix)) {
    String cmd = line.substring(strlen(kTokenPrefix));
    Serial.print("RX:");
    Serial.println(cmd);
    Serial2.print(cmd);
    Serial2.print('\n');
  } else {
    Serial.println("AUTH FAIL");
  }
}

class WriteCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* characteristic, NimBLEConnInfo& connInfo) override {
    (void)connInfo;
    std::string value = characteristic->getValue();
    if (value.empty()) return;

    for (char c : value) {
      if (c == '\n') {
        if (gBuffer.length() > 0) {
          processLine(gBuffer);
          gBuffer = "";
        } else {
          processLine("");
        }
      } else if (c != '\r') {
        gBuffer += c;
      }
    }
  }
};

class ServerCallbacks : public NimBLEServerCallbacks {
  void onDisconnect(NimBLEServer* server, NimBLEConnInfo& connInfo, int reason) override {
    (void)connInfo;
    (void)reason;
    NimBLEDevice::startAdvertising();
  }
};

void setup() {
  Serial.begin(115200);
  Serial2.begin(115200, SERIAL_8N1, 16, 17); // RX=16, TX=17

  NimBLEDevice::init(kDeviceName);
  NimBLEServer* server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  NimBLEService* service = server->createService(
    "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
  );

  gWriteChar = service->createCharacteristic(
    "6E400002-B5A3-F393-E0A9-E50E24DCCA9E",
    NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR
  );

  gWriteChar->setCallbacks(new WriteCallbacks());

  service->start();

  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  
  // 1. Advertisement Data: UUIDs + TX Power
  NimBLEAdvertisementData advData;
  advData.setFlags(0x06); // General Discoverable + BLE Only
  advData.setCompleteServices(NimBLEUUID("6E400001-B5A3-F393-E0A9-E50E24DCCA9E"));
  advData.addTxPower();
  
  // 2. Scan Response Data: Name
  NimBLEAdvertisementData scanData;
  scanData.setName(kDeviceName);

  advertising->setAdvertisementData(advData);
  advertising->setScanResponseData(scanData);

  advertising->start();

  pinMode(2, OUTPUT);
  for(int i=0; i<3; i++) {
    digitalWrite(2, HIGH);
    delay(200);
    digitalWrite(2, LOW);
    delay(200);
  }
  Serial.println("ESP-HID-Bridge started");
}

void loop() {
  // Heartbeat blink every 2 seconds to show it's alive
  static unsigned long lastBlink = 0;
  if (millis() - lastBlink > 2000) {
    lastBlink = millis();
    digitalWrite(2, HIGH);
    delay(50);
    digitalWrite(2, LOW);
  }
  delay(10);
}
