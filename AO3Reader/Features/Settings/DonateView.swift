import Photos
import SwiftUI
import UIKit

/// 設定 › 支持贊助：顯示支付寶收款碼，可保存到相簿。內容全部在本機，不連網。
struct DonateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("喜歡這個項目嗎？")
                        .appFont(.title2, weight: .bold)
                    Text("本項目完全開源、永久免費、無廣告，不收集用戶資料。\n所有功能均可免費使用。如果你喜歡這個項目，可以自願支持獨立開發者的維護與開發工作。\n贊助不會解鎖任何額外功能，也不涉及 AO3 作品的銷售或收費。\n本項目是獨立開發的非官方 AO3 閱讀器，與 Archive of Our Own（AO3）及 Organization for Transformative Works（OTW）不存在官方關聯。")
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
        guard let data = UIImage(named: "DonateQRCode")?.pngData() else { return }
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                message = String(localized: "沒有相簿權限，請在「設定」中允許 YAAO3R 加入照片")
                return
            }
            do {
                try await Self.addToPhotos(data)
                message = String(localized: "已保存到相簿")
            } catch {
                message = String(localized: "無法保存：\(error.localizedDescription)")
            }
        }
    }

    /// 寫入相簿。必須是 nonisolated：照片庫在背景佇列執行這個閉包，
    /// 若閉包被推斷為主執行緒專用，執行時的隔離檢查會讓 App 閃退。
    nonisolated private static func addToPhotos(_ data: Data) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
        }
    }
}
