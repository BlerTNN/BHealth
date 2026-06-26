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
        AssistantMessage(text: "你好，我是你的 AI 健康助手。你可以直接告诉我今天吃了什么，我会先追问关键细节，再用本地营养数据做粗略计算。", isFromUser: false)
    ]
}

@MainActor
final class FoodAssistantViewModel: ObservableObject {
    @Published var draftMessage = ""
    @Published var apiKeyInput = ""
    @Published var messages = AssistantMessage.sample
    @Published var isSending = false
    @Published var hasAPIKey: Bool
    @Published var apiKeyStatusMessage: String?
    @Published var pendingCalculation: MealCalculationResult?
    @Published private(set) var savedRecords: [SavedMealRecord]

    private let apiKeyStore: KeychainAPIKeyStore
    private let engine: FoodAssistantEngine
    private let calculator: MealNutritionCalculator
    private let recordStore: MealRecordLocalStore

    init(
        apiKeyStore: KeychainAPIKeyStore = .shared,
        engine: FoodAssistantEngine = FoodAssistantEngine(),
        calculator: MealNutritionCalculator = MealNutritionCalculator(),
        recordStore: MealRecordLocalStore = MealRecordLocalStore()
    ) {
        self.apiKeyStore = apiKeyStore
        self.engine = engine
        self.calculator = calculator
        self.recordStore = recordStore
        self.hasAPIKey = apiKeyStore.hasAPIKey
        self.savedRecords = recordStore.load()
    }

    func saveAPIKey() {
        do {
            try apiKeyStore.saveAPIKey(apiKeyInput)
            apiKeyInput = ""
            hasAPIKey = true
            apiKeyStatusMessage = "DeepSeek API key 已保存到系统 Keychain。"
        } catch {
            apiKeyStatusMessage = error.localizedDescription
        }
    }

    func deleteAPIKey() {
        do {
            try apiKeyStore.deleteAPIKey()
            hasAPIKey = false
            apiKeyStatusMessage = "已从 Keychain 删除 DeepSeek API key。"
        } catch {
            apiKeyStatusMessage = error.localizedDescription
        }
    }

    func sendDraftMessage() async {
        let trimmed = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draftMessage = ""
        await send(trimmed)
    }

    func send(_ text: String) async {
        guard !isSending else { return }

        messages.append(AssistantMessage(text: text, isFromUser: true))
        isSending = true
        pendingCalculation = nil
        defer { isSending = false }

        let calculation = calculator.calculate(from: text)

        guard hasAPIKey else {
            let reply = localFallbackReply(for: text, calculation: calculation, reason: "还没有保存 DeepSeek API key。")
            messages.append(AssistantMessage(text: reply, isFromUser: false))
            pendingCalculation = calculation
            return
        }

        do {
            let aiReply = try await engine.respond(
                userText: text,
                history: messages,
                calculation: calculation
            )

            messages.append(AssistantMessage(text: aiReply.reply, isFromUser: false))
            if aiReply.shouldOfferSave {
                pendingCalculation = calculation
            }
        } catch {
            let reply = localFallbackReply(for: text, calculation: calculation, reason: error.localizedDescription)
            messages.append(AssistantMessage(text: reply, isFromUser: false))
            pendingCalculation = calculation
        }
    }

    func savePendingCalculation() {
        guard let pendingCalculation else { return }

        let record = SavedMealRecord(
            id: UUID(),
            confirmedAt: Date(),
            calculation: pendingCalculation
        )

        var records = recordStore.load()
        records.insert(record, at: 0)
        recordStore.save(records)
        savedRecords = records
        self.pendingCalculation = nil

        let kcal = Int(record.calculation.totalEnergyKcal.rounded())
        messages.append(AssistantMessage(text: "已确认并保存到本地饮食记录：约 \(kcal) kcal。", isFromUser: false))
    }

    private func localFallbackReply(for text: String, calculation: MealCalculationResult?, reason: String) -> String {
        if let calculation {
            return """
            我先用本地 USDA Foundation Foods 做了粗略计算，但 AI 回复暂时不可用：\(reason)

            估计摄入：约 \(Int(calculation.totalEnergyKcal.rounded())) kcal
            合理范围：\(Int(calculation.rangeLowKcal.rounded()))-\(Int(calculation.rangeHighKcal.rounded())) kcal
            可信度：\(calculation.confidence == "low" ? "较低" : "中等")

            主要依据：\(calculation.items.map { $0.matchedFoodName }.joined(separator: "；"))
            是否确认保存这次饮食记录？
            """
        }

        return """
        我现在还不能完成 AI 解析：\(reason)

        你可以先补充更明确的信息，例如食物名称、数量或克重。比如：“鸡蛋 1 个，牛奶 250g”。
        """
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
        calculation: MealCalculationResult?
    ) async throws -> AssistantAIReply {
        let context = PromptContext(userText: userText, calculation: calculation)
        let contextData = try JSONEncoder.promptEncoder.encode(context)
        let contextJSON = String(data: contextData, encoding: .utf8) ?? "{}"

        let recentHistory = history.suffix(8).map { message in
            DeepSeekMessage(role: message.isFromUser ? "user" : "assistant", content: message.text)
        }

        let systemPrompt = """
        你是 BHealth 的 AI 饮食热量记录助手。必须遵守：
        1. AI 负责理解自然语言、追问缺失信息、解释结果；代码负责食物库查询和热量计算。
        2. 不要凭记忆编造品牌菜单或营养数据，不要输出伪精确热量。
        3. 只能基于 local_calculation_context 中的 deterministic calculation 给出热量；没有 calculation 时优先追问 1-2 个关键问题。
        4. 只有用户明确确认后才能保存记录。你现在只能建议用户确认，不能声称已经保存。
        5. 输出严格 JSON，不要 Markdown，不要代码块。

        JSON schema:
        {
          "reply": "给用户看的中文回复",
          "assistant_state": "collecting|calculating|confirming|low_confidence|needs_source",
          "confidence": "high|medium|low|none",
          "should_offer_save": true
        }
        """

        let userPrompt = """
        local_calculation_context:
        \(contextJSON)

        请基于上面的本地计算上下文回复用户。
        如果有 calculation，必须包含：估计热量、合理范围、可信度、关键假设、来源版本，并询问是否确认保存。
        如果没有 calculation，追问最影响结果的 1-2 个信息，例如食物、份量、克重、品牌/地区或配料。
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

    enum CodingKeys: String, CodingKey {
        case reply
        case assistantState = "assistant_state"
        case confidence
        case shouldOfferSave = "should_offer_save"
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
}

enum AssistantAIReplyError: LocalizedError {
    case invalidEncoding

    var errorDescription: String? {
        "AI 回复无法解析。"
    }
}

struct MealRecordLocalStore {
    private let key = "BHealth.savedMealRecords.v1"

    func load() -> [SavedMealRecord] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder.recordDecoder.decode([SavedMealRecord].self, from: data)) ?? []
    }

    func save(_ records: [SavedMealRecord]) {
        guard let data = try? JSONEncoder.recordEncoder.encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private struct PromptContext: Codable {
    let userText: String
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
