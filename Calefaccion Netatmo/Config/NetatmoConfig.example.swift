//
//  NetatmoConfig.example.swift
//  Calefaccion Netatmo
//
//  Plantilla de configuración de la app de Netatmo Connect (dev.netatmo.com).
//
//  USO: copia este archivo como `NetatmoConfig.swift` en esta misma carpeta y
//  rellena tus credenciales. `NetatmoConfig.swift` está en .gitignore y nunca
//  debe subirse al repositorio.
//
//      cp "Calefaccion Netatmo/Config/NetatmoConfig.example.swift" \
//         "Calefaccion Netatmo/Config/NetatmoConfig.swift"
//
//  Los valores aquí son solo el arranque por defecto: la app permite
//  sobreescribirlos en Ajustes, y entonces se guardan en el Keychain.
//

import Foundation

enum NetatmoConfig {
    /// client_id de tu app en dev.netatmo.com
    static let clientID = "TU_CLIENT_ID"

    /// client_secret de tu app en dev.netatmo.com
    static let clientSecret = "TU_CLIENT_SECRET"

    /// Debe coincidir EXACTAMENTE con la Redirect URI registrada en dev.netatmo.com
    static let redirectURI = "calefaccion-netatmo://oauth-callback"

    /// Esquema del callback usado por ASWebAuthenticationSession
    static let callbackURLScheme = "calefaccion-netatmo"

    /// Permisos solicitados para la API Energy
    static let scopes = ["read_thermostat", "write_thermostat"]

    static var scopeString: String { scopes.joined(separator: " ") }

    // MARK: - Endpoints base

    static let apiBaseURL = URL(string: "https://api.netatmo.com")!

    static var authorizeURL: URL { apiBaseURL.appendingPathComponent("oauth2/authorize") }
    static var tokenURL: URL { apiBaseURL.appendingPathComponent("oauth2/token") }

    /// `true` cuando el usuario todavía no ha rellenado sus credenciales.
    static var isPlaceholder: Bool {
        clientID == "TU_CLIENT_ID" || clientSecret == "TU_CLIENT_SECRET"
    }
}
