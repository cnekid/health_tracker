# 🏥 HealthTracker

스마트 체중계와 혈압계의 측정 데이터를 손쉽게 수집하고, 아이폰 건강앱(Apple HealthKit)과 동기화하여 종합 건강 지표를 누적 관리하는 iOS 애플리케이션 프로젝트입니다.

---

## 📂 프로젝트 구조
```text
health_tracker/
├── docs/                      # 프로젝트 기획, 아키텍처 및 상세 명세
│   └── 01_plan_health_tracker.md # 메인 기획안
├── src/                       # 애플리케이션 소스코드
├── tests/                     # 단위 및 통합 테스트 코드
└── README.md
```

## 🚀 주요 기능
1. **스마트 체중계 BLE 연동**: 체중, 체지방률 등 자동 수신 및 HealthKit 반영
2. **혈압계 카메라 OCR & 간편 입력**: 혈압계 디스플레이 촬영 인식 + 수축기/이완기/맥박 기록
3. **종합 건강 관리 대시보드**: 누적 추이 차트, 상태 판정 뱃지, 진료용 PDF 리포트
4. **Apple HealthKit 완벽 연동**: 온디바이스 프라이버시 중심 동기화

---
*자세한 기획 내용은 [docs/01_plan_health_tracker.md](file:///Users/moses/myfolder/Project/health_tracker/docs/01_plan_health_tracker.md) 문서를 참고하세요.*

