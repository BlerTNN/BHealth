//
//  FoodAssistantViewModel.swift
//  BHealth
//
//  Created by Codex on 2026-06-26.
//

import Foundation
import Combine

struct AssistantMessage: Identifiable, Hashable {
    let id: UUID
    let text: String
    let isFromUser: Bool
    let createdAt: Date

    init(id: UUID = UUID(), text: String, isFromUser: Bool, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.isFromUser = isFromUser
        self.createdAt = createdAt
    }

    static let sample: [AssistantMessage] = [
        AssistantMessage(text: "进入一个模式后，我会按这个模式帮你记录或分析。", isFromUser: false)
    ]
}

enum AssistantMode: String, CaseIterable, Identifiable, Hashable {
    case foodLog
    case historicalFoodLog
    case healthCoach

    var id: String { rawValue }

    var title: String {
        switch self {
        case .foodLog:
            return "记录饮食"
        case .historicalFoodLog:
            return "历史数据添加"
        case .healthCoach:
            return "健康助手"
        }
    }

    var subtitle: String {
        switch self {
        case .foodLog:
            return "记录今天吃了什么、哪一餐和大致热量"
        case .historicalFoodLog:
            return "补录昨天或更早某一天的早餐、午餐等"
        case .healthCoach:
            return "基于历史摄入和消耗提供饮食与减重建议"
        }
    }

    var icon: String {
        switch self {
        case .foodLog:
            return "fork.knife.circle.fill"
        case .historicalFoodLog:
            return "calendar.badge.plus"
        case .healthCoach:
            return "heart.text.square.fill"
        }
    }

    var supportsMealSaving: Bool {
        self != .healthCoach
    }

    var welcomeMessage: String {
        switch self {
        case .foodLog:
            return "告诉我今天吃了什么，我会帮你估算热量。如果餐别或份量还不清楚，我会继续问。"
        case .historicalFoodLog:
            return "告诉我要补录哪一天、吃了什么。我会确认日期、餐别和热量后再保存。"
        case .healthCoach:
            return "你可以问我饮食建议、热量缺口、近期趋势或大概减重速度。我会结合本地历史记录做判断。"
        }
    }
}

@MainActor
final class FoodAssistantViewModel: ObservableObject {
    @Published var draftMessage = ""
    @Published var messages = AssistantMessage.sample
    @Published var isSending = false
    @Published var hasAPIKey: Bool
    @Published var pendingCalculation: MealCalculationResult?
    @Published var pendingMealType: MealType?
    @Published var pendingConsumedAt: Date?
    @Published var selectedMode: AssistantMode?
    @Published private(set) var savedRecords: [SavedMealRecord]

    private let apiKeyStore: KeychainAPIKeyStore
    private let engine: FoodAssistantEngine
    private let calculator: MealNutritionCalculator
    private let probabilisticCoordinator: FoodConversationCoordinator
    private let recordStore: MealRecordLocalStore
    private var probabilisticSession = FoodConversationSession()

    init() {
        let apiKeyStore = KeychainAPIKeyStore.shared
        let engine = FoodAssistantEngine()
        let calculator = MealNutritionCalculator()
        let probabilisticCoordinator = FoodConversationCoordinator()
        let recordStore = MealRecordLocalStore()

        self.apiKeyStore = apiKeyStore
        self.engine = engine
        self.calculator = calculator
        self.probabilisticCoordinator = probabilisticCoordinator
        self.recordStore = recordStore
        self.hasAPIKey = apiKeyStore.hasAPIKey
        self.savedRecords = recordStore.load()
    }

    func refreshAPIKeyStatus() {
        hasAPIKey = apiKeyStore.hasAPIKey
    }

    func openMode(_ mode: AssistantMode) {
        selectedMode = mode
        pendingCalculation = nil
        pendingMealType = nil
        pendingConsumedAt = nil
        probabilisticSession = FoodConversationSession()
        messages = [
            AssistantMessage(text: mode.welcomeMessage, isFromUser: false)
        ]
    }

    func closeMode() {
        selectedMode = nil
        pendingCalculation = nil
        pendingMealType = nil
        pendingConsumedAt = nil
        draftMessage = ""
        probabilisticSession = FoodConversationSession()
        messages = AssistantMessage.sample
    }

    func sendDraftMessage(dashboardContext: String) async {
        let trimmed = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draftMessage = ""
        await send(trimmed, dashboardContext: dashboardContext)
    }

    func send(_ text: String, dashboardContext: String) async {
        guard !isSending else { return }

        messages.append(AssistantMessage(text: text, isFromUser: true))
        isSending = true
        pendingCalculation = nil
        pendingMealType = nil
        pendingConsumedAt = nil
        defer { isSending = false }

        let mode = selectedMode ?? .healthCoach
        let referenceDate = Date()

        if mode.supportsMealSaving, FeatureFlags.probabilisticFoodEstimation {
            let result = probabilisticCoordinator.handle(
                userText: text,
                mode: mode,
                session: &probabilisticSession,
                referenceDate: referenceDate
            )
            messages.append(AssistantMessage(text: result.reply, isFromUser: false))
            if result.shouldOfferSave,
               let calculation = result.calculation,
               let mealType = result.mealType,
               let consumedAt = result.consumedAt {
                pendingMealType = mealType
                pendingConsumedAt = consumedAt
                pendingCalculation = calculation
            }
            return
        }

        let calculation = mode.supportsMealSaving ? calculator.calculate(from: text) : nil
        let detectedMealType = mode.supportsMealSaving ? MealType.detected(in: text) : nil
        let detectedConsumedAt = consumedAtCandidate(for: mode, text: text, referenceDate: referenceDate)

        guard hasAPIKey else {
            let reply = localFallbackReply(
                for: text,
                calculation: calculation,
                mealType: detectedMealType,
                consumedAt: detectedConsumedAt,
                mode: mode,
                reason: "还没有保存 DeepSeek API key。"
            )
            messages.append(AssistantMessage(text: reply, isFromUser: false))
            pendingMealType = detectedMealType
            pendingConsumedAt = detectedConsumedAt
            pendingCalculation = mode.supportsMealSaving && detectedMealType != nil && detectedConsumedAt != nil ? calculation : nil
            return
        }

        do {
            let aiReply = try await engine.respond(
                userText: text,
                history: messages,
                calculation: calculation,
                mode: mode,
                mealType: detectedMealType,
                consumedAt: detectedConsumedAt,
                currentDate: referenceDate,
                dashboardContext: dashboardContext
            )

            messages.append(AssistantMessage(text: aiReply.reply, isFromUser: false))
            let resolvedMealType = aiReply.mealType ?? detectedMealType
            let resolvedConsumedAt = consumedAtCandidate(for: mode, aiReply: aiReply, detectedDate: detectedConsumedAt, referenceDate: referenceDate)
            if mode.supportsMealSaving, aiReply.shouldOfferSave, let resolvedMealType, let resolvedConsumedAt {
                pendingMealType = resolvedMealType
                pendingConsumedAt = resolvedConsumedAt
                pendingCalculation = aiReply.estimatedCalculation(for: text) ?? calculation
            }
        } catch {
            let reply = localFallbackReply(
                for: text,
                calculation: calculation,
                mealType: detectedMealType,
                consumedAt: detectedConsumedAt,
                mode: mode,
                reason: error.localizedDescription
            )
            messages.append(AssistantMessage(text: reply, isFromUser: false))
            pendingMealType = detectedMealType
            pendingConsumedAt = detectedConsumedAt
            pendingCalculation = mode.supportsMealSaving && detectedMealType != nil && detectedConsumedAt != nil ? calculation : nil
        }
    }

    func savePendingCalculation() {
        guard let pendingCalculation, let pendingMealType, let pendingConsumedAt else { return }

        let record = SavedMealRecord(
            confirmedAt: Date(),
            consumedAt: pendingConsumedAt,
            mealType: pendingMealType,
            calculation: pendingCalculation
        )

        recordStore.add(record)
        savedRecords = recordStore.load()
        self.pendingCalculation = nil
        self.pendingMealType = nil
        self.pendingConsumedAt = nil

        let kcal = Int(record.calculation.totalEnergyKcal.rounded())
        messages.append(AssistantMessage(text: "已保存到本地记录：\(record.consumedAt.formatted(date: .abbreviated, time: .omitted)) \(record.mealType.title) \(record.calculation.foodDisplayName)，约 \(kcal) kcal。", isFromUser: false))
    }

    private func localFallbackReply(
        for text: String,
        calculation: MealCalculationResult?,
        mealType: MealType?,
        consumedAt: Date?,
        mode: AssistantMode,
        reason: String
    ) -> String {
        if let calculation {
            if mode == .historicalFoodLog, consumedAt == nil {
                return """
                我先用本地 USDA Foundation Foods 做了粗略计算，但 AI 回复暂时不可用：\(reason)

                估计摄入：约 \(Int(calculation.totalEnergyKcal.rounded())) kcal
                合理范围：\(Int(calculation.rangeLowKcal.rounded()))-\(Int(calculation.rangeHighKcal.rounded())) kcal

                这条历史记录是哪一天？你可以说“昨天”“前天”或具体日期。
                """
            }

            guard let mealType else {
                return """
                我先用本地 USDA Foundation Foods 做了粗略计算，但 AI 回复暂时不可用：\(reason)

                估计摄入：约 \(Int(calculation.totalEnergyKcal.rounded())) kcal
                合理范围：\(Int(calculation.rangeLowKcal.rounded()))-\(Int(calculation.rangeHighKcal.rounded())) kcal

                这是早餐、午餐、晚餐、下午茶、加餐/零食还是夜宵？
                """
            }

            return """
            我先用本地 USDA Foundation Foods 做了粗略计算，但 AI 回复暂时不可用：\(reason)

            估计摄入：约 \(Int(calculation.totalEnergyKcal.rounded())) kcal
            合理范围：\(Int(calculation.rangeLowKcal.rounded()))-\(Int(calculation.rangeHighKcal.rounded())) kcal
            可信度：\(calculation.confidence == "low" ? "较低" : "中等")
            日期：\(consumedAt?.formatted(date: .abbreviated, time: .omitted) ?? "今天")
            餐别：\(mealType.title)

            食品：\(calculation.foodDisplayName)
            主要依据：\(calculation.items.map { $0.matchedFoodName }.joined(separator: "；"))
            是否确认保存这次饮食记录？
            """
        }

        return """
        我现在还不能完成 AI 解析：\(reason)

        你可以先补充更明确的信息，例如食物名称、数量或克重。比如：“鸡蛋 1 个，牛奶 250g”。
        """
    }

    private func consumedAtCandidate(for mode: AssistantMode, text: String, referenceDate: Date) -> Date? {
        switch mode {
        case .foodLog:
            return Calendar.current.startOfDay(for: referenceDate)
        case .historicalFoodLog:
            return MealDateResolver.detectedDate(in: text, referenceDate: referenceDate)
        case .healthCoach:
            return nil
        }
    }

    private func consumedAtCandidate(
        for mode: AssistantMode,
        aiReply: AssistantAIReply,
        detectedDate: Date?,
        referenceDate: Date
    ) -> Date? {
        switch mode {
        case .foodLog:
            return Calendar.current.startOfDay(for: referenceDate)
        case .historicalFoodLog:
            return aiReply.consumedAt(referenceDate: referenceDate) ?? detectedDate
        case .healthCoach:
            return nil
        }
    }
}

struct FoodAssistantEngine {
    private let client: DeepSeekClient

    init(client: DeepSeekClient = DeepSeekClient()) {
        self.client = client
    }

    func respond(
        userText: String,
        history: [AssistantMessage],
        calculation: MealCalculationResult?,
        mode: AssistantMode,
        mealType: MealType?,
        consumedAt: Date?,
        currentDate: Date,
        dashboardContext: String
    ) async throws -> AssistantAIReply {
        let context = PromptContext(
            userText: userText,
            mode: mode.title,
            mealType: mealType?.title,
            currentDate: currentDate,
            consumedAt: consumedAt,
            dashboardContext: dashboardContext,
            calculation: calculation
        )
        let contextData = try JSONEncoder.promptEncoder.encode(context)
        let contextJSON = String(data: contextData, encoding: .utf8) ?? "{}"

        let recentHistory = history.suffix(8).map { message in
            DeepSeekMessage(role: message.isFromUser ? "user" : "assistant", content: message.text)
        }

        let systemPrompt = """
        你是 BHealth 的 AI 饮食热量记录助手。必须遵守：
        1. AI 负责理解自然语言、追问缺失信息、参考食物库证据、进行有标注的粗略推理，并解释结果。
        2. local_calculation_context 中的 calculation 是本地 USDA 食物库和程序计算结果，只作为参考证据，不是唯一来源。
        3. 如果本地食物库没有覆盖用户食物，你可以基于常识做低可信度估算，但必须明确标注“AI 推理估算/低可信度”，不要伪装成权威数据。
        4. 不要编造品牌官方菜单、包装标签或来源版本；品牌食品缺少官方资料时要说明。
        5. 每次最多追问 1-2 个最影响结果的信息。如果信息已足够，可以给区间估算。
        6. 只有用户明确确认后才能保存记录。你现在只能建议用户确认，不能声称已经保存。
        7. 不要输出伪精确热量，优先使用整数和范围。
        8. 记录饮食/历史数据添加模式必须确认餐别；如果用户没有说明早餐、午餐、晚餐、下午茶、加餐/零食或夜宵，先追问餐别，不要要求保存。
        9. 历史数据添加模式必须确认日期；如果日期不明确，先追问日期，不要要求保存。相对日期要基于 current_date 转成 YYYY-MM-DD。
        10. food_items 只写具体食品或饮品名称，不要写整句聊天、请求语气或“帮我估算”。
        11. 如果模式是“健康助手”，提供通用建议、趋势判断、粗略减重估计，不要要求保存饮食记录，should_offer_save 必须为 false。
        12. 输出严格 JSON，不要 Markdown，不要代码块。

        JSON schema:
        {
          "reply": "给用户看的中文回复",
          "assistant_state": "collecting|calculating|confirming|low_confidence|needs_source",
          "confidence": "high|medium|low|none",
          "should_offer_save": true,
          "estimated_energy_kcal": 430,
          "energy_low_kcal": 370,
          "energy_high_kcal": 500,
          "meal_type": "breakfast|lunch|dinner|afternoon_tea|snack|late_night|other|null",
          "consumed_at": "YYYY-MM-DD|null",
          "food_items": ["鸡蛋", "拿铁", "吐司"],
          "assumptions": ["用于保存快照的关键假设"],
          "source_summary": "USDA Foundation Foods 2026-04-30 + AI 推理估算"
        }
        """

        let userPrompt = """
        local_calculation_context:
        \(contextJSON)

        请基于上面的本地计算上下文回复用户。
        模式是：\(mode.title)。
        如果是记录饮食或历史数据添加：
        - 如果用户没有明确餐别，先追问“这是哪一餐？”，meal_type=null，should_offer_save=false。
        - 如果是历史数据添加且用户没有明确日期，先追问“这条记录是哪一天？”，consumed_at=null，should_offer_save=false。
        - 如果已经明确餐别，把 meal_type 和 consumed_at 纳入回复。meal_type 只能使用 breakfast/lunch/dinner/afternoon_tea/snack/late_night/other，consumed_at 只能使用 YYYY-MM-DD 或 null。
        - 如果是记录饮食，consumed_at 使用 current_date 的日期。
        - 如果有 calculation，把它作为参考证据，结合用户描述判断是否需要修正或补充。
        - 如果没有 calculation，但用户描述足够可估算，可以给低可信度区间估算，并填写 estimated_energy_kcal / energy_low_kcal / energy_high_kcal。
        - 信息不足时追问食物、份量、克重、品牌/地区或配料中最关键的 1-2 项。
        - food_items 中只放食品名称，例如 ["鸡蛋", "牛奶"]，不要放“我吃了”“补录昨天”等对话文本。
        - 只有食物信息、餐别和必要日期都明确时，才可以询问“是否确认保存”，并把 should_offer_save 设为 true。
        如果是健康助手：
        - 使用 dashboard_context 总结用户近况。
        - 可以估算热量缺口对应的大概体重变化，但必须说明只是粗略推断。
        - 不要填写待保存热量，should_offer_save=false。
        """

        let messages = [DeepSeekMessage(role: "system", content: systemPrompt)]
            + recentHistory
            + [DeepSeekMessage(role: "user", content: userPrompt)]

        let content = try await client.complete(messages: messages)
        return try AssistantAIReply.parse(from: content)
    }
}

struct AssistantAIReply: Codable, Hashable {
    let reply: String
    let assistantState: String
    let confidence: String
    let shouldOfferSave: Bool
    let estimatedEnergyKcal: Double?
    let energyLowKcal: Double?
    let energyHighKcal: Double?
    let mealTypeRaw: String?
    let consumedAtRaw: String?
    let foodItems: [String]?
    let assumptions: [String]?
    let sourceSummary: String?

    var mealType: MealType? {
        MealType.fromAssistantValue(mealTypeRaw)
    }

    func consumedAt(referenceDate: Date) -> Date? {
        MealDateResolver.assistantDate(from: consumedAtRaw, referenceDate: referenceDate)
    }

    enum CodingKeys: String, CodingKey {
        case reply
        case assistantState = "assistant_state"
        case confidence
        case shouldOfferSave = "should_offer_save"
        case estimatedEnergyKcal = "estimated_energy_kcal"
        case energyLowKcal = "energy_low_kcal"
        case energyHighKcal = "energy_high_kcal"
        case mealTypeRaw = "meal_type"
        case consumedAtRaw = "consumed_at"
        case foodItems = "food_items"
        case assumptions
        case sourceSummary = "source_summary"
    }

    static func parse(from content: String) throws -> AssistantAIReply {
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw AssistantAIReplyError.invalidEncoding
        }

        return try JSONDecoder().decode(AssistantAIReply.self, from: data)
    }

    func estimatedCalculation(for userText: String) -> MealCalculationResult? {
        guard let estimatedEnergyKcal, estimatedEnergyKcal > 0 else { return nil }

        let low = energyLowKcal ?? estimatedEnergyKcal * 0.75
        let high = energyHighKcal ?? estimatedEnergyKcal * 1.25
        let source = sourceSummary ?? "AI 推理估算"
        let snapshotAssumptions = assumptions?.isEmpty == false ? assumptions ?? [] : ["食品库未完全覆盖该描述，使用 AI 常识做粗略区间估算。"]
        let foodName = MealFoodNameFormatter.displayName(from: foodItems, fallback: userText)

        let item = MealItemCalculation(
            rawText: foodName,
            matchedFoodName: foodName,
            fdcId: -1,
            estimatedGrams: 0,
            energyKcal: estimatedEnergyKcal,
            proteinG: nil,
            fatG: nil,
            carbohydrateG: nil,
            confidence: confidence == "medium" ? "medium" : "low",
            sourceName: source,
            sourceVersion: "runtime-estimate",
            assumptions: snapshotAssumptions
        )

        return MealCalculationResult(
            items: [item],
            totalEnergyKcal: estimatedEnergyKcal,
            rangeLowKcal: max(0, min(low, high)),
            rangeHighKcal: max(low, high),
            confidence: confidence == "medium" ? "medium" : "low",
            assumptions: snapshotAssumptions,
            sourceSummary: source
        )
    }
}

enum AssistantAIReplyError: LocalizedError {
    case invalidEncoding

    var errorDescription: String? {
        "AI 回复无法解析。"
    }
}

enum MealDateResolver {
    static func detectedDate(in text: String, referenceDate: Date) -> Date? {
        let normalized = text
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()

        let relativeRules: [(String, Int)] = [
            ("大前天", -3),
            ("前天", -2),
            ("昨天", -1),
            ("昨日", -1),
            ("昨晚", -1),
            ("今天", 0),
            ("今日", 0)
        ]

        if let offset = relativeRules.first(where: { normalized.contains($0.0) })?.1 {
            return Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: referenceDate))
        }

        if let date = dateFromMatchedPattern(#"\d{4}[-/\.]\d{1,2}[-/\.]\d{1,2}"#, in: normalized, referenceDate: referenceDate, includesYear: true) {
            return date
        }

        if let date = dateFromMatchedPattern(#"\d{4}年\d{1,2}月\d{1,2}[日号]?"#, in: normalized, referenceDate: referenceDate, includesYear: true) {
            return date
        }

        if let date = dateFromMatchedPattern(#"\d{1,2}[-/\.]\d{1,2}"#, in: normalized, referenceDate: referenceDate, includesYear: false) {
            return date
        }

        if let date = dateFromMatchedPattern(#"\d{1,2}月\d{1,2}[日号]?"#, in: normalized, referenceDate: referenceDate, includesYear: false) {
            return date
        }

        return nil
    }

    static func assistantDate(from value: String?, referenceDate: Date) -> Date? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "null" else { return nil }

        if let dayPrefix = trimmed.split(separator: "T").first,
           let date = dateFromDayString(String(dayPrefix), referenceDate: referenceDate) {
            return date
        }

        return detectedDate(in: trimmed, referenceDate: referenceDate)
    }

    private static func dateFromMatchedPattern(
        _ pattern: String,
        in text: String,
        referenceDate: Date,
        includesYear: Bool
    ) -> Date? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return dateFromNumbers(in: String(text[range]), referenceDate: referenceDate, includesYear: includesYear)
    }

    private static func dateFromDayString(_ value: String, referenceDate: Date) -> Date? {
        dateFromNumbers(in: value, referenceDate: referenceDate, includesYear: value.prefix(4).allSatisfy(\.isNumber))
    }

    private static func dateFromNumbers(in text: String, referenceDate: Date, includesYear: Bool) -> Date? {
        let values = text
            .split { !$0.isNumber }
            .compactMap { Int($0) }

        let calendar = Calendar.current
        let referenceYear = calendar.component(.year, from: referenceDate)
        let year: Int
        let month: Int
        let day: Int

        if includesYear {
            guard values.count >= 3 else { return nil }
            year = values[0]
            month = values[1]
            day = values[2]
        } else {
            guard values.count >= 2 else { return nil }
            year = referenceYear
            month = values[0]
            day = values[1]
        }

        var components = DateComponents()
        components.calendar = calendar
        components.year = year
        components.month = month
        components.day = day

        guard let date = calendar.date(from: components) else { return nil }
        let normalized = calendar.dateComponents([.year, .month, .day], from: date)
        guard normalized.year == year, normalized.month == month, normalized.day == day else { return nil }

        let startOfDay = calendar.startOfDay(for: date)
        if !includesYear, startOfDay > calendar.startOfDay(for: referenceDate),
           let previousYear = calendar.date(byAdding: .year, value: -1, to: startOfDay) {
            return previousYear
        }

        return startOfDay
    }
}

struct MealRecordLocalStore {
    private let key = "BHealth.savedMealRecords.v1"

    func load() -> [SavedMealRecord] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        let records = (try? JSONDecoder.recordDecoder.decode([SavedMealRecord].self, from: data)) ?? []
        return records.sorted { $0.consumedAt > $1.consumedAt }
    }

    func save(_ records: [SavedMealRecord]) {
        guard let data = try? JSONEncoder.recordEncoder.encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func add(_ record: SavedMealRecord) {
        var records = load()
        records.insert(record, at: 0)
        save(records)
        NotificationCenter.default.post(name: .mealRecordsDidChange, object: nil)
    }

    func update(_ record: SavedMealRecord) {
        var records = load()
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.insert(record, at: 0)
        }
        save(records)
        NotificationCenter.default.post(name: .mealRecordsDidChange, object: nil)
    }

    func delete(_ record: SavedMealRecord) {
        var records = load()
        records.removeAll { $0.id == record.id }
        save(records)
        NotificationCenter.default.post(name: .mealRecordsDidChange, object: nil)
    }
}

private struct PromptContext: Codable {
    let userText: String
    let mode: String
    let mealType: String?
    let currentDate: Date
    let consumedAt: Date?
    let dashboardContext: String
    let calculation: MealCalculationResult?
}

private extension JSONEncoder {
    static var promptEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var recordEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var recordDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
