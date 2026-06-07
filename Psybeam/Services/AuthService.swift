import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import UIKit

enum AuthState: Sendable, Equatable {
    case signedOut
    case authenticating
    case signedIn(userId: String)
    case failed(String)
}

private enum AuthError: Error {
    case badStatus(Int)
}

@MainActor
final class AuthService: NSObject {
    let state = PassthroughSubject<AuthState, Never>()

    private let baseURL: URL
    private let keychain: KeychainStore
    private let session: URLSession
    private var currentNonce: String?

    init(baseURL: URL, keychain: KeychainStore, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.keychain = keychain
        self.session = session
        super.init()
    }

    var isSignedIn: Bool { keychain.token() != nil }

    func restore() {
        guard keychain.token() != nil else {
            state.send(.signedOut)
            return
        }
        Task {
            do {
                let userId = try await refresh()
                state.send(.signedIn(userId: userId))
            } catch {
                keychain.clear()
                state.send(.signedOut)
                AppLogger.shared.warn("session restore failed, signed out: \(error)", category: .auth)
            }
        }
    }

    private func refresh() async throws -> String {
        guard let jwt = keychain.token() else { throw AuthError.badStatus(401) }
        struct Reply: Decodable {
            let token: String
            let user: User
            struct User: Decodable { let id: String }
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("/v1/auth/refresh"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        keychain.setToken(reply.token)
        return reply.user.id
    }

    func signIn() {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        state.send(.authenticating)

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func signOut() {
        keychain.clear()
        state.send(.signedOut)
    }

    private func exchange(identityToken: String, fullName: PersonNameComponents?) {
        let rawNonce = currentNonce
        Task {
            do {
                let userId = try await postApple(identityToken: identityToken, rawNonce: rawNonce, fullName: fullName)
                state.send(.signedIn(userId: userId))
                AppLogger.shared.info("siwa exchange ok", category: .auth)
            } catch {
                state.send(.failed("\(error)"))
                AppLogger.shared.error("siwa exchange failed: \(error)", category: .auth)
            }
        }
    }

    private func postApple(identityToken: String, rawNonce: String?, fullName: PersonNameComponents?) async throws -> String {
        struct Body: Encodable {
            let identityToken: String
            let rawNonce: String?
            let fullName: Name?
            struct Name: Encodable { let givenName: String?; let familyName: String? }
        }
        struct Reply: Decodable {
            let token: String
            let user: User
            struct User: Decodable { let id: String }
        }
        let name = fullName.map { Body.Name(givenName: $0.givenName, familyName: $0.familyName) }
        var request = URLRequest(url: baseURL.appendingPathComponent("/v1/auth/apple"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(identityToken: identityToken, rawNonce: rawNonce, fullName: name))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        keychain.setToken(reply.token)
        return reply.user.id
    }

    private static func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension AuthService: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let token = String(data: tokenData, encoding: .utf8)
        else {
            state.send(.failed("missing_identity_token"))
            return
        }
        exchange(identityToken: token, fullName: credential.fullName)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if (error as? ASAuthorizationError)?.code == .canceled {
            state.send(.signedOut)
        } else {
            state.send(.failed("\(error.localizedDescription)"))
        }
    }
}

extension AuthService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}
