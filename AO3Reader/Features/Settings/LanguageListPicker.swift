// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// 可搜尋的語言長列表。`selection` 為 nil 代表「自動偵測」（僅在 `allowsAutomatic` 時出現）。
struct LanguageListPicker: View {
    let title: LocalizedStringKey
    let languages: [TranslationLanguage]
    var allowsAutomatic = false
    @Binding var selection: String?
    var onSelect: (() -> Void)?

    @State private var query = ""

    var body: some View {
        List {
            if allowsAutomatic, query.isEmpty {
                row(label: Text("自動偵測"), detail: nil, isSelected: selection == nil) { choose(nil) }
            }
            ForEach(languages.filter { $0.matches(query) }) { language in
                row(label: Text(verbatim: language.displayName),
                    detail: language.displayName == language.name ? nil : language.name,
                    isSelected: selection == language.code) { choose(language.code) }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("搜尋語言"))
        .overlay {
            if !languages.contains(where: { $0.matches(query) }) {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private func row(label: Text, detail: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    label.foregroundStyle(.primary)
                    if let detail {
                        Text(verbatim: detail).appFont(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
                }
            }
            .contentShape(.rect)
        }
    }

    private func choose(_ code: String?) {
        selection = code
        onSelect?()
    }
}

/// 設定表單中的語言列：顯示目前選擇，點擊後推入可搜尋列表。
struct LanguageListRow: View {
    let title: LocalizedStringKey
    let languages: [TranslationLanguage]
    var allowsAutomatic = false
    @Binding var selection: String?

    var body: some View {
        NavigationLink {
            LanguagePickerPage(title: title, languages: languages, allowsAutomatic: allowsAutomatic, selection: $selection)
        } label: {
            LabeledContent(title) {
                if let code = selection, let language = TranslationLanguage.lookup(code) {
                    Text(verbatim: language.displayName)
                } else {
                    Text("自動偵測")
                }
            }
        }
    }
}

/// 推入的列表頁：選擇後自動返回。
private struct LanguagePickerPage: View {
    let title: LocalizedStringKey
    let languages: [TranslationLanguage]
    let allowsAutomatic: Bool
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LanguageListPicker(title: title, languages: languages, allowsAutomatic: allowsAutomatic,
                           selection: $selection) { dismiss() }
    }
}

/// 以 sheet 呈現的語言列表（閱讀器選單使用）。
struct TranslationLanguageSheet: View {
    let title: LocalizedStringKey
    let languages: [TranslationLanguage]
    var allowsAutomatic = false
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LanguageListPicker(title: title, languages: languages, allowsAutomatic: allowsAutomatic,
                               selection: $selection) { dismiss() }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消", role: .cancel) { dismiss() }
                    }
                }
        }
    }
}
