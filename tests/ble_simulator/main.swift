import Foundation
import CoreBluetooth
import Network

// MARK: - 상수 및 UUID 정의
let WEIGHT_SCALE_SERVICE_UUID = CBUUID(string: "181D")
let WEIGHT_MEASUREMENT_CHAR_UUID = CBUUID(string: "2A9D")

let OKOK_SERVICE_UUID = CBUUID(string: "FFF0")
let OKOK_MEASUREMENT_CHAR_UUID = CBUUID(string: "FFF1")
let OKOK_ACK_CHAR_UUID = CBUUID(string: "FFF2") // 핸드폰 -> 체중계 수신 확인(ACK) 특성

let DEFAULT_HTTP_PORT: UInt16 = 8765

// MARK: - 패킷 포맷 열거형
enum PacketFormat: String {
    case app = "app"       // 4바이트: [Flags, Status, Weight_MSB, Weight_LSB]
    case okok = "okok"     // 19바이트: OKOK v1.1 정밀 프로토콜 프레임 (BIA 생체지표 포함)
    case sig = "sig"       // 3바이트: Bluetooth SIG WSS 표준
}

// MARK: - 10대 생체 지표 모델 (실제 OKOK 캡처 데이터 구조 1:1 반영)
struct MeasurementPayload {
    var weight: Double        // 체중 (kg) - 예: 80.30
    var bmi: Double           // BMI - 예: 25.9
    var bodyFat: Double       // 지방 (%) - 예: 25.0
    var skeletalRate: Double  // 골격근 비율 (%) - 예: 38.0
    var muscleRate: Double    // 전체 근육 (%) - 예: 70.5
    var waterRate: Double     // 수분 (%) - 예: 52.9
    var visceralFat: Double   // 내장지방 기록 - 예: 14.5
    var bmr: Double           // 기초대사 (kcal/day) - 예: 1651.0
    var format: PacketFormat
    var isSimulated: Bool
    
    // 자동 계산 질량
    var fatKg: Double { (weight * bodyFat) / 100.0 }
    var skeletalKg: Double { (weight * skeletalRate) / 100.0 }
    var muscleKg: Double { (weight * muscleRate) / 100.0 }
    var waterKg: Double { (weight * waterRate) / 100.0 }
}

// MARK: - 밸런스랩 가상 장치 (BLE Peripheral 매니저)
class BalansLabVirtualDevice: NSObject, CBPeripheralManagerDelegate {
    var peripheralManager: CBPeripheralManager!
    var weightChar: CBMutableCharacteristic?
    var okokNotifyChar: CBMutableCharacteristic?
    var okokAckChar: CBMutableCharacteristic?
    
    var subscribedCentrals = Set<CBCentral>()
    var autoStreamTimer: Timer?
    var isSteppedOn = false // 체중계에 사람이 올라섰는지 여부 ([발송] 클릭 시 true, [중단] 또는 ACK 수신 시 false)
    var currentFormat: PacketFormat = .okok
    var isAdvertising = false
    var bluetoothState: CBManagerState = .unknown
    var lastPayload = MeasurementPayload(
        weight: 81.15,
        bmi: 26.2,
        bodyFat: 24.5,
        skeletalRate: 38.0,
        muscleRate: 69.9,
        waterRate: 52.3,
        visceralFat: 14.6,
        bmr: 1646.0,
        format: .okok,
        isSimulated: false
    )
    
    var recentLogs: [(time: String, msg: String, color: String)] = []
    let maxLogCount = 100
    
    override init() {
        super.init()
        self.peripheralManager = CBPeripheralManager(delegate: self, queue: DispatchQueue.main)
    }
    
    func appendLog(_ msg: String, color: String = "slate") {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timeStr = formatter.string(from: Date())
        recentLogs.append((time: timeStr, msg: msg, color: color))
        if recentLogs.count > maxLogCount {
            recentLogs.removeFirst(recentLogs.count - maxLogCount)
        }
        print("[\(timeStr)] \(msg)")
    }
    
    // MARK: - CBPeripheralManagerDelegate
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        self.bluetoothState = peripheral.state
        switch peripheral.state {
        case .poweredOn:
            appendLog("✅ [Bluetooth] 블루투스 활성화 완료. GATT 서비스를 등록합니다...", color: "emerald")
            setupServices()
        case .poweredOff:
            appendLog("⚠️ [Bluetooth] 블루투스가 꺼져 있습니다. 맥북 블루투스를 활성화해주세요.", color: "amber")
        case .unauthorized:
            appendLog("❌ [Bluetooth] 권한 필요: 시스템 설정 > Bluetooth 권한을 허용해주세요.", color: "rose")
        case .unsupported:
            appendLog("❌ [Bluetooth] 이 Mac은 BLE Peripheral 기능을 지원하지 않습니다.", color: "rose")
        case .resetting:
            appendLog("🔄 [Bluetooth] 블루투스 스택 재설정 중...", color: "slate")
        case .unknown:
            appendLog("❓ [Bluetooth] 상태 확인 중...", color: "slate")
        @unknown default:
            break
        }
    }
    
    func setupServices() {
        // 1. 표준 체중계 서비스 (0x181D)
        let wChar = CBMutableCharacteristic(
            type: WEIGHT_MEASUREMENT_CHAR_UUID,
            properties: [.notify, .indicate, .read],
            value: nil,
            permissions: [.readable]
        )
        let wService = CBMutableService(type: WEIGHT_SCALE_SERVICE_UUID, primary: true)
        wService.characteristics = [wChar]
        self.weightChar = wChar
        
        // 2. OKOK / 밸런스랩 커스텀 서비스 (0xFFF0)
        let oNotifyChar = CBMutableCharacteristic(
            type: OKOK_MEASUREMENT_CHAR_UUID,
            properties: [.notify, .indicate, .read],
            value: nil,
            permissions: [.readable]
        )
        let oAckChar = CBMutableCharacteristic(
            type: OKOK_ACK_CHAR_UUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        let oService = CBMutableService(type: OKOK_SERVICE_UUID, primary: true)
        oService.characteristics = [oNotifyChar, oAckChar]
        self.okokNotifyChar = oNotifyChar
        self.okokAckChar = oAckChar
        
        peripheralManager.add(wService)
        peripheralManager.add(oService)
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            appendLog("❌ [GATT] 서비스 등록 실패 (\(service.uuid)): \(error.localizedDescription)", color: "rose")
            return
        }
        appendLog("📌 [GATT] 서비스 등록 완료: \(service.uuid)", color: "slate")
        
        if service.uuid == OKOK_SERVICE_UUID && !isAdvertising {
            startAdvertising()
        }
    }
    
    func startAdvertising() {
        let advData: [String: Any] = [
            CBAdvertisementDataLocalNameKey: "BalansLab-Scale",
            CBAdvertisementDataServiceUUIDsKey: [WEIGHT_SCALE_SERVICE_UUID, OKOK_SERVICE_UUID]
        ]
        peripheralManager.stopAdvertising()
        peripheralManager.startAdvertising(advData)
        isAdvertising = true
        appendLog("📡 [BLE 광고 시작] 장치명: 'BalansLab-Scale' | 수신 대기 중", color: "blue")
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            appendLog("❌ [BLE 광고 실패]: \(error.localizedDescription)", color: "rose")
        }
    }
    
    func startAutoStreaming() {
        guard autoStreamTimer == nil else { return }
        // 구독 중인 Central이 있을 때만 타이머 가동 (구독 없을 시 불필요한 로그 스팸 방지)
        guard !subscribedCentrals.isEmpty else { return }
        autoStreamTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isSteppedOn, !self.subscribedCentrals.isEmpty else {
                self?.stopAutoStreaming()
                return
            }
            self.transmit(payload: self.lastPayload, isLocked: true)
        }
    }
    
    func stopAutoStreaming() {
        autoStreamTimer?.invalidate()
        autoStreamTimer = nil
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        subscribedCentrals.insert(central)
        let shortId = central.identifier.uuidString.prefix(8)
        let maxLen = central.maximumUpdateValueLength
        appendLog("📱 [연결 완료] 내 폰(\(shortId)...)이 체중계에 연결되었습니다. (체중계 올라서기 대기 중... 구독: \(subscribedCentrals.count)대, MTU: \(maxLen)B)", color: "blue")
        
        // 사용자가 가상 체중계 어드민에서 이미 [발송 (체중계 올라섬)]을 누른 상태인 경우에만 패킷 즉시 발송
        if isSteppedOn {
            let packet = buildPacket(payload: self.lastPayload, isLocked: true)
            if let mChar = characteristic as? CBMutableCharacteristic {
                let res = peripheralManager.updateValue(packet, for: mChar, onSubscribedCentrals: [central])
                appendLog("🚀 [스트리밍 발송] 결과: \(res ? "성공" : "대기열 대기") (체중 \(String(format: "%.2f", self.lastPayload.weight))kg)", color: res ? "emerald" : "amber")
            }
            startAutoStreaming()
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribedCentrals.remove(central)
        appendLog("👋 [구독 해제] 핸드폰 연결이 해제되었습니다. (남은 기기: \(subscribedCentrals.count)대)", color: "slate")
        if subscribedCentrals.isEmpty {
            isSteppedOn = false
            stopAutoStreaming()
            // 연결 해제 즉시 BLE 광고를 강제 재시작하여 다음 측정 시 핸드폰에서 언제든 검색되도록 보장
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.startAdvertising()
            }
        }
    }

    // MARK: - GATT 직접 읽기(Read) 핸들러 (핸드폰이 readValue 호출 시 즉시 패킷 반환)
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        let uuid = request.characteristic.uuid
        if uuid == OKOK_MEASUREMENT_CHAR_UUID || uuid == WEIGHT_MEASUREMENT_CHAR_UUID {
            guard isSteppedOn else {
                request.value = Data()
                peripheralManager.respond(to: request, withResult: .success)
                return
            }
            let packet = buildPacket(payload: self.lastPayload, isLocked: true)
            if request.offset > packet.count {
                peripheralManager.respond(to: request, withResult: .invalidOffset)
                return
            }
            request.value = packet.subdata(in: request.offset..<packet.count)
            peripheralManager.respond(to: request, withResult: .success)
            appendLog("📖 [직접 읽기 응답] 핸드폰으로 패킷 직접 전달 완료 (\(request.value?.count ?? 0)B, 특성: \(uuid.uuidString))", color: "emerald")
        } else {
            peripheralManager.respond(to: request, withResult: .success)
        }
    }
    
    // MARK: - 핸드폰의 수신 확인(ACK) 수신 핸들러
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for req in requests {
            if req.characteristic.uuid == OKOK_ACK_CHAR_UUID {
                let centralId = req.central.identifier.uuidString.prefix(8)
                appendLog("📱 [수신 확인] 핸드폰(\(centralId)...)에서 데이터 정상 수신 완료 신호(ACK) 도착! 송출을 종료합니다.", color: "emerald")
                peripheralManager.respond(to: req, withResult: .success)
                self.isSteppedOn = false
                stopAutoStreaming()
                // ACK 수신 후 다음 측정에 대비하여 즉시 광고를 재개
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.startAdvertising()
                }
            } else {
                peripheralManager.respond(to: req, withResult: .success)
            }
        }
    }
    
    // MARK: - 패킷 빌더 (OKOK 19바이트 및 표준 4바이트)
    func buildPacket(payload: MeasurementPayload, isLocked: Bool) -> Data {
        switch payload.format {
        case .app:
            let rawWeight = UInt16(clamping: Int(round(payload.weight * 100.0)))
            let msb = UInt8((rawWeight >> 8) & 0xFF)
            let lsb = UInt8(rawWeight & 0xFF)
            let statusByte: UInt8 = isLocked ? 0x01 : 0x00
            return Data([0x00, statusByte, msb, lsb])
            
        case .okok:
            // OKOK v1.1 정밀 프로토콜 프레임 (19바이트)
            // 0: 0xCA, 1: 0x11, 2: Length(0x0F), 3: Status(0x01: Lock, 0x00: Measuring), 4: Type(0x01)
            // 5~6: 체중(100배), 7~8: 지방(10배), 9~10: 골격근(10배), 11: 내장지방(10배), 12~13: 기초대사(정수), 14~17: 수분/근육, 18: Checksum
            let rawWeight = UInt16(clamping: Int(round(payload.weight * 100.0)))
            let rawFat = UInt16(clamping: Int(round(payload.bodyFat * 10.0)))
            let rawSkeletal = UInt16(clamping: Int(round(payload.skeletalRate * 10.0)))
            let rawVisceral = UInt8(clamping: Int(round(payload.visceralFat)))
            let rawBmr = UInt16(clamping: Int(round(payload.bmr)))
            let rawWater = UInt16(clamping: Int(round(payload.waterRate * 10.0)))
            
            var bytes: [UInt8] = [
                0xCA, 0x11, 0x0F,
                isLocked ? 0x01 : 0x00,
                0x01,
                UInt8((rawWeight >> 8) & 0xFF), UInt8(rawWeight & 0xFF),
                UInt8((rawFat >> 8) & 0xFF), UInt8(rawFat & 0xFF),
                UInt8((rawSkeletal >> 8) & 0xFF), UInt8(rawSkeletal & 0xFF),
                rawVisceral,
                UInt8((rawBmr >> 8) & 0xFF), UInt8(rawBmr & 0xFF),
                UInt8((rawWater >> 8) & 0xFF), UInt8(rawWater & 0xFF),
                0x00, 0x00
            ]
            var checksum: UInt8 = 0
            for b in bytes { checksum ^= b }
            bytes.append(checksum)
            return Data(bytes)
            
        case .sig:
            let rawUnits = UInt16(clamping: Int(round(payload.weight / 0.005)))
            let lsb = UInt8(rawUnits & 0xFF)
            let msb = UInt8((rawUnits >> 8) & 0xFF)
            return Data([0x00, lsb, msb])
        }
    }
    
    // MARK: - 데이터 전송
    @discardableResult
    func transmit(payload: MeasurementPayload, isLocked: Bool) -> String {
        self.lastPayload = payload
        let packet = buildPacket(payload: payload, isLocked: isLocked)
        let hexString = packet.map { String(format: "%02X", $0) }.joined(separator: " ")
        
        var wRes = false
        var oRes = false
        if let char = self.weightChar {
            wRes = peripheralManager.updateValue(packet, for: char, onSubscribedCentrals: nil)
        }
        if let char = self.okokNotifyChar {
            oRes = peripheralManager.updateValue(packet, for: char, onSubscribedCentrals: nil)
        }
        
        let statusStr = isLocked ? "🔒 [고정]" : "⏳ [측정중]"
        let clientCount = subscribedCentrals.count
        let color = isLocked ? "emerald" : "slate"
        appendLog("📤 \(statusStr) 체중: \(String(format: "%.2f", payload.weight))kg (지방 \(String(format: "%.1f", payload.bodyFat))%, 골격근 \(String(format: "%.1f", payload.skeletalRate))%) | 패킷: [\(hexString)] (구독: \(clientCount)대, W=\(wRes), O=\(oRes))", color: color)
        return hexString
    }
    
    // MARK: - 측정 시뮬레이션
    func runSimulation(payload: MeasurementPayload) {
        guard isSteppedOn else { return }
        appendLog("🏃 [시뮬레이션 시작] 체중계 측정 재현 (목표: \(String(format: "%.2f", payload.weight))kg)", color: "amber")
        
        var step1 = payload
        step1.weight = max(30.0, payload.weight - Double.random(in: 1.5...3.0))
        self.transmit(payload: step1, isLocked: false)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self, self.isSteppedOn else { return }
            var step2 = payload
            step2.weight = payload.weight + Double.random(in: -0.6...0.6)
            self.transmit(payload: step2, isLocked: false)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self = self, self.isSteppedOn else { return }
            var step3 = payload
            step3.weight = payload.weight + Double.random(in: -0.1...0.1)
            self.transmit(payload: step3, isLocked: false)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self, self.isSteppedOn else { return }
            self.transmit(payload: payload, isLocked: true)
            self.startAutoStreaming()
            self.appendLog("✨ [시뮬레이션 완료] 목표 체중 \(String(format: "%.2f", payload.weight))kg 확정 발송 완료. 핸드폰 ACK 대기 중...", color: "emerald")
        }
    }
}

// MARK: - 실시간 BLE 레이더 (주변 신호 탐색기) 모델 및 매니저
struct BleDeviceInfo {
    let id: String
    var name: String
    var rssi: Int
    var services: [String]
    var manufacturerHex: String
    var category: String // "scale", "apple", "samsung", "microsoft", "other"
    var isRealScale: Bool
    var isVirtualScale: Bool
    var payloadHex: String
    var scaleEvent: String // "standby", "load", "virtual", "unknown"
    var history: [String]
    var weightCandidate: Double?
    var impedanceCandidate: Int?
    var isLockedCandidate: Bool?
    var connectionStatus: String // "대기중", "자동 연결 시도 중...", "GATT 구독 중...", "실측 수신 완료"
    var realWeight: Double?
    var realBodyFat: Double?
    var realSkeletalRate: Double?
    var realVisceralFat: Int?
    var realBmr: Int?
    var realWaterRate: Double?
    var realIsLocked: Bool?
    var lastSeen: Date
    
    var isLive: Bool {
        return Date().timeIntervalSince(lastSeen) < 4.0
    }
}

class BleRadarManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var centralManager: CBCentralManager!
    var isScanning = false
    var bluetoothState: CBManagerState = .unknown
    var devices: [String: BleDeviceInfo] = [:]
    var deviceOrder: [String] = [] // 순서 래칭용 (신호가 꺼져도 아래로 밀리지 않음)
    weak var virtualDevice: BalansLabVirtualDevice?
    
    // 실제 체중계 스텔스 1:1 자동 연결용 상태 (맥북 자동 1:1 체결 기본 활성화)
    var targetScalePeripheral: CBPeripheral?
    var isConnectingScale = false
    var isConnectedScale = false
    var scaleConnectionState = "idle" // "idle", "connecting", "reading", "completed"
    var autoConnectEnabled = true
    var lastDisconnectTime = Date.distantPast
    
    func log(_ msg: String, color: String = "slate") {
        print("[Radar] \(msg)")
        virtualDevice?.appendLog(msg, color: color)
    }
    
    override init() {
        super.init()
        setbuf(stdout, nil)
        self.centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        self.bluetoothState = central.state
        // 기본값: 대기 모드 (웹 화면에서 [탐색 시작] 버튼을 누를 때만 스캔 개시)
        if central.state != .poweredOn && isScanning {
            stopScan()
        }
    }
    
    func startScan() {
        guard centralManager.state == .poweredOn else { return }
        isScanning = true
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    
    func stopScan() {
        centralManager.stopScan()
        isScanning = false
    }
    
    func clear() {
        devices.removeAll()
        deviceOrder.removeAll()
    }
    
    func deleteDevice(id: String) {
        devices.removeValue(forKey: id)
        deviceOrder.removeAll { $0 == id }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let rawId = peripheral.identifier.uuidString
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let rawName = advName ?? peripheral.name ?? ""
        
        var services: [String] = []
        if let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            services = uuids.map { $0.uuidString }
        }
        
        var serviceDataDict: [CBUUID: Data] = [:]
        if let sData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            serviceDataDict = sData
            for (uuid, data) in sData {
                services.append("SVC:\(uuid.uuidString)=\(data.map { String(format: "%02X", $0) }.joined())")
            }
        }
        
        var mfgHex = ""
        var rawMfgData: Data? = nil
        if let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            rawMfgData = mfgData
            mfgHex = mfgData.map { String(format: "%02X", $0) }.joined()
        }
        
        // 장치 유형 분류 로직
        let upperName = rawName.uppercased()
        let upperMfg = mfgHex.uppercased()
        
        // 1. 사용자 실제 체중계 (AC:12:BB:39:44:E3) 100% 불변 지문 및 전방위 FFF0 매칭
        let hasScaleSignature = upperMfg.contains("E34439BB12AC") ||
                                upperMfg.starts(with: "FFFF00154311FFF011") ||
                                upperMfg.contains("4311FFF0") ||
                                (upperMfg.starts(with: "FFFF") && upperMfg.contains("FFF0")) ||
                                services.contains(where: { $0.contains("FFF0") }) ||
                                serviceDataDict.keys.contains(where: { $0.uuidString.contains("FFF0") }) ||
                                (rawId.uppercased().contains("44E3") && upperMfg.starts(with: "FFFF"))
        let isRealScale = hasScaleSignature
        
        if hasScaleSignature {
            log("🚨 [체중계 원시 전파 포착!] ID: \(rawId.prefix(8)) | RSSI: \(RSSI) dBm | Mfg: [\(mfgHex)] | Srv: \(services)", color: "amber")
        }
        
        // 2. 맥북 가상 체중계
        let isVirtualScale = upperName.contains("BALANSLAB-SCALE") || (upperName.contains("BALANSLAB") && !isRealScale)
        
        // 실제 체중계는 맥OS 임의 UUID 변경에 관계없이 불변 고유 키로 매핑하여 중복 카드 생성 원천 차단
        let canonicalId = isRealScale ? "REAL_SCALE_AC12BB3944E3" : rawId
        
        var category = "other"
        var displayName = rawName.isEmpty ? "이름 없음 (\(rawId.prefix(8)))" : rawName
        var payloadHex = ""
        var scaleEvent = "standby"
        
        let existingDev = devices[canonicalId]
        var parsedRealWeight = existingDev?.realWeight
        var parsedRealBodyFat = existingDev?.realBodyFat
        var parsedRealSkeletalRate = existingDev?.realSkeletalRate
        var parsedRealVisceralFat = existingDev?.realVisceralFat
        var parsedRealBmr = existingDev?.realBmr
        var parsedRealWaterRate = existingDev?.realWaterRate
        var parsedRealIsLocked = existingDev?.realIsLocked
        var scaleConnStatus = existingDev?.connectionStatus ?? "💤 대기 중"
        
        if isRealScale {
            category = "scale"
            displayName = "⭐ 내 실제 체중계 (AC:12:BB:39:44:E3)"
            log("📡 [체중계 신호 감지] RSSI: \(RSSI) dBm | 광고 키: [\(advertisementData.keys.joined(separator: ", "))]", color: "cyan")
            
            if let mfgData = rawMfgData, mfgData.count >= 15 {
                let tail = mfgData.subdata(in: 15..<mfgData.count)
                payloadHex = tail.map { String(format: "%02X", $0) }.joined(separator: " ")
                
                // 패킷 변화 감지 (대기 패킷 FC 00 E3 C5 vs 발 올림 시 변화 패킷)
                if payloadHex.contains("FC 00 E3 C5") {
                    scaleEvent = "standby"
                    scaleConnStatus = "💤 대기 신호 수신 중 (0.00kg)"
                } else if !payloadHex.isEmpty {
                    scaleEvent = "load"
                    scaleConnStatus = "👣 발 올림 감지 (실측 분석 중...)"
                }
                
                // [OKOK v1.1 브로드캐스트 실시간 무중단 디코딩]
                // 1:1 연결을 맺지 않고 광고 패킷에 실시간 무게를 실어 방출하므로 스캔을 절대 끄지 않고 연속 디코딩!
                let (weight, isLocked, candidates) = decodeOkOkBroadcast(data: mfgData, serviceData: serviceDataDict)
                if let w = weight {
                    if w > 10.0 {
                        parsedRealWeight = w
                        parsedRealIsLocked = isLocked
                        scaleConnStatus = isLocked ? "✨ 실측 성공 (\(String(format: "%.2f", w))kg, 🔒확정)" : "📥 실측 중 (\(String(format: "%.2f", w))kg)"
                        
                        let lockStr = isLocked ? "🔒확정" : "⏳측정중"
                        log("🎯 [실제 체중 수신!] \(String(format: "%.2f", w))kg (\(lockStr)) | 페이로드: [\(payloadHex)] | 디코딩: [\(candidates.joined(separator: ", "))]", color: isLocked ? "emerald" : "cyan")
                        
                        // 밸런스랩 표준 BIA 체성분 연산 (176cm, 47세 기준)
                        let h = 176.0
                        let age = 47.0
                        let bmi = w / ((h / 100.0) * (h / 100.0))
                        let bmr = Int(10.0 * w + 6.25 * h - 5.0 * age + 5.0)
                        let bodyFat = max(5.0, min(50.0, 1.20 * bmi + 0.23 * age - 16.2))
                        let skeletal = max(20.0, min(55.0, (w * (1.0 - bodyFat / 100.0) * 0.54 / w) * 100.0))
                        let water = max(40.0, min(75.0, (w * (1.0 - bodyFat / 100.0) * 0.732 / w) * 100.0))
                        let visceral = Int(max(1.0, min(30.0, (bmi - 18.5) * 0.75 + ((age - 20.0) / 10.0) * 1.1)))
                        
                        parsedRealBodyFat = bodyFat
                        parsedRealSkeletalRate = skeletal
                        parsedRealVisceralFat = visceral
                        parsedRealBmr = bmr
                        parsedRealWaterRate = water
                    } else {
                        scaleConnStatus = "💤 대기 신호 수신 중 (0.00kg)"
                    }
                } else {
                    log("📡 [체중계 패킷 수신] 페이로드: [\(payloadHex)] (RSSI: \(RSSI) dBm)", color: "cyan")
                }
                
                // [스텔스 1:1 GATT 악수] 체중계가 연결 가능한 상태면 백그라운드에서 정밀 소수점 및 BIA 19바이트 프레임 직접 취득
                let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? true
                if isConnectable && !isConnectedScale && !isConnectingScale && Date().timeIntervalSince(lastDisconnectTime) > 1.5 {
                    isConnectingScale = true
                    targetScalePeripheral = peripheral
                    peripheral.delegate = self
                    log("⚡ [스텔스 1:1 악수 시도] 체중계와 GATT 연결 체결 시도 (정밀 소수점 및 BIA 프레임 취득용)...", color: "amber")
                    centralManager.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
                }
            }
        } else if isVirtualScale {
            category = "scale"
            displayName = "💻 가상 체중계 (BalansLab-Scale)"
            scaleEvent = "virtual"
        } else if upperMfg.starts(with: "0600") || upperName.contains("MICROSOFT") {
            category = "microsoft"
        } else if upperMfg.starts(with: "4C00") || upperName.contains("APPLE") || upperName.contains("MACBOOK") || upperName.contains("IPHONE") || upperName.contains("IPAD") || upperName.contains("WATCH") {
            category = "apple"
        } else if upperMfg.starts(with: "7500") || upperName.contains("SAMSUNG") || upperName.contains("TV") || upperName.contains("AIRPURIFIER") {
            category = "samsung"
        } else {
            category = "other"
        }
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let curTime = timeFormatter.string(from: Date())
        
        var history = existingDev?.history ?? []
        if isRealScale && !payloadHex.isEmpty {
            let label = (scaleEvent == "load") ? "👣 발 올림" : "💤 대기"
            let weightStr = (parsedRealWeight != nil) ? " [\(String(format: "%.2f", parsedRealWeight!))kg]" : ""
            let entry = "\(curTime) [\(label)\(weightStr)] \(payloadHex) (\(RSSI) dBm)"
            if history.first != entry {
                history.insert(entry, at: 0)
                if history.count > 10 {
                    history.removeLast()
                }
            }
        }
        
        let currentConnStatus = isRealScale ? scaleConnStatus : "대기중"
        
        let info = BleDeviceInfo(
            id: canonicalId,
            name: displayName,
            rssi: RSSI.intValue,
            services: services,
            manufacturerHex: mfgHex,
            category: category,
            isRealScale: isRealScale,
            isVirtualScale: isVirtualScale,
            payloadHex: payloadHex,
            scaleEvent: scaleEvent,
            history: history,
            weightCandidate: nil,
            impedanceCandidate: nil,
            isLockedCandidate: nil,
            connectionStatus: currentConnStatus,
            realWeight: parsedRealWeight,
            realBodyFat: parsedRealBodyFat,
            realSkeletalRate: parsedRealSkeletalRate,
            realVisceralFat: parsedRealVisceralFat,
            realBmr: parsedRealBmr,
            realWaterRate: parsedRealWaterRate,
            realIsLocked: parsedRealIsLocked,
            lastSeen: Date()
        )
        
        // 래칭(Latching): 한 번 잡힌 순서를 보존하여 신호가 꺼져도 위치가 밀리지 않음
        if devices[canonicalId] == nil {
            if category == "scale" {
                deviceOrder.insert(canonicalId, at: 0) // 체중계 후보는 최상단에 고정
            } else {
                deviceOrder.append(canonicalId)
            }
        }
        devices[canonicalId] = info
    }
    
    // MARK: - CBCentralManager 연결 델리게이트 (1:1 자동 연결)
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral.identifier == targetScalePeripheral?.identifier else { return }
        isConnectingScale = false
        isConnectedScale = true
        scaleConnectionState = "reading"
        
        log("🤝 [1:1 연결 성공!] 체중계와 GATT 악수 완료. 서비스 전수 탐색을 개시합니다...", color: "emerald")
        peripheral.discoverServices(nil)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == targetScalePeripheral?.identifier else { return }
        log("❌ [1:1 연결 실패] 사유: \(error?.localizedDescription ?? "알 수 없음"). 스캔을 재개합니다.", color: "rose")
        isConnectingScale = false
        isConnectedScale = false
        scaleConnectionState = "idle"
        targetScalePeripheral = nil
        lastDisconnectTime = Date()
        startScan()
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("👋 [연결 종료] 체중계 1:1 세션이 종료되었습니다. 탐색 스캔을 자동 재개합니다.", color: "slate")
        isConnectingScale = false
        isConnectedScale = false
        scaleConnectionState = "idle"
        targetScalePeripheral = nil
        lastDisconnectTime = Date()
        startScan()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("❌ [알림 구독 실패] 특성(\(characteristic.uuid.uuidString)): \(error.localizedDescription)", color: "rose")
        } else {
            log("✅ [알림 구독 성공] 특성(\(characteristic.uuid.uuidString)) isNotifying: \(characteristic.isNotifying)", color: "emerald")
        }
    }
    
    // MARK: - CBPeripheralDelegate (서비스 및 특성 탐색, 실측 데이터 구독)
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services, !services.isEmpty else {
            log("⚠️ [서비스 없음] 체중계에서 GATT 서비스를 찾을 수 없습니다: \(error?.localizedDescription ?? "없음")", color: "amber")
            return
        }
        let sList = services.map { $0.uuid.uuidString }.joined(separator: ", ")
        log("🔍 [GATT 서비스 발견 (\(services.count)개)] \(sList)", color: "cyan")
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristics = service.characteristics, !characteristics.isEmpty else { return }
        let cList = characteristics.map { $0.uuid.uuidString }.joined(separator: ", ")
        log("🏷️ [특성 발견] 서비스(\(service.uuid.uuidString)): \(cList)", color: "cyan")
        for char in characteristics {
            if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                log("🔔 [알림 구독] 특성(\(char.uuid.uuidString)) Notify 활성화 요청", color: "emerald")
                peripheral.setNotifyValue(true, for: char)
            }
            if char.properties.contains(.read) {
                peripheral.readValue(for: char)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value, !data.isEmpty else { return }
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        log("📦 [실측 패킷 수신] (\(data.count)B, 특성:\(characteristic.uuid.uuidString)) [\(hex)]", color: "emerald")
        parseRealScaleMeasurement(data: data)
    }
    
    // MARK: - OKOK v1.1 브로드캐스트 광고 페이로드 실시간 디코더
    func decodeOkOkBroadcast(data: Data, serviceData: [CBUUID: Data] = [:]) -> (weight: Double?, isLocked: Bool, candidates: [String]) {
        let bytes = [UInt8](data)
        var candidates: [String] = []
        var detectedWeight: Double? = nil
        var isLocked = false
        
        // 1. ServiceData 검사 (0x181D 또는 0xFFF0)
        for (uuid, sData) in serviceData {
            let sBytes = [UInt8](sData)
            if (uuid.uuidString == "181D" || uuid.uuidString.contains("181D")) && sBytes.count >= 3 {
                let rawW = (UInt16(sBytes[2]) << 8) | UInt16(sBytes[1])
                let w = Double(rawW) * 0.005 // SIG WSS 표준 (0.005kg 해상도)
                if w >= 25.0 && w <= 220.0 {
                    candidates.append("WSS:\(String(format: "%.2f", w))kg")
                    detectedWeight = w
                    isLocked = true
                }
            } else if (uuid.uuidString == "FFF0" || uuid.uuidString.contains("FFF0")) && sBytes.count >= 7 {
                let rawW = (UInt16(sBytes[5]) << 8) | UInt16(sBytes[6])
                let w = (rawW > 2500) ? Double(rawW) / 100.0 : Double(rawW) / 10.0
                if w >= 25.0 && w <= 220.0 {
                    candidates.append("FFF0_SVC:\(String(format: "%.2f", w))kg")
                    detectedWeight = w
                    isLocked = (sBytes[3] == 0x01)
                }
            }
        }
        
        // 2. 임베디드 또는 독립형 CA 11 ... 프레임 검사
        if let caIdx = bytes.firstIndex(of: 0xCA), caIdx + 6 < bytes.count, bytes[caIdx + 1] == 0x11 {
            let locked = (bytes[caIdx + 3] == 0x01)
            let rawW = (UInt16(bytes[caIdx + 5]) << 8) | UInt16(bytes[caIdx + 6])
            let w = (rawW > 2500) ? Double(rawW) / 100.0 : Double(rawW) / 10.0
            if w >= 25.0 && w <= 220.0 {
                candidates.append("CA11:\(String(format: "%.2f", w))kg")
                detectedWeight = w
                isLocked = locked
            }
        }
        
        // 3. Chipsea FFFF 0015 ... 패킷 (25바이트 규격: 끝자리 4바이트 [상태, BCD무게, 체크섬, C5])
        if bytes.count >= 24 {
            let b21 = bytes[21]
            let b22 = bytes[22]
            let b24 = bytes[24]
            
            // 상태 검사 (FC = 대기, FF = 실측 확정)
            if b21 == 0xFC && b22 == 0x00 {
                candidates.append("대기(0.00kg)")
                detectedWeight = 0.00
                isLocked = false
            } else if b21 == 0xFF && b24 == 0xC5 {
                // b22 BCD 니블 역순 디코딩: 상위 3, 하위 8 -> 83kg
                let highNibble = Int(b22 >> 4)
                let lowNibble = Int(b22 & 0x0F)
                let bcdInt = lowNibble * 10 + highNibble
                
                // Chipsea BCD 브로드캐스트 정수 무게 (소수점은 GATT 1:1 연결을 통해 실측 획득)
                let finalW = Double(bcdInt)
                candidates.append("Chipsea-BCD: \(String(format: "%.1f", finalW))kg (0x\(String(format: "%02X", b22)) -> \(bcdInt)kg)")
                detectedWeight = finalW
                isLocked = true
            }
        }
        
        return (detectedWeight, isLocked, candidates)
    }
    
    // MARK: - 실제 체중계 19바이트 BIA 완성형 프레임 디코더
    func parseRealScaleMeasurement(data: Data) {
        let bytes = [UInt8](data)
        var weight: Double = 0.0
        var bodyFat: Double = 0.0
        var skeletal: Double = 0.0
        var visceral: Int = 0
        var bmr: Int = 0
        var water: Double = 0.0
        var isLocked = false
        
        // 1. OKOK v1.1 19바이트 프레임 (0xCA 0x11 0x0F ...)
        if bytes.count >= 19 && bytes[0] == 0xCA {
            isLocked = (bytes[3] == 0x01)
            let rawWeight = (UInt16(bytes[5]) << 8) | UInt16(bytes[6])
            // 칩셋 펌웨어 버전에 따라 1소수점(/10) 또는 2소수점(/100) 자동 스케일링
            weight = (rawWeight > 2500) ? Double(rawWeight) / 100.0 : Double(rawWeight) / 10.0
            
            let rawImpedance = (UInt16(bytes[7]) << 8) | UInt16(bytes[8])
            // 밸런스랩 표준: 7~8번 바이트가 BIA 임피던스 저항값(150~1500 Ω)인 경우
            if rawImpedance > 150 && rawImpedance < 1500 {
                let h = 176.0 // 신장 cm
                let age = 47.0
                let h2_r = (h * h) / Double(rawImpedance)
                var ffm = 0.485 * h2_r + 0.338 * weight + 5.32
                ffm = max(weight * 0.45, min(weight * 0.92, ffm))
                let fatMass = max(1.0, weight - ffm)
                bodyFat = (fatMass / weight) * 100.0
                skeletal = (ffm * 0.54 / weight) * 100.0
                water = (ffm * 0.732 / weight) * 100.0
                let bmi = weight / ((h / 100.0) * (h / 100.0))
                visceral = Int(max(1.0, min(30.0, (bmi - 18.5) * 0.75 + ((age - 20.0) / 10.0) * 1.1)))
                bmr = Int(10.0 * weight + 6.25 * h - 5.0 * age + 5.0)
            } else {
                let rawFat = (UInt16(bytes[7]) << 8) | UInt16(bytes[8])
                if rawFat > 0 && rawFat < 600 { bodyFat = Double(rawFat) / 10.0 }
                let rawSkeletal = (UInt16(bytes[9]) << 8) | UInt16(bytes[10])
                if rawSkeletal > 0 && rawSkeletal < 600 { skeletal = Double(rawSkeletal) / 10.0 }
                visceral = Int(bytes[11])
                let rawBmr = (UInt16(bytes[12]) << 8) | UInt16(bytes[13])
                bmr = Int(rawBmr)
                let rawWater = (UInt16(bytes[14]) << 8) | UInt16(bytes[15])
                water = Double(rawWater) / 10.0
            }
        } else if bytes.count >= 4 {
            // 2. 표준 BLE Weight Measurement 프레임
            isLocked = (bytes[1] == 0x01)
            let rawWeight = (UInt16(bytes[2]) << 8) | UInt16(bytes[3])
            weight = (rawWeight > 2500) ? Double(rawWeight) / 100.0 : Double(rawWeight) / 10.0
        }
        
        guard weight > 5.0 && weight < 250.0 else { return }
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let curTime = timeFormatter.string(from: Date())
        
        let lockStr = isLocked ? "🔒최종확정" : "⏳측정중"
        log("✨ [체중 실측 성공!] 체중 \(String(format: "%.2f", weight))kg (\(lockStr), 체지방:\(String(format: "%.1f", bodyFat))%, 골격근:\(String(format: "%.1f", skeletal))%)", color: isLocked ? "emerald" : "cyan")
        
        let canonicalId = "REAL_SCALE_AC12BB3944E3"
        if var dev = devices[canonicalId] {
            dev.realWeight = weight
            dev.realBodyFat = bodyFat > 0 ? bodyFat : dev.realBodyFat
            dev.realSkeletalRate = skeletal > 0 ? skeletal : dev.realSkeletalRate
            dev.realVisceralFat = visceral > 0 ? visceral : dev.realVisceralFat
            dev.realBmr = bmr > 0 ? bmr : dev.realBmr
            dev.realWaterRate = water > 0 ? water : dev.realWaterRate
            dev.realIsLocked = isLocked
            dev.lastSeen = Date()
            dev.connectionStatus = isLocked ? "✨ 실측 수신 완료 (해제됨)" : "📥 실시간 측정 중: \(String(format: "%.2f", weight)) kg"
            
            let logEntry = "\(curTime) [✨실측수신] 체중 \(String(format: "%.2f", weight))kg (\(lockStr))"
            dev.history.insert(logEntry, at: 0)
            if dev.history.count > 5 { dev.history.removeLast() }
            devices[canonicalId] = dev
        }
        
        // 최종 고정(Lock) 데이터를 받으면 체중계와의 연결을 즉시 해제하고 스캔을 재개하여 스마트폰 연결 허용
        if isLocked {
            scaleConnectionState = "completed"
            if let p = targetScalePeripheral {
                centralManager.cancelPeripheralConnection(p)
            }
            targetScalePeripheral = nil
            isConnectingScale = false
            isConnectedScale = false
            lastDisconnectTime = Date()
            startScan()
        }
    }
    
    func getRadarSnapshot() -> [[String: Any]] {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        
        return deviceOrder.compactMap { id -> [String: Any]? in
            guard let dev = devices[id] else { return nil }
            var dict: [String: Any] = [
                "id": dev.id,
                "name": dev.name,
                "rssi": dev.rssi,
                "services": dev.services,
                "manufacturerHex": dev.manufacturerHex,
                "category": dev.category,
                "isRealScale": dev.isRealScale,
                "isVirtualScale": dev.isVirtualScale,
                "payloadHex": dev.payloadHex,
                "scaleEvent": dev.scaleEvent,
                "history": dev.history,
                "isLive": dev.isLive,
                "connectionStatus": dev.connectionStatus,
                "lastSeen": formatter.string(from: dev.lastSeen)
            ]
            if let w = dev.realWeight ?? dev.weightCandidate { dict["weight"] = w }
            if let fat = dev.realBodyFat { dict["bodyFat"] = fat }
            if let skel = dev.realSkeletalRate { dict["skeletalRate"] = skel }
            if let visc = dev.realVisceralFat { dict["visceralFat"] = visc }
            if let bmr = dev.realBmr { dict["bmr"] = bmr }
            if let water = dev.realWaterRate { dict["waterRate"] = water }
            if let lk = dev.realIsLocked ?? dev.isLockedCandidate { dict["isLocked"] = lk }
            return dict
        }
    }
}

// MARK: - 초경량 로컬 HTTP 서버 (NWListener 기반)
class LocalHttpServer {
    let port: NWEndpoint.Port
    var listener: NWListener?
    let device: BalansLabVirtualDevice
    let radar: BleRadarManager
    
    init(port: UInt16 = DEFAULT_HTTP_PORT, device: BalansLabVirtualDevice, radar: BleRadarManager) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.device = device
        self.radar = radar
    }
    
    func resolveHtmlPath() -> String {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        let execPath = CommandLine.arguments[0]
        let execDir = (execPath as NSString).deletingLastPathComponent
        
        let candidates = [
            (execDir as NSString).appendingPathComponent("controller.html"),
            (cwd as NSString).appendingPathComponent("controller.html"),
            (cwd as NSString).appendingPathComponent("tests/ble_simulator/controller.html"),
            (execDir as NSString).appendingPathComponent("Virtual_Scale_Controller.html"),
            (cwd as NSString).appendingPathComponent("Virtual_Scale_Controller.html"),
            (cwd as NSString).appendingPathComponent("plan_health_tracker/ui_balanslab_virtual_device.html")
        ]
        for path in candidates {
            if fm.fileExists(atPath: path) {
                return path
            }
        }
        return (cwd as NSString).appendingPathComponent("tests/ble_simulator/controller.html")
    }
    
    func start() {
        do {
            self.listener = try NWListener(using: .tcp, on: self.port)
            self.listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            self.listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("🌐 [웹 어드민 서버] http://localhost:\(self.port.rawValue) 에서 접속 가능합니다.")
                case .failed(let err):
                    print("❌ [웹 서버 에러]: \(err)")
                default:
                    break
                }
            }
            self.listener?.start(queue: .main)
        } catch {
            print("❌ [웹 서버 시작 실패]: \(error)")
        }
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil,
                  let requestStr = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            
            let response = self.processHttpRequest(requestStr)
            connection.send(content: response, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        }
    }
    
    private func processHttpRequest(_ req: String) -> Data {
        let lines = req.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return buildResponse(status: 400, body: "Bad Request") }
        let tokens = firstLine.split(separator: " ")
        guard tokens.count >= 2 else { return buildResponse(status: 400, body: "Bad Request") }
        
        let method = String(tokens[0])
        let path = String(tokens[1])
        
        if method == "OPTIONS" {
            return buildResponse(status: 204, body: "", contentType: "text/plain")
        }
        
        // 1. GET /api/status
        if method == "GET" && path.starts(with: "/api/status") {
            let statusJson: [String: Any] = [
                "bluetoothState": "\(device.bluetoothState.rawValue)",
                "isAdvertising": device.isAdvertising,
                "subscribedCount": device.subscribedCentrals.count,
                "isSteppedOn": device.isSteppedOn,
                "logs": device.recentLogs.map { ["time": $0.time, "msg": $0.msg, "color": $0.color] }
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: statusJson),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                return buildResponse(status: 200, body: jsonStr, contentType: "application/json")
            }
        }
        
        // 2. POST /api/send (체중계 올라섬 및 측정 발송)
        if method == "POST" && path.starts(with: "/api/send") {
            if let bodyRange = req.range(of: "\r\n\r\n") {
                let bodyStr = String(req[bodyRange.upperBound...])
                if let bodyData = bodyStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                    
                    let weight = (json["weight"] as? Double) ?? 80.30
                    let bmi = (json["bmi"] as? Double) ?? 25.9
                    let bodyFat = (json["bodyFat"] as? Double) ?? 25.0
                    let skeletal = (json["skeletalRate"] as? Double) ?? 38.0
                    let muscle = (json["muscleRate"] as? Double) ?? 70.5
                    let water = (json["waterRate"] as? Double) ?? 52.9
                    let visceral = (json["visceralFat"] as? Double) ?? 14.5
                    let bmr = (json["bmr"] as? Double) ?? 1651.0
                    let fmtStr = (json["format"] as? String) ?? "okok"
                    let isSimulated = (json["isSimulated"] as? Bool) ?? false
                    
                    let payload = MeasurementPayload(
                        weight: weight,
                        bmi: bmi,
                        bodyFat: bodyFat,
                        skeletalRate: skeletal,
                        muscleRate: muscle,
                        waterRate: water,
                        visceralFat: visceral,
                        bmr: bmr,
                        format: PacketFormat(rawValue: fmtStr) ?? .okok,
                        isSimulated: isSimulated
                    )
                    
                    device.isSteppedOn = true
                    // 발송 시 블루투스 광고를 확실히 갱신하여 핸드폰 검색 보장
                    device.startAdvertising()
                    
                    if isSimulated {
                        device.runSimulation(payload: payload)
                    } else {
                        device.transmit(payload: payload, isLocked: true)
                        device.startAutoStreaming()
                    }
                    
                    let res: [String: Any] = ["success": true, "message": "발송 명령이 접수되었습니다."]
                    let resData = (try? JSONSerialization.data(withJSONObject: res)) ?? Data()
                    return buildResponse(status: 200, body: String(data: resData, encoding: .utf8) ?? "{}", contentType: "application/json")
                }
            }
            return buildResponse(status: 400, body: "{\"error\":\"Invalid JSON\"}", contentType: "application/json")
        }

        // 3. POST /api/stop (체중계 내려옴 및 송출 중단)
        if method == "POST" && path.starts(with: "/api/stop") {
            device.isSteppedOn = false
            device.stopAutoStreaming()
            device.appendLog("⏹️ [체중계 내려옴] 사용자가 체중계에서 내려왔습니다. (데이터 송출 중단)", color: "slate")
            let res: [String: Any] = ["success": true, "message": "송출이 중단되었습니다."]
            let resData = (try? JSONSerialization.data(withJSONObject: res)) ?? Data()
            return buildResponse(status: 200, body: String(data: resData, encoding: .utf8) ?? "{}", contentType: "application/json")
        }
        
        // 4. POST /api/radar/start (사용자 요청 시에만 스캔 시작)
        if method == "POST" && path.starts(with: "/api/radar/start") {
            radar.startScan()
            let res: [String: Any] = ["success": true, "isScanning": radar.isScanning]
            let resData = (try? JSONSerialization.data(withJSONObject: res)) ?? Data()
            return buildResponse(status: 200, body: String(data: resData, encoding: .utf8) ?? "{}", contentType: "application/json")
        }
        
        // 5. POST /api/radar/stop (스캔 즉시 중단 - 맥 리소스 낭비 방지)
        if method == "POST" && path.starts(with: "/api/radar/stop") {
            radar.stopScan()
            let res: [String: Any] = ["success": true, "isScanning": radar.isScanning]
            let resData = (try? JSONSerialization.data(withJSONObject: res)) ?? Data()
            return buildResponse(status: 200, body: String(data: resData, encoding: .utf8) ?? "{}", contentType: "application/json")
        }
        
        // 6. GET /api/radar (현재 감지된 BLE 장치 래칭 스냅샷 조회)
        if method == "GET" && path.starts(with: "/api/radar") {
            let list = radar.getRadarSnapshot()
            let res: [String: Any] = [
                "isScanning": radar.isScanning,
                "count": list.count,
                "devices": list
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: res),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                return buildResponse(status: 200, body: jsonStr, contentType: "application/json")
            }
        }
        
        // 7. POST /api/radar/clear (감지 목록 전체 비우기)
        if method == "POST" && path.starts(with: "/api/radar/clear") {
            radar.clear()
            let res: [String: Any] = ["success": true]
            let resData = (try? JSONSerialization.data(withJSONObject: res)) ?? Data()
            return buildResponse(status: 200, body: String(data: resData, encoding: .utf8) ?? "{}", contentType: "application/json")
        }
        
        // 8. POST /api/radar/delete (단일 기기 목록에서 삭제)
        if method == "POST" && path.starts(with: "/api/radar/delete") {
            if let bodyRange = req.range(of: "\r\n\r\n") {
                let bodyStr = String(req[bodyRange.upperBound...])
                if let bodyData = bodyStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                   let id = json["id"] as? String {
                    radar.deleteDevice(id: id)
                }
            }
            let res: [String: Any] = ["success": true]
            let resData = (try? JSONSerialization.data(withJSONObject: res)) ?? Data()
            return buildResponse(status: 200, body: String(data: resData, encoding: .utf8) ?? "{}", contentType: "application/json")
        }
        
        // 9. GET / (웹 어드민 화면 서빙)
        if method == "GET" && (path == "/" || path == "/index.html" || path == "/controller.html") {
            let activePath = resolveHtmlPath()
            if let htmlContent = try? String(contentsOfFile: activePath, encoding: .utf8) {
                return buildResponse(status: 200, body: htmlContent, contentType: "text/html; charset=utf-8")
            } else {
                return buildResponse(status: 200, body: "<h1>BalansLab Virtual Device</h1><p>HTML 파일 경로를 확인해주세요: \(activePath)</p>", contentType: "text/html; charset=utf-8")
            }
        }
        
        return buildResponse(status: 404, body: "Not Found")
    }
    
    private func buildResponse(status: Int, body: String, contentType: String = "text/plain") -> Data {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 204: statusText = "No Content"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        default: statusText = "OK"
        }
        
        let bodyData = body.data(using: .utf8) ?? Data()
        var header = "HTTP/1.1 \(status) \(statusText)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(bodyData.count)\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
        header += "Access-Control-Allow-Headers: Content-Type\r\n"
        header += "Connection: close\r\n\r\n"
        
        var response = header.data(using: .utf8)!
        response.append(bodyData)
        return response
    }
}

// MARK: - 메인 실행부
let device = BalansLabVirtualDevice()
let radar = BleRadarManager()
radar.virtualDevice = device
let server = LocalHttpServer(port: DEFAULT_HTTP_PORT, device: device, radar: radar)
server.start()

print("""
================================================================
   🏥 밸런스랩 가상 장치 엔진 (BalansLab Virtual Device Engine)
================================================================
* 웹 어드민 접속 주소: http://localhost:\(DEFAULT_HTTP_PORT)
* BLE 브로드캐스트 이름: 'BalansLab-Scale'
* 서비스 UUID: 0x181D (표준), 0xFFF0 (OKOK 커스텀 10대 생체지표)
* 핸드폰 수신 확인(ACK) 특성: 0xFFF2 (Write)
----------------------------------------------------------------
웹 브라우저에서 위 주소에 접속하여 [발송] 버튼을 누르면
맥북 블루투스를 통해 실시간 체중계 신호가 방출됩니다.
(종료하려면 Ctrl + C 를 누르세요)
================================================================
""")

RunLoop.main.run()
