# ⚖️ 가상 체중계 BLE 시뮬레이터 (MacBook BLE Peripheral & Web Controller)

HealthTracker 애플리케이션의 스마트 체중계 연동 기능을 **물리 하드웨어 없이도 맥북에서 완벽하게 검증**할 수 있도록 지원하는 macOS 전용 가상 BLE 장치(Peripheral) 및 웹 조종 패널 패키지입니다.

---

## 🛠️ 기술 구성

* **엔진 소스코드:** [`main.swift`](file:///Users/moses/myfolder/Project/health_tracker/tests/ble_simulator/main.swift) (Apple `CoreBluetooth` + `Network` 프레임워크 기반, 외부 라이브러리 의존성 0)
* **실행 바이너리:** [`scale_sim`](file:///Users/moses/myfolder/Project/health_tracker/tests/ble_simulator/scale_sim) (macOS arm64 네이티브 컴파일 실행 파일)
* **웹 조종 패널:** [`controller.html`](file:///Users/moses/myfolder/Project/health_tracker/tests/ble_simulator/controller.html) (12대 생체 지표 슬라이더/인풋 및 주변 BLE 신호 탐색 레이더 탑재)
* **지원 프로토콜:**
  * 표준 블루투스 SIG 체중계 서비스 (`0x181D` / Characteristic `0x2A9D`)
  * OKOK / 밸런스랩 19바이트 BIA 체성분 풀 프레임 서비스 (`0xFFF0` / Characteristic `0xFFF1`)
  * 스마트폰 앱 -> 체중계 수신 확인(ACK) 핸드셰이크 (`0xFFF0` / Characteristic `0xFFF2`)

---

## 🚀 실행 방법

### 1. 가상 체중계 엔진 구동

맥북 터미널에서 아래 명령어로 즉시 실행할 수 있습니다:

```bash
# 1) 폴더 이동 후 실행
cd tests/ble_simulator
./scale_sim

# 또는 프로젝트 루트에서 바로 실행
./tests/ble_simulator/scale_sim
```

> [!NOTE]
> macOS에서 터미널이 블루투스 권한을 요청할 경우 **[허용(Allow)]**을 선택해 주세요.  
> (정상 실행 시 터미널에 `[BLE 광고 시작] 장치명: 'BalansLab-Scale'` 및 `🌐 [웹 어드민 서버] http://localhost:8765`가 출력됩니다.)

*(선택) 소스코드를 직접 수정 후 재컴파일할 때:*
```bash
swiftc -O tests/ble_simulator/main.swift -o tests/ble_simulator/scale_sim
```

---

### 2. 웹 조종 패널 접속 및 제어

1. 맥북 브라우저에서 **`http://localhost:8765`** 접속
2. 체중(예: 80.30kg), 체지방률, 골격근율, 수분율 등 원하는 측정치 조정 (또는 `[랜덤 생성]` / `[기본값 초기화]` 클릭)
3. **`[발송 (체중계 올라섬)]`** 버튼 클릭 시 맥북 블루투스를 통해 실시간 체중계 패킷이 송출됩니다.
4. 하단의 **`[주변 BLE 신호 탐색기 (레이더)]`**를 통해 실제 물리 체중계 등 주변 블루투스 신호를 실시간 모니터링할 수 있습니다.

---

## 📱 연동 테스트 절차

1. **맥북에서 시뮬레이터 실행 및 발송:**
   * `./tests/ble_simulator/scale_sim` 실행 후 브라우저(`http://localhost:8765`)에서 `[발송 (체중계 올라섬)]` 클릭
2. **아이폰(또는 PC) 브라우저에서 HealthTracker 열기:**
   * **아이폰:** 무료 `Bluefy` 브라우저에서 [https://cnekid.github.io/health_tracker/](https://cnekid.github.io/health_tracker/) 접속
   * **맥북/PC 크롬:** 로컬 `index.html` 또는 배포 주소 접속
3. **체중계 연결 및 측정:**
   * 앱 화면의 **`[체중 측정]`** 버튼 터치
   * 블루투스 검색 창에서 **`BalansLab-Scale`** 선택 후 연결
   * 가상 체중계의 체중 및 12대 BIA 체성분 데이터가 앱에 실시간 파싱되어 저장되고, 단축어를 통한 HealthKit 동기화가 진행됩니다.
   * 앱이 수신 완료 신호(ACK)를 보내면 가상 체중계가 이를 감지하여 조종 패널에 `수신 완료` 알림이 표시됩니다.
