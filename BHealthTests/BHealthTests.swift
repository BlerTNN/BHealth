//
//  BHealthTests.swift
//  BHealthTests
//
//  Created by Bill on 2026-06-26.
//

import Testing
import Foundation
@testable import BHealth

struct BHealthTests {

    @Test func exactWeightRiceUsesDeterministicPath() async throws {
        var session = FoodConversationSession()
        let result = FoodConversationCoordinator().handle(
            userText: "早餐 250克熟米饭",
            mode: .foodLog,
            session: &session,
            referenceDate: Date(timeIntervalSince1970: 1_780_000_000)
        )

        #expect(result.shouldOfferSave)
        #expect(result.mealType == .breakfast)
        #expect(result.calculation?.items.first?.matchedFoodName == "熟米饭")
        #expect((result.calculation?.totalEnergyKcal ?? 0) > 300)
        #expect(result.calculation?.rangeLowKcal == result.calculation?.rangeHighKcal)
        #expect(result.calculation?.assumptions.contains { $0.contains("250g") } == true)
    }

    @Test func fuzzyMilletPorridgeAsksForMissingEvidenceBeforeEstimate() async throws {
        var session = FoodConversationSession()
        let result = FoodConversationCoordinator().handle(
            userText: "早餐我喝了一碗小米粥",
            mode: .foodLog,
            session: &session,
            referenceDate: Date(timeIntervalSince1970: 1_780_000_000)
        )

        #expect(!result.shouldOfferSave)
        #expect(result.calculation == nil)
        #expect(result.reply.contains("稀稠度"))
    }

    @Test func vagueMilletPorridgeAsksBeforeOfferingSave() async throws {
        var session = FoodConversationSession()
        let result = FoodConversationCoordinator().handle(
            userText: "一碗小米粥",
            mode: .foodLog,
            session: &session,
            referenceDate: Date(timeIntervalSince1970: 1_780_000_000)
        )

        #expect(!result.shouldOfferSave)
        #expect(result.calculation == nil)
        #expect(result.reply.contains("这是早餐"))
        #expect(!result.reply.contains("通用范围"))
        #expect(!result.reply.contains("算法"))
    }

    @Test func vagueFoodQuestionFollowsEnglishLanguage() async throws {
        var session = FoodConversationSession()
        let result = FoodConversationCoordinator().handle(
            userText: "一碗小米粥",
            mode: .foodLog,
            session: &session,
            referenceDate: Date(timeIntervalSince1970: 1_780_000_000),
            language: .english
        )

        #expect(!result.shouldOfferSave)
        #expect(result.reply.contains("Was this breakfast"))
        #expect(!result.reply.contains("这是早餐"))
    }

    @Test func assistantModeTitlesFollowLanguage() async throws {
        #expect(AssistantMode.foodLog.title(language: .english) == "Log Food")
        #expect(AssistantMode.foodLog.title(language: .chinese) == "记录饮食")
        #expect(AppLanguagePreference.system.title(language: .english) == "System")
    }

    @Test func directEstimateUsesWideProbabilisticRange() async throws {
        var session = FoodConversationSession()
        let result = FoodConversationCoordinator().handle(
            userText: "早餐一碗小米粥，不知道细节，直接估算",
            mode: .foodLog,
            session: &session,
            referenceDate: Date(timeIntervalSince1970: 1_780_000_000)
        )

        #expect(result.shouldOfferSave)
        let calculation = try #require(result.calculation)
        #expect(calculation.rangeHighKcal > calculation.rangeLowKcal)
        #expect(calculation.assumptions.contains { $0.contains("常见份量") })
        #expect(!calculation.assumptions.contains { $0.contains("先验") || $0.contains("配方原型") })
    }

    @Test func multiFoodEstimateKeepsConcreteFoodItems() async throws {
        var session = FoodConversationSession()
        let result = FoodConversationCoordinator().handle(
            userText: "早餐两个水煮蛋、一杯豆浆，不知道细节，直接估算",
            mode: .foodLog,
            session: &session,
            referenceDate: Date(timeIntervalSince1970: 1_780_000_000)
        )

        #expect(result.shouldOfferSave)
        let itemNames = result.calculation?.items.map(\.matchedFoodName) ?? []
        #expect(itemNames.contains("鸡蛋"))
        #expect(itemNames.contains("豆浆"))
    }

    @Test func openVocabularyChineseDishUsesUserPhraseAndRelativeDate() async throws {
        var session = FoodConversationSession()
        let referenceDate = Date(timeIntervalSince1970: 1_780_000_000)
        let result = FoodConversationCoordinator().handle(
            userText: "昨晚吃了一碗卤煮火烧",
            mode: .foodLog,
            session: &session,
            referenceDate: referenceDate
        )

        #expect(result.shouldOfferSave)
        #expect(result.mealType == .dinner)
        #expect(result.calculation?.foodDisplayName == "卤煮火烧")
        #expect((result.calculation?.totalEnergyKcal ?? 0) > 0)

        let expectedDay = Calendar.current.date(
            byAdding: .day,
            value: -1,
            to: Calendar.current.startOfDay(for: referenceDate)
        )
        #expect(result.consumedAt == expectedDay)
    }

    @Test func openVocabularyUnknownDishStillEstimatesInsteadOfRejecting() async throws {
        var session = FoodConversationSession()
        let result = FoodConversationCoordinator().handle(
            userText: "午餐吃了一份麻辣烫",
            mode: .foodLog,
            session: &session,
            referenceDate: Date(timeIntervalSince1970: 1_780_000_000)
        )

        #expect(result.shouldOfferSave)
        #expect(result.mealType == .lunch)
        #expect(result.calculation?.foodDisplayName == "麻辣烫")
        #expect(!result.reply.contains("我还没识别出具体食物"))
    }

}
