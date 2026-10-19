import Foundation
import Observation

struct ReadingWorkMeta: Codable, Hashable, Sendable {
    var title: String
    var authors: [String] = []
    /// Fandom、配對、角色與其他標籤，用於依標籤統計
    var tags: [String] = []
}

/// 單一裝置的閱讀時長紀錄。
struct DeviceReadingLog: Codable, Equatable, Sendable {
    /// 日期（yyyy-MM-dd）→ 作品 ID → 秒數
    var days: [String: [String: Double]] = [:]
    var modifiedAt = Date.distantPast
}

/// 閱讀時長紀錄。每台裝置各自累計，同步合併時每台裝置取較新的一份再相加，不會重複計算。
struct ReadingLog: Codable, Equatable, Sendable {
    var devices: [String: DeviceReadingLog] = [:]
    var works: [String: ReadingWorkMeta] = [:]

    func merged(with other: ReadingLog) -> ReadingLog {
        var result = self
        for (device, log) in other.devices where log.modifiedAt > (result.devices[device]?.modifiedAt ?? .distantPast) {
            result.devices[device] = log
        }
        result.works.merge(other.works) { mine, _ in mine }
        return result
    }
}

enum ReadingStatsPeriod: String, CaseIterable, Identifiable {
    case today, week, month, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: String(localized: "今天")
        case .week: String(localized: "7 天")
        case .month: String(localized: "30 天")
        case .all: String(localized: "全部")
        }
    }
    var days: Int? {
        switch self {
        case .today: 1
        case .week: 7
        case .month: 30
        case .all: nil
        }
    }
}

struct ReadingStats {
    var total: Double = 0
    var byWork: [(id: Int, seconds: Double)] = []
    var byTag: [(tag: String, seconds: Double)] = []
}

/// 時長管理：記錄閱讀時間（依作品、標籤統計），並在連續閱讀達到設定時間時提醒休息。
@MainActor
@Observable
final class ReadingTimeStore {
    private(set) var log: ReadingLog
    let deviceID: String

    var reminderEnabled: Bool {
        didSet { UserDefaults.standard.set(reminderEnabled, forKey: Self.reminderEnabledKey) }
    }
    var reminderMinutes: Int {
        didSet { UserDefaults.standard.set(reminderMinutes, forKey: Self.reminderMinutesKey) }
    }
    /// 連續閱讀已達提醒時間，閱讀頁會彈出提醒
    private(set) var restDue = false

    private var active: (workID: Int, since: Date)?
    private var continuous: TimeInterval = 0
    private var lastActiveEnd: Date?

    private static let url = URL.applicationSupportDirectory.appending(path: "reading-log.json")
    private static let reminderEnabledKey = "reading.reminderEnabled"
    private static let reminderMinutesKey = "reading.reminderMinutes"
    /// 中斷超過這段時間，連續閱讀時間重新計算
    private static let breakThreshold: TimeInterval = 5 * 60

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init() {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "device.id") {
            deviceID = id
        } else {
            deviceID = UUID().uuidString
            defaults.set(deviceID, forKey: "device.id")
        }
        log = (try? Data(contentsOf: Self.url)).flatMap { try? JSONDecoder().decode(ReadingLog.self, from: $0) } ?? ReadingLog()
        reminderEnabled = defaults.bool(forKey: Self.reminderEnabledKey)
        let minutes = defaults.integer(forKey: Self.reminderMinutesKey)
        reminderMinutes = minutes > 0 ? minutes : 45
    }

    // MARK: 計時

    func begin(workID: Int, meta: ReadingWorkMeta) {
        flush()
        let now = Date()
        if let lastActiveEnd, now.timeIntervalSince(lastActiveEnd) > Self.breakThreshold { continuous = 0 }
        log.works[String(workID)] = meta
        active = (workID, now)
    }

    func pause() {
        guard active != nil else { return }
        flush()
        active = nil
        lastActiveEnd = Date()
        save()
    }

    /// 閱讀中定期呼叫，把目前累計寫入紀錄並檢查休息提醒
    func tick() {
        guard active != nil else { return }
        flush()
        // 閱讀中只寫入本機；暫停或離開閱讀頁時才通知同步
        save(notify: false)
    }

    func acknowledgeRest() {
        restDue = false
        continuous = 0
    }

    private func flush() {
        guard let active else { return }
        let now = Date()
        // 單次最多計 15 分鐘，避免 App 被暫停而未收到通知時灌水
        let elapsed = min(max(now.timeIntervalSince(active.since), 0), 15 * 60)
        self.active = (active.workID, now)
        guard elapsed > 0 else { return }
        let day = Self.dayFormatter.string(from: active.since)
        var device = log.devices[deviceID] ?? DeviceReadingLog()
        device.days[day, default: [:]][String(active.workID), default: 0] += elapsed
        device.modifiedAt = now
        log.devices[deviceID] = device
        continuous += elapsed
        if reminderEnabled, continuous >= Double(reminderMinutes * 60) { restDue = true }
    }

    // MARK: 統計

    func stats(for period: ReadingStatsPeriod) -> ReadingStats {
        var allowed: Set<String>?
        if let days = period.days {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            allowed = Set((0..<days).compactMap {
                calendar.date(byAdding: .day, value: -$0, to: today).map(Self.dayFormatter.string)
            })
        }
        var byWork: [Int: Double] = [:]
        for device in log.devices.values {
            for (day, works) in device.days where allowed?.contains(day) ?? true {
                for (id, seconds) in works {
                    if let id = Int(id) { byWork[id, default: 0] += seconds }
                }
            }
        }
        var byTag: [String: Double] = [:]
        for (id, seconds) in byWork {
            for tag in Set(log.works[String(id)]?.tags ?? []) { byTag[tag, default: 0] += seconds }
        }
        return ReadingStats(
            total: byWork.values.reduce(0, +),
            byWork: byWork.map { (id: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds },
            byTag: byTag.map { (tag: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds }
        )
    }

    func meta(for id: Int) -> ReadingWorkMeta? { log.works[String(id)] }

    // MARK: 同步

    func apply(_ merged: ReadingLog) {
        flush()
        // 本機紀錄永遠以記憶體中的為準
        var result = merged
        result.devices[deviceID] = log.devices[deviceID]
        log = result
        save(notify: false)
    }

    private func save(notify: Bool = true) {
        try? JSONEncoder().encode(log).write(to: Self.url, options: .atomic)
        if notify { NotificationCenter.default.post(name: .personalDataChanged, object: nil) }
    }
}

extension WorkSummary {
    var readingMeta: ReadingWorkMeta {
        ReadingWorkMeta(title: title, authors: authors, tags: fandoms + relationships + characters + freeforms)
    }
}
