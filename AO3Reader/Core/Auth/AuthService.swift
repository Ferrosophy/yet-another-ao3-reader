import Foundation
import Observation

/// AO3 帳號登入。只保存 AO3 伺服器下發的 session cookie（`_otwarchive_session`、`remember_user_token`），
/// 不保存密碼。Cookie 依來源網域隔離，所以官網與各鏡像需各自登入。
@MainActor
@Observable
final class AuthService {
    private(set) var username: String?
    private(set) var isWorking = false

    var isLoggedIn: Bool { username != nil }

    /// 以原生表單登入：取得 authenticity_token → POST /users/login → 從回應頁首確認用戶名。
    func login(username: String, password: String, client: AO3Client) async throws {
        isWorking = true
        defer { isWorking = false }

        let loginPage = try await client.get("/users/login")
        guard let token = AO3Parser.authenticityToken(loginPage) else {
            throw AO3Error.parse("找不到登入表單 authenticity_token")
        }
        let (html, _) = try await client.postForm("/users/login", fields: [
            ("authenticity_token", token),
            ("user[login]", username),
            ("user[password]", password),
            ("user[remember_me]", "1"),
            ("commit", "Log in"),
        ])
        guard let name = AO3Parser.loggedInUsername(html) else { throw AO3Error.loginFailed }
        self.username = name
    }

    /// 網頁登入（WKWebView）完成後或切換來源時呼叫，以 cookie 判斷登入狀態。
    func refresh(client: AO3Client) async {
        isWorking = true
        defer { isWorking = false }
        username = try? await client.probe().username
    }

    func logout(client: AO3Client) async {
        if let page = try? await client.get("/"), let token = AO3Parser.authenticityToken(page) {
            _ = try? await client.postForm("/users/logout", fields: [
                ("_method", "delete"),
                ("authenticity_token", token),
            ])
        }
        let storage = HTTPCookieStorage.shared
        for cookie in storage.cookies(for: client.baseURL) ?? [] {
            storage.deleteCookie(cookie)
        }
        username = nil
    }
}
