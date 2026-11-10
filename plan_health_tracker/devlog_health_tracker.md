# 📝 Development Log: HealthTracker

> 프로젝트 단위의 주요 논의 사항, 아키텍처 의사결정, 기술적 특이점, 진행 현황 및 향후 계획을 누적 기록하는 프로젝트 전용 개발 로그입니다.  
> 본 문서는 에이전트가 매 세션마다 필수로 전체를 로드하지 않으며, 과거 맥락 확인 및 세부 지시 추적이 필요할 때 선별적으로 검토(On-Demand)합니다.

---

## 1. 프로젝트 메타데이터
* **프로젝트명:** HealthTracker (통합 온디바이스 스마트 건강 관리 앱)
* **저장 위치:** `plan_health_tracker/devlog_health_tracker.md`
* **연계 기획서:** `plan_health_tracker/plan_health_tracker.md`
* **실행 웹앱:** `plan_health_tracker/ui_health_tracker.html`
* **최초 작성일:** 2026-11-06

---

## 2. 주요 논의 및 사용자 지시 사항 (Key Discussions & Instructions)

### 2.1 제품 방향성 및 기획 원칙
* **상용 앱 파편화 및 광고 탈피:** 기존 `OKOK`(체중계)와 `혈압 기록`(혈압계) 앱의 강제 광고, 유료 구독 유도 및 데이터 파편화를 완전히 대체하는 단일 통합 앱 구축.
* **과장 표현 일체 배제:** "완벽", "영구", "올인클루시브", "오차 없이"와 같은 비현실적이거나 과장된 마케팅성 표현 일체 사용 금지.
* **기획 문서 간결화:** 기획서(`plan_health_tracker.md`) 내 서술은 설명조(~다, ~습니다)를 지양하고 간결한 개조식/명사형 종결(~함, ~임, ~구축)을 적용.
* **8대 BIA 생체분석 지표 일별 개별 저장:** 체중 외에 체지방률, 체수분, 근육량, 골격근량, 골량, 기초대사량, 내장지방, 단백질 등 8개 지표 모두를 일별로 개별 보관 및 조회할 수 있도록 스키마 확정.

### 2.2 플레이북 및 운영 규칙
* **플레이북 vs 프로젝트 로그 분리:**
  * 플레이북(`ai_playbooks/`): 모든 프로젝트에 공통 적용되는 헌법적 표준 지침.
  * 개발 로그(`devlog_<프로젝트명>.md`): 해당 프로젝트의 전용 작업 폴더(`plan_<프로젝트명>/`)에 격리 보관.
* **On-Demand 검토 원칙:** 개발 로그는 매 작업 시 의무적으로 전체를 읽어 컨텍스트를 소모하지 않고, 사용자 지시 사항의 맥락 확인이나 과거 의사결정 확인이 필요한 시점에만 선별 검토.
* **에이전트 대화 어투 일관성:** 에이전트는 사용자와 대화 시 친절하고 전문적인 존댓말(~합니다, ~입니다, ~까요?)을 일관되게 유지함 (`00_core.md`에 등록 완료).

---

## 3. 아키텍처 및 기술 의사결정 히스토리 (Architecture Decisions & History)

### 3.1 플랫폼 선정 (Web BLE Standalone App)
* **배경:** iOS 네이티브 Swift 앱 빌드 시 Apple Developer Program 연회비(12.9만원)가 발생하며, 무료 계정 사용 시 7일마다 Xcode 유선 재서명이 필요하여 유지보수 비용이 과도함.
* **결정:** iOS에서 Web Bluetooth API를 완벽 지원하는 무료 브라우저인 **`Bluefy – Web BLE Browser`** 환경을 타겟으로, 별도 백엔드 서버 없이 동작하는 **단일 파일 온디바이스 웹앱(`ui_health_tracker.html`)** 구조 채택.

### 3.2 로컬 데이터베이스 (IndexedDB)
* **구조:** 브라우저 내장 IndexedDB(`HealthTrackerDB`, v1) 활용.
  * `bodyMetrics` 저장소: `date`(YYYY-MM-DD, PK), `weight`, `bodyFat`, `muscleMass`, `water`, `boneMass`, `bmr`, `visceralFat`, `skeletalMuscle`, `protein`
  * `bpMetrics` 저장소: `date`(YYYY-MM-DD, PK), `systolic`, `diastolic`, `pulse`
* **마이그레이션 및 시드:**
  * 기존 사용자의 317일간 실측 데이터(2025.12.25 ~ 2026.11.06, 9.4kg 감량 곡선)를 기본 시드로 주입하는 엔진 구축.
  * 기존 `OKOK` 앱의 CSV 내보내기 파일을 원클릭으로 파싱하여 IndexedDB로 일괄 병합하는 CSV 업로더 연동.

### 3.3 Apple 건강(HealthKit) 연동 브릿지
* **방식:** Web 환경의 샌드박스를 우회하기 위해 iOS 단축어 URL Scheme(`shortcuts://run-shortcut?name=LogHealth&input=text&text={JSON}`)을 활용.
* **동작:** 웹앱에서 측정 데이터 저장 시 단축어를 원클릭 호출하여 Apple 건강 공식 데이터베이스로 수치 동기화.

### 3.4 하드웨어 연동 방식
* **BalansLab 스마트 체중계 (Web BLE):**
  * Web Bluetooth API(`navigator.bluetooth.requestDevice`)로 표준 체중 서비스(`0x181D`) 및 상용 칩셋 확장 서비스(`0xFFF0`, `0xFFE0`) 스캔 및 자동 페어링.
  * 체중 측정 완료(측정값 홀드/안정화) 감지 시 자동으로 데이터 파싱 및 IndexedDB 기록 트리거.
* **WithWell 혈압계 (Camera OCR):**
  * 수동 입력 피로를 줄이기 위해 HTML5 후면 카메라 뷰파인더(`video` 스트림) 위에 3열 가이드 오버레이(SYS, DIA, PULSE) 배치.
  * 온디바이스 경량 OCR 라이브러리(Tesseract.js)를 통해 LCD 7세그먼트 흑백 콘트라스트 보정 캔버스 처리 후 수치 자동 추출.
  * 카메라 촬영 외에도 앨범 사진 업로드 및 직접 숫자 수정(수동 보정) 3단계 fallback 지원.

---

## 4. 기술적 특이점 및 제약 사항 (Technical Quirks & Constraints)

* **iOS 브라우저 간 BLE 지원 차이:**
  * Apple 기본 Safari 및 Chrome iOS는 WebKit 제약으로 Web Bluetooth API를 지원하지 않음.
  * 체중계 BLE 자동 연결 기능은 반드시 **Bluefy** 브라우저 앱에서 접속해야 정상 동작함. (카메라 OCR 및 수동 입력은 일반 사파리에서도 정상 동작).
* **LCD 세그먼트 OCR 최적화:**
  * 혈압계 LCD 패널 특성상 조명 반사나 각도에 따라 오인식이 발생할 수 있으므로, 캡처 시 그레이스케일 변환 및 이진화(Binarization) 처리를 선행한 후 Tesseract 인식을 수행함.
* **단축어 사전 설치 요구:**
  * Apple 건강 동기화 기능을 최초 사용할 때 사용자의 iPhone에 단축어(`LogHealth`)가 1회 등록되어 있어야 함 (앱 내 모달 가이드 제공).

---

## 5. 현재 산출물 현황 (Deliverables Status)

1. [plan_health_tracker.md](file:///Users/moses/myfolder/Project/health_tracker/plan_health_tracker/plan_health_tracker.md): 기획 명세서 (v1.3.0, 간결체 반영 완료)
2. [index.html](file:///Users/moses/myfolder/Project/health_tracker/index.html) 및 [ui_health_tracker.html](file:///Users/moses/myfolder/Project/health_tracker/plan_health_tracker/ui_health_tracker.html): 신장 176cm 반영, 모바일 헤더 간소화, 반응형 모바일 풀스크린 최적화 완료
3. [devlog_health_tracker.md](file:///Users/moses/myfolder/Project/health_tracker/plan_health_tracker/devlog_health_tracker.md): 프로젝트 개발 로그 (본 문서)
4. **실기기 접속용 정식 배포 URL:** `https://cnekid.github.io/health_tracker/` (GitHub Pages HTTPS 활성화 완료)

---

## 6. 진행 현황 및 향후 계획 (Progress & Next Steps)

* **2026-11-10 진행 완료 (UI 대규모 개편 및 사용자 요구사항 반영):**
  * **상단 헤더 개편:** 타이틀 `HealthTracker`로 단일화, Apple Health 연동 버튼 제거, 오늘 날짜 동적 표시 유지.
  * **체중 카드 개편:** `(밸런스랩 스케일)` 및 `317일 연속` 뱃지 제거, 최근 측정일 기준(`기준일 : 11월 9일`) 표기, `(어제 대비)` -> `(직전 대비)` 증감율 표기 변경.
  * **체중 미니 추이 그래프(Sparkline):** 기존 4개 체지방/BMI 박스를 대체하여 최근 7회 체중 변화 곡선 SVG 배치, 클릭 시 체중 상세 분석 화면으로 즉시 진입하는 인터랙션 구현.
  * **체중 버튼 재구성:** `[체중 측정]`(BLE 다이얼로그) 및 `[직접 수동 입력]`(체중 전용 수동 모달) 버튼 2종 배치.
  * **혈압 카드 개편:** `혈압`으로 타이틀 간소화, `아침` 뱃지 및 하단 최근 체중 변동 타일 제거, `기준일 : 11월 9일` 표기.
  * **혈압 미니 추이 그래프(Sparkline):** 수축기(SYS) & 이완기(DIA) 2라인 SVG 미니 그래프 배치(맥박 제외), 클릭 시 혈압 상세 분석 화면으로 진입.
  * **혈압 버튼 재구성:** `[카메라 OCR 촬영]` 및 `[직접 수동 입력]`(혈압/맥박 전용 수동 모달) 버튼 2종 배치.
  * **하단 네비게이션 개편:** 기존 5개 탭에서 `[홈]`, `[상세]`, `[설정]` 3개 탭 구조로 통합 재편.
  * **[상세] 탭 신규 구축 (건강 지표 매트릭스 & 항목별 상세 3단 뷰):**
    * 최근 3회 측정 일자(`11/09`, `11/08`, `11/07`)를 열(Column)로 하고, 10대 생체 지표(체중, 체지방률, 골격근량, 골격근율, BMI, 내장지방, 체수분, 기초대사량, 혈압, 맥박)를 행(Row)으로 하는 정돈된 비교 테이블 구현.
    * 테이블의 각 행 터치 시 진입하는 **항목별 상세 화면(Metric Detail View)** 구축:
      1. 항목 설명 및 의학적 기준 범위 (정상/주의/비만 게이지 바)
      2. 기간 필터별(최근 7회, 30회, 전체) 지표 추이 상세 SVG 인터랙티브 그래프
      3. 전체 기록 수치 표 (측정일시, 측정값, 직전 대비 증감, 출처)
  * **디자인 정돈:** 과도한 원색/뱃지 색상 사용을 배제하고 애플 헬스 스타일의 절제된 화이트/슬레이트 모노톤과 의미 기반 단일 포인트 컬러 적용.
  * **배포 및 검증:** GitHub Pages 자동 배포 완료 (`https://cnekid.github.io/health_tracker/`).

* **2026-11-09 진행 완료:**
  * 사용자 신장(176cm) 기준 BMI/생체지표 공식 업데이트 완료.
  * 모바일 상단 복잡도 최소화를 위해 OKOK 수동 업로드 버튼 제거 (추후 제공되는 CSV는 사전 탑재 방식으로 처리 예정).
  * 실제 모바일 기기 접속 시 가짜 상태바 및 목업 베젤을 숨기고 네이티브 풀스크린으로 표시되도록 반응형 CSS 개선.
  * `cnekid/health_tracker` GitHub 공개 저장소 생성 및 GitHub Pages 정식 배포 완료 (`https://cnekid.github.io/health_tracker/`).

* **다음 테스트 과제:**
  1. **iPhone Bluefy 실기기 접속 테스트:**
     * App Store에서 무료 `Bluefy` 브라우저 설치 후 `https://cnekid.github.io/health_tracker/` 접속.
     * 체중계 탭에서 시뮬레이션 및 실제 BLE 페어링 동작 확인.
     * 혈압 탭에서 카메라 OCR 권한 허용 및 인식 테스트.
  2. **OKOK 실제 CSV 파일 전달 시 일괄 변환 주입.**
  3. **Apple 건강 단축어 원클릭 설치 링크 제공.**

