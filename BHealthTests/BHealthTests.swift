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

    @Test func assistantModeTitlesFollowLanguage() {
        #expect(AssistantMode.allCases.map(\.rawValue) == ["foodLog", "healthCoach"])
        #expect(AssistantMode.foodLog.title(language: .english) == "Log Food")
        #expect(AssistantMode.foodLog.title(language: .chinese) == "记录饮食")
        #expect(AssistantMode.foodLog.subtitle(language: .chinese).contains("补录"))
        #expect(AppLanguagePreference.system.title(language: .english) == "System")
    }

    @Test func assistantReplyParsesDirectAIEstimate() throws {
        let content = """
        {
          "reply": "我理解为午餐吃了一份麻辣烫，估计约 650 kcal，范围 520-820 kcal。请确认是否保存。",
          "assistant_state": "confirming",
          "confidence": "medium",
          "should_offer_save": true,
          "estimated_energy_kcal": 650,
          "energy_low_kcal": 520,
          "energy_high_kcal": 820,
          "meal_type": "lunch",
          "consumed_at": "2026-06-29",
          "food_items": ["麻辣烫"],
          "assumptions": ["按普通单人份估算"],
          "source_summary": "AI 推理估算"
        }
        """

        let reply = try AssistantAIReply.parse(from: content)
        #expect(reply.shouldOfferSave)
        #expect(reply.mealType == .lunch)
        #expect(reply.estimatedEnergyKcal == 650)

        let calculation = try #require(reply.estimatedCalculation(for: "午餐吃了一份麻辣烫"))
        #expect(calculation.totalEnergyKcal == 650)
        #expect(calculation.rangeLowKcal == 520)
        #expect(calculation.rangeHighKcal == 820)
        #expect(calculation.foodDisplayName == "麻辣烫")
    }

    @Test func assistantReplyParserAcceptsCommonModelJSONVariations() throws {
        let content = """
        ```json
        {
          "reply": "我先理解为午餐吃了一碗小米粥，约 180 kcal。",
          "assistant_state": "confirming",
          "confidence": "medium",
          "should_offer_save": "true",
          "estimated_energy_kcal": "180 kcal",
          "energy_low_kcal": "130",
          "energy_high_kcal": "240",
          "meal_type": "lunch",
          "consumed_at": "2026-06-29",
          "food_items": "小米粥",
          "assumptions": "按普通饭碗估算",
          "source_summary": null
        }
        ```
        """

        let reply = try AssistantAIReply.parse(from: content)
        #expect(reply.shouldOfferSave)
        #expect(reply.mealType == .lunch)
        #expect(reply.foodItems == ["小米粥"])
        #expect(reply.assumptions == ["按普通饭碗估算"])
        #expect(reply.estimatedEnergyKcal == 180)
    }

    @Test func assistantReplyFallsBackToPlainTextWhenModelSkipsJSON() {
        let reply = AssistantAIReply.parseOrFallback(
            from: "这是哪一餐？早餐、午餐还是晚餐？",
            language: .chinese
        )

        #expect(reply.reply == "这是哪一餐？早餐、午餐还是晚餐？")
        #expect(!reply.shouldOfferSave)
        #expect(reply.mealType == nil)
    }

    @Test func assistantReplyFallbackExtractsReplyFromMalformedJSON() {
        let content = """
        {
          "reply": "我理解为你昨晚吃了一碗卤煮火烧，大约 600-800 kcal。请确认是否保存。",
          "assistant_state": "confirming",
          "should_offer_save": tru
        """

        let reply = AssistantAIReply.parseOrFallback(from: content, language: .chinese)
        #expect(reply.reply == "我理解为你昨晚吃了一碗卤煮火烧，大约 600-800 kcal。请确认是否保存。")
        #expect(!reply.shouldOfferSave)
    }

    @Test func mealDateResolverHandlesRelativeDinnerDate() {
        let referenceDate = Date(timeIntervalSince1970: 1_780_000_000)
        let expectedDay = Calendar.current.date(
            byAdding: .day,
            value: -1,
            to: Calendar.current.startOfDay(for: referenceDate)
        )

        #expect(MealDateResolver.detectedDate(in: "昨晚吃了一碗卤煮火烧", referenceDate: referenceDate) == expectedDay)
    }
}
