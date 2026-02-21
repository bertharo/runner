import AuthenticationServices
import SwiftUI

@MainActor
final class AuthenticationManager: NSObject, ObservableObject {
    static let shared = AuthenticationManager()

    @Published var isAuthenticated = false
    @Published var userEmail: String?
    @Published var userIdentifier: String?
    @Published var errorMessage: String?

    private override init() {
        super.init()
        loadCredentials()
    }

    // MARK: - Sign In

    func signIn() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
    }

    // MARK: - Credential State Check

    func checkCredentialState() {
        guard let userIdentifier else { return }

        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userIdentifier) { [weak self] state, _ in
            Task { @MainActor in
                switch state {
                case .authorized:
                    break
                case .revoked, .notFound:
                    self?.signOut()
                default:
                    break
                }
            }
        }
    }

    // MARK: - Complete Sign In (called from SwiftUI SignInWithAppleButton)

    func completeSignIn(userId: String, email: String?) {
        Self.saveKeychainItem(key: "apple_user_identifier", value: userId)
        userIdentifier = userId

        if let email {
            Self.saveKeychainItem(key: "apple_user_email", value: email)
            self.userEmail = email
        }

        isAuthenticated = true
        errorMessage = nil
    }

    // MARK: - Sign Out

    func signOut() {
        Self.deleteKeychainItem(key: "apple_user_identifier")
        Self.deleteKeychainItem(key: "apple_user_email")
        isAuthenticated = false
        userIdentifier = nil
        userEmail = nil
    }

    // MARK: - Keychain Helpers

    private func loadCredentials() {
        userIdentifier = Self.readKeychainItem(key: "apple_user_identifier")
        userEmail = Self.readKeychainItem(key: "apple_user_email")
        isAuthenticated = userIdentifier != nil
    }

    private static func saveKeychainItem(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func readKeychainItem(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKeychainItem(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthenticationManager: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }

        let userId = credential.user
        let email = credential.email // Only available on first sign-in

        Task { @MainActor in
            Self.saveKeychainItem(key: "apple_user_identifier", value: userId)
            self.userIdentifier = userId

            // Email is only provided on first sign-in — persist immediately
            if let email {
                Self.saveKeychainItem(key: "apple_user_email", value: email)
                self.userEmail = email
            }

            self.isAuthenticated = true
            self.errorMessage = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            let authError = error as? ASAuthorizationError
            // Don't show error for user cancellation
            if authError?.code == .canceled { return }
            self.errorMessage = error.localizedDescription
        }
    }
}
