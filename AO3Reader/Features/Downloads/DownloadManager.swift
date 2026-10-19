import Foundation
import Observation

/// 下載列表：批次下載的作品依序下載（每部之間稍作間隔，避免對 AO3 造成負擔）。
@MainActor
@Observable
final class DownloadManager {
    enum State: Equatable {
        case waiting, downloading, done, failed(String)
    }

    struct DownloadTask: Identifiable {
        let id = UUID()
        let workID: Int
        let title: String
        let format: DownloadFormat
        let client: AO3Client
        var state: State = .waiting
        var file: URL?
    }

    private(set) var tasks: [DownloadTask] = []
    private var isRunning = false

    /// 每次批次最多選取的作品數
    static let batchLimit = 25

    func enqueue(_ works: [WorkSummary], format: DownloadFormat, client: AO3Client) {
        for work in works {
            tasks.append(DownloadTask(workID: work.id, title: work.title, format: format, client: client))
        }
        run()
    }

    func retry(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].state = .waiting
        run()
    }

    func remove(_ ids: [UUID]) {
        tasks.removeAll { task in ids.contains(task.id) && task.state != .downloading }
    }

    func clearFinished() {
        tasks.removeAll { $0.state == .done }
    }

    var activeCount: Int { tasks.filter { $0.state == .waiting || $0.state == .downloading }.count }

    private func run() {
        guard !isRunning else { return }
        isRunning = true
        Task {
            while let index = tasks.firstIndex(where: { $0.state == .waiting }) {
                tasks[index].state = .downloading
                let task = tasks[index]
                let state: State
                var file: URL?
                do {
                    file = try await task.client.downloadWork(id: task.workID, title: task.title, format: task.format, href: nil)
                    state = .done
                } catch {
                    state = .failed(error.localizedDescription)
                }
                if let current = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[current].state = state
                    tasks[current].file = file
                }
                try? await Task.sleep(for: .seconds(2))
            }
            isRunning = false
        }
    }
}
