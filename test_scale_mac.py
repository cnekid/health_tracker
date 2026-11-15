import asyncio
import sys
import time
from bleak import BleakScanner

TARGET_MAC_BYTES = bytes([0xE3, 0x44, 0x39, 0xBB, 0x12, 0xAC])  # AC:12:BB:39:44:E3 reverse
TARGET_MAC_DIRECT = bytes([0xAC, 0x12, 0xBB, 0x39, 0x44, 0xE3]) # direct
TARGET_CID = 0xFFFF

print("=" * 65)
print("🔍 [맥북 실시간 BLE 체중계 패킷 캡처 및 BIA 디코더]")
print("📡 맥북 블루투스 안테나가 활성화되었습니다.")
print("👉 지금 체중계에 맨발로 올라서서 측정을 완료해 주세요 (5분간 대기)")
print("=" * 65)
sys.stdout.flush()

received_count = 0
last_dot_time = time.time()

def callback(device, advertisement_data):
    global received_count
    mfg_data = advertisement_data.manufacturer_data
    if not mfg_data:
        return

    matched = False
    raw_payload = None
    matched_cid = None

    for cid, data in mfg_data.items():
        data_bytes = bytes(data)
        if cid == TARGET_CID or TARGET_MAC_BYTES in data_bytes or TARGET_MAC_DIRECT in data_bytes:
            matched = True
            matched_cid = cid
            raw_payload = data_bytes
            break

    if matched and raw_payload:
        received_count += 1
        now_str = time.strftime("%H:%M:%S")
        full_hex = f"{matched_cid:04X}" + raw_payload.hex().upper()
        spaced_hex = " ".join([full_hex[i:i+2] for i in range(0, len(full_hex), 2)])
        
        print(f"\n[{now_str}] 🎯 체중계 신호 포착! (수신 #{received_count})")
        print(f"  • 기기 식별자: {device.address} (RSSI: {advertisement_data.rssi} dBm)")
        print(f"  • 제조사 ID: 0x{matched_cid:04X} | 전체 길이: {len(full_hex)//2} 바이트")
        print(f"  • 원본 패킷: {spaced_hex}")

        # Payload analysis (Chipsea 25-byte protocol)
        # full_hex: FF FF 00 15 43 11 FF F0 11 E3 44 39 BB 12 AC DC [Weight] [Impedance] ...
        full_bytes = bytes.fromhex(full_hex)
        print("  --- [실시간 데이터 해석 후보] ---")
        # In 25 bytes, byte 14..20 usually contain weight & impedance
        for offset in range(14, min(len(full_bytes) - 1, 23)):
            val_le = int.from_bytes(full_bytes[offset:offset+2], "little")
            val_be = int.from_bytes(full_bytes[offset:offset+2], "big")
            print(f"    바이트 [{offset:02d}-{offset+1:02d}] ({full_bytes[offset]:02X} {full_bytes[offset+1]:02X}) ➔ "
                  f"LE: {val_le} (kg: {val_le/100:.2f} / 저항: {val_le}Ω) | "
                  f"BE: {val_be} (kg: {val_be/100:.2f} / 저항: {val_be}Ω)")
        print("-" * 65)
        sys.stdout.flush()

async def main():
    global last_dot_time
    scanner = BleakScanner(detection_callback=callback)
    await scanner.start()
    try:
        # Wait up to 300 seconds (5 minutes)
        for second in range(300):
            await asyncio.sleep(1)
            if time.time() - last_dot_time >= 5:
                if received_count == 0:
                    sys.stdout.write(".")
                    sys.stdout.flush()
                last_dot_time = time.time()
            if received_count >= 15:
                print("\n✅ 안정적인 신호 연속 수신 확인 완료!")
                break
    finally:
        await scanner.stop()
        if received_count == 0:
            print("\n⚠️ 5분 동안 체중계 신호가 감지되지 않았습니다.")
        else:
            print(f"\n⏹️ 총 {received_count}개의 유효 패킷 수신 완료.")

if __name__ == "__main__":
    asyncio.run(main())
