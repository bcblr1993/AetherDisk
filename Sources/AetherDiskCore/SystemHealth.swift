import Foundation
import Darwin
import IOKit.ps

public enum PressureSeverity: String, Codable, Sendable, Equatable {
    case normal
    case elevated
    case high

    public var title: String {
        switch self {
        case .normal: "健康"
        case .elevated: "偏高"
        case .high: "承压"
        }
    }
}

public struct MemoryTelemetry: Sendable, Equatable {
    public var totalBytes: Int64
    public var usedBytes: Int64
    public var appBytes: Int64
    public var wiredBytes: Int64
    public var compressedBytes: Int64
    public var availableBytes: Int64
    public var pressure: PressureSeverity

    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(usedBytes) / Double(totalBytes)))
    }

    public init(
        totalBytes: Int64,
        usedBytes: Int64,
        appBytes: Int64,
        wiredBytes: Int64,
        compressedBytes: Int64,
        availableBytes: Int64,
        pressure: PressureSeverity
    ) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.appBytes = appBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.availableBytes = availableBytes
        self.pressure = pressure
    }
}

public struct CPUTelemetry: Sendable, Equatable {
    public var usageFraction: Double
    public var userFraction: Double
    public var systemFraction: Double
    public var loadAverage1m: Double
    public var loadAverage5m: Double
    public var coreCount: Int
    public var thermalLabel: String
    public var thermalSeverity: PressureSeverity
    public var uptimeSeconds: TimeInterval

    public init(
        usageFraction: Double,
        userFraction: Double,
        systemFraction: Double,
        loadAverage1m: Double,
        loadAverage5m: Double,
        coreCount: Int,
        thermalLabel: String,
        thermalSeverity: PressureSeverity,
        uptimeSeconds: TimeInterval
    ) {
        self.usageFraction = usageFraction
        self.userFraction = userFraction
        self.systemFraction = systemFraction
        self.loadAverage1m = loadAverage1m
        self.loadAverage5m = loadAverage5m
        self.coreCount = coreCount
        self.thermalLabel = thermalLabel
        self.thermalSeverity = thermalSeverity
        self.uptimeSeconds = uptimeSeconds
    }
}

public struct PowerTelemetry: Sendable, Equatable {
    public var hasBattery: Bool
    public var percentage: Int?
    public var isCharging: Bool
    public var isPluggedIn: Bool
    public var statusLabel: String

    public init(
        hasBattery: Bool,
        percentage: Int?,
        isCharging: Bool,
        isPluggedIn: Bool,
        statusLabel: String
    ) {
        self.hasBattery = hasBattery
        self.percentage = percentage
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.statusLabel = statusLabel
    }
}

public struct NetworkTelemetry: Sendable, Equatable {
    public var totalReceivedBytes: UInt64
    public var totalSentBytes: UInt64
    public var downloadBytesPerSec: Int64
    public var uploadBytesPerSec: Int64
    public var activeInterfaces: Int
    public var sampledAt: Date

    public init(
        totalReceivedBytes: UInt64,
        totalSentBytes: UInt64,
        downloadBytesPerSec: Int64,
        uploadBytesPerSec: Int64,
        activeInterfaces: Int,
        sampledAt: Date = Date()
    ) {
        self.totalReceivedBytes = totalReceivedBytes
        self.totalSentBytes = totalSentBytes
        self.downloadBytesPerSec = downloadBytesPerSec
        self.uploadBytesPerSec = uploadBytesPerSec
        self.activeInterfaces = activeInterfaces
        self.sampledAt = sampledAt
    }
}

public struct SystemHealthSnapshot: Sendable, Equatable {
    public var memory: MemoryTelemetry
    public var cpu: CPUTelemetry
    public var power: PowerTelemetry
    public var network: NetworkTelemetry
    public var hostModelLabel: String
    public var osVersionLabel: String
    public var sampledAt: Date

    public init(
        memory: MemoryTelemetry,
        cpu: CPUTelemetry,
        power: PowerTelemetry,
        network: NetworkTelemetry,
        hostModelLabel: String,
        osVersionLabel: String,
        sampledAt: Date = Date()
    ) {
        self.memory = memory
        self.cpu = cpu
        self.power = power
        self.network = network
        self.hostModelLabel = hostModelLabel
        self.osVersionLabel = osVersionLabel
        self.sampledAt = sampledAt
    }
}

public final class SystemHealthSampler: @unchecked Sendable {
    private struct CPUTicks {
        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0
    }

    private let lock = NSLock()
    private var previousTicks: CPUTicks?
    private var previousNetwork: NetworkTelemetry?

    public init() {}

    public func sample() -> SystemHealthSnapshot {
        let now = Date()
        let mem = Self.readMemory()
        let power = Self.readPower()
        let rawNet = Self.readRawNetworkCounters()
        let rawTicks = Self.readCPUTicks()

        let (cpu, net) = lock.withLock { () -> (CPUTelemetry, NetworkTelemetry) in
            let cpuUsage = Self.computeCPU(current: rawTicks, previous: previousTicks)
            previousTicks = rawTicks

            var dlRate: Int64 = 0
            var ulRate: Int64 = 0
            if let prev = previousNetwork {
                let dt = now.timeIntervalSince(prev.sampledAt)
                if dt >= 0.15 {
                    if rawNet.rx >= prev.totalReceivedBytes {
                        dlRate = Int64(Double(rawNet.rx - prev.totalReceivedBytes) / dt)
                    }
                    if rawNet.tx >= prev.totalSentBytes {
                        ulRate = Int64(Double(rawNet.tx - prev.totalSentBytes) / dt)
                    }
                }
            }
            let netSnap = NetworkTelemetry(
                totalReceivedBytes: rawNet.rx,
                totalSentBytes: rawNet.tx,
                downloadBytesPerSec: max(0, dlRate),
                uploadBytesPerSec: max(0, ulRate),
                activeInterfaces: rawNet.interfaces,
                sampledAt: now
            )
            previousNetwork = netSnap
            return (cpuUsage, netSnap)
        }

        return SystemHealthSnapshot(
            memory: mem,
            cpu: cpu,
            power: power,
            network: net,
            hostModelLabel: Self.readHardwareModel(),
            osVersionLabel: ProcessInfo.processInfo.operatingSystemVersionString,
            sampledAt: now
        )
    }

    private static func readMemory() -> MemoryTelemetry {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        var pageSizeValue: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSizeValue)
        let pageSize = Int64(pageSizeValue > 0 ? pageSizeValue : 16_384)
        guard kr == KERN_SUCCESS, total > 0 else {
            return MemoryTelemetry(
                totalBytes: max(1, total),
                usedBytes: 0,
                appBytes: 0,
                wiredBytes: 0,
                compressedBytes: 0,
                availableBytes: max(0, total),
                pressure: .normal
            )
        }

        let wired = Int64(stats.wire_count) * pageSize
        let compressed = Int64(stats.compressor_page_count) * pageSize
        let internalPages = Int64(stats.internal_page_count)
        let purgeablePages = Int64(stats.purgeable_count)
        let appMemory = max(0, (internalPages - purgeablePages) * pageSize)
        let activeFallback = Int64(stats.active_count) * pageSize
        let effectiveApp = appMemory > 0 ? appMemory : activeFallback
        let rawUsed = effectiveApp + wired + compressed
        let used = min(total, max(0, rawUsed))
        let available = max(0, total - used)

        let ratio = Double(used) / Double(total)
        let compressedRatio = Double(compressed) / Double(total)
        let pressure: PressureSeverity
        if ratio >= 0.88 || compressedRatio >= 0.25 {
            pressure = .high
        } else if ratio >= 0.74 || compressedRatio >= 0.14 {
            pressure = .elevated
        } else {
            pressure = .normal
        }

        return MemoryTelemetry(
            totalBytes: total,
            usedBytes: used,
            appBytes: effectiveApp,
            wiredBytes: wired,
            compressedBytes: compressed,
            availableBytes: available,
            pressure: pressure
        )
    }

    private static func readCPUTicks() -> CPUTicks? {
        var numCPUsU: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0
        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUsU,
            &cpuInfo,
            &numCPUInfo
        )
        guard kr == KERN_SUCCESS, let info = cpuInfo else { return nil }
        defer {
            let byteCount = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), byteCount)
        }

        var sum = CPUTicks()
        let stride = Int(CPU_STATE_MAX)
        for i in 0..<Int(numCPUsU) {
            let base = i * stride
            sum.user += UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            sum.system += UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            sum.idle += UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            sum.nice += UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
        }
        return sum
    }

    private static func computeCPU(current: CPUTicks?, previous: CPUTicks?) -> CPUTelemetry {
        var loads = [Double](repeating: 0.0, count: 3)
        _ = getloadavg(&loads, 3)
        let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)

        var userFrac = 0.0
        var sysFrac = 0.0
        var totalFrac = min(1.0, max(0.0, loads[0] / Double(cores)))

        if let cur = current, let prev = previous,
           cur.user >= prev.user, cur.system >= prev.system, cur.idle >= prev.idle, cur.nice >= prev.nice {
            let dUser = cur.user - prev.user + (cur.nice - prev.nice)
            let dSys = cur.system - prev.system
            let dIdle = cur.idle - prev.idle
            let dTotal = dUser + dSys + dIdle
            if dTotal > 0 {
                userFrac = Double(dUser) / Double(dTotal)
                sysFrac = Double(dSys) / Double(dTotal)
                totalFrac = min(1.0, max(0.0, Double(dUser + dSys) / Double(dTotal)))
            }
        }

        let thermalState = ProcessInfo.processInfo.thermalState
        let thermalLabel: String
        let thermalSeverity: PressureSeverity
        switch thermalState {
        case .nominal:
            thermalLabel = "散热正常"
            thermalSeverity = .normal
        case .fair:
            thermalLabel = "轻度温热"
            thermalSeverity = .normal
        case .serious:
            thermalLabel = "温度偏高"
            thermalSeverity = .elevated
        case .critical:
            thermalLabel = "高温限频"
            thermalSeverity = .high
        @unknown default:
            thermalLabel = "正常"
            thermalSeverity = .normal
        }

        return CPUTelemetry(
            usageFraction: totalFrac,
            userFraction: userFrac,
            systemFraction: sysFrac,
            loadAverage1m: max(0.0, loads[0]),
            loadAverage5m: max(0.0, loads[1]),
            coreCount: cores,
            thermalLabel: thermalLabel,
            thermalSeverity: thermalSeverity,
            uptimeSeconds: ProcessInfo.processInfo.systemUptime
        )
    }

    private static func readPower() -> PowerTelemetry {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !list.isEmpty else {
            return PowerTelemetry(
                hasBattery: false,
                percentage: nil,
                isCharging: false,
                isPluggedIn: true,
                statusLabel: "交流电源直连"
            )
        }

        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            let type = desc[kIOPSTypeKey as String] as? String ?? ""
            if type == kIOPSInternalBatteryType as String {
                let cur = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 0
                let maxCap = max(1, desc[kIOPSMaxCapacityKey as String] as? Int ?? 100)
                let pct = min(100, max(0, Int((Double(cur) / Double(maxCap) * 100.0).rounded())))
                let isCharging = (desc[kIOPSIsChargingKey as String] as? Bool) ?? false
                let state = desc[kIOPSPowerSourceStateKey as String] as? String ?? ""
                let plugged = state == (kIOPSACPowerValue as String) || isCharging
                let label = isCharging ? "正在充电 · \(pct)%" : (plugged ? "外接电源 · \(pct)%" : "电池供电 · \(pct)%")
                return PowerTelemetry(
                    hasBattery: true,
                    percentage: pct,
                    isCharging: isCharging,
                    isPluggedIn: plugged,
                    statusLabel: label
                )
            }
        }

        return PowerTelemetry(
            hasBattery: false,
            percentage: nil,
            isCharging: false,
            isPluggedIn: true,
            statusLabel: "交流电源直连"
        )
    }

    private static func readRawNetworkCounters() -> (rx: UInt64, tx: UInt64, interfaces: Int) {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else {
            return (0, 0, 0)
        }
        defer { freeifaddrs(first) }

        var totalRX: UInt64 = 0
        var totalTX: UInt64 = 0
        var activeNames = Set<String>()

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let ifa = current.pointee
            let flags = Int32(ifa.ifa_flags)
            let isUp = (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            if isUp, !isLoopback, let addr = ifa.ifa_addr, Int32(addr.pointee.sa_family) == AF_LINK, let data = ifa.ifa_data {
                let name = String(cString: ifa.ifa_name)
                if name.hasPrefix("en") || name.hasPrefix("utun") || name.hasPrefix("bridge") || name.hasPrefix("pdp_ip") {
                    let netData = data.assumingMemoryBound(to: if_data.self).pointee
                    totalRX &+= UInt64(netData.ifi_ibytes)
                    totalTX &+= UInt64(netData.ifi_obytes)
                    if name.hasPrefix("en") {
                        activeNames.insert(name)
                    }
                }
            }
            cursor = ifa.ifa_next
        }
        return (totalRX, totalTX, activeNames.count)
    }

    private static func readHardwareModel() -> String {
        var size: size_t = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else {
            return "Mac"
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else {
            return "Mac"
        }
        let str = String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return str.isEmpty ? "Mac" : str
    }
}

// MARK: - Telemetry History & Low Space Evaluation

public struct TelemetryHistorySample: Sendable, Equatable, Identifiable {
    public var id: Date { sampledAt }
    public var sampledAt: Date
    public var cpuFraction: Double
    public var memoryFraction: Double
    public var downloadBytesPerSec: Int64
    public var uploadBytesPerSec: Int64

    public init(
        sampledAt: Date = Date(),
        cpuFraction: Double,
        memoryFraction: Double,
        downloadBytesPerSec: Int64 = 0,
        uploadBytesPerSec: Int64 = 0
    ) {
        self.sampledAt = sampledAt
        self.cpuFraction = Self.clampFraction(cpuFraction)
        self.memoryFraction = Self.clampFraction(memoryFraction)
        self.downloadBytesPerSec = max(0, downloadBytesPerSec)
        self.uploadBytesPerSec = max(0, uploadBytesPerSec)
    }

    fileprivate static func clampFraction(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1.0, max(0.0, value))
    }
}

public struct TelemetryHistoryBuffer: Sendable, Equatable {
    public let capacity: Int
    public private(set) var samples: [TelemetryHistorySample]

    public init(capacity: Int = 30, samples: [TelemetryHistorySample] = []) {
        let boundedCapacity = max(1, capacity)
        self.capacity = boundedCapacity
        let sanitized = samples.map {
            TelemetryHistorySample(
                sampledAt: $0.sampledAt,
                cpuFraction: $0.cpuFraction,
                memoryFraction: $0.memoryFraction,
                downloadBytesPerSec: $0.downloadBytesPerSec,
                uploadBytesPerSec: $0.uploadBytesPerSec
            )
        }
        if sanitized.count > boundedCapacity {
            self.samples = Array(sanitized.suffix(boundedCapacity))
        } else {
            self.samples = sanitized
        }
    }

    public mutating func append(_ snapshot: SystemHealthSnapshot) {
        let sample = TelemetryHistorySample(
            sampledAt: snapshot.sampledAt,
            cpuFraction: TelemetryHistorySample.clampFraction(snapshot.cpu.usageFraction),
            memoryFraction: TelemetryHistorySample.clampFraction(snapshot.memory.usedFraction),
            downloadBytesPerSec: max(0, snapshot.network.downloadBytesPerSec),
            uploadBytesPerSec: max(0, snapshot.network.uploadBytesPerSec)
        )
        samples.append(sample)
        let limit = max(1, capacity)
        if samples.count > limit {
            samples.removeFirst(samples.count - limit)
        }
    }

    public var cpuSeries: [Double] {
        samples.map(\.cpuFraction)
    }

    public var memorySeries: [Double] {
        samples.map(\.memoryFraction)
    }

    public var peakCPU: Double {
        samples.map(\.cpuFraction).max() ?? 0
    }

    public var peakMemory: Double {
        samples.map(\.memoryFraction).max() ?? 0
    }

    public var averageCPU: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0.0) { $0 + $1.cpuFraction } / Double(samples.count)
    }

    public var averageMemory: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0.0) { $0 + $1.memoryFraction } / Double(samples.count)
    }
}

public enum LowSpaceThresholdGiB: Int, CaseIterable, Codable, Sendable, Identifiable {
    case gb10 = 10
    case gb20 = 20
    case gb50 = 50
    case gb100 = 100

    public var id: Int { rawValue }
    public var title: String { "\(rawValue) GiB" }
    public var bytes: Int64 { Int64(rawValue) * 1024 * 1024 * 1024 }
}

public struct LowSpaceAlertState: Sendable, Equatable {
    public var isTriggered: Bool
    public var freeBytes: Int64
    public var thresholdBytes: Int64
    public var deficitBytes: Int64
    public var severity: PressureSeverity
    public var headline: String
    public var detail: String

    public init(
        isTriggered: Bool,
        freeBytes: Int64,
        thresholdBytes: Int64,
        deficitBytes: Int64,
        severity: PressureSeverity,
        headline: String,
        detail: String
    ) {
        self.isTriggered = isTriggered
        self.freeBytes = freeBytes
        self.thresholdBytes = thresholdBytes
        self.deficitBytes = deficitBytes
        self.severity = severity
        self.headline = headline
        self.detail = detail
    }
}

public enum LowSpaceEvaluator {
    /// 只读计算当前卷剩余空间与用户阈值差额，绝不触发任何自动清理。
    public static func evaluate(volume: VolumeSpace, thresholdGiB: Int) -> LowSpaceAlertState {
        let clampedGiB = max(1, thresholdGiB)
        let (product, overflow) = Int64(clampedGiB).multipliedReportingOverflow(by: 1024 * 1024 * 1024)
        let thresholdBytes = overflow ? Int64.max : product
        let safeFree = max(0, volume.free)

        guard volume.total > 0 else {
            return LowSpaceAlertState(
                isTriggered: false,
                freeBytes: safeFree,
                thresholdBytes: thresholdBytes,
                deficitBytes: 0,
                severity: .normal,
                headline: "容量等待采样",
                detail: "正在读取卷容量信息，当前低空间提醒阈值设为 \(clampedGiB) GiB（仅只读监测，不会自动清理）。"
            )
        }

        if safeFree < thresholdBytes {
            let deficitBytes = thresholdBytes - safeFree
            let severity: PressureSeverity = safeFree < (thresholdBytes / 2) ? .high : .elevated
            return LowSpaceAlertState(
                isTriggered: true,
                freeBytes: safeFree,
                thresholdBytes: thresholdBytes,
                deficitBytes: deficitBytes,
                severity: severity,
                headline: "可用空间低于 \(clampedGiB) GiB 提醒阈值",
                detail: "当前卷剩余 \(DiskFormat.bytes(safeFree))，低于设定的 \(clampedGiB) GiB 阈值（差额 \(DiskFormat.bytes(deficitBytes))）。仅作只读提醒，请前往系统清理或空间透镜手动核查。"
            )
        }

        return LowSpaceAlertState(
            isTriggered: false,
            freeBytes: safeFree,
            thresholdBytes: thresholdBytes,
            deficitBytes: 0,
            severity: .normal,
            headline: "可用空间高于 \(clampedGiB) GiB 阈值",
            detail: "当前卷剩余 \(DiskFormat.bytes(safeFree))，高于设定的 \(clampedGiB) GiB 低空间提醒阈值。"
        )
    }
}

// MARK: - Smart Care & Smart Assistant Synthesis

public struct SmartCarePillar: Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var headlineValue: String
    public var badgeText: String
    public var symbol: String
    public var targetPage: String
    public var severity: PressureSeverity

    public init(
        id: String,
        title: String,
        subtitle: String,
        headlineValue: String,
        badgeText: String,
        symbol: String,
        targetPage: String,
        severity: PressureSeverity
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.headlineValue = headlineValue
        self.badgeText = badgeText
        self.symbol = symbol
        self.targetPage = targetPage
        self.severity = severity
    }
}

public struct AssistantInsight: Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var detail: String
    public var actionLabel: String
    public var targetPage: String
    public var symbol: String
    public var severity: PressureSeverity

    public init(
        id: String,
        title: String,
        detail: String,
        actionLabel: String,
        targetPage: String,
        symbol: String,
        severity: PressureSeverity
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.actionLabel = actionLabel
        self.targetPage = targetPage
        self.symbol = symbol
        self.severity = severity
    }
}

public struct SmartCareSummary: Sendable, Equatable {
    public var healthScore: Int
    public var statusTitle: String
    public var statusSubtitle: String
    public var pillars: [SmartCarePillar]
    public var insights: [AssistantInsight]

    public init(
        healthScore: Int,
        statusTitle: String,
        statusSubtitle: String,
        pillars: [SmartCarePillar],
        insights: [AssistantInsight]
    ) {
        self.healthScore = healthScore
        self.statusTitle = statusTitle
        self.statusSubtitle = statusSubtitle
        self.pillars = pillars
        self.insights = insights
    }
}

public enum SmartCareEngine {
    public static func evaluate(
        scan: ScanResult?,
        recommendations: [Recommendation],
        volume: VolumeSpace,
        health: SystemHealthSnapshot?,
        appsReport: ApplicationsReport?,
        protectionReport: ProtectionAuditReport? = nil,
        trash: TrashSummary?,
        snapshots: APFSSnapshotReport?,
        fullDiskAccessGranted: Bool,
        isExternalVolume: Bool,
        lowSpaceThresholdGiB: Int = 20
    ) -> SmartCareSummary {
        var score = 96
        var insights: [AssistantInsight] = []

        let eligibleRecs = isExternalVolume ? [] : recommendations.filter { !$0.blocked }
        let eligibleBytes = eligibleRecs.reduce(Int64(0)) { $0 + $1.node.allocated }
        let protectedRecCount = recommendations.filter(\.blocked).count

        let lowSpaceAlert = LowSpaceEvaluator.evaluate(volume: volume, thresholdGiB: lowSpaceThresholdGiB)
        let freeRatio = volume.total > 0 ? Double(volume.free) / Double(volume.total) : 0.5
        if freeRatio < 0.10 {
            score -= 22
            let thresholdNote = lowSpaceAlert.isTriggered
                ? "（已低于设定的 \(max(1, lowSpaceThresholdGiB)) GiB 阈值，差额 \(DiskFormat.bytes(lowSpaceAlert.deficitBytes))）"
                : ""
            insights.append(
                AssistantInsight(
                    id: "low-disk-space",
                    title: "磁盘剩余可用空间低于 10%",
                    detail: "当前卷剩余 \(DiskFormat.bytes(volume.free))\(thresholdNote)。建议优先通过空间透镜与系统清理核查大体积缓存或陈旧杂物。",
                    actionLabel: "打开空间透镜",
                    targetPage: "overview",
                    symbol: "externaldrive.badge.exclamationmark",
                    severity: .high
                )
            )
        } else if freeRatio < 0.20 {
            score -= 10
        }

        if lowSpaceAlert.isTriggered,
           !insights.contains(where: { $0.id == "low-disk-space" || $0.id == "low-space-threshold" }) {
            if freeRatio >= 0.20 {
                score -= (lowSpaceAlert.severity == .high ? 12 : 6)
            }
            insights.append(
                AssistantInsight(
                    id: "low-space-threshold",
                    title: lowSpaceAlert.headline,
                    detail: lowSpaceAlert.detail,
                    actionLabel: isExternalVolume ? "打开空间透镜" : "前往系统清理",
                    targetPage: isExternalVolume ? "overview" : "suggestions",
                    symbol: "externaldrive.badge.exclamationmark",
                    severity: lowSpaceAlert.severity
                )
            )
        }

        if eligibleBytes >= 512 * 1024 * 1024 {
            score -= 12
        } else if eligibleBytes >= 32 * 1024 * 1024 {
            score -= 6
        }

        if !eligibleRecs.isEmpty {
            insights.append(
                AssistantInsight(
                    id: "cleanable-caches",
                    title: "发现 \(eligibleRecs.count) 项可安全核验的缓存与日志",
                    detail: "目录占用合计 \(DiskFormat.bytes(eligibleBytes))（已自动排除 \(protectedRecCount) 项含源码、安装包或个人数据的目录）。确认后仅移入废纸篓。",
                    actionLabel: "审阅系统清理",
                    targetPage: "suggestions",
                    symbol: "sparkles",
                    severity: eligibleBytes >= 512 * 1024 * 1024 ? .elevated : .normal
                )
            )
        }

        let largeFiles = scan?.analysis?.largeFiles ?? []
        let duplicateGroups = scan?.analysis?.duplicateGroups ?? []
        let redundantBytes = duplicateGroups.reduce(Int64(0)) { $0 + $1.potentialRedundantAllocated }
        if !duplicateGroups.isEmpty {
            score -= 4
            insights.append(
                AssistantInsight(
                    id: "duplicate-clues",
                    title: "发现 \(duplicateGroups.count) 组同体积同扩展名文件线索",
                    detail: "纯元数据比对发现疑似冗余约 \(DiskFormat.bytes(redundantBytes))，未读取文件内容，支持一键快速预览核实。",
                    actionLabel: "查看我的杂物",
                    targetPage: "large",
                    symbol: "doc.on.doc.fill",
                    severity: .normal
                )
            )
        }

        if let scan, scan.unreadable > 0 {
            score -= 5
            insights.append(
                AssistantInsight(
                    id: "permission-gaps",
                    title: "\(scan.unreadable) 个受限路径未计入本次统计",
                    detail: "受 macOS 隐私保护影响，部分目录未能读取。授予完整磁盘访问权限后可获得更完整的只读透视。",
                    actionLabel: "查看权限设置",
                    targetPage: "settings",
                    symbol: "lock.trianglebadge.exclamationmark",
                    severity: .elevated
                )
            )
        } else if !fullDiskAccessGranted {
            insights.append(
                AssistantInsight(
                    id: "fda-hint",
                    title: "完整磁盘访问权限尚未开启",
                    detail: "开启后可只读统计 Safari、邮件等隐私容器的空间占用，扫描绝不读取任何文件内容。",
                    actionLabel: "前往设置",
                    targetPage: "settings",
                    symbol: "hand.raised.shield",
                    severity: .normal
                )
            )
        }

        if let mem = health?.memory, mem.pressure != .normal {
            score -= (mem.pressure == .high ? 10 : 5)
            insights.append(
                AssistantInsight(
                    id: "memory-pressure",
                    title: "系统内存负载\(mem.pressure.title)（已用 \(Int((mem.usedFraction * 100).rounded()))%）",
                    detail: "当前活跃与联动内存占用 \(DiskFormat.bytes(mem.usedBytes))，压缩内存 \(DiskFormat.bytes(mem.compressedBytes))。可前往性能监控查看实时状态。",
                    actionLabel: "查看性能监控",
                    targetPage: "performance",
                    symbol: "memorychip",
                    severity: mem.pressure
                )
            )
        }

        if let orphans = appsReport?.orphanedData, !orphans.isEmpty {
            let orphanBytes = orphans.reduce(Int64(0)) { $0 + $1.allocated }
            insights.append(
                AssistantInsight(
                    id: "orphan-app-data",
                    title: "识别到 \(orphans.count) 项疑似卸载应用残留缓存",
                    detail: "在用户缓存与状态目录中发现约 \(DiskFormat.bytes(orphanBytes)) 无匹配已安装应用的条目，可在应用管理中核对。",
                    actionLabel: "打开应用管理",
                    targetPage: "applications",
                    symbol: "app.badge.checkmark",
                    severity: .normal
                )
            )
        }

        if let snapCount = snapshots?.snapshots.count, snapCount > 0 {
            insights.append(
                AssistantInsight(
                    id: "apfs-snapshots",
                    title: "当前卷存在 \(snapCount) 个 APFS 本地快照",
                    detail: "本地时间机器快照会在空间充裕时驻留，使清理后的可用容量延迟释放；macOS 会在需要时自动回收。",
                    actionLabel: "查看空间透镜",
                    targetPage: "overview",
                    symbol: "camera.aperture",
                    severity: .normal
                )
            )
        }

        if insights.isEmpty {
            insights.append(
                AssistantInsight(
                    id: "all-healthy",
                    title: "你的 Mac 空间与运行指标状态良好",
                    detail: "所有扫描严格本机只读进行，源码、工程工作树与应用安装包均处于自动保护之下。",
                    actionLabel: "浏览空间透镜",
                    targetPage: "overview",
                    symbol: "checkmark.seal.fill",
                    severity: .normal
                )
            )
        }

        let clampedScore = min(99, max(45, score))
        let statusTitle: String
        let statusSubtitle: String
        if scan == nil {
            statusTitle = "准备就绪 · 等待一键智能体检"
            statusSubtitle = "一次只读扫描串联系统垃圾、空间气泡透镜、大文件杂物、应用残留与实时健康指标。"
        } else if clampedScore >= 88 {
            statusTitle = "Mac 空间与健康状态极佳"
            statusSubtitle = "已扫描 \(scan?.files.formatted() ?? "0") 个文件，识别可检缓存 \(DiskFormat.bytes(eligibleBytes))，核心开发与个人资产完好受保护。"
        } else if clampedScore >= 72 {
            statusTitle = "发现可整理的缓存与杂物空间"
            statusSubtitle = "建议逐项审阅 \(eligibleRecs.count) 个缓存目录与 \(largeFiles.count) 个跨目录大文件，确认后安全移入废纸篓。"
        } else {
            statusTitle = "存储或内存负载偏高，建议护理"
            statusSubtitle = "当前磁盘可用 \(DiskFormat.bytes(volume.free))，可结合空间透镜与系统清理释放冗余缓存。"
        }

        // Build CleanMyMac 5's exact 5 signature pillars: Cleanup, Protection, Performance, Applications, Space Lens
        let cleanupPillar = SmartCarePillar(
            id: "cleanup",
            title: "系统清理",
            subtitle: isExternalVolume ? "外部卷锁定只读" : "\(eligibleRecs.count) 项可检 · \(protectedRecCount) 项受保护",
            headlineValue: isExternalVolume ? "仅分析" : (scan == nil ? "待扫描" : DiskFormat.bytes(eligibleBytes)),
            badgeText: isExternalVolume ? "只读保护" : "缓存与日志",
            symbol: "sparkles",
            targetPage: "suggestions",
            severity: eligibleBytes >= 512 * 1024 * 1024 ? .elevated : .normal
        )

        let launchAgentsCount = protectionReport?.thirdPartyLaunchCount ?? 0
        let shieldCount = (protectionReport?.vaultShields.count ?? 5) + (protectionReport?.customProtectedCount ?? 0)
        let protectionPillar = SmartCarePillar(
            id: "protection",
            title: "安全保护",
            subtitle: "\(launchAgentsCount) 项第三方代理 · \(shieldCount) 重保护防线",
            headlineValue: fullDiskAccessGranted ? "防线已就绪" : "权限受限",
            badgeText: fullDiskAccessGranted ? "只读守护" : "需检查权限",
            symbol: "checkmark.shield.fill",
            targetPage: "protection",
            severity: fullDiskAccessGranted ? .normal : .elevated
        )

        let memPct = health.map { Int(($0.memory.usedFraction * 100).rounded()) } ?? 0
        let cpuPct = health.map { Int(($0.cpu.usageFraction * 100).rounded()) } ?? 0
        let trashNote = (trash?.readable == true && (trash?.allocated ?? 0) > 0)
            ? "废纸篓 \(DiskFormat.bytes(trash?.allocated ?? 0))"
            : "CPU \(cpuPct)% · 散热正常"
        let healthPillar = SmartCarePillar(
            id: "performance",
            title: "性能优化",
            subtitle: "内存已用 \(memPct)% · \(trashNote)",
            headlineValue: "可用 \(DiskFormat.bytes(volume.free))",
            badgeText: health?.memory.pressure.title ?? "实时监控",
            symbol: "bolt.heart.fill",
            targetPage: "performance",
            severity: health?.memory.pressure ?? .normal
        )

        let appCount = appsReport?.apps.count ?? 0
        let orphanCount = appsReport?.orphanedData.count ?? 0
        let appHeadline: String = {
            if let rep = appsReport, !rep.apps.isEmpty {
                return "\(rep.apps.count) 款应用"
            }
            return "只读透视"
        }()
        let appsPillar = SmartCarePillar(
            id: "apps",
            title: "应用管理",
            subtitle: orphanCount > 0 ? "含 \(orphanCount) 项疑似卸载残留" : "\(appCount) 款已装 · 本体保护",
            headlineValue: appHeadline,
            badgeText: "本体保护",
            symbol: "square.stack.3d.up.fill",
            targetPage: "applications",
            severity: orphanCount > 5 ? .elevated : .normal
        )

        let lensPillar = SmartCarePillar(
            id: "spacelens",
            title: "空间透镜",
            subtitle: scan.map { "\($0.directories.formatted()) 个目录 · \(largeFiles.count) 个大文件" } ?? "气泡星图直观透视目录层级",
            headlineValue: scan.map { DiskFormat.bytes($0.allocated) } ?? DiskFormat.bytes(volume.used),
            badgeText: "气泡透镜",
            symbol: "circle.hexagongrid.fill",
            targetPage: "overview",
            severity: (freeRatio < 0.12 || lowSpaceAlert.severity == .high)
                ? .high
                : (lowSpaceAlert.isTriggered ? .elevated : .normal)
        )

        return SmartCareSummary(
            healthScore: clampedScore,
            statusTitle: statusTitle,
            statusSubtitle: statusSubtitle,
            pillars: [cleanupPillar, protectionPillar, healthPillar, appsPillar, lensPillar],
            insights: insights
        )
    }
}
