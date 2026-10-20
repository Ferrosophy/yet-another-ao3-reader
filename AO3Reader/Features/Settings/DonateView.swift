import Photos
import SwiftUI
import UIKit

/// 設定 › 投喂開發者：顯示支付寶收款碼，可保存到相簿。內容全部在本機，不連網。
struct DonateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("喜歡這個項目嗎？")
                        .appFont(.title2, weight: .bold)
                    Text("如果它為你帶來了一點便利，歡迎請我喝杯咖啡。你的支持將幫助項目持續開發與維護。☕")
                        .appFont(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Image("DonateQRCode")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 320)
                        .clipShape(.rect(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                    Button {
                        save()
                    } label: {
                        Label("保存QR code到相簿", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .frame(maxWidth: 320)
                    if let message {
                        Text(message)
                            .appFont(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }

    private func save() {
        guard let image = UIImage(named: "DonateQRCode") else { return }
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                message = String(localized: "沒有相簿權限，請在「設定」中允許 YAAO3R 加入照片")
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    _ = PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                message = String(localized: "已保存到相簿")
            } catch {
                message = String(localized: "無法保存：\(error.localizedDescription)")
            }
        }
    }
}
