//
//  ProbabilisticFoodEstimator.swift
//  BHealth
//
//  Created by Codex on 2026-06-27.
//

import Foundation

struct FoodConversationCoordinator {
    private let parser = FoodEventParser()
    private let missingAnalyzer = MissingEvidenceAnalyzer()
    private let questionSelector = QuestionSelectionEngine()
    private let estimator = CalorieMonteCarloEstimator()
    private let explanationBuilder = MealExplanationBuilder()

    func handle(
        userText: String,
        mode: AssistantMode,
        session: inout FoodConversationSession,
        referenceDate: Date
    ) -> FoodAssistantTurnResult {
        session.turnCount += 1
        let drafts = parser.parse(
            userText: userText,
            mode: mode,
            existingDrafts: session.drafts,
            referenceDate: referenceDate
        )
        session.drafts = drafts

        guard !drafts.isEmpty else {
            return FoodAssistantTurnResult(
                reply: "我还没识别出具体食物。可以直接告诉我食物名称和大概份量，比如“一碗小米粥”或“250克熟米饭”。",
                calculation: nil,
                mealType: nil,
                consumedAt: nil,
                shouldOfferSave: false
            )
        }

        let unresolved = drafts.flatMap { missingAnalyzer.unresolvedFields(for: $0, mode: mode) }
        let selectedQuestions = questionSelector.questions(
            for: unresolved,
            session: session,
            drafts: drafts
        )

        if !selectedQuestions.isEmpty {
            selectedQuestions.map(\.field).forEach { session.askedFields.append($0) }
            session.drafts = drafts.map { draft in
                var updated = draft
                updated.questionCount += 1
                updated.unresolvedFields = missingAnalyzer.unresolvedFields(for: updated, mode: mode)
                return updated
            }

            let questionText = selectedQuestions.map(\.text).joined(separator: "\n")
            return FoodAssistantTurnResult(
                reply: "\(questionText)\n\n也可以说“不知道”或“直接估算”，我会用更宽的通用范围计算。",
                calculation: nil,
                mealType: drafts.first?.mealType,
                consumedAt: drafts.first?.consumedAt,
                shouldOfferSave: false
            )
        }

        do {
            let result = try estimator.estimateMeal(drafts: drafts, sampleCount: 4_000)
            let calculation = result.calculation
            let reply = explanationBuilder.confirmationReply(
                calculation: calculation,
                itemEstimates: result.itemEstimates,
                mealType: drafts.first?.mealType,
                consumedAt: drafts.first?.consumedAt
            )
            return FoodAssistantTurnResult(
                reply: reply,
                calculation: calculation,
                mealType: drafts.first?.mealType,
                consumedAt: drafts.first?.consumedAt,
                shouldOfferSave: true
            )
        } catch {
            return FoodAssistantTurnResult(
                reply: "这次信息还不足以做可靠估算：\(error.localizedDescription)",
                calculation: nil,
                mealType: drafts.first?.mealType,
                consumedAt: drafts.first?.consumedAt,
                shouldOfferSave: false
            )
        }
    }
}

private struct FoodEventParser {
    private let ontology = FoodOntologyRepository()

    func parse(
        userText: String,
        mode: AssistantMode,
        existingDrafts: [FoodEventDraft],
        referenceDate: Date
    ) -> [FoodEventDraft] {
        let quickEstimate = userText.contains("直接估算") || userText.contains("不知道") || userText.contains("不记得")
        let detectedMealType = MealType.detected(in: userText) ?? existingDrafts.first?.mealType
        let detectedDate = consumedAt(for: mode, userText: userText, existingDrafts: existingDrafts, referenceDate: referenceDate)
        let globalEvidence = commonEvidence(from: userText)
        let fragments = FoodMentionExtractor.mentions(from: userText)
            .map(\.rawText)
            .filter { !$0.isEmpty }

        var newDrafts = fragments
            .compactMap { draft(from: $0, wholeMessage: userText, mealType: detectedMealType, consumedAt: detectedDate, quickEstimate: quickEstimate) }

        if newDrafts.isEmpty, !existingDrafts.isEmpty {
            newDrafts = existingDrafts.map { draft in
                merge(globalText: userText, into: draft, mealType: detectedMealType, consumedAt: detectedDate, quickEstimate: quickEstimate)
            }
        }

        if newDrafts.isEmpty,
           let draft = draft(from: userText, wholeMessage: userText, mealType: detectedMealType, consumedAt: detectedDate, quickEstimate: quickEstimate) {
            newDrafts = [draft]
        }

        return newDrafts.map { draft in
            var updated = draft
            updated.evidence.append(contentsOf: globalEvidence)
            updated.unresolvedFields = []
            return updated
        }
    }

    private func draft(
        from fragment: String,
        wholeMessage: String,
        mealType: MealType?,
        consumedAt: Date?,
        quickEstimate: Bool
    ) -> FoodEventDraft? {
        let candidates = ontology.resolve(fragment)
        guard let best = candidates.first else { return nil }

        var draft = FoodEventDraft(
            rawText: fragment,
            mealType: mealType,
            consumedAt: consumedAt,
            foodCandidates: candidates,
            selectedFoodID: best.confidence >= 0.72 ? best.foodID : nil,
            foodCategory: best.confidence >= 0.72 ? best.category : nil,
            explicitServingCount: servingCount(in: fragment),
            userRequestedQuickEstimate: quickEstimate
        )
        apply(text: "\(fragment) \(wholeMessage)", to: &draft)
        draft.evidence.append(
            FoodEvidence(
                field: "food_identity",
                normalizedValue: best.displayName,
                source: .databaseMatch,
                confidence: best.confidence,
                userVisibleDescription: "识别为\(best.displayName)"
            )
        )
        return draft
    }

    private func merge(
        globalText: String,
        into draft: FoodEventDraft,
        mealType: MealType?,
        consumedAt: Date?,
        quickEstimate: Bool
    ) -> FoodEventDraft {
        var updated = draft
        updated.mealType = mealType ?? updated.mealType
        updated.consumedAt = consumedAt ?? updated.consumedAt
        updated.userRequestedQuickEstimate = updated.userRequestedQuickEstimate || quickEstimate
        apply(text: globalText, to: &updated)
        return updated
    }

    private func apply(text: String, to draft: inout FoodEventDraft) {
        let normalized = text.lowercased()
        if let grams = explicitGrams(in: normalized) {
            draft.exactWeightGrams = grams
            draft.evidence.append(evidence("exact_weight_g", "\(Int(grams))g", "用户提供 \(Int(grams))g"))
        }

        if draft.containerClass == nil || draft.containerClass == .unknown {
            draft.containerClass = container(in: normalized)
        }
        if draft.fillLevel == nil || draft.fillLevel == .unknown {
            draft.fillLevel = fillLevel(in: normalized)
        }
        if draft.consistencyClass == nil || draft.consistencyClass == .unknown {
            draft.consistencyClass = consistency(in: normalized)
        }
        if draft.consumedFraction == nil || draft.consumedFraction == .unknown {
            draft.consumedFraction = consumedFraction(in: normalized)
        }
        if draft.preparationMethod == nil || draft.preparationMethod == .unknown {
            draft.preparationMethod = preparation(in: normalized)
        }

        additions(in: normalized).forEach { addition in
            if !draft.additions.contains(addition) {
                draft.additions.append(addition)
            }
        }
        exclusions(in: normalized).forEach { exclusion in
            if !draft.exclusions.contains(exclusion) {
                draft.exclusions.append(exclusion)
            }
        }
    }

    private func commonEvidence(from text: String) -> [FoodEvidence] {
        var evidenceItems: [FoodEvidence] = []
        if let container = container(in: text), container != .unknown {
            evidenceItems.append(evidence("container_class", container.rawValue, "容器：\(container.displayName)"))
        }
        if let fill = fillLevel(in: text), fill != .unknown {
            evidenceItems.append(evidence("fill_level", fill.rawValue, "装满程度：\(fill.displayName)"))
        }
        if let consistency = consistency(in: text), consistency != .unknown {
            evidenceItems.append(evidence("consistency", consistency.rawValue, "稀稠度：\(consistency.displayName)"))
        }
        if text.contains("无糖") || text.contains("没加糖") || text.contains("不加糖") {
            evidenceItems.append(evidence("high_calorie_additions", "no_sugar", "未加糖"))
        }
        return evidenceItems
    }

    private func consumedAt(
        for mode: AssistantMode,
        userText: String,
        existingDrafts: [FoodEventDraft],
        referenceDate: Date
    ) -> Date? {
        switch mode {
        case .foodLog:
            return Calendar.current.startOfDay(for: referenceDate)
        case .historicalFoodLog:
            return MealDateResolver.detectedDate(in: userText, referenceDate: referenceDate) ?? existingDrafts.first?.consumedAt
        case .healthCoach:
            return nil
        }
    }

    private func evidence(_ field: String, _ value: String, _ description: String) -> FoodEvidence {
        FoodEvidence(
            field: field,
            normalizedValue: value,
            source: .explicitUserStatement,
            confidence: 0.95,
            userVisibleDescription: description
        )
    }

    private func explicitGrams(in text: String) -> Double? {
        firstNumber(in: text, pattern: #"(\d+(?:\.\d+)?)\s*(g|克)"#)
    }

    private func servingCount(in text: String) -> Double {
        if let value = firstNumber(in: text, pattern: #"(\d+(?:\.\d+)?)\s*(个|颗|只|杯|碗|片|份)"#) {
            return value
        }
        if text.contains("半") { return 0.5 }
        if text.contains("两") || text.contains("二") { return 2 }
        if text.contains("三") { return 3 }
        if text.contains("四") { return 4 }
        return 1
    }

    private func firstNumber(in text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[valueRange])
    }

    private func container(in text: String) -> ContainerClass? {
        if text.contains("大汤碗") || text.contains("大碗") { return .largeSoupBowl }
        if text.contains("小饭碗") || text.contains("小碗") { return .smallRiceBowl }
        if text.contains("普通碗") || text.contains("饭碗") || text.contains("一碗") { return .regularRiceBowl }
        if text.contains("大杯") || text.contains("马克杯") { return .largeMug }
        if text.contains("小杯") { return .smallCup }
        if text.contains("杯") { return .regularCup }
        if text.contains("汤匙") || text.contains("大勺") { return .tablespoon }
        if text.contains("茶匙") || text.contains("小勺") { return .teaspoon }
        if text.contains("一把") || text.contains("把") { return .handful }
        if text.contains("片") { return .slice }
        if text.contains("个") || text.contains("颗") || text.contains("只") { return .piece }
        return nil
    }

    private func fillLevel(in text: String) -> FillLevel? {
        if text.contains("半") { return .half }
        if text.contains("七八分") || text.contains("八分") { return .eightyPercent }
        if text.contains("大半") { return .threeQuarters }
        if text.contains("快满") || text.contains("接近满") { return .nearlyFull }
        if text.contains("满") { return .full }
        return nil
    }

    private func consistency(in text: String) -> ConsistencyClass? {
        if text.contains("很稀") { return .veryThin }
        if text.contains("偏稀") || text.contains("稀") { return .thin }
        if text.contains("很稠") { return .veryThick }
        if text.contains("偏稠") || text.contains("稠") { return .thick }
        if text.contains("普通") || text.contains("正常") { return .regular }
        return nil
    }

    private func consumedFraction(in text: String) -> ConsumedFraction? {
        if text.contains("喝完") || text.contains("吃完") || text.contains("全吃") || text.contains("都吃") { return .all }
        if text.contains("吃了一半") || text.contains("喝了一半") { return .half }
        if text.contains("大部分") || text.contains("基本") { return .most }
        return nil
    }

    private func preparation(in text: String) -> PreparationMethod? {
        if text.contains("水煮") || text.contains("煮") { return .boiled }
        if text.contains("煎") || text.contains("炒") { return .fried }
        if text.contains("蒸") { return .steamed }
        return nil
    }

    private func additions(in text: String) -> [FoodAddition] {
        var additions: [FoodAddition] = []
        if text.contains("加糖") || text.contains("勺糖") || text.contains("白糖") { additions.append(.sugar) }
        if text.contains("牛奶") { additions.append(.milk) }
        if text.contains("炼乳") { additions.append(.condensedMilk) }
        if text.contains("油") { additions.append(.oil) }
        if text.contains("酱") { additions.append(.sauce) }
        return additions
    }

    private func exclusions(in text: String) -> [FoodExclusion] {
        var exclusions: [FoodExclusion] = []
        if text.contains("无糖") || text.contains("没加糖") || text.contains("不加糖") { exclusions.append(.noSugar) }
        if text.contains("没加奶") || text.contains("不加奶") { exclusions.append(.noMilk) }
        if text.contains("少油") || text.contains("没油") || text.contains("不放油") { exclusions.append(.noOil) }
        return exclusions
    }
}

private struct MissingEvidenceAnalyzer {
    func unresolvedFields(for draft: FoodEventDraft, mode: AssistantMode) -> [FoodField] {
        var fields: [FoodField] = []
        if mode.supportsMealSaving, draft.mealType == nil {
            fields.append(.mealType)
        }
        if mode == .historicalFoodLog, draft.consumedAt == nil {
            fields.append(.consumedAt)
        }
        if draft.selectedFoodID == nil {
            fields.append(.foodIdentity)
            return fields
        }
        if draft.userRequestedQuickEstimate || draft.exactWeightGrams != nil {
            return fields + spoonTypeIfNeeded(for: draft)
        }

        switch draft.foodCategory ?? .unknown {
        case .porridge:
            if draft.consistencyClass == nil || draft.consistencyClass == .unknown { fields.append(.consistency) }
            if draft.containerClass == nil || draft.containerClass == .unknown { fields.append(.containerClass) }
            if draft.fillLevel == nil || draft.fillLevel == .unknown { fields.append(.fillLevel) }
            if draft.additions.isEmpty, draft.exclusions.isEmpty { fields.append(.highCalorieAdditions) }
        case .cookedRice, .beverage:
            if draft.containerClass == nil || draft.containerClass == .unknown { fields.append(.containerClass) }
            if draft.fillLevel == nil || draft.fillLevel == .unknown { fields.append(.fillLevel) }
        case .homeDish:
            fields.append(.containerClass)
            fields.append(.consumedFraction)
            fields.append(.highCalorieAdditions)
        case .egg, .bakery, .fruit, .nut, .noodle, .soup, .unknown:
            break
        }

        return fields + spoonTypeIfNeeded(for: draft)
    }

    private func spoonTypeIfNeeded(for draft: FoodEventDraft) -> [FoodField] {
        guard draft.additions.contains(.sugar),
              draft.rawText.contains("勺"),
              draft.containerClass != .teaspoon,
              draft.containerClass != .tablespoon else {
            return []
        }
        return [.spoonType]
    }
}

private struct QuestionSelectionEngine {
    struct Question {
        let field: FoodField
        let text: String
    }

    func questions(
        for unresolvedFields: [FoodField],
        session: FoodConversationSession,
        drafts: [FoodEventDraft]
    ) -> [Question] {
        let uniqueFields = orderedUnique(unresolvedFields)
        let forced = uniqueFields.filter { $0 == .mealType || $0 == .consumedAt || $0 == .foodIdentity }
        let asked = Set(session.askedFields)
        let remaining = (forced.isEmpty ? uniqueFields : forced).filter { !asked.contains($0) }
        let maxQuestions = forced.isEmpty ? 2 : 1
        let questions = remaining.prefix(maxQuestions).compactMap { question(for: $0, drafts: drafts) }

        if !questions.isEmpty { return questions }
        guard session.turnCount < 3 else { return [] }
        return uniqueFields.filter { !asked.contains($0) }.prefix(2).compactMap { question(for: $0, drafts: drafts) }
    }

    private func orderedUnique(_ fields: [FoodField]) -> [FoodField] {
        var seen = Set<FoodField>()
        return fields.filter { seen.insert($0).inserted }
    }

    private func question(for field: FoodField, drafts: [FoodEventDraft]) -> Question? {
        switch field {
        case .mealType:
            return Question(field: field, text: "这是早餐、午餐、晚餐、下午茶、加餐/零食还是夜宵？")
        case .consumedAt:
            return Question(field: field, text: "这条历史记录是哪一天？可以说“昨天”“前天”或具体日期。")
        case .foodIdentity:
            let names = drafts.first?.foodCandidates.prefix(3).map(\.displayName).joined(separator: "、") ?? ""
            return Question(field: field, text: names.isEmpty ? "这是哪一种食物？" : "我不太确定食物类型，是 \(names) 里的哪一种？")
        case .containerClass:
            return Question(field: field, text: "容器更接近小饭碗、普通饭碗还是大汤碗？")
        case .fillLevel:
            return Question(field: field, text: "大约是半碗、七八分满，还是接近满碗？")
        case .consistency:
            return Question(field: field, text: "稀稠度更接近偏稀、普通还是偏稠？")
        case .highCalorieAdditions:
            return Question(field: field, text: "有没有加糖、牛奶、炼乳、油或比较多的酱料？")
        case .consumedFraction:
            return Question(field: field, text: "这份大概吃完了、吃了一半，还是只吃了少量？")
        case .spoonType:
            return Question(field: field, text: "加糖那一勺更像小茶匙还是大汤匙？")
        case .recipeVariant, .packageWeight:
            return nil
        }
    }
}

private struct FoodOntologyRepository {
    struct FoodEntry {
        let id: String
        let name: String
        let category: FoodCategory
        let aliases: [String]
    }

    private let entries: [FoodEntry] = [
        FoodEntry(id: "millet_porridge", name: "小米粥", category: .porridge, aliases: ["小米粥", "小米稀饭", "黄米粥"]),
        FoodEntry(id: "rice_congee", name: "白粥", category: .porridge, aliases: ["白粥", "大米粥", "米粥", "稀饭"]),
        FoodEntry(id: "cooked_rice", name: "熟米饭", category: .cookedRice, aliases: ["米饭", "白米饭", "熟米饭"]),
        FoodEntry(id: "boiled_egg", name: "鸡蛋", category: .egg, aliases: ["鸡蛋", "水煮蛋", "煮鸡蛋", "蛋"]),
        FoodEntry(id: "soy_milk", name: "豆浆", category: .beverage, aliases: ["豆浆"]),
        FoodEntry(id: "milk", name: "牛奶", category: .beverage, aliases: ["牛奶"]),
        FoodEntry(id: "latte", name: "拿铁", category: .beverage, aliases: ["拿铁", "拿铁咖啡"]),
        FoodEntry(id: "toast", name: "吐司", category: .bakery, aliases: ["吐司", "面包", "一片吐司"]),
        FoodEntry(id: "apple", name: "苹果", category: .fruit, aliases: ["苹果"]),
        FoodEntry(id: "banana", name: "香蕉", category: .fruit, aliases: ["香蕉"]),
        FoodEntry(id: "nuts", name: "坚果", category: .nut, aliases: ["坚果", "杏仁", "核桃"]),
        FoodEntry(id: "noodles", name: "面条", category: .noodle, aliases: ["面条", "面", "汤面"]),
        FoodEntry(id: "home_stir_fry", name: "家常炒菜", category: .homeDish, aliases: ["鱼香肉丝", "炒菜", "一盘菜"])
    ]

    func resolve(_ text: String) -> [FoodCandidate] {
        let normalized = text.lowercased()
        let candidates = entries.compactMap { entry -> FoodCandidate? in
            let matchedAlias = entry.aliases.first { normalized.contains($0.lowercased()) }
            guard let alias = matchedAlias else { return nil }
            let confidence = alias == entry.name ? 0.94 : 0.82
            return FoodCandidate(foodID: entry.id, displayName: entry.name, category: entry.category, confidence: confidence)
        }
        return candidates.sorted { $0.confidence > $1.confidence }
    }
}

private struct MealEstimationResult {
    let calculation: MealCalculationResult
    let itemEstimates: [CalorieEstimate]
}

private struct CalorieMonteCarloEstimator {
    private let nutrition = NutritionRepository()
    private let portionPriors = PortionPriorRepository()
    private let recipes = RecipePrototypeRepository()

    func estimateMeal(drafts: [FoodEventDraft], sampleCount: Int) throws -> MealEstimationResult {
        var generator = SeededRandomGenerator(seed: UInt64(abs(drafts.map(\.rawText).joined().hashValue)) + 20260627)
        let itemResults = try drafts.map { try estimateItem(draft: $0, sampleCount: sampleCount, generator: &generator) }
        var totalSamples = Array(repeating: 0.0, count: sampleCount)

        for result in itemResults {
            for index in totalSamples.indices {
                totalSamples[index] += result.samples[index]
            }
        }

        let totalEstimate = CalorieEstimate.make(
            samples: totalSamples,
            confidence: confidence(for: drafts),
            assumptions: itemResults.flatMap(\.estimate.assumptions),
            uncertaintyDrivers: itemResults.flatMap(\.estimate.uncertaintyDrivers),
            sourceIDs: Array(Set(itemResults.flatMap(\.estimate.sourceIDs))).sorted()
        )

        let items = zip(drafts, itemResults).map { draft, result in
            MealItemCalculation(
                rawText: draft.rawText,
                matchedFoodName: draft.foodCandidates.first?.displayName ?? draft.rawText,
                fdcId: -1,
                estimatedGrams: result.medianGrams,
                energyKcal: result.estimate.median,
                proteinG: nil,
                fatG: nil,
                carbohydrateG: nil,
                confidence: result.estimate.confidence.legacyLabel,
                sourceName: "BHealth probabilistic estimator",
                sourceVersion: "probabilistic_estimator_v1",
                assumptions: result.estimate.assumptions.map(\.description) + result.estimate.uncertaintyDrivers.map { "不确定性：\($0.description)" }
            )
        }

        let calculation = MealCalculationResult(
            items: items,
            totalEnergyKcal: totalEstimate.median,
            rangeLowKcal: totalEstimate.p10,
            rangeHighKcal: totalEstimate.p90,
            confidence: totalEstimate.confidence.legacyLabel,
            assumptions: totalEstimate.assumptions.map(\.description) + totalEstimate.uncertaintyDrivers.map { "不确定性：\($0.description)" },
            sourceSummary: "probabilistic_estimator_v1 · \(totalEstimate.sourceIDs.joined(separator: " · "))"
        )

        return MealEstimationResult(calculation: calculation, itemEstimates: itemResults.map(\.estimate))
    }

    private func estimateItem(
        draft: FoodEventDraft,
        sampleCount: Int,
        generator: inout SeededRandomGenerator
    ) throws -> ItemSamplingResult {
        guard let foodID = draft.selectedFoodID ?? draft.foodCandidates.first?.foodID else {
            throw EstimationError.unresolvedFood
        }

        let nutrient = nutrition.nutrition(for: foodID)
        let recipe = recipes.prototype(for: foodID, consistency: draft.consistencyClass)
        var samples: [Double] = []
        var gramSamples: [Double] = []
        samples.reserveCapacity(sampleCount)
        gramSamples.reserveCapacity(sampleCount)

        for _ in 0..<sampleCount {
            let grams = gramsForDraft(draft, foodID: foodID, generator: &generator)
            let density = recipe?.sampleEnergyDensity(generator: &generator) ?? nutrient.energyKcalPer100g
            let consumed = draft.exactWeightGrams == nil
                ? portionPriors.consumedFraction(draft.consumedFraction).sample(generator: &generator)
                : 1.0
            let baseKcal = grams * density / 100.0 * consumed
            let additions = additionCalories(draft, generator: &generator)
            gramSamples.append(grams)
            samples.append(max(0, baseKcal + additions))
        }

        let sourceIDs = ["curated_prior_v1", "recipe_prototype_v1", nutrient.sourceID]
        let confidence = confidence(for: [draft])
        let assumptions = assumptions(for: draft)
        let drivers = uncertaintyDrivers(for: draft)
        let estimate = CalorieEstimate.make(
            samples: samples,
            confidence: confidence,
            assumptions: assumptions,
            uncertaintyDrivers: drivers,
            sourceIDs: sourceIDs
        )

        return ItemSamplingResult(
            samples: samples,
            estimate: estimate,
            medianGrams: percentile(gramSamples, 0.5)
        )
    }

    private func gramsForDraft(
        _ draft: FoodEventDraft,
        foodID: String,
        generator: inout SeededRandomGenerator
    ) -> Double {
        if let grams = draft.exactWeightGrams {
            return grams
        }

        let count = max(0.25, draft.explicitServingCount ?? 1)
        if let perPiece = portionPriors.pieceWeight(foodID: foodID, container: draft.containerClass) {
            return perPiece.sample(generator: &generator) * count
        }

        let volume = portionPriors.containerVolume(draft.containerClass, foodCategory: draft.foodCategory).sample(generator: &generator)
        let fill = portionPriors.fillFraction(draft.fillLevel).sample(generator: &generator)
        let massDensity = recipes.prototype(for: foodID, consistency: draft.consistencyClass)?.sampleMassDensity(generator: &generator) ?? 1.0
        return volume * fill * massDensity * count
    }

    private func additionCalories(_ draft: FoodEventDraft, generator: inout SeededRandomGenerator) -> Double {
        var calories = 0.0
        if draft.additions.contains(.sugar), !draft.exclusions.contains(.noSugar) {
            let grams: Double
            if draft.containerClass == .teaspoon {
                grams = TriangularDistribution(min: 3, mode: 4, max: 6).sample(generator: &generator)
            } else if draft.containerClass == .tablespoon {
                grams = TriangularDistribution(min: 9, mode: 12, max: 16).sample(generator: &generator)
            } else {
                grams = TriangularDistribution(min: 4, mode: 8, max: 14).sample(generator: &generator)
            }
            calories += grams * 3.87
        }
        if draft.additions.contains(.oil), !draft.exclusions.contains(.noOil) {
            let grams = TriangularDistribution(min: 3, mode: 8, max: 18).sample(generator: &generator)
            calories += grams * 8.84
        }
        if draft.additions.contains(.condensedMilk) {
            let grams = TriangularDistribution(min: 8, mode: 15, max: 30).sample(generator: &generator)
            calories += grams * 3.2
        }
        return calories
    }

    private func confidence(for drafts: [FoodEventDraft]) -> EstimateConfidence {
        let score = drafts.map { draft -> Double in
            let foodIdentity = (draft.foodCandidates.first?.confidence ?? 0.4)
            let portion: Double
            if draft.exactWeightGrams != nil {
                portion = 1.0
            } else if draft.containerClass != nil, draft.containerClass != .unknown, draft.fillLevel != nil, draft.fillLevel != .unknown {
                portion = 0.65
            } else if draft.userRequestedQuickEstimate {
                portion = 0.30
            } else {
                portion = 0.35
            }
            let recipe = draft.consistencyClass == nil || draft.consistencyClass == .unknown ? 0.55 : 0.75
            let consumption = draft.consumedFraction == nil || draft.consumedFraction == .unknown ? 0.75 : 0.9
            return foodIdentity * portion * recipe * 0.75 * consumption
        }.min() ?? 0.3

        switch score {
        case 0.85...:
            return .high
        case 0.65..<0.85:
            return .mediumHigh
        case 0.45..<0.65:
            return .medium
        case 0.25..<0.45:
            return .low
        default:
            return .veryLow
        }
    }

    private func assumptions(for draft: FoodEventDraft) -> [EstimateAssumption] {
        var values: [String] = []
        if let grams = draft.exactWeightGrams {
            values.append("按用户提供的 \(Int(grams.rounded()))g 做确定性计算。")
        } else {
            values.append("未提供克重，使用通用份量先验，不使用个人历史。")
        }
        if let container = draft.containerClass, container != .unknown {
            values.append("容器按\(container.displayName)的通用容量分布估算。")
        }
        if let fill = draft.fillLevel, fill != .unknown {
            values.append("装满程度按\(fill.displayName)分布估算。")
        }
        if let consistency = draft.consistencyClass, consistency != .unknown {
            values.append("配方原型按\(consistency.displayName)估算。")
        }
        if draft.exclusions.contains(.noSugar) {
            values.append("用户说明未加糖。")
        }
        return values.map { EstimateAssumption(description: $0) }
    }

    private func uncertaintyDrivers(for draft: FoodEventDraft) -> [UncertaintyDriver] {
        var drivers: [String] = []
        if draft.exactWeightGrams == nil {
            drivers.append("实际克重未知。")
        }
        if draft.containerClass == nil || draft.containerClass == .unknown {
            drivers.append("容器大小未明确。")
        }
        if draft.consistencyClass == nil || draft.consistencyClass == .unknown, draft.foodCategory == .porridge {
            drivers.append("粥的米水比例未知。")
        }
        if draft.fillLevel == nil || draft.fillLevel == .unknown, draft.foodCategory == .porridge {
            drivers.append("装满程度未明确。")
        }
        return drivers.map { UncertaintyDriver(description: $0) }
    }

    private func percentile(_ values: [Double], _ quantile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * quantile)))
        return sorted[index]
    }
}

private struct ItemSamplingResult {
    let samples: [Double]
    let estimate: CalorieEstimate
    let medianGrams: Double
}

private enum EstimationError: LocalizedError {
    case unresolvedFood

    var errorDescription: String? {
        "还没有确定食物类型。"
    }
}

private struct NutritionRepository {
    struct Nutrient {
        let energyKcalPer100g: Double
        let sourceID: String
    }

    func nutrition(for foodID: String) -> Nutrient {
        switch foodID {
        case "millet_porridge":
            return Nutrient(energyKcalPer100g: 55, sourceID: "curated_recipe_density_v1")
        case "rice_congee":
            return Nutrient(energyKcalPer100g: 45, sourceID: "curated_recipe_density_v1")
        case "cooked_rice":
            return Nutrient(energyKcalPer100g: 130, sourceID: "curated_cn_common_food_v1")
        case "boiled_egg":
            return Nutrient(energyKcalPer100g: 143, sourceID: "USDA Foundation Foods fallback")
        case "soy_milk":
            return Nutrient(energyKcalPer100g: 42, sourceID: "curated_cn_common_food_v1")
        case "milk":
            return Nutrient(energyKcalPer100g: 61, sourceID: "USDA Foundation Foods fallback")
        case "latte":
            return Nutrient(energyKcalPer100g: 48, sourceID: "curated_beverage_v1")
        case "toast":
            return Nutrient(energyKcalPer100g: 265, sourceID: "USDA Foundation Foods fallback")
        case "apple":
            return Nutrient(energyKcalPer100g: 52, sourceID: "USDA Foundation Foods fallback")
        case "banana":
            return Nutrient(energyKcalPer100g: 89, sourceID: "USDA Foundation Foods fallback")
        case "nuts":
            return Nutrient(energyKcalPer100g: 590, sourceID: "USDA Foundation Foods fallback")
        default:
            return Nutrient(energyKcalPer100g: 120, sourceID: "broad_category_prior_v1")
        }
    }
}

private struct PortionPriorRepository {
    func containerVolume(_ container: ContainerClass?, foodCategory: FoodCategory?) -> TriangularDistribution {
        switch container ?? .unknown {
        case .smallRiceBowl:
            return TriangularDistribution(min: 160, mode: 220, max: 300)
        case .regularRiceBowl:
            return TriangularDistribution(min: 280, mode: 350, max: 450)
        case .largeSoupBowl:
            return TriangularDistribution(min: 450, mode: 650, max: 900)
        case .smallCup:
            return TriangularDistribution(min: 120, mode: 180, max: 240)
        case .regularCup:
            return TriangularDistribution(min: 200, mode: 250, max: 330)
        case .largeMug:
            return TriangularDistribution(min: 300, mode: 420, max: 560)
        case .smallPlate:
            return TriangularDistribution(min: 120, mode: 180, max: 260)
        case .regularPlate:
            return TriangularDistribution(min: 220, mode: 320, max: 480)
        case .largePlate:
            return TriangularDistribution(min: 360, mode: 520, max: 760)
        case .handful:
            return TriangularDistribution(min: 18, mode: 30, max: 50)
        case .slice:
            return TriangularDistribution(min: 22, mode: 32, max: 48)
        case .piece:
            return TriangularDistribution(min: 45, mode: 60, max: 90)
        case .teaspoon:
            return TriangularDistribution(min: 4, mode: 5, max: 6)
        case .tablespoon:
            return TriangularDistribution(min: 12, mode: 15, max: 18)
        case .package, .unknown:
            if foodCategory == .porridge {
                return TriangularDistribution(min: 180, mode: 350, max: 650)
            }
            return TriangularDistribution(min: 80, mode: 160, max: 350)
        }
    }

    func fillFraction(_ fillLevel: FillLevel?) -> TriangularDistribution {
        switch fillLevel ?? .unknown {
        case .quarter:
            return TriangularDistribution(min: 0.20, mode: 0.25, max: 0.35)
        case .half:
            return TriangularDistribution(min: 0.42, mode: 0.50, max: 0.60)
        case .threeQuarters:
            return TriangularDistribution(min: 0.62, mode: 0.75, max: 0.85)
        case .eightyPercent:
            return TriangularDistribution(min: 0.70, mode: 0.80, max: 0.90)
        case .nearlyFull:
            return TriangularDistribution(min: 0.82, mode: 0.92, max: 1.0)
        case .full:
            return TriangularDistribution(min: 0.90, mode: 1.0, max: 1.08)
        case .heaped:
            return TriangularDistribution(min: 1.0, mode: 1.12, max: 1.25)
        case .unknown:
            return TriangularDistribution(min: 0.45, mode: 0.80, max: 1.0)
        }
    }

    func consumedFraction(_ value: ConsumedFraction?) -> TriangularDistribution {
        switch value ?? .unknown {
        case .quarter:
            return TriangularDistribution(min: 0.18, mode: 0.25, max: 0.35)
        case .half:
            return TriangularDistribution(min: 0.42, mode: 0.50, max: 0.60)
        case .most:
            return TriangularDistribution(min: 0.70, mode: 0.88, max: 1.0)
        case .all:
            return TriangularDistribution(min: 0.95, mode: 1.0, max: 1.0)
        case .unknown:
            return TriangularDistribution(min: 0.75, mode: 1.0, max: 1.0)
        }
    }

    func pieceWeight(foodID: String, container: ContainerClass?) -> TriangularDistribution? {
        switch foodID {
        case "boiled_egg":
            return TriangularDistribution(min: 45, mode: 55, max: 65)
        case "toast":
            return TriangularDistribution(min: 25, mode: 35, max: 50)
        case "apple":
            return TriangularDistribution(min: 120, mode: 180, max: 260)
        case "banana":
            return TriangularDistribution(min: 80, mode: 118, max: 160)
        case "nuts":
            return container == .handful ? TriangularDistribution(min: 18, mode: 30, max: 50) : nil
        default:
            return nil
        }
    }
}

private struct RecipePrototypeRepository {
    struct Prototype {
        let energyDensity: TriangularDistribution
        let massDensity: TriangularDistribution

        func sampleEnergyDensity(generator: inout SeededRandomGenerator) -> Double {
            energyDensity.sample(generator: &generator)
        }

        func sampleMassDensity(generator: inout SeededRandomGenerator) -> Double {
            massDensity.sample(generator: &generator)
        }
    }

    func prototype(for foodID: String, consistency: ConsistencyClass?) -> Prototype? {
        guard foodID == "millet_porridge" || foodID == "rice_congee" else { return nil }
        let density = TriangularDistribution(min: 0.96, mode: 1.02, max: 1.10)
        switch consistency ?? .unknown {
        case .veryThin:
            return Prototype(energyDensity: TriangularDistribution(min: 18, mode: 28, max: 42), massDensity: density)
        case .thin:
            return Prototype(energyDensity: TriangularDistribution(min: 25, mode: 40, max: 60), massDensity: density)
        case .regular:
            return Prototype(energyDensity: TriangularDistribution(min: 40, mode: 62, max: 90), massDensity: density)
        case .thick:
            return Prototype(energyDensity: TriangularDistribution(min: 65, mode: 92, max: 130), massDensity: density)
        case .veryThick:
            return Prototype(energyDensity: TriangularDistribution(min: 90, mode: 125, max: 170), massDensity: density)
        case .unknown:
            return Prototype(energyDensity: TriangularDistribution(min: 25, mode: 62, max: 130), massDensity: density)
        }
    }
}

private struct MealExplanationBuilder {
    func confirmationReply(
        calculation: MealCalculationResult,
        itemEstimates: [CalorieEstimate],
        mealType: MealType?,
        consumedAt: Date?
    ) -> String {
        let kcal = roundedKcal(calculation.totalEnergyKcal)
        let low = roundedKcal(calculation.rangeLowKcal)
        let high = roundedKcal(calculation.rangeHighKcal)
        let confidence = itemEstimates.map(\.confidence).minByRank ?? .low
        let assumptions = Array(calculation.assumptions.prefix(3)).joined(separator: "\n- ")

        return """
        估计摄入：约 \(kcal) kcal
        较可能范围：\(low)-\(high) kcal
        可信度：\(confidence.displayName)

        已用信息：\(mealType?.title ?? "餐别待确认")，\(consumedAt?.formatted(date: .abbreviated, time: .omitted) ?? "日期待确认")，\(calculation.foodDisplayName)

        主要假设：
        - \(assumptions.isEmpty ? "使用通用份量先验和配方原型。" : assumptions)

        是否确认保存这次饮食记录？
        """
    }

    private func roundedKcal(_ value: Double) -> Int {
        let absolute = abs(value)
        if absolute < 100 {
            return Int((value / 5).rounded() * 5)
        }
        if absolute <= 500 {
            return Int((value / 10).rounded() * 10)
        }
        return Int((value / 25).rounded() * 25)
    }
}

private struct TriangularDistribution: Hashable {
    let min: Double
    let mode: Double
    let max: Double

    func sample(generator: inout SeededRandomGenerator) -> Double {
        guard max > min else { return min }
        let u = generator.nextUnit()
        let c = (mode - min) / (max - min)
        if u < c {
            return min + sqrt(u * (max - min) * (mode - min))
        }
        return max - sqrt((1 - u) * (max - min) * (max - mode))
    }
}

private struct SeededRandomGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x1234abcd : seed
    }

    mutating func nextUnit() -> Double {
        state = 6364136223846793005 &* state &+ 1442695040888963407
        return Double(state >> 11) / Double(UInt64.max >> 11)
    }
}

private extension CalorieEstimate {
    static func make(
        samples: [Double],
        confidence: EstimateConfidence,
        assumptions: [EstimateAssumption],
        uncertaintyDrivers: [UncertaintyDriver],
        sourceIDs: [String]
    ) -> CalorieEstimate {
        let sorted = samples.sorted()
        return CalorieEstimate(
            p10: percentile(sorted, 0.10),
            p25: percentile(sorted, 0.25),
            median: percentile(sorted, 0.50),
            mean: samples.reduce(0, +) / Double(max(1, samples.count)),
            p75: percentile(sorted, 0.75),
            p90: percentile(sorted, 0.90),
            confidence: confidence,
            uncertaintyDrivers: uncertaintyDrivers,
            assumptions: assumptions,
            sourceIDs: sourceIDs
        )
    }

    private static func percentile(_ sortedValues: [Double], _ quantile: Double) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        let index = min(sortedValues.count - 1, max(0, Int(Double(sortedValues.count - 1) * quantile)))
        return sortedValues[index]
    }
}

private extension Array where Element == EstimateConfidence {
    var minByRank: EstimateConfidence? {
        sorted { $0.rank < $1.rank }.first
    }
}

private extension EstimateConfidence {
    var rank: Int {
        switch self {
        case .veryLow: return 0
        case .low: return 1
        case .medium: return 2
        case .mediumHigh: return 3
        case .high: return 4
        }
    }
}

private extension ContainerClass {
    var displayName: String {
        switch self {
        case .smallRiceBowl: return "小饭碗"
        case .regularRiceBowl: return "普通饭碗"
        case .largeSoupBowl: return "大汤碗"
        case .smallCup: return "小杯"
        case .regularCup: return "普通杯"
        case .largeMug: return "大杯"
        case .smallPlate: return "小盘"
        case .regularPlate: return "普通盘"
        case .largePlate: return "大盘"
        case .tablespoon: return "汤匙"
        case .teaspoon: return "茶匙"
        case .handful: return "一把"
        case .piece: return "单个"
        case .slice: return "一片"
        case .package: return "包装"
        case .unknown: return "未知容器"
        }
    }
}

private extension FillLevel {
    var displayName: String {
        switch self {
        case .quarter: return "四分之一"
        case .half: return "半份"
        case .threeQuarters: return "大半份"
        case .eightyPercent: return "八分满"
        case .nearlyFull: return "接近满"
        case .full: return "满"
        case .heaped: return "冒尖"
        case .unknown: return "未知"
        }
    }
}

private extension ConsistencyClass {
    var displayName: String {
        switch self {
        case .veryThin: return "很稀"
        case .thin: return "偏稀"
        case .regular: return "普通"
        case .thick: return "偏稠"
        case .veryThick: return "很稠"
        case .unknown: return "未知"
        }
    }
}
