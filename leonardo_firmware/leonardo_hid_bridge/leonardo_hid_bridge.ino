#include <Keyboard.h>
#include <Mouse.h>

static const uint16_t kMaxLineLength = 200;
static bool gArmed = false;
static bool gOverflow = false;

char gLineBuffer[kMaxLineLength + 1];
uint16_t gLineIndex = 0;

void resetBuffer() {
  gLineIndex = 0;
  gOverflow = false;
  gLineBuffer[0] = '\0';
}

void logAction(const String& msg) {
  Serial.println(msg);
}

void sendKey(uint8_t key) {
  Keyboard.press(key);
  delay(10);
  Keyboard.releaseAll();
}

uint8_t keyFromName(const String& keyName, bool& ok) {
  ok = true;
  if (keyName == "ENTER") return KEY_RETURN;
  if (keyName == "TAB") return KEY_TAB;
  if (keyName == "ESC") return KEY_ESC;
  if (keyName == "BACKSPACE") return KEY_BACKSPACE;
  if (keyName == "UP") return KEY_UP_ARROW;
  if (keyName == "DOWN") return KEY_DOWN_ARROW;
  if (keyName == "LEFT") return KEY_LEFT_ARROW;
  if (keyName == "RIGHT") return KEY_RIGHT_ARROW;
  ok = false;
  return 0;
}

uint8_t mouseButtonFromName(const String& buttonName, bool& ok) {
  ok = true;
  if (buttonName == "LEFT") return MOUSE_LEFT;
  if (buttonName == "RIGHT") return MOUSE_RIGHT;
  if (buttonName == "MIDDLE") return MOUSE_MIDDLE;
  ok = false;
  return 0;
}

void handleType(const String& text) {
  if (!gArmed) {
    logAction("IGNORED (DISARMED): TYPE");
    return;
  }
  logAction("TYPE: " + text);
  Keyboard.print(text);
}

void handleKey(const String& keyName) {
  if (!gArmed) {
    logAction("IGNORED (DISARMED): KEY");
    return;
  }
  bool ok = false;
  uint8_t key = keyFromName(keyName, ok);
  if (!ok) {
    logAction("UNKNOWN KEY: " + keyName);
    return;
  }
  logAction("KEY: " + keyName);
  sendKey(key);
}

void handleDelay(const String& msString) {
  if (!gArmed) {
    logAction("IGNORED (DISARMED): DELAY");
    return;
  }
  int ms = msString.toInt();
  if (ms < 0) ms = 0;
  if (ms > 5000) ms = 5000;
  logAction("DELAY: " + String(ms));
  delay(ms);
}

void handleMouseMove(const String& args) {
  int commaIndex = args.indexOf(',');
  if (commaIndex < 0) {
    logAction("MOUSE MOVE invalid args");
    return;
  }
  int dx = args.substring(0, commaIndex).toInt();
  int dy = args.substring(commaIndex + 1).toInt();
  dx = constrain(dx, -127, 127);
  dy = constrain(dy, -127, 127);
  Mouse.move(dx, dy, 0);
  logAction("MOUSE MOVE: " + String(dx) + "," + String(dy));
}

void handleMouseScroll(const String& args) {
  int dy = 0;
  int commaIndex = args.indexOf(',');
  if (commaIndex >= 0) {
    dy = args.substring(commaIndex + 1).toInt();
  } else {
    dy = args.toInt();
  }
  dy = constrain(dy, -127, 127);
  Mouse.move(0, 0, dy);
  logAction("MOUSE SCROLL: " + String(dy));
}

void handleMouseButton(const String& action, const String& buttonName) {
  bool ok = false;
  String name = buttonName;
  name.toUpperCase();
  uint8_t button = mouseButtonFromName(name, ok);
  if (!ok) {
    logAction("UNKNOWN MOUSE BUTTON: " + buttonName);
    return;
  }
  if (action == "DOWN") {
    Mouse.press(button);
  } else if (action == "UP") {
    Mouse.release(button);
  } else if (action == "CLICK") {
    Mouse.click(button);
  } else {
    logAction("UNKNOWN MOUSE ACTION: " + action);
    return;
  }
  logAction("MOUSE " + action + ": " + name);
}

void handleMouse(const String& payload) {
  if (!gArmed) {
    logAction("IGNORED (DISARMED): MOUSE");
    return;
  }
  int colonIndex = payload.indexOf(':');
  String action = colonIndex >= 0 ? payload.substring(0, colonIndex) : payload;
  String args = colonIndex >= 0 ? payload.substring(colonIndex + 1) : "";
  action.toUpperCase();

  if (action == "MOVE") {
    handleMouseMove(args);
    return;
  }
  if (action == "SCROLL") {
    handleMouseScroll(args);
    return;
  }
  if (action == "DOWN" || action == "UP" || action == "CLICK") {
    handleMouseButton(action, args);
    return;
  }

  logAction("UNKNOWN MOUSE CMD: " + payload);
}

void handleHotkey(const String& combo) {
  if (!gArmed) {
    logAction("IGNORED (DISARMED): HOTKEY");
    return;
  }

  bool ctrl = false;
  bool alt = false;
  bool shift = false;
  bool win = false;

  String remaining = combo;
  String finalKey;

  while (true) {
    int plusIndex = remaining.indexOf('+');
    String token = plusIndex >= 0 ? remaining.substring(0, plusIndex) : remaining;
    token.trim();
    token.toUpperCase();

    if (token == "CTRL") ctrl = true;
    else if (token == "ALT") alt = true;
    else if (token == "SHIFT") shift = true;
    else if (token == "WIN") win = true;
    else finalKey = token;

    if (plusIndex < 0) break;
    remaining = remaining.substring(plusIndex + 1);
  }

  if (finalKey.length() == 0) {
    logAction("HOTKEY missing final key");
    return;
  }

  if (ctrl) Keyboard.press(KEY_LEFT_CTRL);
  if (alt) Keyboard.press(KEY_LEFT_ALT);
  if (shift) Keyboard.press(KEY_LEFT_SHIFT);
  if (win) Keyboard.press(KEY_LEFT_GUI);

  bool ok = false;
  uint8_t key = keyFromName(finalKey, ok);
  if (ok) {
    Keyboard.press(key);
  } else if (finalKey.length() == 1 && finalKey[0] >= 'A' && finalKey[0] <= 'Z') {
    Keyboard.press(finalKey[0]);
  } else if (finalKey == "R" || finalKey == "T") {
    Keyboard.press(finalKey[0]);
  } else {
    logAction("UNKNOWN HOTKEY: " + finalKey);
  }

  delay(10);
  Keyboard.releaseAll();
  logAction("HOTKEY: " + combo);
}

void handleCommand(const String& line) {
  Serial.print("RX: ");
  Serial.println(line);

  if (line == "ARM:ON") {
    gArmed = true;
    logAction("ARMED");
    return;
  }
  if (line == "ARM:OFF") {
    gArmed = false;
    logAction("DISARMED");
    return;
  }

  if (line.startsWith("TYPE:")) {
    handleType(line.substring(5));
    return;
  }
  if (line.startsWith("KEY:")) {
    handleKey(line.substring(4));
    return;
  }
  if (line.startsWith("HOTKEY:")) {
    handleHotkey(line.substring(7));
    return;
  }
  if (line.startsWith("MOUSE:")) {
    handleMouse(line.substring(6));
    return;
  }
  if (line.startsWith("DELAY:")) {
    handleDelay(line.substring(6));
    return;
  }

  logAction("UNKNOWN CMD: " + line);
}

void setup() {
  Serial.begin(115200);
  Serial1.begin(115200);

  delay(3000); // Startup safety delay
  Keyboard.begin();
  Mouse.begin();

  logAction("Leonardo HID bridge ready (ARMED=false)");
}

void loop() {
  while (Serial1.available() > 0) {
    char c = Serial1.read();

    if (c == '\n') {
      if (!gOverflow) {
        gLineBuffer[gLineIndex] = '\0';
        handleCommand(String(gLineBuffer));
      } else {
        logAction("IGNORED: line too long");
      }
      resetBuffer();
      continue;
    }

    if (c == '\r') {
      continue;
    }

    if (gOverflow) {
      continue;
    }

    if (gLineIndex < kMaxLineLength) {
      gLineBuffer[gLineIndex++] = c;
    } else {
      gOverflow = true;
    }
  }
}
