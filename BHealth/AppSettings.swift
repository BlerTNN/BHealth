//
//  AppSettings.swift
//  BHealth
//
//  Created by Codex on 2026-06-29.
//

import Combine
import Foundation
import SwiftUI

enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case english
    case chinese

    var localeIdentifier: String {
        switch self {
        case .english:
            return "en"
        case .chinese:
            return "zh-Hans"
        }
    }

    var aiInstructionName: String {
        switch self {
        case .english:
            return "English"
        case .chinese:
            return "简体中文"
        }
    }
}

enum AppLanguagePreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case english
    case chinese

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .system:
            return AppText.text("跟随系统", "System", language: language)
        case .english:
            return "English"
        case .chinese:
            return "中文"
        }
    }

    func subtitle(language: AppLanguage) -> String {
        switch self {
        case .system:
            return AppText.text("默认使用设备系统语言", "Use the device language by default", language: language)
        case .english:
            return AppText.text("固定显示英文", "Always show English", language: language)
        case .chinese:
            return AppText.text("固定显示中文", "Always show Chinese", language: language)
        }
    }

    var resolvedLanguage: AppLanguage {
        switch self {
        case .system:
            return Self.systemLanguage
        case .english:
            return .english
        case .chinese:
            return .chinese
        }
    }

    private static var systemLanguage: AppLanguage {
        let identifier = Locale.preferredLanguages.first ?? Locale.current.identifier
        return identifier.lowercased().hasPrefix("zh") ? .chinese : .english
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var languagePreference: AppLanguagePreference {
        didSet {
            UserDefaults.standard.set(languagePreference.rawValue, forKey: Self.languagePreferenceKey)
        }
    }

    private static let languagePreferenceKey = "BHealth.languagePreference.v1"

    init() {
        let storedValue = UserDefaults.standard.string(forKey: Self.languagePreferenceKey)
        languagePreference = storedValue.flatMap(AppLanguagePreference.init(rawValue:)) ?? .system
    }

    var resolvedLanguage: AppLanguage {
        languagePreference.resolvedLanguage
    }

    var locale: Locale {
        Locale(identifier: resolvedLanguage.localeIdentifier)
    }

    func text(_ chinese: String, _ english: String) -> String {
        AppText.text(chinese, english, language: resolvedLanguage)
    }
}
