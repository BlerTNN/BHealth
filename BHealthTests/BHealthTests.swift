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
        #expect(calculation.assumptions.contains { $0.contains("通用份量先验") })
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

}
