//
//  APIStatusResponse.swift
//  Calefaccion Netatmo
//
//  Respuesta genérica de los endpoints de escritura (setroomthermpoint,
//  setthermmode, switchhomeschedule).
//

import Foundation

struct APIStatusResponse: Decodable {
    let status: String
    let timeExec: Double?
    let timeServer: TimeInterval?
}

/// Cuerpo de error estándar de la API de Netatmo.
struct NetatmoErrorResponse: Decodable {
    let error: NetatmoErrorBody?
}

struct NetatmoErrorBody: Decodable {
    let code: Int?
    let message: String?
}
