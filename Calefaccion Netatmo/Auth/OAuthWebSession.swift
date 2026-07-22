//
//  OAuthWebSession.swift
//  Calefaccion Netatmo
//
//  Envoltorio async de ASWebAuthenticationSession para el flujo Authorization Code.
//

import AuthenticationServices
import UIKit

@MainActor
final class OAuthWebSession: NSObject, ASWebAuthenticationPresentationContextProviding {

    /// Presenta la hoja de login de Netatmo y devuelve la URL de callback recibida.
    func authenticate(authorizationURL: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    if let authError = error as? ASWebAuthenticationSessionError,
                       authError.code == .canceledLogin {
                        continuation.resume(throwing: APIError.oauthFailed("Cancelado por el usuario."))
                    } else {
                        continuation.resume(throwing: APIError.network(error))
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: APIError.oauthFailed("No se recibió URL de callback."))
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                continuation.resume(throwing: APIError.oauthFailed("No se pudo iniciar la sesión de autenticación."))
            }
        }
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first

        guard let windowScene else {
            preconditionFailure("No hay UIWindowScene disponible para presentar el login de Netatmo.")
        }
        return windowScene.keyWindow ?? UIWindow(windowScene: windowScene)
    }
}
