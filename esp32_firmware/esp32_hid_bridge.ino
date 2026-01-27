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
  void onWrite(NimBLECharacteristic* characteristic) override {
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
  void onDisconnect(NimBLEServer* server) override {
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
  advertising->addServiceUUID(service->getUUID());
  advertising->setScanResponse(true);
  advertising->start();

  Serial.println("ESP-HID-Bridge started");
}

void loop() {
  delay(10);
}
