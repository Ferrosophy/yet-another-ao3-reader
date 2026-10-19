import SwiftUI

/// 標籤輸入框：輸入時向 AO3 /autocomplete 查詢匹配的正式標籤，點選後加入為標籤膠囊。
/// 綁定值仍是官網使用的逗號分隔字串，方便直接帶入搜尋參數。
struct TagTokenField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let kind: AutocompleteKind

    @Environment(AppState.self) private var app
    @State private var input = ""
    @State private var suggestions: [String] = []
    @State private var lookup: Task<Void, Never>?

    private var tokens: [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !tokens.isEmpty {
                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(tokens, id: \.self) { token in
                        Button {
                            remove(token)
                        } label: {
                            HStack(spacing: 4) {
                                Text(token).lineLimit(1)
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .appFont(.footnote)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .fixedSize()
                        }
                        .buttonStyle(.borderless)
                        .glassEffect(.regular.tint(.accentColor.opacity(0.15)).interactive(), in: .capsule)
                        .accessibilityLabel("移除 \(token)")
                    }
                }
            }

            TextField(title, text: $input)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { add(input) }
                .onChange(of: input) { scheduleLookup() }

            ForEach(suggestions.prefix(8), id: \.self) { suggestion in
                Button {
                    add(suggestion)
                } label: {
                    Label(suggestion, systemImage: "tag")
                        .appFont(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func scheduleLookup() {
        lookup?.cancel()
        let term = input.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else {
            suggestions = []
            return
        }
        let client = app.client
        let kind = kind
        lookup = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let result = (try? await client.autocomplete(kind, term: term)) ?? []
            guard !Task.isCancelled else { return }
            suggestions = result.filter { !tokens.contains($0) }
        }
    }

    private func add(_ raw: String) {
        // 官網以逗號分隔標籤，標籤名稱本身不可含逗號
        let tag = raw.replacingOccurrences(of: ",", with: " ").trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !tokens.contains(tag) else { return }
        text = (tokens + [tag]).joined(separator: ",")
        input = ""
        suggestions = []
    }

    private func remove(_ token: String) {
        text = tokens.filter { $0 != token }.joined(separator: ",")
    }
}
