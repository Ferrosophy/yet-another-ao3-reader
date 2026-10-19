import SwiftUI

struct TranslationSettingsView: View {
    @Environment(AppState.self) private var app
    @State private var apiKey = ""
    @State private var keyStatus: String?
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        @Bindable var settings = app.translation
        let kind = settings.config.provider

        Form {
            Section {
                Picker("翻譯服務", selection: $settings.config.provider) {
                    ForEach(TranslationProviderKind.allCases) { Text($0.title).tag($0) }
                }
                Picker("原文語言", selection: $settings.config.sourceLanguageCode) {
                    Text("自動偵測").tag(String?.none)
                    ForEach(TranslationLanguage.all) { Text($0.name).tag(Optional($0.code)) }
                }
                Picker("目標語言", selection: $settings.config.targetLanguageCode) {
                    ForEach(TranslationLanguage.all) { Text($0.name).tag($0.code) }
                }
                Picker("顯示方式", selection: $settings.config.displayMode) {
                    ForEach(BilingualDisplayMode.allCases) { Text($0.title).tag($0) }
                }
            } footer: {
                Text("沉浸式翻譯：譯文顯示在每段原文下方，不會取代原文。")
            }

            if kind.requiresAPIKey {
                Section {
                    SecureField("API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(saveKey)
                    HStack {
                        Button("儲存到本機鑰匙圈", action: saveKey)
                        Spacer()
                        if let keyStatus {
                            Text(keyStatus).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("API Key")
                } footer: {
                    Text("只保存在這台裝置，不同步、不上傳，僅在翻譯請求中直接送往服務商。")
                }
            }

            switch kind {
            case .openAICompatible:
                Section("OpenAI 相容 API") {
                    TextField("Base URL", text: $settings.config.openAIBaseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Menu("常用預設") {
                        ForEach(OpenAIPreset.all) { preset in
                            Button(preset.name) { settings.config.openAIBaseURL = preset.baseURL }
                        }
                    }
                    TextField("模型名稱", text: $settings.config.openAIModel, prompt: Text("例如 gpt-4o-mini、deepseek-chat"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            case .anthropic:
                Section("Claude 模型") {
                    TextField("模型名稱", text: $settings.config.anthropicModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Menu("常用模型") {
                        ForEach(["claude-sonnet-5-5", "claude-haiku-5-5", "claude-opus-5-5"], id: \.self) { model in
                            Button(model) { settings.config.anthropicModel = model }
                        }
                    }
                }
            case .gemini:
                Section("Gemini 模型") {
                    TextField("模型名稱", text: $settings.config.geminiModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            case .googleWeb:
                Section {
                    Text("使用 Google 翻譯網頁端點，無需金鑰。屬非官方介面，大量使用時可能被暫時限流。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .bingFree:
                Section {
                    Text("使用 Edge 瀏覽器內建的微軟翻譯端點，無需金鑰。屬非官方介面，可能變更或限流。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .microsoftAzure:
                Section {
                    TextField("區域（如 eastasia、global）", text: Binding(
                        get: { settings.config.azureRegion ?? "" },
                        set: { settings.config.azureRegion = $0.isEmpty ? nil : $0 }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                } header: {
                    Text("Azure Translator")
                } footer: {
                    Text("在 Azure 入口網站建立 Translator 資源後取得金鑰與區域；全域資源可留空。")
                }
            case .googleCloud:
                EmptyView()
            }

            if kind.isLLM {
                Section {
                    TextEditor(text: $settings.config.extraInstructions)
                        .frame(minHeight: 100)
                } header: {
                    Text("額外翻譯指示")
                } footer: {
                    Text("例如人名譯法對照（Harry → 哈利）、文風要求、是否保留敬語等，會附加到 AI 的系統提示中。")
                }
            }

            Section {
                Button {
                    Task { await test() }
                } label: {
                    HStack {
                        Text("測試翻譯")
                        if isTesting { Spacer(); ProgressView() }
                    }
                }
                .disabled(isTesting)
                if let testResult {
                    Text(testResult).font(.callout)
                }
            }
        }
        .navigationTitle("翻譯")
        .onAppear(perform: loadKey)
        .onChange(of: kind) {
            loadKey()
            testResult = nil
        }
    }

    private func loadKey() {
        apiKey = app.translation.apiKey(for: app.translation.config.provider)
        keyStatus = apiKey.isEmpty ? nil : "已保存"
    }

    private func saveKey() {
        do {
            try app.translation.setAPIKey(apiKey, for: app.translation.config.provider)
            keyStatus = apiKey.isEmpty ? "已刪除" : "已保存"
        } catch {
            keyStatus = error.localizedDescription
        }
    }

    private func test() async {
        isTesting = true
        defer { isTesting = false }
        let sample = "The rain had stopped, but neither of them moved to leave."
        do {
            let provider = try app.translation.makeProvider()
            let result = try await provider.translate([sample], from: app.translation.config.sourceLanguage, to: app.translation.config.targetLanguage)
            testResult = "✅ \(result.first ?? "")"
        } catch {
            testResult = "❌ \(error.localizedDescription)"
        }
    }
}
