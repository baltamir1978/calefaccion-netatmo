//
//  NetatmoAPIClient.swift
//  Calefaccion Netatmo
//
//  Cliente HTTP genérico: añade el Bearer token, decodifica y reintenta una vez
//  tras renovar el token si la API responde 401/403 (token expirado).
//

import Foundation

final class NetatmoAPIClient {
    private let authManager: AuthManager
    private let session: URLSession
    private let decoder: JSONDecoder

    init(authManager: AuthManager, session: URLSession = URLSession(configuration: .default)) {
        self.authManager = authManager
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - API pública

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        try await send(path: path, method: .get, query: query, form: [:])
    }

    func post<T: Decodable>(_ path: String, form: [String: String] = [:]) async throws -> T {
        try await send(path: path, method: .post, query: [:], form: form)
    }

    // MARK: - Núcleo

    private func send<T: Decodable>(
        path: String,
        method: HTTPMethod,
        query: [String: String],
        form: [String: String],
        isRetry: Bool = false
    ) async throws -> T {
        let token = try await authManager.validAccessToken()
        let request = try buildRequest(path: path, method: method, query: query, form: form, token: token)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        if (http.statusCode == 401 || http.statusCode == 403), !isRetry {
            // Token probablemente expirado: renovar y reintentar una vez.
            _ = try await authManager.forceRefresh()
            return try await send(path: path, method: method, query: query, form: form, isRetry: true)
        }

        guard (200..<300).contains(http.statusCode) else {
            let err = try? decoder.decode(NetatmoErrorResponse.self, from: data)
            throw APIError.httpError(status: http.statusCode, code: err?.error?.code, message: err?.error?.message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func buildRequest(
        path: String,
        method: HTTPMethod,
        query: [String: String],
        form: [String: String],
        token: String
    ) throws -> URLRequest {
        var components = URLComponents(
            url: NetatmoConfig.apiBaseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if method == .get, !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if method == .post {
            request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = formEncode(form).data(using: .utf8)
        }
        return request
    }

    private func formEncode(_ parameters: [String: String]) -> String {
        parameters.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? value
            return "\(key)=\(encoded)"
        }.joined(separator: "&")
    }
}
