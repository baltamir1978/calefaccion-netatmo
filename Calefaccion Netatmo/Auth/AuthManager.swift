//
//  AuthManager.swift
//  Calefaccion Netatmo
//
//  Orquesta el flujo OAuth2 Authorization Code, persiste los tokens y los renueva.
//  Las credenciales (client_id/secret/redirect) se leen de AppSettings.
//

import Foundation
import Observation

@MainActor
@Observable
final class AuthManager {

    private(set) var tokens: TokenBundle?
    private(set) var isAuthenticating = false
    var lastError: String?

    var isAuthenticated: Bool { tokens != nil }

    private let settings: AppSettings
    private let store = TokenStore()
    private let webSession = OAuthWebSession()
    private let urlSession = URLSession(configuration: .default)

    /// Coalesce de renovaciones concurrentes.
    private var refreshTask: Task<String, Error>?

    init(settings: AppSettings) {
        self.settings = settings
        tokens = store.load()
    }

    // MARK: - Login

    func login() async {
        guard settings.hasValidCredentials else {
            lastError = APIError.notConfigured.errorDescription
            return
        }
        isAuthenticating = true
        lastError = nil
        defer { isAuthenticating = false }

        let creds = settings.credentials
        do {
            let state = UUID().uuidString
            let authURL = buildAuthorizationURL(state: state, credentials: creds)
            let callback = try await webSession.authenticate(
                authorizationURL: authURL,
                callbackScheme: creds.callbackScheme
            )
            let (code, returnedState) = try parseCallback(callback)
            guard returnedState == state else {
                throw APIError.oauthFailed("El parámetro 'state' no coincide.")
            }
            let bundle = try await exchangeCodeForTokens(code: code, credentials: creds)
            store.save(bundle)
            tokens = bundle
        } catch {
            lastError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func logout() {
        store.clear()
        tokens = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Token de acceso válido (renueva si hace falta)

    func validAccessToken() async throws -> String {
        guard let tokens else { throw APIError.notAuthenticated }
        if !tokens.isExpired { return tokens.accessToken }
        return try await refreshIfNeeded()
    }

    /// Fuerza un refresh (lo llama el API client tras un 401/403).
    func forceRefresh() async throws -> String {
        try await refreshIfNeeded()
    }

    private func refreshIfNeeded() async throws -> String {
        if let refreshTask { return try await refreshTask.value }

        let task = Task { () throws -> String in
            defer { refreshTask = nil }
            guard let current = tokens else { throw APIError.notAuthenticated }
            do {
                let bundle = try await refreshTokens(refreshToken: current.refreshToken)
                store.save(bundle)
                tokens = bundle
                return bundle.accessToken
            } catch {
                logout()
                throw APIError.tokenRefreshFailed
            }
        }
        refreshTask = task
        return try await task.value
    }

    // MARK: - Construcción de URLs y parsing

    private func buildAuthorizationURL(state: String, credentials: NetatmoCredentials) -> URL {
        var components = URLComponents(url: NetatmoConfig.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "redirect_uri", value: credentials.redirectURI),
            URLQueryItem(name: "scope", value: NetatmoConfig.scopeString),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "response_type", value: "code"),
        ]
        return components.url!
    }

    private func parseCallback(_ url: URL) throws -> (code: String, state: String?) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIError.oauthFailed("Callback ilegible.")
        }
        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            throw APIError.oauthFailed(error)
        }
        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw APIError.oauthFailed("No se recibió el código de autorización.")
        }
        let state = components.queryItems?.first(where: { $0.name == "state" })?.value
        return (code, state)
    }

    // MARK: - Peticiones al endpoint de token

    private func exchangeCodeForTokens(code: String, credentials: NetatmoCredentials) async throws -> TokenBundle {
        try await requestToken(parameters: [
            "grant_type": "authorization_code",
            "client_id": credentials.clientID,
            "client_secret": credentials.clientSecret,
            "code": code,
            "redirect_uri": credentials.redirectURI,
            "scope": NetatmoConfig.scopeString,
        ])
    }

    private func refreshTokens(refreshToken: String) async throws -> TokenBundle {
        let creds = settings.credentials
        return try await requestToken(parameters: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": creds.clientID,
            "client_secret": creds.clientSecret,
        ])
    }

    private func requestToken(parameters: [String: String]) async throws -> TokenBundle {
        var request = URLRequest(url: NetatmoConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode(parameters).data(using: .utf8)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw APIError.network(error)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let err = try? JSONDecoder().decode(NetatmoErrorResponse.self, from: data)
            throw APIError.httpError(status: http.statusCode, code: err?.error?.code, message: err?.error?.message)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            let token = try decoder.decode(TokenResponse.self, from: data)
            let expiresIn = token.expiresIn ?? token.expireIn ?? 10800
            return TokenBundle(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
            )
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func formEncode(_ parameters: [String: String]) -> String {
        parameters.map { key, value in
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? value
            return "\(key)=\(encodedValue)"
        }.joined(separator: "&")
    }
}

// MARK: - Respuesta del endpoint de token

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int?
    let expireIn: Int?
}

extension CharacterSet {
    /// Caracteres permitidos sin escapar en un valor de query x-www-form-urlencoded.
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
