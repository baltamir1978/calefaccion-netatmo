//
//  APIError.swift
//  Calefaccion Netatmo
//

import Foundation

enum APIError: LocalizedError {
    case notConfigured
    case notAuthenticated
    case invalidResponse
    case httpError(status: Int, code: Int?, message: String?)
    case decoding(Error)
    case network(Error)
    case oauthFailed(String)
    case tokenRefreshFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Faltan las credenciales de Netatmo. Rellena NetatmoConfig con tu client_id y client_secret."
        case .notAuthenticated:
            return "No has iniciado sesión en Netatmo."
        case .invalidResponse:
            return "Respuesta inválida del servidor."
        case let .httpError(status, code, message):
            let detail = message ?? "sin detalle"
            if let code { return "Error \(status) (código \(code)): \(detail)" }
            return "Error HTTP \(status): \(detail)"
        case let .decoding(error):
            return "No se pudieron interpretar los datos: \(error.localizedDescription)"
        case let .network(error):
            return "Error de red: \(error.localizedDescription)"
        case let .oauthFailed(reason):
            return "Fallo de autenticación: \(reason)"
        case .tokenRefreshFailed:
            return "No se pudo renovar la sesión. Vuelve a iniciar sesión."
        }
    }

    /// Indica si conviene forzar un logout (token inválido de forma permanente).
    var requiresReauth: Bool {
        switch self {
        case .notAuthenticated, .tokenRefreshFailed: return true
        default: return false
        }
    }
}
