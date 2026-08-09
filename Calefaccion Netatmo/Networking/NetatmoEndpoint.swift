//
//  NetatmoEndpoint.swift
//  Calefaccion Netatmo
//
//  Rutas de la API Energy de Netatmo.
//

import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

enum NetatmoEndpoint {
    static let homesData = "/api/homesdata"
    static let homeStatus = "/api/homestatus"
    static let setRoomThermpoint = "/api/setroomthermpoint"
    static let setThermMode = "/api/setthermmode"
    static let switchHomeSchedule = "/api/switchhomeschedule"
    static let syncHomeSchedule = "/api/synchomeschedule"
    static let createNewHomeSchedule = "/api/createnewhomeschedule"
    static let renameHomeSchedule = "/api/renamehomeschedule"
    static let deleteHomeSchedule = "/api/deletehomeschedule"
    static let getRoomMeasure = "/api/getroommeasure"
}
