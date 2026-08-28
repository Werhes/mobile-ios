//
//  AppTab.swift
//  OpenVK for iOS
//

import Foundation

enum AppTab: Int, CaseIterable, Identifiable {
    case feed, search, music, messages, more

    var id: Int { rawValue }

    var icon: String {
        switch self {
        case .feed:     return "house"
        case .search:   return "magnifyingglass"
        case .music:    return "music.note"
        case .messages: return "message"
        case .more:     return "square.grid.2x2"
        }
    }

    var iconFilled: String {
        switch self {
        case .feed:     return "house.fill"
        case .search:   return "magnifyingglass"
        case .music:    return "music.note"
        case .messages: return "message.fill"
        case .more:     return "square.grid.2x2"
        }
    }

    var label: String {
        switch self {
        case .feed:     return "Лента"
        case .search:   return "Поиск"
        case .music:    return "Музыка"
        case .messages: return "Сообщения"
        case .more:     return "Прочее"
        }
    }
}
