# ESP32 - Leonardo HID Bridge

This monorepo implements a transparent, permission-based macro keyboard pipeline:

Flutter Android app -> BLE -> ESP32 -> UART -> Arduino Leonardo -> USB HID -> Laptop

Use it only with devices you own or have permission to control.

## Architecture

```
+-------------------+         BLE          +-------------------+      UART       +----------------------+     USB HID     +---------+
| Flutter Android   |  ------------------> | ESP32-WROOM       |  -------------> | Arduino Leonardo    |  -------------> | Laptop  |
| App (Android)     |  Write characteristic | GATT server +     |  Serial2 115200 | Keyboard emulator   |  USB keyboard   |         |
+-------------------+                      | auth token gate   |                 | (Keyboard.h)        |                 |         |
```

## Wiring Diagram

```
ESP32-WROOM                    Arduino Leonardo
-----------                    -----------------
GPIO17 (TX2)  ----------------> RX1 (Pin 0)
GPIO16 (RX2)  <---------------- TX1 (Pin 1)  [LEVEL SHIFT / VOLTAGE DIVIDER REQUIRED]
GND           ----------------> GND

Leonardo USB -> Laptop (HID keyboard)
```

Warning: Leonardo TX is 5V. Use a level shifter or voltage divider into ESP32 RX (GPIO16).

## Command Protocol

Each line must end with `\n` and include a token prefix:

```
TOKEN=1234;<COMMAND>\n
```

Commands:
- ARM:ON / ARM:OFF
- TYPE:<text>
- KEY:ENTER | KEY:TAB | KEY:ESC | KEY:BACKSPACE | KEY:UP | KEY:DOWN | KEY:LEFT | KEY:RIGHT
- HOTKEY:CTRL+ALT+T (modifiers: CTRL/ALT/SHIFT/WIN + final key)
- DELAY:<ms> (max 5000)

The ESP32 checks the token prefix. If missing or wrong, it logs AUTH FAIL and ignores the line.

## Build / Flash / Run

### 1) Flutter Android app

```
cd flutter_app
flutter pub get
flutter run
```

- The app uses flutter_blue_plus and requires Android BLE permissions.
- Open settings (gear icon) to edit token and toggle Auto ARM on connect.
- The Control screen includes manual buttons plus a Macros section.

### 2) ESP32 firmware (Arduino framework)

1. Install NimBLE-Arduino library (Arduino IDE -> Library Manager).
2. Select board: ESP32 Dev Module (or your ESP32-WROOM board).
3. Open `esp32_firmware/esp32_hid_bridge.ino`.
4. Flash to the ESP32.

### 3) Arduino Leonardo firmware

1. Select board: Arduino Leonardo.
2. Open `leonardo_firmware/leonardo_hid_bridge.ino`.
3. Flash to the Leonardo.

## Flutter App Macros

Macros are preprogrammed sequences of command lines. When tapped, each line is sent in order
with a short delay between lines. You can stop a running macro with the Stop button.

## Troubleshooting

BLE Scan shows nothing
- Ensure Bluetooth is on.
- Grant permissions: BLUETOOTH_SCAN / BLUETOOTH_CONNECT.
- On Android 11 and older, location permission is required for BLE scanning.

Connect succeeds but no typing
- Verify token matches on ESP32 and in the app settings.
- Ensure Leonardo is ARMED (ARM:ON).
- Check UART wiring and ground.

Garbage characters or no UART data
- Confirm baud rate is 115200 on both boards.
- Use a level shifter between Leonardo TX (5V) and ESP32 RX.

Disconnects or unstable BLE
- Move closer to the ESP32.
- Reduce macro speed (increase delay).

## Safety Notes

- ARM switch: The Leonardo defaults to ARMED = false. It will ignore commands until
  you explicitly send ARM:ON.
- Startup delay: The Leonardo waits 3 seconds before Keyboard.begin() to prevent
  accidental keystrokes on boot.
- Use this only on devices you own or have explicit permission to control.

## Quick Test Sequence

1. Connect from the Flutter app.
2. Tap ARM ON.
3. Tap Demo: Hello + Enter macro.
4. Tap ARM OFF when done.
