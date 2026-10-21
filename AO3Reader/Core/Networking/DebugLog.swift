// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation

/// 除錯紀錄：每個 AO3 / 鏡像請求的狀態、偵測到的防護（Cloudflare、Anubis）、回應片段與送出的請求標頭，
/// 以及人機驗證頁的導覽過程。在「設定」連續點擊版本號三次進入除錯頁查看。只保存在本機。
struct DebugEntry: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case ok, http, cloudflare, anubis, network, parse, verify
    }

    var id = UUID()
    var date = Date()
    var kind: Kind
    var method = "GET"
    var url: String
    var status: Int?
    var summary: String
    /// 詳細內容：請求 / 回應標頭、Cookie 名稱、回應開頭
    var detail: String = ""

    var isProblem: Bool { kind != .ok && kind != .verify }
}

@MainActor
@Observable
final class DebugLog {
    static let shared = DebugLog()

    private(set) var entries: [DebugEntry] = []
    private static let limit = 300
    private static let url = URL.cachesDirectory.appending(path: "debug-log.json")

    private init() {
        entries = (try? Data(contentsOf: Self.url)).flatMap { try? JSONDecoder().decode([DebugEntry].self, from: $0) } ?? []
    }

    @ObservationIgnored private var saveTask: Task<Void, Never>?

    func add(_ entry: DebugEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        // 合併短時間內的多筆紀錄再寫入
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            self.saveTask = nil
            try? JSONEncoder().encode(self.entries).write(to: Self.url, options: .atomic)
        }
    }

    func clear() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: Self.url)
    }

    /// 從任何執行緒記錄。寫入前統一脫敏：網址中的敏感參數、頁面裡的驗證權杖與電子郵件地址
    nonisolated static func record(_ entry: DebugEntry) {
        var entry = entry
        entry.url = redactURL(entry.url)
        entry.detail = redact(entry.detail)
        Task { @MainActor in DebugLog.shared.add(entry) }
    }

    /// 名稱含這些字的網址參數，值一律隱藏
    nonisolated private static let sensitiveParameters = ["token", "password", "passwd", "secret", "key", "session", "auth", "email", "login"]

    nonisolated static func redactURL(_ text: String) -> String {
        guard var components = URLComponents(string: text), let items = components.queryItems, !items.isEmpty else { return text }
        components.queryItems = items.map { item in
            let name = item.name.lowercased()
            return sensitiveParameters.contains { name.contains($0) } ? URLQueryItem(name: item.name, value: "redacted") : item
        }
        return components.string ?? text
    }

    /// 隱藏頁面片段中的驗證權杖（authenticity_token、csrf-token）與電子郵件地址
    nonisolated static func redact(_ text: String) -> String {
        let rules: [(String, String)] = [
            (#"(name="authenticity_token"[^>]*?value=")[^"]*"#, "$1<redacted>"),
            (#"(value=")[^"]*("[^>]*?name="authenticity_token")"#, "$1<redacted>$2"),
            (#"(name="csrf-token"[^>]*?content=")[^"]*"#, "$1<redacted>"),
            (#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, "<email>"),
        ]
        var result = text
        for (pattern, template) in rules {
            result = result.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return result
    }

    /// 全部紀錄的文字版（複製給開發者）
    func exportText() -> String {
        entries.map { $0.text }.joined(separator: "\n\n----------\n\n")
    }
}

extension DebugEntry {
    var text: String {
        let formatter = ISO8601DateFormatter()
        var lines = ["[\(formatter.string(from: date))] \(kind.rawValue.uppercased()) \(method) \(url)"]
        if let status { lines.append("Status: \(status)") }
        lines.append(summary)
        if !detail.isEmpty { lines.append(detail) }
        return lines.joined(separator: "\n")
    }

    /// 由一次回應建立紀錄：判斷防護類型，附上標頭、Cookie 名稱與回應開頭
    static func response(_ response: HTTPURLResponse, data: Data, method: String, requestHeaders: [String: String],
                         kind: Kind, summary: String) -> DebugEntry {
        let url = response.url?.absoluteString ?? ""
        var detail: [String] = ["— Request headers —"]
        for (key, value) in requestHeaders.sorted(by: { $0.key < $1.key }) { detail.append("\(key): \(value)") }
        let cookies = response.url.flatMap { HTTPCookieStorage.shared.cookies(for: $0) } ?? []
        detail.append("Cookies sent: " + (cookies.isEmpty ? "(none)" : cookies.map(\.name).sorted().joined(separator: ", ")))
        detail.append("— Response headers —")
        for (key, value) in response.allHeaderFields.map({ ("\($0.key)", "\($0.value)") }).sorted(by: { $0.0 < $1.0 }) {
            // Set-Cookie 只記名稱，不記內容
            if key.lowercased() == "set-cookie" {
                detail.append("Set-Cookie: " + value.split(separator: ",").compactMap { $0.split(separator: "=").first }
                    .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ", "))
            } else {
                detail.append("\(key): \(value)")
            }
        }
        // 成功的請求不記內容，只有出問題時附上回應開頭
        if kind != .ok {
            detail.append("— Body (first 1500 bytes, \(data.count) total) —")
            detail.append(String(decoding: data.prefix(1500), as: UTF8.self))
        }
        return DebugEntry(kind: kind, method: method, url: url, status: response.statusCode, summary: summary,
                          detail: detail.joined(separator: "\n"))
    }
}
