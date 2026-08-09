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
            return String(localized: "Faltan las credenciales de Netatmo. Rellena NetatmoConfig con tu client_id y client_secret.")
        case .notAuthenticated:
            return String(localized: "No has iniciado sesión en Netatmo.")
        case .invalidResponse:
            return String(localized: "Respuesta inválida del servidor.")
        case let .httpError(status, code, message):
            let detail = message ?? String(localized: "sin detalle")
            if let code { return String(localized: "Error \(status) (código \(code)): \(detail)") }
            return String(localized: "Error HTTP \(status): \(detail)")
        case let .decoding(error):
            return String(localized: "No se pudieron interpretar los datos: \(error.localizedDescription)")
        case let .network(error):
            return String(localized: "Error de red: \(error.localizedDescription)")
        case let .oauthFailed(reason):
            return String(localized: "Fallo de autenticación: \(reason)")
        case .tokenRefreshFailed:
            return String(localized: "No se pudo renovar la sesión. Vuelve a iniciar sesión.")
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
