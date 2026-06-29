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
                await applyLocalCalculationAfterAI(
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
    ) async {
        let result = localCalculationResult(
            userText: userText,
            aiReply: aiReply,
            mode: mode,
            mealType: mealType,
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

        guard let reviewedCalculation = await sanityCheckedCalculation(
            localCalculation: calculation,
            userText: userText,
            aiReply: aiReply,
            mode: mode,
            mealType: mealType,
            consumedAt: consumedAt
        ) else {
            return
        }

        pendingMealType = mealType
        pendingConsumedAt = consumedAt
        pendingCalculation = reviewedCalculation
    }

    private func sanityCheckedCalculation(
        localCalculation: MealCalculationResult,
        userText: String,
        aiReply: AssistantAIReply,
        mode: AssistantMode,
        mealType: MealType,
        consumedAt: Date
    ) async -> MealCalculationResult? {
        do {
            let review = try await engine.reviewEstimate(
                userText: userText,
                aiReply: aiReply,
                calculation: localCalculation,
                mode: mode,
                mealType: mealType,
                consumedAt: consumedAt,
                language: language
            )
            return review.correctedCalculation(
                fallback: localCalculation,
                userText: calculationFoodText(userText: userText, aiReply: aiReply),
                language: language
            ) ?? localCalculation
        } catch {
            if error is DeepSeekError || error is KeychainError {
                handleAPIUnavailable(
                    userText: userText,
                    mode: mode,
                    reason: assistantErrorMessage(error, language: language),
                    referenceDate: Date()
                )
                return nil
            }

            if EstimatePlausibility.isCounterintuitive(calculation: localCalculation, userText: userText) {
                messages.append(
                    AssistantMessage(
                        text: AppText.text(
                            "我已经理解这条记录，但最终常识校验暂时失败。为了避免显示明显不可靠的热量，请稍后重试，或补充更明确的份量后再发送。",
                            "I understood this record, but the final common-sense check failed. To avoid showing a clearly unreliable calorie estimate, please try again later or add a clearer portion.",
                            language: language
                        ),
                        isFromUser: false
                    )
                )
                return nil
            }
            return localCalculation
        }
    }

    private func localCalculationResult(
        userText: String,
        aiReply: AssistantAIReply?,
        mode: AssistantMode,
        mealType: MealType?,
        referenceDate: Date,
        forceQuickEstimate: Bool
    ) -> FoodAssistantTurnResult {
        let localInput = localCalculationInput(
            userText: userText,
            aiReply: aiReply,
            mealType: mealType,
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
        forceQuickEstimate: Bool
    ) -> String {
        var parts: [String] = []
        if let mealType {
            parts.append(mealType.title(language: .chinese))
        }
        parts.append(calculationFoodText(userText: userText, aiReply: aiReply))
        if forceQuickEstimate {
            parts.append("不知道细节，直接估算")
        }
        return parts.joined(separator: "，")
    }

    private func calculationFoodText(userText: String, aiReply: AssistantAIReply?) -> String {
        if let normalized = aiReply?.normalizedFoodText,
           !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let cleaned = cleanedCalculationText(normalized)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        let itemText = (aiReply?.foodItems ?? [])
            .map(cleanedCalculationText)
            .filter { !$0.isEmpty }
            .joined(separator: "，")
        if !itemText.isEmpty {
            return itemText
        }

        return cleanedCalculationText(userText)
    }

    private func cleanedCalculationText(_ value: String) -> String {
        var text = MealFoodNameFormatter.cleaned(value)
        let patterns = [
            #"\d{4}[-/\.]\d{1,2}[-/\.]\d{1,2}"#,
            #"\d{1,2}月\d{1,2}[日号]?"#,
            #"\d+(?:\.\d+)?\s*(?:kcal|千卡|大卡|卡路里)"#,
            #"(?:已记录|待确认记录|待确认|请确认是否正确|请确认|如果正确|系统将估算热量并保存|系统将|保存记录|已保存)"#
        ]

        for pattern in patterns {
            text = Self.replacingMatches(in: text, pattern: pattern, with: "")
        }

        return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
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

    private static func replacingMatches(in text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
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
        6. 只有用户明确确认后才能保存记录。你现在只能建议用户确认，不能声称已经保存；reply 里不要写“已记录”“已保存”。
        7. 不要在 reply 里直接给 kcal 数字；estimated_energy_kcal、energy_low_kcal、energy_high_kcal 填 null。
        8. 记录饮食/历史数据添加模式必须确认餐别；“早上/中午/晚上/今晚/昨晚”等自然表达可以分别理解为早餐/午餐/晚餐。如果用户没有说明早餐、午餐、晚餐、下午茶、加餐/零食或夜宵，先追问餐别，不要要求保存。
        9. 历史数据添加模式必须确认日期；如果日期不明确，先追问日期，不要要求保存。相对日期要基于 current_date 转成 YYYY-MM-DD。
        10. food_items 只写具体食品或饮品名称，不要写整句聊天、请求语气或“帮我估算”。
        11. 如果模式是“健康助手”，提供通用建议、趋势判断、粗略减重估计，不要要求保存饮食记录，should_offer_save 必须为 false。
        12. normalized_food_text 是给本地计算器使用的隐藏字段，优先用简体中文，保留食物名称、数量、容器、稀稠度、配料、吃完比例等关键信息，不要包含日期、餐别、kcal、聊天语气、确认话术；信息不足时填 null。
        13. 给用户看的 reply 不能提到 local_calculation_context、算法、程序计算、USDA、数据库、概率、先验、配方原型等实现细节；要像自然的 AI 助手一样追问和确认。
        14. reply、assumptions、source_summary 必须使用 \(responseLanguage)。如果用户输入是另一种语言，也要优先服从这个 App 语言设置。
        15. 输出严格 JSON，不要 Markdown，不要代码块。reply 必须是非空字符串，should_offer_save 必须是 JSON boolean，不要写成字符串。

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
        - 只有食物信息、餐别和必要日期都明确时，才可以询问“请查看下方估算并确认”，并把 should_offer_save 设为 true。不要说“已记录”或“已保存”。
        如果是健康助手：
        - 使用 dashboard_context 总结用户近况。
        - 可以估算热量缺口对应的大概体重变化，但必须说明只是粗略推断。
        - 不要填写待保存热量，should_offer_save=false。
        """

        let messages = [DeepSeekMessage(role: "system", content: systemPrompt)]
            + recentHistory
            + [DeepSeekMessage(role: "user", content: userPrompt)]

        let content = try await client.complete(messages: messages)
        return AssistantAIReply.parseOrFallback(from: content, language: language)
    }

    func reviewEstimate(
        userText: String,
        aiReply: AssistantAIReply,
        calculation: MealCalculationResult,
        mode: AssistantMode,
        mealType: MealType,
        consumedAt: Date,
        language: AppLanguage
    ) async throws -> CalorieSanityReview {
        let context = SanityReviewContext(
            originalUserText: userText,
            aiReply: aiReply,
            localCalculation: calculation,
            mode: mode.title(language: language),
            mealType: mealType.title(language: language),
            consumedAt: consumedAt,
            appLanguage: language.aiInstructionName
        )
        let contextData = try JSONEncoder.promptEncoder.encode(context)
        let contextJSON = String(data: contextData, encoding: .utf8) ?? "{}"
        let responseLanguage = language.aiInstructionName

        let systemPrompt = """
        你是 BHealth 在展示结果前的最终热量常识校验员。必须遵守：
        1. 输入里有用户原话、AI 对自然语言的理解、本地估算结果。你的任务是判断这个估算在常识上是否明显离谱。
        2. 只有“特别反常识”才覆盖，比如一份普通饭碗/一碗/一份单人餐被估到 1500 kcal 以上，且用户没有说超大份、很多油、很多酱、多份、吃撑或多种额外高热量食物。
        3. 如果本地估算只是粗略但仍可能成立，should_override=false。
        4. 如果应该覆盖，请根据用户原话重新给出 corrected_energy_kcal、corrected_low_kcal、corrected_high_kcal。使用常见单人份经验和食物组成推理，不要机械累加配料为多份主菜。
        5. 例子：普通饭碗量的三文鱼、紫薯、糙米能量碗，少量鹰嘴豆和紫薯泥，通常约 450-700 kcal，不应是几千 kcal。
        6. food_items 只写用户实际吃的食品/菜品名称，不要写日期、餐别、kcal、确认话术或算法过程。
        7. assumptions、source_summary、reply_adjustment 必须使用 \(responseLanguage)。不要提到算法、数据库、概率、先验、蒙特卡洛或程序实现。
        8. 输出严格 JSON，不要 Markdown，不要代码块。

        JSON schema:
        {
          "should_override": false,
          "corrected_energy_kcal": null,
          "corrected_low_kcal": null,
          "corrected_high_kcal": null,
          "confidence": "high|medium|low",
          "food_items": ["三文鱼紫薯糙米能量碗"],
          "assumptions": ["按普通单人份饭碗估算"],
          "source_summary": "常见单人份经验估算",
          "reply_adjustment": "可选，给用户看的简短修正说明"
        }
        """

        let userPrompt = """
        sanity_review_context:
        \(contextJSON)

        请在结果展示给用户前做常识校验。App 当前语言是：\(responseLanguage)。
        """

        let content = try await client.complete(
            messages: [
                DeepSeekMessage(role: "system", content: systemPrompt),
                DeepSeekMessage(role: "user", content: userPrompt)
            ],
            temperature: 0
        )
        return try CalorieSanityReview.parse(from: content)
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

    init(
        reply: String,
        assistantState: String = "collecting",
        confidence: String = "none",
        shouldOfferSave: Bool = false,
        estimatedEnergyKcal: Double? = nil,
        energyLowKcal: Double? = nil,
        energyHighKcal: Double? = nil,
        mealTypeRaw: String? = nil,
        consumedAtRaw: String? = nil,
        foodItems: [String]? = nil,
        normalizedFoodText: String? = nil,
        assumptions: [String]? = nil,
        sourceSummary: String? = nil
    ) {
        self.reply = reply
        self.assistantState = assistantState
        self.confidence = confidence
        self.shouldOfferSave = shouldOfferSave
        self.estimatedEnergyKcal = estimatedEnergyKcal
        self.energyLowKcal = energyLowKcal
        self.energyHighKcal = energyHighKcal
        self.mealTypeRaw = mealTypeRaw
        self.consumedAtRaw = consumedAtRaw
        self.foodItems = foodItems
        self.normalizedFoodText = normalizedFoodText
        self.assumptions = assumptions
        self.sourceSummary = sourceSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reply = container.decodeLossyString(forKey: .reply) ?? ""
        assistantState = container.decodeLossyString(forKey: .assistantState) ?? "collecting"
        confidence = container.decodeLossyString(forKey: .confidence) ?? "none"
        shouldOfferSave = container.decodeLossyBool(forKey: .shouldOfferSave, defaultValue: false)
        estimatedEnergyKcal = container.decodeLossyDouble(forKey: .estimatedEnergyKcal)
        energyLowKcal = container.decodeLossyDouble(forKey: .energyLowKcal)
        energyHighKcal = container.decodeLossyDouble(forKey: .energyHighKcal)
        mealTypeRaw = container.decodeLossyString(forKey: .mealTypeRaw)
        consumedAtRaw = container.decodeLossyString(forKey: .consumedAtRaw)
        foodItems = container.decodeLossyStringArray(forKey: .foodItems)
        normalizedFoodText = container.decodeLossyString(forKey: .normalizedFoodText)
        assumptions = container.decodeLossyStringArray(forKey: .assumptions)
        sourceSummary = container.decodeLossyString(forKey: .sourceSummary)
    }

    static func parse(from content: String) throws -> AssistantAIReply {
        let data = try AssistantJSONPayload.data(from: content)
        return try JSONDecoder().decode(AssistantAIReply.self, from: data)
    }

    static func parseOrFallback(from content: String, language: AppLanguage) -> AssistantAIReply {
        do {
            let parsed = try parse(from: content)
            let reply = parsed.reply.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reply.isEmpty else {
                return plainTextFallback(from: content, language: language)
            }
            return parsed
        } catch {
            return plainTextFallback(from: content, language: language)
        }
    }

    private static func plainTextFallback(from content: String, language: AppLanguage) -> AssistantAIReply {
        AssistantAIReply(
            reply: AssistantTextFallback.reply(from: content, language: language),
            assistantState: "collecting",
            confidence: "none",
            shouldOfferSave: false
        )
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

struct CalorieSanityReview: Codable, Hashable {
    let shouldOverride: Bool
    let correctedEnergyKcal: Double?
    let correctedLowKcal: Double?
    let correctedHighKcal: Double?
    let confidence: String?
    let foodItems: [String]?
    let assumptions: [String]?
    let sourceSummary: String?
    let replyAdjustment: String?

    enum CodingKeys: String, CodingKey {
        case shouldOverride = "should_override"
        case correctedEnergyKcal = "corrected_energy_kcal"
        case correctedLowKcal = "corrected_low_kcal"
        case correctedHighKcal = "corrected_high_kcal"
        case confidence
        case foodItems = "food_items"
        case assumptions
        case sourceSummary = "source_summary"
        case replyAdjustment = "reply_adjustment"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shouldOverride = container.decodeLossyBool(forKey: .shouldOverride, defaultValue: false)
        correctedEnergyKcal = container.decodeLossyDouble(forKey: .correctedEnergyKcal)
        correctedLowKcal = container.decodeLossyDouble(forKey: .correctedLowKcal)
        correctedHighKcal = container.decodeLossyDouble(forKey: .correctedHighKcal)
        confidence = container.decodeLossyString(forKey: .confidence)
        foodItems = container.decodeLossyStringArray(forKey: .foodItems)
        assumptions = container.decodeLossyStringArray(forKey: .assumptions)
        sourceSummary = container.decodeLossyString(forKey: .sourceSummary)
        replyAdjustment = container.decodeLossyString(forKey: .replyAdjustment)
    }

    static func parse(from content: String) throws -> CalorieSanityReview {
        let data = try AssistantJSONPayload.data(from: content)
        return try JSONDecoder().decode(CalorieSanityReview.self, from: data)
    }

    func correctedCalculation(
        fallback: MealCalculationResult,
        userText: String,
        language: AppLanguage
    ) -> MealCalculationResult? {
        guard shouldOverride,
              let correctedEnergyKcal,
              correctedEnergyKcal > 0 else {
            return nil
        }

        let lowCandidate = correctedLowKcal ?? correctedEnergyKcal * 0.75
        let highCandidate = correctedHighKcal ?? correctedEnergyKcal * 1.25
        let low = max(0, min(lowCandidate, correctedEnergyKcal, highCandidate))
        let high = max(lowCandidate, correctedEnergyKcal, highCandidate)
        let normalizedConfidence = CalorieSanityReview.normalizedConfidence(confidence)
        let displayName = MealFoodNameFormatter.displayName(from: foodItems, fallback: fallback.foodDisplayName)
        let visibleName = displayName.isEmpty ? MealFoodNameFormatter.cleaned(userText) : displayName
        let correctedAssumptions = CalorieSanityReview.cleanedList(assumptions)
        let finalAssumptions = correctedAssumptions.isEmpty
            ? [AppText.text("按用户描述和常见单人份量做最终校验后估算。", "Estimated after a final common-sense check against the described single serving.", language: language)]
            : correctedAssumptions
        let source = sourceSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? sourceSummary!.trimmingCharacters(in: .whitespacesAndNewlines)
            : AppText.text("常见单人份经验估算", "Common single-serving estimate", language: language)

        let item = MealItemCalculation(
            rawText: visibleName,
            matchedFoodName: visibleName,
            fdcId: -2,
            estimatedGrams: fallback.items.map(\.estimatedGrams).reduce(0, +),
            energyKcal: correctedEnergyKcal,
            proteinG: nil,
            fatG: nil,
            carbohydrateG: nil,
            confidence: normalizedConfidence,
            sourceName: source,
            sourceVersion: "ai_sanity_review_v1",
            assumptions: finalAssumptions
        )

        return MealCalculationResult(
            items: [item],
            totalEnergyKcal: correctedEnergyKcal,
            rangeLowKcal: low,
            rangeHighKcal: high,
            confidence: normalizedConfidence,
            assumptions: finalAssumptions,
            sourceSummary: source
        )
    }

    private static func normalizedConfidence(_ value: String?) -> String {
        switch value?.lowercased() {
        case "high", "medium":
            return "medium"
        default:
            return "low"
        }
    }

    private static func cleanedList(_ values: [String]?) -> [String] {
        (values ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private enum EstimatePlausibility {
    static func isCounterintuitive(calculation: MealCalculationResult, userText: String) -> Bool {
        let normalized = userText
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let singleServingSignals = [
            "一碗", "普通碗", "饭碗", "一份", "普通份", "单人", "one bowl", "regular bowl", "one serving"
        ]
        let multipleSignals = ["两份", "三份", "多份", "很多油", "重油", "很多酱", "double", "large", "extra large"]
        let seemsSingleServing = singleServingSignals.contains { normalized.contains($0) }
        let explicitlyLarge = multipleSignals.contains { normalized.contains($0) }

        guard seemsSingleServing, !explicitlyLarge else { return false }
        return calculation.totalEnergyKcal > 1_500 || calculation.rangeHighKcal > 2_000
    }
}

private enum AssistantJSONPayload {
    static func data(from content: String) throws -> Data {
        let cleaned = cleanedText(from: content)

        if let data = cleaned.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }

        guard let object = firstJSONObject(in: cleaned),
              let data = object.data(using: .utf8) else {
            throw AssistantAIReplyError.invalidEncoding
        }

        return data
    }

    static func cleanedText(from content: String) -> String {
        content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```JSON", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func textWithoutFirstJSONObject(from text: String) -> String {
        guard let range = firstJSONObjectRange(in: text) else {
            return text
        }
        var remaining = text
        remaining.removeSubrange(range)
        return remaining.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstJSONObject(in text: String) -> String? {
        guard let range = firstJSONObjectRange(in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func firstJSONObjectRange(in text: String) -> ClosedRange<String.Index>? {
        var startIndex: String.Index?
        var depth = 0
        var isInsideString = false
        var isEscaped = false

        for index in text.indices {
            let character = text[index]

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                    continue
                }
                if character == "\\" {
                    isEscaped = true
                    continue
                }
                if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            if character == "\"" {
                isInsideString = true
                continue
            }

            if character == "{" {
                if depth == 0 {
                    startIndex = index
                }
                depth += 1
                continue
            }

            if character == "}", depth > 0 {
                depth -= 1
                if depth == 0, let startIndex {
                    return startIndex...index
                }
            }
        }

        return nil
    }
}

private enum AssistantTextFallback {
    static func reply(from content: String, language: AppLanguage) -> String {
        let cleaned = AssistantJSONPayload.cleanedText(from: content)
        if let reply = extractedReplyValue(from: cleaned) {
            return reply
        }

        let withoutJSON = AssistantJSONPayload.textWithoutFirstJSONObject(from: cleaned)
        let candidate = (withoutJSON.isEmpty ? cleaned : withoutJSON)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !candidate.isEmpty, !candidate.looksLikeRawJSON else {
            return AppText.text(
                "我理解了。你可以继续补充餐别、日期或大致份量，我会接着帮你记录。",
                "I understand. You can keep adding the meal, date, or rough portion, and I will continue helping you log it.",
                language: language
            )
        }

        return candidate
    }

    private static func extractedReplyValue(from text: String) -> String? {
        guard let keyRange = text.range(of: "\"reply\"") ?? text.range(of: "'reply'") else {
            return nil
        }
        guard let colonIndex = text[keyRange.upperBound...].firstIndex(of: ":") else {
            return nil
        }

        var index = text.index(after: colonIndex)
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
        guard index < text.endIndex else {
            return nil
        }

        let quote = text[index]
        guard quote == "\"" || quote == "'" else {
            return nil
        }

        var value = ""
        var isEscaped = false
        index = text.index(after: index)

        while index < text.endIndex {
            let character = text[index]
            if isEscaped {
                value.append(unescaped(character))
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == quote {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            } else {
                value.append(character)
            }
            index = text.index(after: index)
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func unescaped(_ character: Character) -> Character {
        switch character {
        case "n":
            return "\n"
        case "t":
            return "\t"
        case "r":
            return "\r"
        default:
            return character
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyString(forKey key: Key) -> String? {
        if (try? decodeNil(forKey: key)) == true {
            return nil
        }
        if let value = try? decode(String.self, forKey: key) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isNullLiteral ? nil : trimmed
        }
        if let value = try? decode(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }
        return nil
    }

    func decodeLossyBool(forKey key: Key, defaultValue: Bool) -> Bool {
        if let value = try? decode(Bool.self, forKey: key) {
            return value
        }
        if let value = decodeLossyString(forKey: key)?.lowercased() {
            if ["true", "yes", "y", "1", "是", "需要"].contains(value) {
                return true
            }
            if ["false", "no", "n", "0", "否", "不需要"].contains(value) {
                return false
            }
        }
        if let value = try? decode(Double.self, forKey: key) {
            return value != 0
        }
        return defaultValue
    }

    func decodeLossyDouble(forKey key: Key) -> Double? {
        if (try? decodeNil(forKey: key)) == true {
            return nil
        }
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return Double(value)
        }
        guard let value = decodeLossyString(forKey: key) else {
            return nil
        }

        let numeric = value
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "kcal", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "千卡", with: "")
            .replacingOccurrences(of: "大卡", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(numeric)
    }

    func decodeLossyStringArray(forKey key: Key) -> [String]? {
        if (try? decodeNil(forKey: key)) == true {
            return nil
        }
        if let values = try? decode([String].self, forKey: key) {
            return cleaned(values)
        }
        if let values = try? decode([Double].self, forKey: key) {
            return cleaned(values.map { String($0) })
        }
        if let value = decodeLossyString(forKey: key) {
            let separators = CharacterSet(charactersIn: "，,、;\n")
            let values = value
                .components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return cleaned(values)
        }
        return nil
    }

    private func cleaned(_ values: [String]) -> [String]? {
        let cleanedValues = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.isNullLiteral }
        return cleanedValues.isEmpty ? nil : cleanedValues
    }
}

private extension String {
    var isNullLiteral: Bool {
        let normalized = lowercased()
        return normalized == "null" || normalized == "nil" || normalized == "none" || normalized == "无"
    }

    var looksLikeRawJSON: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return false }
        return (first == "{" || first == "[") && trimmed.contains(":")
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

private struct SanityReviewContext: Codable {
    let originalUserText: String
    let aiReply: AssistantAIReply
    let localCalculation: MealCalculationResult
    let mode: String
    let mealType: String
    let consumedAt: Date
    let appLanguage: String
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
