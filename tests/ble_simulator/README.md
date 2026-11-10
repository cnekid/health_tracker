# ⚖️ 가상 체중계 BLE 시뮬레이터 (MacBook BLE Peripheral)

HealthTracker 애플리케이션의 체중계 연동 기능을 물리 체중계 없이 책상에서 테스트할 수 있도록 지원하는 맥북 전용 가상 BLE 장치(Peripheral)입니다.

---

## 🛠️ 기술 사양

* **언어 및 컴파일러:** Swift 6 (macOS 기본 내장 `swiftc`)
* **프레임워크:** macOS 시스템 내장 `CoreBluetooth` (`CBPeripheralManager`)
* **광고 장치명:** `BalansLab-Scale`
* **GATT 서비스:**
  1. **0x181D (Weight Scale Service)**: 표준 체중계 서비스
     - Characteristic `0x2A9D`: Weight Measurement (Notify / Indicate / Read)
  2. **0xFFF0 (OKOK Custom Service)**: 밸런스랩 및 OKOK 호환 체중계 서비스
     - Characteristic `0xFFF1`: OKOK Measurement (Notify / Read)

---

## 🚀 실행 방법

맥북 터미널에서 아래 명령어로 즉시 실행할 수 있습니다:

```bash
# 1. 빌드된 실행 파일 바로 실행
./tests/ble_simulator/scale_sim

# (선택) 소스코드 직접 수정 후 재컴파일 실행 시
swiftc -O tests/ble_simulator/main.swift -o tests/ble_simulator/scale_sim
./tests/ble_simulator/scale_sim
```

> [!NOTE]
> macOS에서 터미널이 블루투스 권한을 최초 요청할 경우 **[허용(Allow)]**을 눌러주세요.  
> (시스템 설정 > 개인정보 보호 및 보안 > Bluetooth 에서 터미널 권한 확인 가능)

---

## ⌨️ CLI 인터랙티브 명령어

실행 후 터미널에 아래 명령어를 입력하여 체중 전송을 제어할 수 있습니다:

| 명령어 | 기능 설명 | 예시 |
| :--- | :--- | :--- |
| **`[Enter]` (빈 줄 입력)** | 80.80kg 체중계 올라섬 시뮬레이션 (요동 ➔ 80.80kg 고정) | `[Enter]` |
| **`w <체중>`** | 지정한 체중을 수치 고정(Locked) 상태로 즉시 전송 | `w 79.5` |
| **`s <체중>`** | 지정한 목표 체중으로 올라섬 시뮬레이션 후 확정 전송 | `s 75.2` |
| **`f <1\|2\|3>`** | 패킷 포맷 변경 (1: App 호환 4B, 2: OKOK 19B, 3: SIG WSS 3B) | `f 1` |
| **`status`** | BLE 광고 상태, 구독 중인 기기(중앙 장치) 수 확인 | `status` |
| **`h`** | 도움말 및 배너 재출력 | `h` |
| **`q`** | 시뮬레이터 안전 종료 | `q` |

---

## 📱 연동 테스트 절차

1. **맥북 터미널에서 시뮬레이터 실행:**
   ```bash
   ./tests/ble_simulator/scale_sim
   ```
   `[BLE 광고 시작] 장치명: 'BalansLab-Scale'` 문구가 출력되는지 확인합니다.

2. **아이폰(또는 맥북) 브라우저에서 HealthTracker 열기:**
   - **아이폰:** 무료 `Bluefy` 브라우저에서 `https://cnekid.github.io/health_tracker/` 접속
   - **맥북 크롬:** `chrome://flags`에서 Web Bluetooth 활성화 후 배포 주소 접속

3. **체중계 연결 및 측정:**
   - 앱 화면의 **`체중계 BLE 연결`** 버튼 터치
   - 블루투스 검색 팝업창에서 **`BalansLab-Scale`** 선택 후 [페어링/연결]
   - 터미널에서 `[연결 성공] 클라이언트가 알림을 구독했습니다!` 로그 확인
   - 터미널에서 `[Enter]` 또는 `w 80.8` 입력
   - 앱 화면에서 체중 숫자가 실시간으로 반영되고, `측정 완료 (저장됨)` 상태로 변하며 Apple Health 단축어가 호출되는지 확인!
