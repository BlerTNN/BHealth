//
//  AppText.swift
//  BHealth
//
//  Created by Codex on 2026-06-29.
//

import Foundation

enum AppText {
    static func text(_ chinese: String, _ english: String, language: AppLanguage) -> String {
        language == .chinese ? chinese : english
    }

    static func shortDate(_ value: Date, language: AppLanguage) -> String {
        value.formatted(.dateTime.locale(Locale(identifier: language.localeIdentifier)).year().month().day())
    }

    static func shortDateTime(_ value: Date, language: AppLanguage) -> String {
        value.formatted(.dateTime.locale(Locale(identifier: language.localeIdentifier)).year().month().day().hour().minute())
    }

    static func monthDayWeekday(_ value: Date, language: AppLanguage) -> String {
        value.formatted(.dateTime.locale(Locale(identifier: language.localeIdentifier)).month().day().weekday(.wide))
    }
}
