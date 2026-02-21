import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @EnvironmentObject private var authManager: AuthenticationManager

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "figure.run")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text("tränare")
                .font(.largeTitle.bold())

            Text("Sign in to get started")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email]
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                    authManager.completeSignIn(userId: credential.user, email: credential.email)
                case .failure(let error):
                    let authError = error as? ASAuthorizationError
                    if authError?.code == .canceled { return }
                    authManager.errorMessage = error.localizedDescription
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .padding(.horizontal, 40)

            if let error = authManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
        }
    }
}
