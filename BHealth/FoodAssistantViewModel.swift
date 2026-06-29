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

    static let sample: [AssistantMessage] = sample(language: .chinese)

    static func sample(language: AppLanguage) -> [AssistantMessage] {
        [
            AssistantMessage(
                text: AppText.text("进入一个模式后，我会按这个模式帮你记录或分析。", "Choose a mode and I will help you log or analyze in that context.", language: language),
                isFromUser: false
            )
        ]
    }
}

enum AssistantMode: String, CaseIterable, Identifiable, Hashable {
    case foodLog
    case historicalFoodLog
    case healthCoach

    var id: String { rawValue }

    var title: String {
        title(language: .chinese)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .foodLog:
            return AppText.text("记录饮食", "Log Food", language: language)
        case .historicalFoodLog:
            return AppText.text("历史数据添加", "Add Past Data", language: language)
        case .healthCoach:
            return AppText.text("健康助手", "Health Coach", language: language)
        }
    }

    var subtitle: String {
        subtitle(language: .chinese)
    }

    func subtitle(language: AppLanguage) -> String {
        switch self {
        case .foodLog:
            return AppText.text("记录今天吃了什么、哪一餐和大致热量", "Log what you ate today, the meal, and rough calories", language: language)
        case .historicalFoodLog:
            return AppText.text("补录昨天或更早某一天的早餐、午餐等", "Add breakfast, lunch, or other meals from a past date", language: language)
        case .healthCoach:
            return AppText.text("基于历史摄入和消耗提供饮食与减重建议", "Get nutrition and weight guidance from your history", language: language)
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
        welcomeMessage(language: .chinese)
    }

    func welcomeMessage(language: AppLanguage) -> String {
        switch self {
        case .foodLog:
            return AppText.text("告诉我今天吃了什么，我会帮你估算热量。如果餐别或份量还不清楚，我会继续问。", "Tell me what you ate today. I will estimate calories and ask follow-up questions if the meal or portion is unclear.", language: language)
        case .historicalFoodLog:
            return AppText.text("告诉我要补录哪一天、吃了什么。我会确认日期、餐别和热量后再保存。", "Tell me the date and what you ate. I will confirm the date, meal, and calories before saving.", language: language)
        case .healthCoach:
            return AppText.text("你可以问我饮食建议、热量缺口、近期趋势或大概减重速度。我会结合本地历史记录做判断。", "Ask about nutrition advice, calorie deficit, trends, or rough weight-loss pace. I will use your local history for context.", language: language)
        }
    }
}

struct LocalAlgorithmFallbackRequest: Identifiable, Hashable {
    let id = UUID()
    let userText: String
    let mode: AssistantMode
    let reason: String
    let referenceDate: Date

    func message(language: AppLanguage) -> String {
        AppText.text(
            "当前 API 不可用：\(reason)\n\n是否改用本地算法做粗略估算？本地算法会尽量根据已提供信息计算，但准确性会低一些。",
            "The API is currently unavailable: \(reason)\n\nUse the local estimator for a rough estimate instead? It will use the details you provided, but accuracy may be lower.",
            language: language
        )
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
    @Published var localAlgorithmFallbackRequest: LocalAlgorithmFallbackRequest?
    @Published var selectedMode: AssistantMode?
    @Published private(set) var savedRecords: [SavedMealRecord]

    private let apiKeyStore: KeychainAPIKeyStore
    private let engine: FoodAssistantEngine
    private let probabilisticCoordinator: FoodConversationCoordinator
    private let recordStore: MealRecordLocalStore
    private var probabilisticSession = FoodConversationSession()
    private var language: AppLanguage = .chinese

    init() {
        let apiKeyStore = KeychainAPIKeyStore.shared
        let engine = FoodAssistantEngine()
        let probabilisticCoordinator = FoodConversationCoordinator()
        let recordStore = MealRecordLocalStore()

        self.apiKeyStore = apiKeyStore
        self.engine = engine
        self.probabilisticCoordinator = probabilisticCoordinator
        self.recordStore = recordStore
        self.hasAPIKey = apiKeyStore.hasAPIKey
        self.savedRecords = recordStore.load()
    }

    func refreshAPIKeyStatus() {
        hasAPIKey = apiKeyStore.hasAPIKey
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
        messages = selectedMode.map { [AssistantMessage(text: $0.welcomeMessage(language: language), isFromUser: false)] }
            ?? AssistantMessage.sample(language: language)
    }

    func openMode(_ mode: AssistantMode, language: AppLanguage? = nil) {
        if let language {
            self.language = language
        }
        selectedMode = mode
        pendingCalculation = nil
        pendingMealType = nil
        pendingConsumedAt = nil
        localAlgorithmFallbackRequest = nil
        probabilisticSession = FoodConversationSession()
        messages = [
            AssistantMessage(text: mode.welcomeMessage(language: self.language), isFromUser: false)
        ]
    }

    func closeMode(language: AppLanguage? = nil) {
        if let language {
            self.language = language
        }
        selectedMode = nil
        pendingCalculation = nil
        pendingMealType = nil
        pendingConsumedAt = nil
        localAlgorithmFallbackRequest = nil
        draftMessage = ""
        probabilisticSession = FoodConversationSession()
        messages = AssistantMessage.sample(language: self.language)
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
        localAlgorithmFallbackRequest = nil
        defer { isSending = false }

        let mode = selectedMode ?? .healthCoach
        let referenceDate = Date()
        let detectedMealType = mode.supportsMealSaving ? MealType.detected(in: text) : nil
        let detectedConsumedAt = consumedAtCandidate(for: mode, text: text, referenceDate: referenceDate)

        guard hasAPIKey else {
            handleAPIUnavailable(
                userText: text,
                mode: mode,
                reason: AppText.text("还没有保存 DeepSeek API key。", "No DeepSeek API key has been saved.", language: language),
                referenceDate: referenceDate
            )
            return
        }

        do {
            let aiReply = try await engine.respond(
                userText: text,
                history: messages,
                calculation: nil,
                mode: mode,
                mealType: detectedMealType,
                consumedAt: detectedConsumedAt,
                currentDate: referenceDate,
                dashboardContext: dashboardContext,
                language: language
            )

            messages.append(AssistantMessage(text: aiReply.reply, isFromUser: false))
            let resolvedMealType = aiReply.mealType ?? detectedMealType
            let resolvedConsumedAt = consumedAtCandidate(for: mode, aiReply: aiReply, detectedDate: detectedConsumedAt, referenceDate: referenceDate)
            if mode.supportsMealSaving, aiReply.shouldOfferSave, let resolvedMealType, let resolvedConsumedAt {
                applyLocalCalculationAfterAI(
                    userText: text,
                    aiReply: aiReply,
                    mode: mode,
                    mealType: resolvedMealType,
                    consumedAt: resolvedConsumedAt,
                    referenceDate: referenceDate
                )
            }
        } catch {
            handleAPIUnavailable(
                userText: text,
                mode: mode,
                reason: assistantErrorMessage(error, language: language),
                referenceDate: referenceDate
            )
        }
    }

    private func assistantErrorMessage(_ error: Error, language: AppLanguage) -> String {
        if let error = error as? DeepSeekError {
            return error.message(language: language)
        }
        if let error = error as? KeychainError {
            return error.message(language: language)
        }
        if let error = error as? AssistantAIReplyError {
            return error.message(language: language)
        }
        return error.localizedDescription
    }

    private func handleAPIUnavailable(
        userText: String,
        mode: AssistantMode,
        reason: String,
        referenceDate: Date
    ) {
        if mode.supportsMealSaving, FeatureFlags.probabilisticFoodEstimation {
            localAlgorithmFallbackRequest = LocalAlgorithmFallbackRequest(
                userText: userText,
                mode: mode,
                reason: reason,
                referenceDate: referenceDate
            )
            return
        }

        messages.append(
            AssistantMessage(
                text: AppText.text(
                    "当前 API 不可用：\(reason)\n\n请稍后重试，或到“我的”里检查 DeepSeek API key。",
                    "The API is currently unavailable: \(reason)\n\nPlease try again later, or check your DeepSeek API key in Me.",
                    language: language
                ),
                isFromUser: false
            )
        )
    }

    func runLocalAlgorithmFallback(_ request: LocalAlgorithmFallbackRequest) {
        localAlgorithmFallbackRequest = nil
        let result = localCalculationResult(
            userText: request.userText,
            aiReply: nil,
            mode: request.mode,
            mealType: nil,
            consumedAt: nil,
            referenceDate: request.referenceDate,
            forceQuickEstimate: false
        )
        messages.append(AssistantMessage(text: result.reply, isFromUser: false))
        applyPendingCalculationIfAvailable(result)
    }

    func cancelLocalAlgorithmFallback() {
        localAlgorithmFallbackRequest = nil
        messages.append(
            AssistantMessage(
                text: AppText.text(
                    "已取消本地算法估算。你可以稍后重试，或到“我的”里检查 API key。",
                    "Local estimation was canceled. You can try again later or check your API key in Me.",
                    language: language
                ),
                isFromUser: false
            )
        )
    }

    private func applyLocalCalculationAfterAI(
        userText: String,
        aiReply: AssistantAIReply,
        mode: AssistantMode,
        mealType: MealType,
        consumedAt: Date,
        referenceDate: Date
    ) {
        let result = localCalculationResult(
            userText: userText,
            aiReply: aiReply,
            mode: mode,
            mealType: mealType,
            consumedAt: consumedAt,
            referenceDate: referenceDate,
            forceQuickEstimate: true
        )

        guard let calculation = result.calculation else {
            messages.append(
                AssistantMessage(
                    text: AppText.text(
                        "我已经理解这条记录，但还不能可靠估算这个食物的热量。请再补充一个更常见的食物名称、克重或主要配料。",
                        "I understand this record, but I still cannot estimate this food reliably yet. Please add a more common food name, weight, or main ingredients.",
                        language: language
                    ),
                    isFromUser: false
                )
            )
            return
        }

        pendingMealType = mealType
        pendingConsumedAt = consumedAt
        pendingCalculation = calculation
    }

    private func localCalculationResult(
        userText: String,
        aiReply: AssistantAIReply?,
        mode: AssistantMode,
        mealType: MealType?,
        consumedAt: Date?,
        referenceDate: Date,
        forceQuickEstimate: Bool
    ) -> FoodAssistantTurnResult {
        let localInput = localCalculationInput(
            userText: userText,
            aiReply: aiReply,
            mealType: mealType,
            consumedAt: consumedAt,
            forceQuickEstimate: forceQuickEstimate
        )

        var session = FoodConversationSession()
        return probabilisticCoordinator.handle(
            userText: localInput,
            mode: mode,
            session: &session,
            referenceDate: referenceDate,
            language: language
        )
    }

    private func localCalculationInput(
        userText: String,
        aiReply: AssistantAIReply?,
        mealType: MealType?,
        consumedAt: Date?,
        forceQuickEstimate: Bool
    ) -> String {
        var parts: [String] = []
        if let mealType {
            parts.append(mealType.title(language: .chinese))
        }
        if let consumedAt {
            parts.append(Self.localDateFormatter.string(from: consumedAt))
        }
        if let normalized = aiReply?.normalizedFoodText?.trimmingCharacters(in: .whitespacesAndNewlines), !normalized.isEmpty {
            parts.append(normalized)
        } else {
            parts.append(userText)
        }
        if forceQuickEstimate {
            parts.append("不知道细节，直接估算")
        }
        return parts.joined(separator: "，")
    }

    private func applyPendingCalculationIfAvailable(_ result: FoodAssistantTurnResult) {
        guard result.shouldOfferSave,
              let calculation = result.calculation,
              let mealType = result.mealType,
              let consumedAt = result.consumedAt else {
            return
        }
        pendingMealType = mealType
        pendingConsumedAt = consumedAt
        pendingCalculation = calculation
    }

    private static let localDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

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
        messages.append(
            AssistantMessage(
                text: AppText.text(
                    "已保存到本地记录：\(AppText.shortDate(record.consumedAt, language: language)) \(record.mealType.title(language: language)) \(record.calculation.foodDisplayName)，约 \(kcal) kcal。",
                    "Saved locally: \(AppText.shortDate(record.consumedAt, language: language)) \(record.mealType.title(language: language)) \(record.calculation.foodDisplayName), about \(kcal) kcal.",
                    language: language
                ),
                isFromUser: false
            )
        )
    }

    private func consumedAtCandidate(for mode: AssistantMode, text: String, referenceDate: Date) -> Date? {
        switch mode {
        case .foodLog:
            return MealDateResolver.detectedDate(in: text, referenceDate: referenceDate) ?? Calendar.current.startOfDay(for: referenceDate)
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
            return aiReply.consumedAt(referenceDate: referenceDate) ?? detectedDate ?? Calendar.current.startOfDay(for: referenceDate)
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
        dashboardContext: String,
        language: AppLanguage
    ) async throws -> AssistantAIReply {
        let context = PromptContext(
            userText: userText,
            mode: mode.title(language: language),
            mealType: mealType?.title(language: language),
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

        let responseLanguage = language.aiInstructionName
        let systemPrompt = """
        你是 BHealth 的 AI 饮食热量记录助手。必须遵守：
        1. AI 负责理解自然语言、追问缺失信息、整理食物、份量、餐别和日期；最终 kcal 会由 App 的本地计算器根据你的结构化理解再计算。
        2. local_calculation_context 只提供会话和日期背景；不要假装它已经完成热量计算。
        3. 如果食物复杂或信息模糊，你应先追问最影响结果的 1-2 个问题；如果用户说不知道或直接估算，可以标记为可估算。
        4. 不要编造品牌官方菜单、包装标签或来源版本；品牌食品缺少官方资料时要说明。
        5. 每次最多追问 1-2 个最影响结果的信息。如果信息已足够，回复应说明你理解成了什么，并让用户查看下方估算确认。
        6. 只有用户明确确认后才能保存记录。你现在只能建议用户确认，不能声称已经保存。
        7. 不要在 reply 里直接给 kcal 数字；estimated_energy_kcal、energy_low_kcal、energy_high_kcal 填 null。
        8. 记录饮食/历史数据添加模式必须确认餐别；“早上/中午/晚上/今晚/昨晚”等自然表达可以分别理解为早餐/午餐/晚餐。如果用户没有说明早餐、午餐、晚餐、下午茶、加餐/零食或夜宵，先追问餐别，不要要求保存。
        9. 历史数据添加模式必须确认日期；如果日期不明确，先追问日期，不要要求保存。相对日期要基于 current_date 转成 YYYY-MM-DD。
        10. food_items 只写具体食品或饮品名称，不要写整句聊天、请求语气或“帮我估算”。
        11. 如果模式是“健康助手”，提供通用建议、趋势判断、粗略减重估计，不要要求保存饮食记录，should_offer_save 必须为 false。
        12. normalized_food_text 是给本地计算器使用的隐藏字段，优先用简体中文，保留食物名称、数量、容器、稀稠度、配料、吃完比例等关键信息，不要包含聊天语气；信息不足时填 null。
        13. 给用户看的 reply 不能提到 local_calculation_context、算法、程序计算、USDA、数据库、概率、先验、配方原型等实现细节；要像自然的 AI 助手一样追问和确认。
        14. reply、assumptions、source_summary 必须使用 \(responseLanguage)。如果用户输入是另一种语言，也要优先服从这个 App 语言设置。
        15. 输出严格 JSON，不要 Markdown，不要代码块。

        JSON schema:
        {
          "reply": "给用户看的 \(responseLanguage) 回复",
          "assistant_state": "collecting|calculating|confirming|low_confidence|needs_source",
          "confidence": "high|medium|low|none",
          "should_offer_save": true,
          "estimated_energy_kcal": null,
          "energy_low_kcal": null,
          "energy_high_kcal": null,
          "meal_type": "breakfast|lunch|dinner|afternoon_tea|snack|late_night|other|null",
          "consumed_at": "YYYY-MM-DD|null",
          "food_items": ["鸡蛋", "拿铁", "吐司"],
          "normalized_food_text": "早餐 一碗偏稠小米粥 无糖|null",
          "assumptions": ["用于保存快照的关键假设，使用 \(responseLanguage)"],
          "source_summary": "来源摘要，使用 \(responseLanguage)"
        }
        """

        let userPrompt = """
        local_calculation_context:
        \(contextJSON)

        请基于上面的本地计算上下文回复用户。
        App 当前语言是：\(responseLanguage)。所有面向用户的文字必须使用这个语言。
        模式是：\(mode.title(language: language))。
        如果是记录饮食或历史数据添加：
        - 如果用户没有明确餐别，先追问“这是哪一餐？”，meal_type=null，should_offer_save=false。
        - 如果是历史数据添加且用户没有明确日期，先追问“这条记录是哪一天？”，consumed_at=null，should_offer_save=false。
        - 如果已经明确餐别，把 meal_type 和 consumed_at 纳入回复。meal_type 只能使用 breakfast/lunch/dinner/afternoon_tea/snack/late_night/other，consumed_at 只能使用 YYYY-MM-DD 或 null。
        - 如果是记录饮食，consumed_at 默认使用 current_date 的日期；但用户明确说“昨天/昨晚/前天”等相对日期时，要基于 current_date 转成对应日期。
        - 不要自己直接输出最终 kcal；如果用户描述足够可估算，把 should_offer_save 设为 true，并填写 normalized_food_text，App 会在你回复后计算。
        - 如果用户描述足够但份量仍不精确，normalized_food_text 可以保留“普通碗/一份/不知道细节/直接估算”等信息。
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
    let normalizedFoodText: String?
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
        case normalizedFoodText = "normalized_food_text"
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

    func estimatedCalculation(for userText: String, language: AppLanguage = .chinese) -> MealCalculationResult? {
        guard let estimatedEnergyKcal, estimatedEnergyKcal > 0 else { return nil }

        let low = energyLowKcal ?? estimatedEnergyKcal * 0.75
        let high = energyHighKcal ?? estimatedEnergyKcal * 1.25
        let source = sourceSummary ?? AppText.text("AI 推理估算", "AI estimate", language: language)
        let snapshotAssumptions = assumptions?.isEmpty == false ? assumptions ?? [] : [
            AppText.text("根据你的描述做粗略区间估算。", "Made a rough range estimate from your description.", language: language)
        ]
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

    func message(language: AppLanguage) -> String {
        AppText.text("AI 回复无法解析。", "The AI response could not be parsed.", language: language)
    }

    var errorDescription: String? {
        message(language: .chinese)
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
