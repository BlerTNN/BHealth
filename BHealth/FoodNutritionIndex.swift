//
//  FoodNutritionIndex.swift
//  BHealth
//
//  Created by Codex on 2026-06-26.
//

import Foundation

struct FoodNutritionMetadata: Codable, Hashable {
    let sourceName: String
    let sourceType: String
    let sourceGrade: String
    let market: String
    let versionDate: String
    let retrievedAt: String
    let sourceUrl: String
    let licenseName: String
    let originalSha256: String
    let itemCount: Int
}

struct FoodNutritionItem: Codable, Hashable, Identifiable {
    let fdcId: Int
    let description: String
    let category: String
    let dataType: String
    let publicationDate: String
    let energySource: String
    let nutrientsPer100g: NutrientValues
    let portions: [FoodPortion]

    var id: Int { fdcId }
}

struct NutrientValues: Codable, Hashable {
    let energyKcalPer100g: Double
    let proteinGPer100g: Double?
    let fatGPer100g: Double?
    let carbohydrateGPer100g: Double?
    let fiberGPer100g: Double?
    let sugarGPer100g: Double?
}

struct FoodPortion: Codable, Hashable {
    let label: String
    let grams: Double
}

struct FoodSearchMatch: Hashable, Identifiable {
    let item: FoodNutritionItem
    let score: Double
    let query: String

    var id: Int { item.fdcId }
}

struct FoodMention: Hashable, Identifiable {
    let id = UUID()
    let rawText: String
    let query: String
}

struct MealItemCalculation: Codable, Hashable, Identifiable {
    let id: UUID
    let rawText: String
    let matchedFoodName: String
    let fdcId: Int
    let estimatedGrams: Double
    let energyKcal: Double
    let proteinG: Double?
    let fatG: Double?
    let carbohydrateG: Double?
    let confidence: String
    let sourceName: String
    let sourceVersion: String
    let assumptions: [String]

    init(
        id: UUID = UUID(),
        rawText: String,
        matchedFoodName: String,
        fdcId: Int,
        estimatedGrams: Double,
        energyKcal: Double,
        proteinG: Double?,
        fatG: Double?,
        carbohydrateG: Double?,
        confidence: String,
        sourceName: String,
        sourceVersion: String,
        assumptions: [String]
    ) {
        self.id = id
        self.rawText = rawText
        self.matchedFoodName = matchedFoodName
        self.fdcId = fdcId
        self.estimatedGrams = estimatedGrams
        self.energyKcal = energyKcal
        self.proteinG = proteinG
        self.fatG = fatG
        self.carbohydrateG = carbohydrateG
        self.confidence = confidence
        self.sourceName = sourceName
        self.sourceVersion = sourceVersion
        self.assumptions = assumptions
    }
}

struct MealCalculationResult: Codable, Hashable, Identifiable {
    let id: UUID
    let createdAt: Date
    let items: [MealItemCalculation]
    let totalEnergyKcal: Double
    let rangeLowKcal: Double
    let rangeHighKcal: Double
    let confidence: String
    let assumptions: [String]
    let sourceSummary: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        items: [MealItemCalculation],
        totalEnergyKcal: Double,
        rangeLowKcal: Double,
        rangeHighKcal: Double,
        confidence: String,
        assumptions: [String],
        sourceSummary: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.items = items
        self.totalEnergyKcal = totalEnergyKcal
        self.rangeLowKcal = rangeLowKcal
        self.rangeHighKcal = rangeHighKcal
        self.confidence = confidence
        self.assumptions = assumptions
        self.sourceSummary = sourceSummary
    }
}

enum MealFoodNameFormatter {
    nonisolated static func displayName(from items: [MealItemCalculation]) -> String {
        let names = items
            .map(\.displayFoodName)
            .filter { !$0.isEmpty && $0 != "饮食记录" }

        return joined(names, fallback: "饮食记录")
    }

    nonisolated static func displayName(from foodItems: [String]?, fallback: String) -> String {
        let names = (foodItems ?? [])
            .map(cleaned)
            .filter { !$0.isEmpty }

        if !names.isEmpty {
            return joined(names, fallback: cleaned(fallback))
        }

        let cleanedFallback = cleaned(fallback)
        return cleanedFallback.isEmpty ? "饮食记录" : cleanedFallback
    }

    nonisolated static func cleaned(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        if let separatorRange = text.range(of: "：") ?? text.range(of: ":") {
            let head = String(text[..<separatorRange.lowerBound])
            if head.contains("补录") || head.contains("记录") || head.contains("这一天") || head.contains("今天") || head.contains("昨天") || head.contains("前天") {
                text = String(text[separatorRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let prefixes = [
            "我早餐吃了", "我午餐吃了", "我晚餐吃了", "我早饭吃了", "我午饭吃了", "我晚饭吃了",
            "我昨晚吃了", "我今晚吃了", "昨晚吃了", "今晚吃了", "晚上吃了",
            "早餐吃了", "午餐吃了", "晚餐吃了", "早饭吃了", "午饭吃了", "晚饭吃了",
            "今天吃了", "昨天吃了", "昨日吃了", "前天吃了", "这一天吃了", "补录这一天", "补录昨天", "补录前天",
            "我吃了", "吃了", "补录", "记录"
        ]
        for prefix in prefixes where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        let suffixes = [
            "帮我估算一下热量", "帮我估算热量", "帮我算一下热量", "帮我算热量",
            "大概多少热量", "大概多少卡路里", "大概多少卡", "估算热量", "算热量",
            "多少热量", "多少卡路里", "多少卡", "是否确认保存"
        ]
        for suffix in suffixes where text.hasSuffix(suffix) {
            text.removeLast(suffix.count)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        text = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        return text
    }

    nonisolated private static func joined(_ names: [String], fallback: String) -> String {
        guard !names.isEmpty else { return fallback.isEmpty ? "饮食记录" : fallback }
        let visibleNames = Array(names.prefix(3))
        return visibleNames.joined(separator: "、") + (names.count > visibleNames.count ? "等" : "")
    }
}

extension MealItemCalculation {
    nonisolated var displayFoodName: String {
        let cleanedRawText = MealFoodNameFormatter.cleaned(rawText)
        if !cleanedRawText.isEmpty {
            return cleanedRawText
        }

        let cleanedMatch = MealFoodNameFormatter.cleaned(matchedFoodName)
        if !cleanedMatch.isEmpty && cleanedMatch != "AI 推理估算" {
            return cleanedMatch
        }

        return "饮食记录"
    }
}

extension MealCalculationResult {
    nonisolated var foodDisplayName: String {
        MealFoodNameFormatter.displayName(from: items)
    }
}

enum MealType: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case breakfast
    case lunch
    case dinner
    case afternoonTea
    case snack
    case lateNight
    case other

    var id: String { rawValue }

    var title: String {
        title(language: .chinese)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .breakfast:
            return AppText.text("早餐", "Breakfast", language: language)
        case .lunch:
            return AppText.text("午餐", "Lunch", language: language)
        case .dinner:
            return AppText.text("晚餐", "Dinner", language: language)
        case .afternoonTea:
            return AppText.text("下午茶", "Afternoon tea", language: language)
        case .snack:
            return AppText.text("加餐/零食", "Snack", language: language)
        case .lateNight:
            return AppText.text("夜宵", "Late night", language: language)
        case .other:
            return AppText.text("其他", "Other", language: language)
        }
    }

    static func detected(in text: String) -> MealType? {
        let normalized = text
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()

        let rules: [(MealType, [String])] = [
            (.breakfast, ["早餐", "早饭", "早上", "breakfast"]),
            (.lunch, ["午餐", "午饭", "中饭", "中午", "lunch"]),
            (.afternoonTea, ["下午茶", "茶点", "afternoon tea"]),
            (.lateNight, ["夜宵", "宵夜", "late night"]),
            (.dinner, ["晚餐", "晚饭", "晚上", "今晚", "昨晚", "dinner", "supper"]),
            (.snack, ["加餐", "零食", "小食", "snack"]),
            (.other, ["其他"])
        ]

        return rules.first { _, tokens in
            tokens.contains { normalized.contains($0) }
        }?.0
    }

    static func fromAssistantValue(_ value: String?) -> MealType? {
        guard let value else { return nil }
        let normalized = value
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch normalized {
        case "breakfast", "早餐", "早饭":
            return .breakfast
        case "lunch", "午餐", "午饭", "中饭":
            return .lunch
        case "dinner", "晚餐", "晚饭":
            return .dinner
        case "afternoon_tea", "afternoontea", "下午茶":
            return .afternoonTea
        case "snack", "snacks", "加餐", "零食", "加餐_零食":
            return .snack
        case "late_night", "latenight", "夜宵", "宵夜":
            return .lateNight
        case "other", "其他":
            return .other
        default:
            return detected(in: normalized)
        }
    }
}

struct SavedMealRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let confirmedAt: Date
    let consumedAt: Date
    let mealType: MealType
    let calculation: MealCalculationResult

    init(
        id: UUID = UUID(),
        confirmedAt: Date = Date(),
        consumedAt: Date,
        mealType: MealType,
        calculation: MealCalculationResult
    ) {
        self.id = id
        self.confirmedAt = confirmedAt
        self.consumedAt = consumedAt
        self.mealType = mealType
        self.calculation = calculation
    }

    enum CodingKeys: String, CodingKey {
        case id
        case confirmedAt
        case consumedAt
        case mealType
        case calculation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        confirmedAt = try container.decode(Date.self, forKey: .confirmedAt)
        consumedAt = try container.decodeIfPresent(Date.self, forKey: .consumedAt) ?? confirmedAt
        mealType = try container.decodeIfPresent(MealType.self, forKey: .mealType) ?? .other
        calculation = try container.decode(MealCalculationResult.self, forKey: .calculation)
    }
}

final class FoodNutritionIndex {
    static let shared = FoodNutritionIndex()

    let metadata: FoodNutritionMetadata
    let foods: [FoodNutritionItem]

    private init() {
        do {
            guard let url = Bundle.main.url(forResource: "FoodNutritionIndex", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }

            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(FoodNutritionPayload.self, from: data)
            metadata = payload.metadata
            foods = payload.foods
        } catch {
            metadata = FoodNutritionMetadata(
                sourceName: "USDA FoodData Central Foundation Foods",
                sourceType: "government_food_database",
                sourceGrade: "B",
                market: "US",
                versionDate: "unknown",
                retrievedAt: "unknown",
                sourceUrl: "https://fdc.nal.usda.gov/download-datasets",
                licenseName: "USDA FoodData Central public domain",
                originalSha256: "",
                itemCount: 0
            )
            foods = []
        }
    }

    func search(query: String, limit: Int = 5) -> [FoodSearchMatch] {
        let expandedQuery = FoodQueryNormalizer.expandedSearchText(for: query)
        let queryTokens = FoodQueryNormalizer.tokens(from: expandedQuery)
        guard !queryTokens.isEmpty else { return [] }

        return foods.compactMap { item -> FoodSearchMatch? in
            let searchableText = "\(item.description) \(item.category)"
            let normalizedText = FoodQueryNormalizer.normalized(searchableText)
            let nameTokens = Set(FoodQueryNormalizer.tokens(from: searchableText))
            var score = 0.0

            for token in queryTokens {
                if nameTokens.contains(token) {
                    score += 3.0
                } else if normalizedText.contains(token) {
                    score += 1.1
                }
            }

            if normalizedText.contains(expandedQuery) {
                score += 4.0
            }

            if item.description.localizedCaseInsensitiveContains(query) {
                score += 2.0
            }

            guard score > 0 else { return nil }
            return FoodSearchMatch(item: item, score: score, query: query)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.item.description < rhs.item.description
            }
            return lhs.score > rhs.score
        }
        .prefix(limit)
        .map { $0 }
    }
}

struct FoodMentionExtractor {
    static func mentions(from text: String) -> [FoodMention] {
        let whole = cleaned(text)
        if shouldKeepAsCompositeMeal(whole) {
            let composite = strippedNonFoodNoise(whole)
            if isMeaningfulFoodFragment(composite) {
                return [FoodMention(rawText: composite, query: FoodQueryNormalizer.expandedSearchText(for: composite))]
            }
        }

        let separators = CharacterSet(charactersIn: "，,、;；\n")
        let roughParts = text
            .components(separatedBy: separators)
            .flatMap { $0.components(separatedBy: "和") }
            .flatMap { $0.components(separatedBy: "以及") }
            .flatMap { $0.components(separatedBy: "还有") }
            .map { cleaned($0) }
            .map { strippedNonFoodNoise($0) }
            .filter { isMeaningfulFoodFragment($0) }

        let parts = roughParts.isEmpty ? [strippedNonFoodNoise(cleaned(text))] : roughParts
            .filter { isMeaningfulFoodFragment($0) }
        return parts.map { FoodMention(rawText: $0, query: FoodQueryNormalizer.expandedSearchText(for: $0)) }
    }

    private static func cleaned(_ value: String) -> String {
        MealFoodNameFormatter.cleaned(value)
    }

    private static func shouldKeepAsCompositeMeal(_ value: String) -> Bool {
        let normalized = value.lowercased()
        let compositeMarkers = ["能量碗", "沙拉碗", "energy bowl", "poke bowl"]
        return compositeMarkers.contains { normalized.contains($0) }
    }

    private static func strippedNonFoodNoise(_ value: String) -> String {
        var text = value
        let patterns = [
            #"\d{4}[-/\.]\d{1,2}[-/\.]\d{1,2}"#,
            #"\d{1,2}月\d{1,2}[日号]?"#,
            #"\d+(?:\.\d+)?\s*(?:kcal|千卡|大卡|卡路里)"#,
            #"(?:已记录|已保存|待确认记录|待确认|请确认是否正确|请确认|如果正确|系统将估算热量并保存|系统将|保存记录)"#
        ]
        for pattern in patterns {
            text = replacingMatches(in: text, pattern: pattern, with: "")
        }
        return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func isMeaningfulFoodFragment(_ value: String) -> Bool {
        let text = value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        guard text.count >= 2 else { return false }

        let lower = text.lowercased()
        let rejectedPatterns = [
            #"^\d{4}[-/\.]\d{1,2}[-/\.]\d{1,2}$"#,
            #"^\d{1,2}[-/\.]\d{1,2}$"#,
            #"^\d{1,2}月\d{1,2}[日号]?$"#,
            #"^\d+(?:\.\d+)?\s*(?:kcal|千卡|大卡|卡路里)$"#
        ]
        if rejectedPatterns.contains(where: { lower.range(of: $0, options: .regularExpression) != nil }) {
            return false
        }

        let administrativePhrases = [
            "已记录", "已保存", "待确认", "请确认", "如果正确", "系统将", "估算热量并保存"
        ]
        if administrativePhrases.contains(where: { text.contains($0) }) {
            return false
        }

        return text.contains { !$0.isNumber && !$0.isWhitespace && $0 != "-" && $0 != "/" && $0 != "." }
    }

    private static func replacingMatches(in text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }
}

struct MealNutritionCalculator {
    let index: FoodNutritionIndex

    init(index: FoodNutritionIndex = .shared) {
        self.index = index
    }

    func calculate(from userText: String, language: AppLanguage = .chinese) -> MealCalculationResult? {
        let mentions = FoodMentionExtractor.mentions(from: userText)
        var calculations: [MealItemCalculation] = []
        var assumptions = Set<String>()

        for mention in mentions {
            guard let match = index.search(query: mention.query, limit: 1).first, match.score >= 3.0 else {
                assumptions.insert(AppText.text("还没能可靠识别“\(mention.rawText)”，暂不把它计入估算。", "I could not reliably identify \"\(mention.rawText)\", so it was not included in this estimate.", language: language))
                continue
            }

            let quantity = FoodQuantityEstimator.estimateGrams(for: match.item, from: mention.rawText, language: language)
            let factor = quantity.grams / 100.0
            let nutrients = match.item.nutrientsPer100g
            let energy = nutrients.energyKcalPer100g * factor
            let confidence = confidenceLabel(for: match.score, quantity: quantity)
            let itemAssumptions = quantity.assumptions + [
                AppText.text("参考常见的 \(match.item.description) 营养信息估算。", "Estimated using common nutrition information for \(match.item.description).", language: language)
            ]

            itemAssumptions.forEach { assumptions.insert($0) }

            calculations.append(
                MealItemCalculation(
                    rawText: mention.rawText,
                    matchedFoodName: match.item.description,
                    fdcId: match.item.fdcId,
                    estimatedGrams: quantity.grams,
                    energyKcal: energy,
                    proteinG: nutrients.proteinGPer100g.map { $0 * factor },
                    fatG: nutrients.fatGPer100g.map { $0 * factor },
                    carbohydrateG: nutrients.carbohydrateGPer100g.map { $0 * factor },
                    confidence: confidence,
                    sourceName: index.metadata.sourceName,
                    sourceVersion: index.metadata.versionDate,
                    assumptions: itemAssumptions
                )
            )
        }

        guard !calculations.isEmpty else { return nil }

        let totalEnergy = calculations.reduce(0) { $0 + $1.energyKcal }
        let confidence = calculations.contains { $0.confidence == "low" } ? "low" : "medium"
        let spread = confidence == "low" ? 0.28 : 0.18
        let allAssumptions = Array(assumptions).sorted()

        return MealCalculationResult(
            items: calculations,
            totalEnergyKcal: totalEnergy,
            rangeLowKcal: max(0, totalEnergy * (1 - spread)),
            rangeHighKcal: totalEnergy * (1 + spread),
            confidence: confidence,
            assumptions: allAssumptions,
            sourceSummary: "\(index.metadata.sourceName) \(index.metadata.versionDate)"
        )
    }

    private func confidenceLabel(for score: Double, quantity: QuantityEstimate) -> String {
        if score >= 8.0, quantity.isExplicit {
            return "medium"
        }
        return "low"
    }
}

struct QuantityEstimate: Hashable {
    let grams: Double
    let isExplicit: Bool
    let assumptions: [String]
}

enum FoodQuantityEstimator {
    static func estimateGrams(for item: FoodNutritionItem, from text: String, language: AppLanguage = .chinese) -> QuantityEstimate {
        if let explicitGrams = explicitGramAmount(in: text) {
            return QuantityEstimate(
                grams: explicitGrams,
                isExplicit: true,
                assumptions: [AppText.text("按用户提供的 \(format(explicitGrams))g 计算。", "Calculated from the provided \(format(explicitGrams))g.", language: language)]
            )
        }

        let amount = numericAmount(in: text)
        let lower = text.lowercased()

        if lower.contains("杯") || lower.contains("cup") {
            let grams = portion(containing: "cup", in: item)?.grams ?? 240
            return QuantityEstimate(
                grams: grams * amount,
                isExplicit: false,
                assumptions: [AppText.text("未提供克重，按 \(format(amount)) 杯约 \(format(grams * amount))g 估算。", "No exact weight was provided; estimated \(format(amount)) cup(s) as about \(format(grams * amount))g.", language: language)]
            )
        }

        if lower.contains("片") || lower.contains("slice") {
            let grams = portion(containing: "slice", in: item)?.grams ?? 30
            return QuantityEstimate(
                grams: grams * amount,
                isExplicit: false,
                assumptions: [AppText.text("未提供克重，按 \(format(amount)) 片约 \(format(grams * amount))g 估算。", "No exact weight was provided; estimated \(format(amount)) slice(s) as about \(format(grams * amount))g.", language: language)]
            )
        }

        if lower.contains("个") || lower.contains("颗") || lower.contains("只") || lower.contains("piece") || lower.contains("egg") {
            let grams = item.portions.first?.grams ?? 100
            return QuantityEstimate(
                grams: grams * amount,
                isExplicit: false,
                assumptions: [AppText.text("未提供克重，按 \(format(amount)) 个常见份量约 \(format(grams * amount))g 估算。", "No exact weight was provided; estimated \(format(amount)) common piece(s) as about \(format(grams * amount))g.", language: language)]
            )
        }

        if let portion = item.portions.first {
            return QuantityEstimate(
                grams: portion.grams * amount,
                isExplicit: false,
                assumptions: [AppText.text("未提供克重，按 \(format(amount)) 份 \(portion.label) 约 \(format(portion.grams * amount))g 估算。", "No exact weight was provided; estimated \(format(amount)) serving(s) as about \(format(portion.grams * amount))g.", language: language)]
            )
        }

        return QuantityEstimate(
            grams: 100 * amount,
            isExplicit: false,
            assumptions: [AppText.text("未提供克重或标准份量，暂按 \(format(100 * amount))g 估算。", "No exact weight or standard portion was provided; estimated about \(format(100 * amount))g.", language: language)]
        )
    }

    private static func explicitGramAmount(in text: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)\s*(g|克|克重)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[valueRange])
    }

    private static func numericAmount(in text: String) -> Double {
        let pattern = #"(\d+(?:\.\d+)?)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
           let valueRange = Range(match.range(at: 1), in: text),
           let value = Double(text[valueRange]) {
            return text.contains("半") ? value * 0.5 : value
        }

        if text.contains("半") { return 0.5 }
        if text.contains("两") || text.contains("二") { return 2 }
        if text.contains("三") { return 3 }
        if text.contains("四") { return 4 }
        return 1
    }

    private static func portion(containing token: String, in item: FoodNutritionItem) -> FoodPortion? {
        item.portions.first { $0.label.localizedCaseInsensitiveContains(token) }
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }
}

enum FoodQueryNormalizer {
    private static let zhToEnglish: [(String, String)] = [
        ("鸡胸肉", "chicken breast"),
        ("鸡肉", "chicken"),
        ("鸡蛋", "egg whole"),
        ("蛋白", "egg white"),
        ("蛋黄", "egg yolk"),
        ("鸡腿", "chicken drumstick"),
        ("牛肉", "beef"),
        ("猪肉", "pork"),
        ("培根", "bacon"),
        ("火腿", "ham"),
        ("米饭", "rice"),
        ("炒饭", "fried rice"),
        ("面包", "bread"),
        ("吐司", "bread"),
        ("牛奶", "milk"),
        ("拿铁", "milk"),
        ("咖啡", "coffee"),
        ("酸奶", "yogurt"),
        ("芝士", "cheese"),
        ("奶酪", "cheese"),
        ("苹果", "apple"),
        ("香蕉", "banana"),
        ("番茄", "tomato"),
        ("西红柿", "tomato"),
        ("生菜", "lettuce"),
        ("土豆", "potato"),
        ("红薯", "sweet potato"),
        ("杏仁", "almond"),
        ("三文鱼", "salmon"),
        ("沙拉", "lettuce tomato"),
        ("鹰嘴豆泥", "hummus")
    ]

    static func expandedSearchText(for text: String) -> String {
        var expanded = text
        for (zh, english) in zhToEnglish where text.contains(zh) {
            expanded += " \(english)"
        }
        return normalized(expanded)
    }

    static func normalized(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\p{Han}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func tokens(from text: String) -> [String] {
        normalized(text)
            .split(separator: " ")
            .map(String.init)
            .filter { token in
                token.count > 1 && !stopWords.contains(token)
            }
    }

    private static let stopWords: Set<String> = [
        "the", "and", "with", "without", "raw", "cooked", "prepared", "我", "吃了", "一个", "一杯", "一片"
    ]
}

private struct FoodNutritionPayload: Codable {
    let metadata: FoodNutritionMetadata
    let foods: [FoodNutritionItem]
}
