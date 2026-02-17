import AuthenticationServices
import Foundation
import UIKit

@MainActor
final class StravaAuth: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var isAuthenticated = false
    @Published var errorMessage: String?
    private var authSession: ASWebAuthenticationSession?

    private static let proxyBaseURL = "https://runtracker-proxy.bertharo.workers.dev"
    private static let authURL = "https://www.strava.com/oauth/authorize"
    private static let callbackScheme = "runtracker"

    override init() {
        super.init()
        isAuthenticated = Self.accessToken != nil
    }

    // MARK: - Token Storage (UserDefaults)

    static var accessToken: String? {
        get { UserDefaults.standard.string(forKey: "strava_access_token") }
        set { UserDefaults.standard.set(newValue, forKey: "strava_access_token") }
    }

    static var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: "strava_refresh_token") }
        set { UserDefaults.standard.set(newValue, forKey: "strava_refresh_token") }
    }

    static var expiresAt: Int {
        get { UserDefaults.standard.integer(forKey: "strava_expires_at") }
        set { UserDefaults.standard.set(newValue, forKey: "strava_expires_at") }
    }

    // MARK: - Proxy Config

    private func fetchClientId() async throws -> String {
        let url = URL(string: "\(Self.proxyBaseURL)/strava/config")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        guard let clientId = json["client_id"] as? String else {
            throw URLError(.badServerResponse)
        }
        return clientId
    }

    // MARK: - OAuth Flow

    func authorize() {
        Task {
            do {
                let clientId = try await fetchClientId()

                var components = URLComponents(string: Self.authURL)!
                components.queryItems = [
                    URLQueryItem(name: "client_id", value: clientId),
                    URLQueryItem(name: "redirect_uri", value: "\(Self.callbackScheme)://localhost"),
                    URLQueryItem(name: "response_type", value: "code"),
                    URLQueryItem(name: "scope", value: "activity:read_all"),
                    URLQueryItem(name: "approval_prompt", value: "auto"),
                ]

                authSession = ASWebAuthenticationSession(
                    url: components.url!,
                    callbackURLScheme: Self.callbackScheme
                ) { [weak self] callbackURL, error in
                    Task { @MainActor in
                        guard let self else { return }
                        self.authSession = nil
                        if let error {
                            self.errorMessage = error.localizedDescription
                            return
                        }
                        guard let callbackURL,
                              let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                                .queryItems?.first(where: { $0.name == "code" })?.value else {
                            self.errorMessage = "No authorization code received."
                            return
                        }
                        await self.exchangeCode(code)
                    }
                }
                authSession?.presentationContextProvider = self
                authSession?.prefersEphemeralWebBrowserSession = false
                authSession?.start()
            } catch {
                errorMessage = "Failed to fetch config: \(error.localizedDescription)"
            }
        }
    }

    private func exchangeCode(_ code: String) async {
        do {
            let tokens = try await tokenRequest(params: [
                "code": code,
                "grant_type": "authorization_code",
            ])
            saveTokens(tokens)
            isAuthenticated = true
            errorMessage = nil
        } catch {
            errorMessage = "Token exchange failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Token Refresh

    func getValidAccessToken() async throws -> String {
        guard let access = Self.accessToken, let refresh = Self.refreshToken else {
            throw URLError(.userAuthenticationRequired)
        }

        let now = Int(Date().timeIntervalSince1970)
        if Self.expiresAt > now + 60 {
            return access
        }

        let tokens = try await tokenRequest(params: [
            "refresh_token": refresh,
            "grant_type": "refresh_token",
        ])
        saveTokens(tokens)
        return tokens.accessToken
    }

    // MARK: - Disconnect

    func disconnect() {
        Self.accessToken = nil
        Self.refreshToken = nil
        Self.expiresAt = 0
        isAuthenticated = false
    }

    // MARK: - Helpers

    private struct TokenResponse {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Int
    }

    private func tokenRequest(params: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "\(Self.proxyBaseURL)/strava/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: params)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: body])
        }

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return TokenResponse(
            accessToken: json["access_token"] as! String,
            refreshToken: json["refresh_token"] as! String,
            expiresAt: json["expires_at"] as! Int
        )
    }

    private func saveTokens(_ tokens: TokenResponse) {
        Self.accessToken = tokens.accessToken
        Self.refreshToken = tokens.refreshToken
        Self.expiresAt = tokens.expiresAt
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}
