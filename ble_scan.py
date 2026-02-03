import asyncio
from bleak import BleakScanner

async def main():
    print("Scanning for BLE devices for 10 seconds...")
    devices = await BleakScanner.discover(timeout=10.0)
    found = False
    for d in devices:
        name = d.name or "Unknown"
        if "ESP-HID" in name:
            found = True
            print(f"MATCH FOUND: {name} ({d.address})")
        else:
            print(f"Found: {name} ({d.address})")
    
    if found:
        print("\nSUCCESS: ESP-HID-Bridge device was detected!")
    else:
        print("\nFAIL: ESP-HID-Bridge was NOT found in this scan.")

if __name__ == "__main__":
    asyncio.run(main())

