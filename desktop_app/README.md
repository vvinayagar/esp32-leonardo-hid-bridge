# Windows Desktop Receiver (Wi-Fi)

This app listens for UDP commands from the Flutter app and executes
keyboard/mouse actions on Windows.

## Setup

1. Install Python 3.9+.
2. Install dependencies:

```
pip install -r requirements.txt
```

3. Run the receiver:

```
python windows_receiver.py
```

## Configure

- Token: must match the Flutter app token.
- UDP Port: default `51515`.
- Keep the phone and PC on the same Wi-Fi network.
- In the Flutter app settings, set Desktop Host to your PC IP
  (for example `192.168.1.10`) and Port to the same UDP port.

Windows may prompt for firewall access. Allow UDP on the selected port.

## Notes

- The receiver obeys ARM:ON / ARM:OFF. It will ignore commands while disarmed.
- Commands use the same protocol as the ESP32 bridge:
  `TOKEN=1234;TYPE:hello`
- Mouse and trackpad commands are supported:
  `MOUSE:MOVE:x,y`, `MOUSE:SCROLL:dy`, `MOUSE:CLICK:LEFT`, etc.
