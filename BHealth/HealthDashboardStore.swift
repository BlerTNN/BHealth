//
//  HealthDashboardStore.swift
//  BHealth
//
//  Created by Codex on 2026-06-26.
//

import Combine
import Foundation

#if canImport(HealthKit)
import HealthKit
#endif

struct UserHealthProfile: Codable, Hashable {
    var name: String
    var heightCm: Double?
    var weightKg: Double?
    var age: Int?
    var targetWeightKg: Double?
    var biologicalSex: String?
    var lastSyncedAt: Date?

    static let defaultProfile = UserHealthProfile(
        name: "Bill",
        heightCm: 175,
        weightKg: 70,
        age: 30,
        targetWeightKg: 68,
        biologicalSex: nil,
        lastSyncedAt: nil
    )
}

struct DailyHealthOverview: Identifiable, Hashable {
    let date: Date
    var intakeKcal: Double
    var activeEnergyKcal: Double
    var basalEnergyKcal: Double
    var stepCount: Double
    var basalIsEstimated: Bool

    var id: Date { Calendar.current.startOfDay(for: date) }

    var totalBurnKcal: Double {
        activeEnergyKcal + basalEnergyKcal
    }

    var balanceKcal: Double {
        totalBurnKcal - intakeKcal
    }
}

@MainActor
final class HealthDashboardStore: ObservableObject {
    @Published private(set) var profile: UserHealthProfile
    @Published private(set) var today: DailyHealthOverview
    @Published private(set) var weeklySummaries: [DailyHealthOverview]
    @Published private(set) var yearSummaries: [DailyHealthOverview]
    @Published private(set) var savedMealRecords: [SavedMealRecord]
    @Published var healthKitStatusMessage: String
    @Published var isSyncingHealthKit = false

    private let profileStore = ProfileLocalStore()
    private let mealRecordStore = MealRecordLocalStore()
    private let healthKitService = HealthKitService()
    private var healthMetricsByDay: [Date: HealthDayMetrics] = [:]
    private var mealRecordsCancellable: AnyCancellable?

    var healthKitAvailable: Bool {
        healthKitService.isAvailable
    }

    init() {
        profile = profileStore.load()
        savedMealRecords = mealRecordStore.load()
        today = DailyHealthOverview.empty(for: Date())
        weeklySummaries = []
        yearSummaries = []
        healthKitStatusMessage = healthKitService.isAvailable ? "尚未同步 Apple Health / Fitness" : "当前设备不可用 HealthKit"

        recomputeSummaries()
        mealRecordsCancellable = NotificationCenter.default.publisher(for: .mealRecordsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadMealRecords()
            }
    }

    func requestHealthAuthorizationAndRefresh() async {
        guard healthKitService.isAvailable else {
            healthKitStatusMessage = "当前设备不可用 HealthKit。请在 iPhone 或支持的模拟器上运行。"
            return
        }

        isSyncingHealthKit = true
        defer { isSyncingHealthKit = false }

        do {
            try await healthKitService.requestAuthorization()
            try await refreshFromHealthKit()
        } catch {
            healthKitStatusMessage = "Apple Health 同步失败：\(error.localizedDescription)"
        }
    }

    func refreshHealthDataIfPossible() async {
        guard healthKitService.isAvailable,
              profile.lastSyncedAt != nil,
              !isSyncingHealthKit else {
            return
        }

        isSyncingHealthKit = true
        defer { isSyncingHealthKit = false }

        do {
            try await refreshFromHealthKit()
        } catch {
            healthKitStatusMessage = "Apple Health / Fitness 自动刷新失败：\(error.localizedDescription)"
        }
    }

    func refreshFromHealthKit() async throws {
        let snapshot = try await healthKitService.fetchSnapshot()
        merge(snapshot: snapshot)
        profile.lastSyncedAt = Date()
        profileStore.save(profile)
        recomputeSummaries()
        healthKitStatusMessage = "Apple Health / Fitness 已同步"
    }

    func saveProfile(_ updatedProfile: UserHealthProfile) {
        profile = updatedProfile
        profileStore.save(updatedProfile)
        recomputeSummaries()
    }

    func reloadMealRecords() {
        savedMealRecords = mealRecordStore.load()
        recomputeSummaries()
    }

    func updateMealRecord(_ record: SavedMealRecord) {
        mealRecordStore.update(record)
        reloadMealRecords()
    }

    func deleteMealRecord(_ record: SavedMealRecord) {
        mealRecordStore.delete(record)
        reloadMealRecords()
    }

    var assistantContextSummary: String {
        let averageIntake = average(of: yearSummaries.suffix(30).map(\.intakeKcal))
        let averageBurn = average(of: yearSummaries.suffix(30).map(\.totalBurnKcal))
        let averageBalance = averageBurn - averageIntake
        let recentRecords = savedMealRecords
            .prefix(8)
            .map { record in
                "\(record.consumedAt.formatted(date: .numeric, time: .omitted)) \(record.mealType.title) \(Int(record.calculation.totalEnergyKcal.rounded()))kcal"
            }
            .joined(separator: "；")

        return """
        今日摄入 \(Int(today.intakeKcal.rounded())) kcal，总消耗 \(Int(today.totalBurnKcal.rounded())) kcal，运动消耗 \(Int(today.activeEnergyKcal.rounded())) kcal。
        近30日平均摄入 \(Int(averageIntake.rounded())) kcal，平均消耗 \(Int(averageBurn.rounded())) kcal，平均热量差 \(Int(averageBalance.rounded())) kcal/日。
        近期饮食记录：\(recentRecords.isEmpty ? "暂无" : recentRecords)
        """
    }

    private func merge(snapshot: HealthKitSnapshot) {
        if let heightCm = snapshot.heightCm {
            profile.heightCm = heightCm
        }
        if let weightKg = snapshot.weightKg {
            profile.weightKg = weightKg
        }
        if let age = snapshot.age {
            profile.age = age
        }
        if let biologicalSex = snapshot.biologicalSex {
            profile.biologicalSex = biologicalSex
        }

        healthMetricsByDay = Dictionary(uniqueKeysWithValues: snapshot.days.map { (Calendar.current.startOfDay(for: $0.date), $0) })
    }

    private func recomputeSummaries() {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let basal = estimatedBasalEnergyKcal()
        var summaries: [DailyHealthOverview] = []

        for offset in stride(from: -364, through: 0, by: 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: todayStart) else { continue }
            let intake = intakeKcal(on: day)
            let metrics = healthMetricsByDay[day]

            summaries.append(
                DailyHealthOverview(
                    date: day,
                    intakeKcal: intake,
                    activeEnergyKcal: metrics?.activeEnergyKcal ?? 0,
                    basalEnergyKcal: basal,
                    stepCount: metrics?.stepCount ?? 0,
                    basalIsEstimated: true
                )
            )
        }

        yearSummaries = summaries
        weeklySummaries = Array(summaries.suffix(7))
        today = summaries.last ?? DailyHealthOverview.empty(for: Date())
    }

    private func intakeKcal(on day: Date) -> Double {
        let calendar = Calendar.current
        return savedMealRecords.reduce(0) { partial, record in
            guard calendar.isDate(record.consumedAt, inSameDayAs: day) else { return partial }
            return partial + record.calculation.totalEnergyKcal
        }
    }

    private func average(of values: [Double]) -> Double {
        let nonZeroValues = values.filter { $0 > 0 }
        guard !nonZeroValues.isEmpty else { return 0 }
        return nonZeroValues.reduce(0, +) / Double(nonZeroValues.count)
    }

    private func estimatedBasalEnergyKcal() -> Double {
        guard let heightCm = profile.heightCm,
              let weightKg = profile.weightKg,
              let age = profile.age else {
            return 0
        }

        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        switch profile.biologicalSex {
        case "female":
            return max(0, base - 161)
        case "male":
            return max(0, base + 5)
        default:
            return max(0, base - 78)
        }
    }
}

private struct ProfileLocalStore {
    private let key = "BHealth.userHealthProfile.v1"

    func load() -> UserHealthProfile {
        guard let data = UserDefaults.standard.data(forKey: key),
              let profile = try? JSONDecoder.profileDecoder.decode(UserHealthProfile.self, from: data) else {
            return .defaultProfile
        }
        return profile
    }

    func save(_ profile: UserHealthProfile) {
        guard let data = try? JSONEncoder.profileEncoder.encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct HealthKitSnapshot {
    let heightCm: Double?
    let weightKg: Double?
    let age: Int?
    let biologicalSex: String?
    let days: [HealthDayMetrics]
}

struct HealthDayMetrics: Hashable {
    let date: Date
    let activeEnergyKcal: Double
    let stepCount: Double
}

struct HealthKitService {
#if canImport(HealthKit)
    private let healthStore = HKHealthStore()

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        let readTypes = try readableObjectTypes()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitServiceError.authorizationDenied)
                }
            }
        }
    }

    func fetchSnapshot() async throws -> HealthKitSnapshot {
        async let heightMeters = latestQuantity(.height, unit: .meter())
        async let weightKg = latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo))
        async let activeEnergy = dailyCumulativeValues(.activeEnergyBurned, unit: .kilocalorie())
        async let workoutEnergy = dailyWorkoutEnergyValues()
        async let steps = dailyCumulativeValues(.stepCount, unit: .count())

        let profile = readCharacteristics()
        let heightValue = try await heightMeters
        let weightValue = try await weightKg
        let activeByDay = try await activeEnergy
        let workoutByDay = try await workoutEnergy
        let stepsByDay = try await steps

        let calendar = Calendar.current
        let allDays = Set(activeByDay.keys)
            .union(workoutByDay.keys)
            .union(stepsByDay.keys)
            .sorted()

        let metrics = allDays.map { day in
            let normalizedDay = calendar.startOfDay(for: day)
            let activeKcal = max(activeByDay[normalizedDay] ?? 0, workoutByDay[normalizedDay] ?? 0)
            return HealthDayMetrics(
                date: normalizedDay,
                activeEnergyKcal: activeKcal,
                stepCount: stepsByDay[normalizedDay] ?? 0
            )
        }

        return HealthKitSnapshot(
            heightCm: heightValue.map { $0 * 100 },
            weightKg: weightValue,
            age: profile.age,
            biologicalSex: profile.biologicalSex,
            days: metrics
        )
    }

    private func readableObjectTypes() throws -> Set<HKObjectType> {
        var types = Set<HKObjectType>()

        for identifier in [
            HKQuantityTypeIdentifier.activeEnergyBurned,
            .stepCount,
            .height,
            .bodyMass
        ] {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        types.insert(HKObjectType.workoutType())

        if let dateOfBirth = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
            types.insert(dateOfBirth)
        }

        if let biologicalSex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) {
            types.insert(biologicalSex)
        }

        guard !types.isEmpty else { throw HealthKitServiceError.unavailable }
        return types
    }

    private func latestQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }

        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }

            healthStore.execute(query)
        }
    }

    private func dailyWorkoutEnergyValues() async throws -> [Date: Double] {
        guard let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return [:]
        }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -364, to: todayStart),
              let endDate = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
            return [:]
        }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let values = (samples as? [HKWorkout] ?? []).reduce(into: [Date: Double]()) { result, workout in
                    let day = calendar.startOfDay(for: workout.startDate)
                    let kcal = workout.statistics(for: activeEnergyType)?
                        .sumQuantity()?
                        .doubleValue(for: .kilocalorie()) ?? 0
                    result[day, default: 0] += kcal
                }

                continuation.resume(returning: values)
            }

            healthStore.execute(query)
        }
    }

    private func dailyCumulativeValues(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> [Date: Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [:] }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -364, to: todayStart),
              let endDate = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
            return [:]
        }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
            var interval = DateComponents()
            interval.day = 1

            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: startDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                var values: [Date: Double] = [:]
                collection?.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                    let day = calendar.startOfDay(for: statistics.startDate)
                    values[day] = statistics.sumQuantity()?.doubleValue(for: unit) ?? 0
                }

                continuation.resume(returning: values)
            }

            healthStore.execute(query)
        }
    }

    private func readCharacteristics() -> (age: Int?, biologicalSex: String?) {
        var age: Int?
        if let components = try? healthStore.dateOfBirthComponents(),
           let birthDate = Calendar.current.date(from: components) {
            age = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
        }

        let biologicalSex: String?
        switch (try? healthStore.biologicalSex().biologicalSex) {
        case .female:
            biologicalSex = "female"
        case .male:
            biologicalSex = "male"
        default:
            biologicalSex = nil
        }

        return (age, biologicalSex)
    }
#else
    var isAvailable: Bool { false }

    func requestAuthorization() async throws {
        throw HealthKitServiceError.unavailable
    }

    func fetchSnapshot() async throws -> HealthKitSnapshot {
        throw HealthKitServiceError.unavailable
    }
#endif
}

enum HealthKitServiceError: LocalizedError {
    case unavailable
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "HealthKit 在当前设备不可用。"
        case .authorizationDenied:
            return "用户未授权读取 Apple Health 数据。"
        }
    }
}

extension DailyHealthOverview {
    static func empty(for date: Date) -> DailyHealthOverview {
        DailyHealthOverview(
            date: date,
            intakeKcal: 0,
            activeEnergyKcal: 0,
            basalEnergyKcal: 0,
            stepCount: 0,
            basalIsEstimated: true
        )
    }
}

extension Notification.Name {
    static let mealRecordsDidChange = Notification.Name("BHealth.mealRecordsDidChange")
}

private extension JSONEncoder {
    static var profileEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var profileDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
