//
//  FoodEstimationModels.swift
//  BHealth
//
//  Created by Codex on 2026-06-27.
//

import Foundation

enum FoodEvidenceSource: String, Codable, Hashable, Sendable {
    case explicitUserStatement
    case llmExtraction
    case databaseMatch
    case categoryPrior
    case recipePrototype
    case assumedDefault
}

struct FoodEvidence: Codable, Hashable, Sendable {
    let field: String
    let normalizedValue: String
    let source: FoodEvidenceSource
    let confidence: Double
    let userVisibleDescription: String
}

enum FoodCategory: String, Codable, Hashable, Sendable {
    case porridge
    case cookedRice
    case egg
    case beverage
    case bakery
    case fruit
    case nut
    case noodle
    case soup
    case homeDish
    case unknown
}

enum PreparationMethod: String, Codable, Hashable, Sendable {
    case boiled
    case fried
    case steamed
    case raw
    case unknown
}

enum ContainerClass: String, Codable, CaseIterable, Hashable, Sendable {
    case smallRiceBowl
    case regularRiceBowl
    case largeSoupBowl
    case smallCup
    case regularCup
    case largeMug
    case smallPlate
    case regularPlate
    case largePlate
    case tablespoon
    case teaspoon
    case handful
    case piece
    case slice
    case package
    case unknown
}

enum FillLevel: String, Codable, Hashable, Sendable {
    case quarter
    case half
    case threeQuarters
    case eightyPercent
    case nearlyFull
    case full
    case heaped
    case unknown
}

enum ConsistencyClass: String, Codable, Hashable, Sendable {
    case veryThin
    case thin
    case regular
    case thick
    case veryThick
    case unknown
}

enum SizeDescriptor: String, Codable, Hashable, Sendable {
    case small
    case regular
    case large
    case unknown
}

enum ConsumedFraction: String, Codable, Hashable, Sendable {
    case quarter
    case half
    case most
    case all
    case unknown
}

enum FoodAddition: String, Codable, Hashable, Sendable {
    case sugar
    case milk
    case condensedMilk
    case oil
    case sauce
    case nuts
}

enum FoodExclusion: String, Codable, Hashable, Sendable {
    case noSugar
    case noMilk
    case noOil
    case noSauce
}

enum FoodField: String, Codable, Hashable, Sendable {
    case mealType
    case consumedAt
    case foodIdentity
    case recipeVariant
    case containerClass
    case fillLevel
    case consistency
    case highCalorieAdditions
    case consumedFraction
    case packageWeight
    case spoonType
}

struct FoodCandidate: Codable, Hashable, Sendable {
    let foodID: String
    let displayName: String
    let category: FoodCategory
    let confidence: Double
}

struct FoodEventDraft: Codable, Hashable, Sendable {
    var rawText: String
    var mealType: MealType?
    var consumedAt: Date?

    var foodCandidates: [FoodCandidate]
    var selectedFoodID: String?
    var foodCategory: FoodCategory?

    var brand: String?
    var market: String?
    var preparationMethod: PreparationMethod?

    var exactWeightGrams: Double?
    var exactVolumeMilliliters: Double?
    var explicitServingCount: Double?

    var containerClass: ContainerClass?
    var fillLevel: FillLevel?
    var consistencyClass: ConsistencyClass?
    var sizeDescriptor: SizeDescriptor?
    var consumedFraction: ConsumedFraction?

    var additions: [FoodAddition]
    var exclusions: [FoodExclusion]

    var evidence: [FoodEvidence]
    var unresolvedFields: [FoodField]
    var userRequestedQuickEstimate: Bool
    var questionCount: Int

    init(
        rawText: String,
        mealType: MealType? = nil,
        consumedAt: Date? = nil,
        foodCandidates: [FoodCandidate] = [],
        selectedFoodID: String? = nil,
        foodCategory: FoodCategory? = nil,
        brand: String? = nil,
        market: String? = "generic_cn",
        preparationMethod: PreparationMethod? = nil,
        exactWeightGrams: Double? = nil,
        exactVolumeMilliliters: Double? = nil,
        explicitServingCount: Double? = nil,
        containerClass: ContainerClass? = nil,
        fillLevel: FillLevel? = nil,
        consistencyClass: ConsistencyClass? = nil,
        sizeDescriptor: SizeDescriptor? = nil,
        consumedFraction: ConsumedFraction? = nil,
        additions: [FoodAddition] = [],
        exclusions: [FoodExclusion] = [],
        evidence: [FoodEvidence] = [],
        unresolvedFields: [FoodField] = [],
        userRequestedQuickEstimate: Bool = false,
        questionCount: Int = 0
    ) {
        self.rawText = rawText
        self.mealType = mealType
        self.consumedAt = consumedAt
        self.foodCandidates = foodCandidates
        self.selectedFoodID = selectedFoodID
        self.foodCategory = foodCategory
        self.brand = brand
        self.market = market
        self.preparationMethod = preparationMethod
        self.exactWeightGrams = exactWeightGrams
        self.exactVolumeMilliliters = exactVolumeMilliliters
        self.explicitServingCount = explicitServingCount
        self.containerClass = containerClass
        self.fillLevel = fillLevel
        self.consistencyClass = consistencyClass
        self.sizeDescriptor = sizeDescriptor
        self.consumedFraction = consumedFraction
        self.additions = additions
        self.exclusions = exclusions
        self.evidence = evidence
        self.unresolvedFields = unresolvedFields
        self.userRequestedQuickEstimate = userRequestedQuickEstimate
        self.questionCount = questionCount
    }
}

enum EstimateConfidence: String, Codable, Hashable, Sendable {
    case high
    case mediumHigh
    case medium
    case low
    case veryLow

    var legacyLabel: String {
        switch self {
        case .high, .mediumHigh:
            return "medium"
        case .medium, .low, .veryLow:
            return "low"
        }
    }

    var displayName: String {
        displayName(language: .chinese)
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .high:
            return AppText.text("高", "High", language: language)
        case .mediumHigh:
            return AppText.text("中高", "Medium-high", language: language)
        case .medium:
            return AppText.text("中等", "Medium", language: language)
        case .low:
            return AppText.text("低", "Low", language: language)
        case .veryLow:
            return AppText.text("很低", "Very low", language: language)
        }
    }
}

struct UncertaintyDriver: Codable, Hashable, Sendable {
    let description: String
}

struct EstimateAssumption: Codable, Hashable, Sendable {
    let description: String
}

struct CalorieEstimate: Codable, Hashable, Sendable {
    let p10: Double
    let p25: Double
    let median: Double
    let mean: Double
    let p75: Double
    let p90: Double
    let confidence: EstimateConfidence
    let uncertaintyDrivers: [UncertaintyDriver]
    let assumptions: [EstimateAssumption]
    let sourceIDs: [String]
}

struct ResolvedFoodEvent: Codable, Hashable, Sendable {
    let draft: FoodEventDraft
    let evidence: [FoodEvidence]
}

struct FoodConversationSession: Hashable {
    var drafts: [FoodEventDraft] = []
    var askedFields: [FoodField] = []
    var turnCount = 0
}

struct FoodAssistantTurnResult {
    let reply: String
    let calculation: MealCalculationResult?
    let mealType: MealType?
    let consumedAt: Date?
    let shouldOfferSave: Bool
}
