# 🏥 HealthTracker

스마트 체중계와 혈압계의 측정 데이터를 손쉽게 수집하고, 아이폰 건강앱(Apple HealthKit)과 동기화하여 종합 건강 지표를 누적 관리하는 온디바이스 스마트 건강 관리 애플리케이션 프로젝트입니다.

---

## 📂 프로젝트 구조

```text
health_tracker/
├── plan_health_tracker/               # 기획, UI 화면 및 개발 로그 전용 워크스페이스
│   ├── plan_health_tracker.md         # 메인 기획안 (단일 원본)
│   ├── ui_health_tracker.html         # 메인 앱 화면 구성안 (인터랙티브 웹앱)
│   ├── ui_balanslab_virtual_device.html # 밸런스랩 가상 장치 테스트 어드민
│   └── devlog_health_tracker.md       # 프로젝트 개발 로그
├── tests/                             # 단위 및 통합 테스트 / 시뮬레이터
│   └── ble_simulator/                 # macOS Swift 기반 가상 체중계 BLE 엔진
├── 샘플 사진/                          # 실물 측정기기 LCD 및 화면 참조 사진
├── src/                               # 추후 본개발 소스코드
└── README.md
```

## 🚀 주요 기능
1. **스마트 체중계 BLE 연동**: 체중, 체지방률, 골격근율 등 8대 BIA 지표 자동 수신 및 HealthKit 반영
2. **혈압계 카메라 OCR & 간편 입력**: 혈압계 3단 LCD 디스플레이 촬영 자동 인식 + 아침/점심/저녁 기록
3. **종합 건강 관리 대시보드**: 최근 측정치 스파크라인, 10대 생체 지표 매트릭스 및 상세 분석 뷰
4. **Apple HealthKit 완벽 연동**: 단축어(Shortcuts) 브릿지를 통한 온디바이스 100% 프라이버시 동기화
5. **밸런스랩 가상 장치 테스트 어드민**: 맥북을 BLE 체중계로 구동하여 데이터 생성/수정 및 송수신 검증

---
*자세한 기획 내용은 [plan_health_tracker/plan_health_tracker.md](file:///Users/moses/myfolder/Project/health_tracker/plan_health_tracker/plan_health_tracker.md) 문서를 참고하세요.*
