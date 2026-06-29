//
//  ContentView.swift
//  BHealth
//
//  Created by Bill on 2026-06-26.
//

import Charts
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @State private var selectedTab = HealthTab.overview

    var body: some View {
        TabView(selection: $selectedTab) {
            OverviewView()
                .tabItem {
                    Label(appSettings.text("总览", "Overview"), systemImage: "heart.text.square.fill")
                }
                .tag(HealthTab.overview)

            AssistantView()
                .tabItem {
                    Label(appSettings.text("AI 助手", "AI Assistant"), systemImage: "sparkles")
                }
                .tag(HealthTab.assistant)

            ProfileView()
                .tabItem {
                    Label(appSettings.text("我的", "Me"), systemImage: "person.crop.circle.fill")
                }
                .tag(HealthTab.profile)
        }
        .tint(AppColor.healthGreen)
    }
}

private enum HealthTab {
    case overview
    case assistant
    case profile
}

private struct OverviewView: View {
    @EnvironmentObject private var healthStore: HealthDashboardStore
    @EnvironmentObject private var appSettings: AppSettings

    private var today: DailyHealthOverview {
        healthStore.today
    }

    private var basalBurn: Int {
        Int(today.basalEnergyKcal.rounded())
    }

    private var activeBurn: Int {
        Int(today.activeEnergyKcal.rounded())
    }

    private var calorieBalance: Int {
        Int(today.balanceKcal.rounded())
    }

    private var weeklyEntries: [CalorieEntry] {
        healthStore.weeklySummaries.map { summary in
            CalorieEntry(
                date: summary.date,
                intake: Int(summary.intakeKcal.rounded()),
                burn: Int(summary.totalBurnKcal.rounded())
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CalorieSummaryCard(
                        calorieBalance: calorieBalance
                    )

                    HStack(spacing: 12) {
                        MetricCard(
                            title: appSettings.text("基础代谢", "Basal burn"),
                            value: "\(basalBurn)",
                            unit: "kcal",
                            systemImage: "person.fill.checkmark",
                            tint: today.basalIsEstimated ? AppColor.skyBlue : AppColor.healthGreen
                        )

                        MetricCard(
                            title: appSettings.text("健身消耗", "Active burn"),
                            value: "\(activeBurn)",
                            unit: "kcal",
                            systemImage: "figure.run",
                            tint: AppColor.energyOrange
                        )
                    }

                    WeeklyTrendChartCard(entries: weeklyEntries)

                    InsightCard(summary: today)

                    MealHistorySection(records: healthStore.savedMealRecords)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .background(AppColor.screenBackground.ignoresSafeArea())
            .navigationTitle(appSettings.text("今日总览", "Today"))
            .task {
                await healthStore.refreshHealthDataIfPossible()
            }
        }
    }
}

private struct CalorieSummaryCard: View {
    @EnvironmentObject private var appSettings: AppSettings
    let calorieBalance: Int

    private var isOverBudget: Bool {
        calorieBalance < 0
    }

    private var tint: Color {
        isOverBudget ? AppColor.warningRed : AppColor.healthGreen
    }

    private var statusTitle: String {
        isOverBudget ? appSettings.text("今日已超出", "Over today") : appSettings.text("今日余量", "Remaining today")
    }

    private var statusSubtitle: String {
        isOverBudget ? appSettings.text("摄入已高于今日消耗", "Intake is above today's burn") : appSettings.text("目标是让摄入低于消耗", "Aim to keep intake below burn")
    }

    private var displayedBalance: Int {
        abs(calorieBalance)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: isOverBudget ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(statusTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(displayedBalance)")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(tint)

                        Text("kcal")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(statusSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
        }
        .healthCard()
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()

                    Text(unit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .healthCard()
    }
}

private struct WeeklyTrendChartCard: View {
    @EnvironmentObject private var appSettings: AppSettings
    let entries: [CalorieEntry]

    var body: some View {
        let intakeLabel = appSettings.text("摄入", "Intake")
        let burnLabel = appSettings.text("消耗", "Burn")

        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appSettings.text("近 7 天趋势", "Last 7 Days"))
                        .font(.headline.weight(.semibold))

                    Text(appSettings.text("每日摄入与消耗对比", "Daily intake vs burn"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    YearCalendarView()
                } label: {
                    Label(appSettings.text("年历", "Year"), systemImage: "calendar")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.bordered)
                .tint(AppColor.healthGreen)
            }

            Chart(entries) { entry in
                BarMark(
                    x: .value(appSettings.text("日期", "Date"), entry.date, unit: .day),
                    y: .value(appSettings.text("卡路里", "Calories"), entry.intake)
                )
                .foregroundStyle(by: .value(appSettings.text("类型", "Type"), intakeLabel))
                .position(by: .value(appSettings.text("类型", "Type"), intakeLabel))
                .cornerRadius(6)

                BarMark(
                    x: .value(appSettings.text("日期", "Date"), entry.date, unit: .day),
                    y: .value(appSettings.text("卡路里", "Calories"), entry.burn)
                )
                .foregroundStyle(by: .value(appSettings.text("类型", "Type"), burnLabel))
                .position(by: .value(appSettings.text("类型", "Type"), burnLabel))
                .cornerRadius(6)
            }
            .chartForegroundStyleScale([
                intakeLabel: AppColor.healthGreen,
                burnLabel: AppColor.energyOrange
            ])
            .chartLegend(position: .bottom, alignment: .leading)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .frame(height: 190)
        }
        .healthCard()
    }
}

private struct YearCalendarView: View {
    @EnvironmentObject private var healthStore: HealthDashboardStore
    @EnvironmentObject private var appSettings: AppSettings
    @State private var monthGroups: [YearMonthGroup] = []
    @State private var selectedDate: Date?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                YearCalendarSummaryCard(summaries: healthStore.yearSummaries)

                ForEach(monthGroups) { group in
                    CalendarMonthSection(group: group) { date in
                        selectedDate = date
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(AppColor.screenBackground.ignoresSafeArea())
        .navigationTitle(appSettings.text("近一年日历", "Year Calendar"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: Binding(
            get: { selectedDate != nil },
            set: { isPresented in
                if !isPresented {
                    selectedDate = nil
                }
            }
        )) {
            if let selectedDate {
                DailyCalendarDetailView(date: selectedDate)
            }
        }
        .onAppear {
            refreshMonthGroups(from: healthStore.yearSummaries)
        }
        .onChange(of: healthStore.yearSummaries) { _, summaries in
            refreshMonthGroups(from: summaries)
        }
    }

    private func refreshMonthGroups(from summaries: [DailyHealthOverview]) {
        monthGroups = YearCalendarDataBuilder.monthGroups(from: summaries)
    }
}

private struct YearCalendarSummaryCard: View {
    @EnvironmentObject private var appSettings: AppSettings
    let summaries: [DailyHealthOverview]

    private var recordedDays: Int {
        summaries.filter(\.hasUserVisibleData).count
    }

    private var overBudgetDays: Int {
        summaries.filter { $0.hasUserVisibleData && $0.balanceKcal < 0 }.count
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(AppColor.healthGreen.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(appSettings.text("每日余量记录", "Daily Balance"))
                    .font(.headline.weight(.semibold))

                Text(appSettings.text("已记录 \(recordedDays) 天，超出 \(overBudgetDays) 天", "\(recordedDays) days recorded, \(overBudgetDays) over budget"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .healthCard()
    }
}

private struct YearMonthGroup: Identifiable {
    let monthStart: Date
    let slots: [CalendarMonthSlot]

    var id: Date { monthStart }
}

private struct CalendarMonthSlot: Identifiable {
    let id: String
    let summary: DailyHealthOverview?
}

private enum YearCalendarDataBuilder {
    static func monthGroups(from summaries: [DailyHealthOverview], calendar: Calendar = .current) -> [YearMonthGroup] {
        let grouped = Dictionary(grouping: summaries) { summary in
            calendar.date(from: calendar.dateComponents([.year, .month], from: summary.date)) ?? summary.date
        }

        return grouped.keys.sorted(by: >).map { monthStart in
            let monthSummaries = (grouped[monthStart] ?? []).sorted { $0.date < $1.date }
            return YearMonthGroup(
                monthStart: monthStart,
                slots: slots(for: monthStart, summaries: monthSummaries, calendar: calendar)
            )
        }
    }

    private static func slots(
        for monthStart: Date,
        summaries: [DailyHealthOverview],
        calendar: Calendar
    ) -> [CalendarMonthSlot] {
        guard let firstSummary = summaries.first else { return [] }

        let weekdayOffset = calendar.component(.weekday, from: monthStart) - 1
        let dayOffset = calendar.component(.day, from: firstSummary.date) - 1
        let placeholders = (0..<(weekdayOffset + dayOffset)).map { index in
            CalendarMonthSlot(id: "\(monthStart.timeIntervalSince1970)-placeholder-\(index)", summary: nil)
        }
        let days = summaries.map { summary in
            CalendarMonthSlot(id: "day-\(summary.id.timeIntervalSince1970)", summary: summary)
        }

        return placeholders + days
    }
}

private struct CalendarMonthSection: View {
    @EnvironmentObject private var appSettings: AppSettings
    let group: YearMonthGroup
    let selectDate: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private var weekdaySymbols: [String] {
        appSettings.resolvedLanguage == .chinese
            ? ["日", "一", "二", "三", "四", "五", "六"]
            : ["S", "M", "T", "W", "T", "F", "S"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(monthTitle)
                .font(.headline.weight(.semibold))

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(group.slots) { slot in
                    if let summary = slot.summary {
                        Button {
                            selectDate(summary.date)
                        } label: {
                            DayBalanceCell(summary: summary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear
                            .frame(height: 58)
                    }
                }
            }
        }
        .healthCard()
    }

    private var monthTitle: String {
        group.monthStart.formatted(.dateTime.locale(appSettings.locale).year().month(.wide))
    }
}

private struct DayBalanceCell: View {
    let summary: DailyHealthOverview

    private var tint: Color {
        summary.balanceKcal < 0 ? AppColor.warningRed : AppColor.healthGreen
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("\(Calendar.current.component(.day, from: summary.date))")
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)

            Text(balanceText)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(summary.hasUserVisibleData ? tint : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(cellBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(summary.hasUserVisibleData ? tint.opacity(0.22) : Color.clear, lineWidth: 1)
        }
    }

    private var balanceText: String {
        guard summary.hasUserVisibleData else { return "--" }
        let value = Int(summary.balanceKcal.rounded())
        if value > 0 {
            return "+\(value)"
        }
        return "\(value)"
    }

    private var cellBackground: Color {
        guard summary.hasUserVisibleData else { return AppColor.softFill.opacity(0.45) }
        return tint.opacity(0.12)
    }
}

private struct DailyCalendarDetailView: View {
    @EnvironmentObject private var healthStore: HealthDashboardStore
    @EnvironmentObject private var appSettings: AppSettings
    let date: Date

    private var summary: DailyHealthOverview {
        healthStore.yearSummaries.first {
            Calendar.current.isDate($0.date, inSameDayAs: date)
        } ?? DailyHealthOverview.empty(for: date)
    }

    private var records: [SavedMealRecord] {
        healthStore.savedMealRecords.filter {
            Calendar.current.isDate($0.consumedAt, inSameDayAs: date)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DailyBalanceHeaderCard(summary: summary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    DetailMetricCard(title: appSettings.text("摄入", "Intake"), value: summary.intakeKcal, unit: "kcal", icon: "fork.knife", tint: AppColor.healthGreen)
                    DetailMetricCard(title: appSettings.text("总消耗", "Total burn"), value: summary.totalBurnKcal, unit: "kcal", icon: "flame.fill", tint: AppColor.energyOrange)
                    DetailMetricCard(title: appSettings.text("健身消耗", "Active burn"), value: summary.activeEnergyKcal, unit: "kcal", icon: "figure.run", tint: AppColor.skyBlue)
                    DetailMetricCard(
                        title: appSettings.text("基础代谢", "Basal burn"),
                        value: summary.basalEnergyKcal,
                        unit: "kcal",
                        icon: "person.fill.checkmark",
                        tint: AppColor.violet
                    )
                }

                DetailMetricCard(title: appSettings.text("步数", "Steps"), value: summary.stepCount, unit: appSettings.text("步", "steps"), icon: "figure.walk", tint: AppColor.healthGreen)

                VStack(alignment: .leading, spacing: 14) {
                    Text(appSettings.text("当日饮食", "Meals"))
                        .font(.headline.weight(.semibold))

                    if records.isEmpty {
                        Text(appSettings.text("暂无饮食记录", "No meal records"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(AppColor.softFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        ForEach(records) { record in
                            MealRecordRow(record: record)
                        }
                    }
                }
                .healthCard()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(AppColor.screenBackground.ignoresSafeArea())
        .navigationTitle(AppText.monthDayWeekday(date, language: appSettings.resolvedLanguage))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DailyBalanceHeaderCard: View {
    @EnvironmentObject private var appSettings: AppSettings
    let summary: DailyHealthOverview

    private var isOverBudget: Bool {
        summary.balanceKcal < 0
    }

    private var tint: Color {
        isOverBudget ? AppColor.warningRed : AppColor.healthGreen
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isOverBudget ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(isOverBudget ? appSettings.text("当日超出", "Over Budget") : appSettings.text("当日余量", "Remaining"))
                    .font(.headline.weight(.semibold))

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(abs(Int(summary.balanceKcal.rounded())))")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)

                    Text("kcal")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .healthCard()
    }
}

private struct DetailMetricCard: View {
    let title: String
    let value: Double
    let unit: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int(value.rounded()))")
                        .font(.headline.weight(.bold))
                        .monospacedDigit()

                    Text(unit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .healthCard(padding: 14)
    }
}

private struct InsightCard: View {
    @EnvironmentObject private var appSettings: AppSettings
    let summary: DailyHealthOverview

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(appSettings.text("今日建议", "Today's Suggestion"), systemImage: "lightbulb.max.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .healthCard()
    }

    private var message: String {
        if summary.intakeKcal == 0 {
            return appSettings.text("今天还没有确认保存的饮食记录。你可以到 AI 助手页用自然语言记录一餐，总览会自动更新摄入热量。", "No confirmed meals yet today. Record a meal in the AI Assistant and the overview will update automatically.")
        }

        if summary.balanceKcal >= 250 {
            return appSettings.text("今天热量仍有约 \(Int(summary.balanceKcal.rounded())) kcal 余量。晚餐可以优先选择高蛋白、低油脂食物，并保持轻量活动。", "You still have about \(Int(summary.balanceKcal.rounded())) kcal remaining today. For dinner, prioritize high-protein, lower-fat foods and keep some light activity.")
        }

        if summary.balanceKcal >= 0 {
            return appSettings.text("今天摄入和消耗比较接近。后续记录尽量补充克重或份量，热量估算会更可靠。", "Your intake and burn are close today. Adding weights or portions to future records will make estimates more reliable.")
        }

        return appSettings.text("今天摄入已高于消耗约 \(abs(Int(summary.balanceKcal.rounded()))) kcal。可以选择散步或拉伸，不建议用高强度运动强行抵消。", "Your intake is about \(abs(Int(summary.balanceKcal.rounded()))) kcal above burn today. A walk or stretching is fine; avoid trying to forcefully offset it with intense exercise.")
    }
}

private struct MealHistorySection: View {
    @EnvironmentObject private var healthStore: HealthDashboardStore
    @EnvironmentObject private var appSettings: AppSettings
    @State private var showsHistory = false

    let records: [SavedMealRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appSettings.text("历史饮食记录", "Meal History"))
                        .font(.headline.weight(.semibold))

                    Text(records.isEmpty ? appSettings.text("暂无已确认记录", "No confirmed records yet") : appSettings.text("共 \(records.count) 条，可查看和修改", "\(records.count) records, editable"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showsHistory = true
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.bordered)
            }

            ForEach(records.prefix(3)) { record in
                MealRecordRow(record: record)
            }

            if records.count > 3 {
                Button {
                    showsHistory = true
                } label: {
                    Text(appSettings.text("查看全部记录", "View All Records"))
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.healthGreen)
            }
        }
        .healthCard()
        .sheet(isPresented: $showsHistory) {
            MealHistoryListView()
                .environmentObject(healthStore)
        }
    }
}

private struct MealRecordRow: View {
    @EnvironmentObject private var appSettings: AppSettings
    let record: SavedMealRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "fork.knife")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppColor.healthGreen)
                .frame(width: 32, height: 32)
                .background(AppColor.healthGreen.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(recordTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text("\(AppText.shortDate(record.consumedAt, language: appSettings.resolvedLanguage)) · \(record.mealType.title(language: appSettings.resolvedLanguage))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(Int(record.calculation.totalEnergyKcal.rounded())) kcal")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
        }
        .padding(12)
        .background(AppColor.softFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var recordTitle: String {
        record.calculation.foodDisplayName
    }
}

private struct MealHistoryListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var healthStore: HealthDashboardStore
    @EnvironmentObject private var appSettings: AppSettings
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var didSetInitialDate = false
    @State private var editingRecord: SavedMealRecord?

    private var selectedRecords: [SavedMealRecord] {
        let calendar = Calendar.current
        return healthStore.savedMealRecords.filter {
            calendar.isDate($0.consumedAt, inSameDayAs: selectedDate)
        }
    }

    private var selectedTotalKcal: Int {
        Int(selectedRecords.reduce(0) { $0 + $1.calculation.totalEnergyKcal }.rounded())
    }

    var body: some View {
        NavigationStack {
            List {
                if healthStore.savedMealRecords.isEmpty {
                    ContentUnavailableView(appSettings.text("暂无记录", "No Records"), systemImage: "fork.knife", description: Text(appSettings.text("在 AI 助手中确认保存后会出现在这里。", "Confirmed meals from the AI Assistant will appear here.")))
                } else {
                    Section {
                        DatePicker(appSettings.text("日期", "Date"), selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .tint(AppColor.healthGreen)

                        HStack {
                            Label(appSettings.text("\(selectedRecords.count) 条记录", "\(selectedRecords.count) records"), systemImage: "calendar")
                                .font(.subheadline.weight(.semibold))

                            Spacer()

                            Text("\(selectedTotalKcal) kcal")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(AppColor.healthGreen)
                                .monospacedDigit()
                        }
                    }

                    if selectedRecords.isEmpty {
                        ContentUnavailableView(
                            appSettings.text("当天暂无记录", "No Records That Day"),
                            systemImage: "calendar.badge.exclamationmark",
                            description: Text(appSettings.text("请选择其他日期，或在 AI 助手中补录这一天的饮食。", "Choose another date, or add meals for this day in the AI Assistant."))
                        )
                    } else {
                        Section(appSettings.text("当日记录", "Records")) {
                            ForEach(selectedRecords) { record in
                                Button {
                                    editingRecord = record
                                } label: {
                                    MealRecordRow(record: record)
                                }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        healthStore.deleteMealRecord(record)
                                    } label: {
                                        Label(appSettings.text("删除", "Delete"), systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(appSettings.text("历史记录", "History"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appSettings.text("完成", "Done")) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                setInitialSelectedDateIfNeeded()
            }
            .sheet(item: $editingRecord) { record in
                MealRecordEditorView(record: record) { updatedRecord in
                    healthStore.updateMealRecord(updatedRecord)
                } deleteAction: {
                    healthStore.deleteMealRecord(record)
                }
            }
        }
    }

    private func setInitialSelectedDateIfNeeded() {
        guard !didSetInitialDate else { return }
        didSetInitialDate = true
        if let latestDate = healthStore.savedMealRecords.first?.consumedAt {
            selectedDate = Calendar.current.startOfDay(for: latestDate)
        }
    }
}

private struct MealRecordEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettings
    @State private var foodName: String
    @State private var kcal: String
    @State private var consumedAt: Date
    @State private var mealType: MealType

    let record: SavedMealRecord
    let saveAction: (SavedMealRecord) -> Void
    let deleteAction: () -> Void

    init(
        record: SavedMealRecord,
        saveAction: @escaping (SavedMealRecord) -> Void,
        deleteAction: @escaping () -> Void
    ) {
        self.record = record
        self.saveAction = saveAction
        self.deleteAction = deleteAction
        _foodName = State(initialValue: record.calculation.foodDisplayName)
        _kcal = State(initialValue: "\(Int(record.calculation.totalEnergyKcal.rounded()))")
        _consumedAt = State(initialValue: record.consumedAt)
        _mealType = State(initialValue: record.mealType)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 16) {
                        EditorTextRow(
                            title: appSettings.text("食品", "Food"),
                            subtitle: appSettings.text("已保存的具体食物", "Saved food item"),
                            icon: "fork.knife",
                            tint: AppColor.healthGreen,
                            placeholder: appSettings.text("例如 鸡蛋、拿铁、吐司", "e.g. Eggs, latte, toast"),
                            text: $foodName,
                            keyboard: .text
                        )

                        Divider()

                        EditorTextRow(
                            title: appSettings.text("热量", "Calories"),
                            subtitle: appSettings.text("当餐估算摄入", "Estimated intake for this meal"),
                            icon: "flame.fill",
                            tint: AppColor.energyOrange,
                            placeholder: "kcal",
                            text: $kcal,
                            keyboard: .number,
                            unit: "kcal"
                        )

                        Divider()

                        MealTypeEditorRow(selection: $mealType)

                        Divider()

                        EditorDateRow(
                            title: appSettings.text("日期", "Date"),
                            subtitle: appSettings.text("这餐归属的日期", "Date for this meal"),
                            icon: "calendar",
                            tint: AppColor.skyBlue,
                            date: $consumedAt
                        )
                    }
                    .healthCard()

                    Button(role: .destructive) {
                        deleteAction()
                        dismiss()
                    } label: {
                        Label(appSettings.text("删除记录", "Delete Record"), systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .background(AppColor.screenBackground.ignoresSafeArea())
            .navigationTitle(appSettings.text("编辑记录", "Edit Record"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appSettings.text("取消", "Cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(appSettings.text("保存", "Save")) {
                        saveAction(updatedRecord)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(Double(kcal) == nil || foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var updatedRecord: SavedMealRecord {
        let energy = Double(kcal) ?? record.calculation.totalEnergyKcal
        let trimmedName = foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = MealItemCalculation(
            rawText: trimmedName,
            matchedFoodName: trimmedName,
            fdcId: record.calculation.items.first?.fdcId ?? -1,
            estimatedGrams: record.calculation.items.first?.estimatedGrams ?? 0,
            energyKcal: energy,
            proteinG: nil,
            fatG: nil,
            carbohydrateG: nil,
            confidence: record.calculation.confidence,
            sourceName: appSettings.text("用户编辑", "User edit"),
            sourceVersion: "manual",
            assumptions: [appSettings.text("用户手动编辑历史记录。", "Record edited manually.")]
        )
        let calculation = MealCalculationResult(
            id: record.calculation.id,
            createdAt: record.calculation.createdAt,
            items: [item],
            totalEnergyKcal: energy,
            rangeLowKcal: energy,
            rangeHighKcal: energy,
            confidence: record.calculation.confidence,
            assumptions: [appSettings.text("用户手动编辑历史记录。", "Record edited manually.")],
            sourceSummary: appSettings.text("用户编辑", "User edit")
        )

        return SavedMealRecord(
            id: record.id,
            confirmedAt: record.confirmedAt,
            consumedAt: consumedAt,
            mealType: mealType,
            calculation: calculation
        )
    }
}

private struct AssistantView: View {
    @EnvironmentObject private var healthStore: HealthDashboardStore
    @EnvironmentObject private var appSettings: AppSettings
    @StateObject private var viewModel = FoodAssistantViewModel()
    @State private var navigationPath: [AssistantMode] = []
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack(path: $navigationPath) {
            AssistantModeSelectionView { mode in
                viewModel.openMode(mode, language: appSettings.resolvedLanguage)
                navigationPath.append(mode)
            }
            .background(AppColor.screenBackground.ignoresSafeArea())
            .navigationTitle(appSettings.text("AI 助手", "AI Assistant"))
            .navigationDestination(for: AssistantMode.self) { mode in
                assistantChat(mode: mode)
                    .onAppear {
                        if viewModel.selectedMode != mode {
                            viewModel.openMode(mode, language: appSettings.resolvedLanguage)
                        }
                    }
            }
            .onChange(of: navigationPath) { _, path in
                if path.isEmpty {
                    isInputFocused = false
                    viewModel.closeMode()
                }
            }
            .onChange(of: appSettings.resolvedLanguage) { _, language in
                if let selectedMode = viewModel.selectedMode {
                    viewModel.openMode(selectedMode, language: language)
                } else {
                    viewModel.closeMode(language: language)
                }
            }
            .onAppear {
                viewModel.refreshAPIKeyStatus()
                viewModel.setLanguage(appSettings.resolvedLanguage)
            }
        }
    }

    private func assistantChat(mode: AssistantMode) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }

                            if viewModel.isSending {
                                LoadingBubble()
                                    .id("loading")
                            }

                            if let calculation = viewModel.pendingCalculation {
                                MealCalculationDraftCard(
                                    calculation: calculation,
                                    mealType: viewModel.pendingMealType,
                                    consumedAt: viewModel.pendingConsumedAt,
                                    saveAction: viewModel.savePendingCalculation
                                )
                                .id(calculation.id)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture {
                    isInputFocused = false
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    withAnimation(.snappy) {
                        proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.isSending) { _, isSending in
                    guard isSending else { return }
                    withAnimation(.snappy) {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.pendingCalculation?.id) { _, id in
                    guard let id else { return }
                    withAnimation(.snappy) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }

            ChatInputBar(
                text: $viewModel.draftMessage,
                isSending: viewModel.isSending,
                isFocused: $isInputFocused,
                sendAction: {
                    isInputFocused = false
                    Task {
                        await viewModel.sendDraftMessage(dashboardContext: healthStore.assistantContextSummary(language: appSettings.resolvedLanguage))
                    }
                }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
        .navigationTitle(mode.title(language: appSettings.resolvedLanguage))
        .alert(item: $viewModel.localAlgorithmFallbackRequest) { request in
            Alert(
                title: Text(appSettings.text("当前 API 不可用", "API Unavailable")),
                message: Text(request.message(language: appSettings.resolvedLanguage)),
                primaryButton: .default(Text(appSettings.text("通过算法估算", "Use Local Estimate"))) {
                    viewModel.runLocalAlgorithmFallback(request)
                },
                secondaryButton: .cancel(Text(appSettings.text("取消", "Cancel"))) {
                    viewModel.cancelLocalAlgorithmFallback()
                }
            )
        }
    }
}

private struct AssistantModeSelectionView: View {
    @EnvironmentObject private var appSettings: AppSettings
    let selectMode: (AssistantMode) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(appSettings.text("选择助手", "Choose Assistant"))
                    .font(.largeTitle.weight(.bold))
                    .padding(.top, 8)

                ForEach(AssistantMode.allCases) { mode in
                    Button {
                        selectMode(mode)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(AppColor.healthGreen)
                                .frame(width: 54, height: 54)
                                .background(AppColor.healthGreen.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                            VStack(alignment: .leading, spacing: 5) {
                                Text(mode.title(language: appSettings.resolvedLanguage))
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text(mode.subtitle(language: appSettings.resolvedLanguage))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .healthCard()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
    }
}

private struct APIKeySetupCard: View {
    @EnvironmentObject private var appSettings: AppSettings
    @Binding var apiKeyInput: String
    let hasAPIKey: Bool
    let statusMessage: String?
    let saveAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: hasAPIKey ? "checkmark.shield.fill" : "key.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColor.healthGreen)
                    .frame(width: 36, height: 36)
                    .background(AppColor.healthGreen.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(hasAPIKey ? appSettings.text("DeepSeek 已连接", "DeepSeek Connected") : "DeepSeek API Key")
                        .font(.headline.weight(.semibold))

                    Text(hasAPIKey ? appSettings.text("密钥保存在系统 Keychain", "Key saved in system Keychain") : appSettings.text("保存后开始真实 AI 对话", "Save it to enable real AI conversations"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if hasAPIKey {
                Button(role: .destructive, action: deleteAction) {
                    Label(appSettings.text("删除密钥", "Delete Key"), systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            } else {
                HStack(spacing: 10) {
                    SecureField("DeepSeek API Key", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)

                    Button(action: saveAction) {
                        Label(appSettings.text("保存", "Save"), systemImage: "lock.fill")
                            .font(.subheadline.weight(.bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColor.healthGreen)
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .healthCard()
    }
}

private struct LanguageSettingsCard: View {
    @EnvironmentObject private var appSettings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColor.skyBlue)
                    .frame(width: 36, height: 36)
                    .background(AppColor.skyBlue.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(appSettings.text("语言", "Language"))
                        .font(.headline.weight(.semibold))

                    Text(appSettings.text("AI 回复和界面文案会跟随此设置", "AI replies and app text follow this setting"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            Picker(appSettings.text("语言", "Language"), selection: $appSettings.languagePreference) {
                ForEach(AppLanguagePreference.allCases) { preference in
                    Text(preference.title(language: appSettings.resolvedLanguage))
                        .tag(preference)
                }
            }
            .pickerStyle(.segmented)

            Text(appSettings.languagePreference.subtitle(language: appSettings.resolvedLanguage))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .healthCard()
    }
}

private struct ChatBubble: View {
    let message: AssistantMessage

    var body: some View {
        HStack(alignment: .bottom) {
            if message.isFromUser {
                Spacer(minLength: 44)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColor.healthGreen)
                    .frame(width: 30, height: 30)
                    .background(AppColor.healthGreen.opacity(0.14), in: Circle())
            }

            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(message.isFromUser ? .white : .primary)
                .lineSpacing(3)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(
                    message.isFromUser ? AppColor.healthGreen : AppColor.cardBackground,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )

            if message.isFromUser {
                Image(systemName: "person.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(AppColor.healthGreen, in: Circle())
            } else {
                Spacer(minLength: 44)
            }
        }
    }
}

private struct LoadingBubble: View {
    @EnvironmentObject private var appSettings: AppSettings

    var body: some View {
        HStack(alignment: .bottom) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppColor.healthGreen)
                .frame(width: 30, height: 30)
                .background(AppColor.healthGreen.opacity(0.14), in: Circle())

            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)

                Text(appSettings.text("正在分析", "Analyzing"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Spacer(minLength: 44)
        }
    }
}

private struct MealCalculationDraftCard: View {
    @EnvironmentObject private var appSettings: AppSettings
    let calculation: MealCalculationResult
    let mealType: MealType?
    let consumedAt: Date?
    let saveAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(appSettings.text("待确认记录", "Pending Record"), systemImage: "doc.badge.clock")
                    .font(.headline.weight(.semibold))

                Spacer()

                Text(confidenceText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(confidenceColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(confidenceColor.opacity(0.14), in: Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(Int(calculation.totalEnergyKcal.rounded()))")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text("kcal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(appSettings.text("较可能范围 \(Int(calculation.rangeLowKcal.rounded()))-\(Int(calculation.rangeHighKcal.rounded()))", "Likely range \(Int(calculation.rangeLowKcal.rounded()))-\(Int(calculation.rangeHighKcal.rounded()))"))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let consumedAt {
                    Label(appSettings.text("日期：\(AppText.shortDate(consumedAt, language: appSettings.resolvedLanguage))", "Date: \(AppText.shortDate(consumedAt, language: appSettings.resolvedLanguage))"), systemImage: "calendar")
                }

                if let mealType {
                    Label(appSettings.text("餐别：\(mealType.title(language: appSettings.resolvedLanguage))", "Meal: \(mealType.title(language: appSettings.resolvedLanguage))"), systemImage: "sparkles")
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(calculation.items.prefix(3)) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(AppColor.healthGreen)
                            .padding(.top, 7)

                        Text(appSettings.text("\(item.displayFoodName)：约 \(Int(item.energyKcal.rounded())) kcal", "\(item.displayFoodName): about \(Int(item.energyKcal.rounded())) kcal"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            if !calculation.assumptions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appSettings.text("估算依据", "Estimate Basis"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(Array(calculation.assumptions.prefix(3)), id: \.self) { assumption in
                        Label(assumption, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            Button(action: saveAction) {
                Label(appSettings.text("确认记录", "Confirm Record"), systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.healthGreen)
        }
        .healthCard()
    }

    private var confidenceText: String {
        calculation.confidence == "low" ? appSettings.text("低可信度", "Low confidence") : appSettings.text("中等可信度", "Medium confidence")
    }

    private var confidenceColor: Color {
        calculation.confidence == "low" ? AppColor.energyOrange : AppColor.healthGreen
    }
}

private struct ChatInputBar: View {
    @EnvironmentObject private var appSettings: AppSettings
    @Binding var text: String
    let isSending: Bool
    var isFocused: FocusState<Bool>.Binding
    let sendAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField(appSettings.text("输入饮食、运动或健康问题", "Enter food, exercise, or health questions"), text: $text, axis: .vertical)
                .focused(isFocused)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button(action: sendAction) {
                Group {
                    if isSending {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(sendDisabled ? Color.secondary.opacity(0.35) : AppColor.healthGreen, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(sendDisabled)
            .animation(.snappy, value: sendDisabled)
        }
    }

    private var sendDisabled: Bool {
        isSending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct ProfileView: View {
    @EnvironmentObject private var healthStore: HealthDashboardStore
    @EnvironmentObject private var appSettings: AppSettings
    @State private var isEditingProfile = false
    @State private var apiKeyInput = ""
    @State private var hasAPIKey = KeychainAPIKeyStore.shared.hasAPIKey
    @State private var apiKeyStatusMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    profileHeader

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ProfileMetricCard(title: appSettings.text("身高", "Height"), value: formatNumber(healthStore.profile.heightCm), unit: "cm", icon: "ruler", tint: AppColor.skyBlue)
                        ProfileMetricCard(title: appSettings.text("体重", "Weight"), value: formatNumber(healthStore.profile.weightKg), unit: "kg", icon: "scalemass.fill", tint: AppColor.healthGreen)
                        ProfileMetricCard(title: appSettings.text("年龄", "Age"), value: formatInteger(healthStore.profile.age), unit: appSettings.text("岁", "yr"), icon: "calendar", tint: AppColor.energyOrange)
                        ProfileMetricCard(title: appSettings.text("目标体重", "Goal Weight"), value: formatNumber(healthStore.profile.targetWeightKg), unit: "kg", icon: "target", tint: AppColor.violet)
                    }

                    APIKeySetupCard(
                        apiKeyInput: $apiKeyInput,
                        hasAPIKey: hasAPIKey,
                        statusMessage: apiKeyStatusMessage,
                        saveAction: saveAPIKey,
                        deleteAction: deleteAPIKey
                    )

                    LanguageSettingsCard()

                    syncCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .background(AppColor.screenBackground.ignoresSafeArea())
            .navigationTitle(appSettings.text("我的", "Me"))
            .onAppear {
                hasAPIKey = KeychainAPIKeyStore.shared.hasAPIKey
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isEditingProfile = true
                    } label: {
                        Label(appSettings.text("编辑", "Edit"), systemImage: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $isEditingProfile) {
                ProfileEditorView(
                    profile: healthStore.profile,
                    saveAction: healthStore.saveProfile
                )
            }
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppColor.healthGreen.gradient)
                    .frame(width: 78, height: 78)

                Text(String(healthStore.profile.name.prefix(1)).uppercased())
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(healthStore.profile.name)
                    .font(.title2.weight(.bold))

                Text(profileSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }

            Spacer(minLength: 0)
        }
        .healthCard()
    }

    private var syncCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColor.healthGreen)
                    .frame(width: 40, height: 40)
                    .background(AppColor.healthGreen.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Health / Fitness")
                        .font(.headline.weight(.semibold))

                    Text(healthStore.healthKitStatusMessage(language: appSettings.resolvedLanguage))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Button {
                Task {
                    await healthStore.requestHealthAuthorizationAndRefresh()
                }
            } label: {
                Label(healthStore.isSyncingHealthKit ? appSettings.text("同步中", "Syncing") : appSettings.text("同步健康与健身数据", "Sync Health & Fitness Data"), systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.healthGreen)
            .disabled(healthStore.isSyncingHealthKit || !healthStore.healthKitAvailable)
        }
        .healthCard()
    }

    private var profileSubtitle: String {
        if let syncedAt = healthStore.profile.lastSyncedAt {
            return appSettings.text("上次同步：\(AppText.shortDateTime(syncedAt, language: appSettings.resolvedLanguage))", "Last synced: \(AppText.shortDateTime(syncedAt, language: appSettings.resolvedLanguage))")
        }
        return appSettings.text("目标：稳步控制热量，建立长期健康记录", "Goal: manage calories steadily and build a long-term health record")
    }

    private func formatNumber(_ value: Double?) -> String {
        guard let value else { return "--" }
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    private func formatInteger(_ value: Int?) -> String {
        guard let value else { return "--" }
        return "\(value)"
    }

    private func saveAPIKey() {
        do {
            try KeychainAPIKeyStore.shared.saveAPIKey(apiKeyInput)
            apiKeyInput = ""
            hasAPIKey = true
            apiKeyStatusMessage = appSettings.text("DeepSeek API key 已保存到系统 Keychain。", "DeepSeek API key saved to system Keychain.")
        } catch {
            let reason = (error as? KeychainError)?.message(language: appSettings.resolvedLanguage) ?? error.localizedDescription
            apiKeyStatusMessage = appSettings.text("保存 API key 失败：\(reason)", "Failed to save API key: \(reason)")
        }
    }

    private func deleteAPIKey() {
        do {
            try KeychainAPIKeyStore.shared.deleteAPIKey()
            hasAPIKey = false
            apiKeyStatusMessage = appSettings.text("已从 Keychain 删除 DeepSeek API key。", "DeepSeek API key deleted from Keychain.")
        } catch {
            let reason = (error as? KeychainError)?.message(language: appSettings.resolvedLanguage) ?? error.localizedDescription
            apiKeyStatusMessage = appSettings.text("删除 API key 失败：\(reason)", "Failed to delete API key: \(reason)")
        }
    }
}

private struct ProfileMetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(unit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .healthCard()
    }
}

private struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettings
    @State private var name: String
    @State private var height: String
    @State private var weight: String
    @State private var age: String
    @State private var targetWeight: String
    @State private var biologicalSex: String

    let saveAction: (UserHealthProfile) -> Void

    init(profile: UserHealthProfile, saveAction: @escaping (UserHealthProfile) -> Void) {
        _name = State(initialValue: profile.name)
        _height = State(initialValue: profile.heightCm.map { Self.format($0) } ?? "")
        _weight = State(initialValue: profile.weightKg.map { Self.format($0) } ?? "")
        _age = State(initialValue: profile.age.map(String.init) ?? "")
        _targetWeight = State(initialValue: profile.targetWeightKg.map { Self.format($0) } ?? "")
        _biologicalSex = State(initialValue: profile.biologicalSex ?? "unspecified")
        self.saveAction = saveAction
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 16) {
                        EditorTextRow(
                            title: appSettings.text("姓名", "Name"),
                            subtitle: appSettings.text("个人资料显示名称", "Profile display name"),
                            icon: "person.fill",
                            tint: AppColor.healthGreen,
                            placeholder: appSettings.text("姓名", "Name"),
                            text: $name,
                            keyboard: .text
                        )

                        Divider()

                        EditorTextRow(
                            title: appSettings.text("身高", "Height"),
                            subtitle: appSettings.text("用于估算基础代谢", "Used to estimate basal burn"),
                            icon: "ruler",
                            tint: AppColor.skyBlue,
                            placeholder: "cm",
                            text: $height,
                            keyboard: .decimal,
                            unit: "cm"
                        )

                        Divider()

                        EditorTextRow(
                            title: appSettings.text("体重", "Weight"),
                            subtitle: appSettings.text("当前体重", "Current weight"),
                            icon: "scalemass.fill",
                            tint: AppColor.healthGreen,
                            placeholder: "kg",
                            text: $weight,
                            keyboard: .decimal,
                            unit: "kg"
                        )

                        Divider()

                        EditorTextRow(
                            title: appSettings.text("年龄", "Age"),
                            subtitle: appSettings.text("用于健康估算", "Used for health estimates"),
                            icon: "calendar",
                            tint: AppColor.energyOrange,
                            placeholder: appSettings.text("岁", "yr"),
                            text: $age,
                            keyboard: .number,
                            unit: appSettings.text("岁", "yr")
                        )

                        Divider()

                        EditorTextRow(
                            title: appSettings.text("目标体重", "Goal Weight"),
                            subtitle: appSettings.text("长期目标", "Long-term target"),
                            icon: "target",
                            tint: AppColor.violet,
                            placeholder: "kg",
                            text: $targetWeight,
                            keyboard: .decimal,
                            unit: "kg"
                        )

                        Divider()

                        BiologicalSexEditorRow(selection: $biologicalSex)
                    }
                    .healthCard()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .background(AppColor.screenBackground.ignoresSafeArea())
            .navigationTitle(appSettings.text("编辑资料", "Edit Profile"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appSettings.text("取消", "Cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(appSettings.text("完成", "Done")) {
                        saveAction(
                            UserHealthProfile(
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Bill" : name,
                                heightCm: Double(height),
                                weightKg: Double(weight),
                                age: Int(age),
                                targetWeightKg: Double(targetWeight),
                                biologicalSex: biologicalSex == "unspecified" ? nil : biologicalSex,
                                lastSyncedAt: nil
                            )
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }
}

private enum EditorKeyboardKind {
    case text
    case number
    case decimal

#if os(iOS)
    var keyboardType: UIKeyboardType {
        switch self {
        case .text:
            return .default
        case .number:
            return .numberPad
        case .decimal:
            return .decimalPad
        }
    }
#endif
}

private struct EditorTextRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let placeholder: String
    @Binding var text: String
    let keyboard: EditorKeyboardKind
    var unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorFieldHeader(title: title, subtitle: subtitle, icon: icon, tint: tint)

            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
#if os(iOS)
                    .keyboardType(keyboard.keyboardType)
#endif

                if let unit {
                    Text(unit)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppColor.softFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct EditorDateRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    @Binding var date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorFieldHeader(title: title, subtitle: subtitle, icon: icon, tint: tint)

            DatePicker("", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .tint(AppColor.healthGreen)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppColor.softFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct MealTypeEditorRow: View {
    @EnvironmentObject private var appSettings: AppSettings
    @Binding var selection: MealType

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorFieldHeader(title: appSettings.text("餐别", "Meal"), subtitle: appSettings.text("这餐属于哪个时段", "Which part of the day this meal belongs to"), icon: "sparkles", tint: AppColor.violet)

            Picker(appSettings.text("餐别", "Meal"), selection: $selection) {
                ForEach(MealType.allCases) { type in
                    Text(type.title(language: appSettings.resolvedLanguage)).tag(type)
                }
            }
            .pickerStyle(.menu)
            .tint(AppColor.healthGreen)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppColor.softFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct BiologicalSexEditorRow: View {
    @EnvironmentObject private var appSettings: AppSettings
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorFieldHeader(title: appSettings.text("生理性别", "Biological Sex"), subtitle: appSettings.text("用于基础代谢估算", "Used to estimate basal burn"), icon: "figure.stand", tint: AppColor.violet)

            Picker(appSettings.text("生理性别", "Biological Sex"), selection: $selection) {
                Text(appSettings.text("未指定", "Not set")).tag("unspecified")
                Text(appSettings.text("男", "Male")).tag("male")
                Text(appSettings.text("女", "Female")).tag("female")
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct EditorFieldHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct CalorieEntry: Identifiable {
    let id = UUID()
    let date: Date
    let intake: Int
    let burn: Int
}

private enum AppColor {
    static let healthGreen = Color(red: 0.11, green: 0.78, blue: 0.36)
    static let energyOrange = Color(red: 1.0, green: 0.55, blue: 0.18)
    static let warningRed = Color(red: 0.95, green: 0.22, blue: 0.22)
    static let skyBlue = Color(red: 0.18, green: 0.55, blue: 0.95)
    static let violet = Color(red: 0.48, green: 0.39, blue: 0.95)

    static var screenBackground: Color {
#if os(macOS)
        Color(nsColor: .windowBackgroundColor)
#else
        Color(uiColor: .systemGroupedBackground)
#endif
    }

    static var cardBackground: Color {
#if os(macOS)
        Color(nsColor: .controlBackgroundColor)
#else
        Color(uiColor: .secondarySystemGroupedBackground)
#endif
    }

    static var softFill: Color {
#if os(macOS)
        Color(nsColor: .separatorColor).opacity(0.18)
#else
        Color(uiColor: .tertiarySystemFill)
#endif
    }
}

private extension View {
    func healthCard(padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 8)
    }
}

private extension DailyHealthOverview {
    var hasUserVisibleData: Bool {
        intakeKcal > 0 || activeEnergyKcal > 0 || stepCount > 0 || !basalIsEstimated
    }
}

#Preview {
    ContentView()
        .environmentObject(HealthDashboardStore())
        .environmentObject(AppSettings())
}
