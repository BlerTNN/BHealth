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
    @State private var selectedTab = HealthTab.overview

    var body: some View {
        TabView(selection: $selectedTab) {
            OverviewView()
                .tabItem {
                    Label("总览", systemImage: "heart.text.square.fill")
                }
                .tag(HealthTab.overview)

            AssistantView()
                .tabItem {
                    Label("AI 助手", systemImage: "sparkles")
                }
                .tag(HealthTab.assistant)

            ProfileView()
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle.fill")
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
                            title: "基础代谢",
                            value: "\(basalBurn)",
                            unit: "kcal",
                            systemImage: "person.fill.checkmark",
                            tint: today.basalIsEstimated ? AppColor.skyBlue : AppColor.healthGreen
                        )

                        MetricCard(
                            title: "健身消耗",
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
            .navigationTitle("今日总览")
            .task {
                await healthStore.refreshHealthDataIfPossible()
            }
        }
    }
}

private struct CalorieSummaryCard: View {
    let calorieBalance: Int

    private var isOverBudget: Bool {
        calorieBalance < 0
    }

    private var tint: Color {
        isOverBudget ? AppColor.warningRed : AppColor.healthGreen
    }

    private var statusTitle: String {
        isOverBudget ? "今日已超出" : "今日余量"
    }

    private var statusSubtitle: String {
        isOverBudget ? "摄入已高于今日消耗" : "目标是让摄入低于消耗"
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
    let entries: [CalorieEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("近 7 天趋势")
                        .font(.headline.weight(.semibold))

                    Text("每日摄入与消耗对比")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    YearCalendarView()
                } label: {
                    Label("年历", systemImage: "calendar")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.bordered)
                .tint(AppColor.healthGreen)
            }

            Chart(entries) { entry in
                BarMark(
                    x: .value("日期", entry.date, unit: .day),
                    y: .value("卡路里", entry.intake)
                )
                .foregroundStyle(by: .value("类型", "摄入"))
                .position(by: .value("类型", "摄入"))
                .cornerRadius(6)

                BarMark(
                    x: .value("日期", entry.date, unit: .day),
                    y: .value("卡路里", entry.burn)
                )
                .foregroundStyle(by: .value("类型", "消耗"))
                .position(by: .value("类型", "消耗"))
                .cornerRadius(6)
            }
            .chartForegroundStyleScale([
                "摄入": AppColor.healthGreen,
                "消耗": AppColor.energyOrange
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

    private var monthGroups: [YearMonthGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: healthStore.yearSummaries) { summary in
            calendar.date(from: calendar.dateComponents([.year, .month], from: summary.date)) ?? summary.date
        }

        return grouped.keys.sorted(by: >).map { monthStart in
            YearMonthGroup(
                monthStart: monthStart,
                summaries: (grouped[monthStart] ?? []).sorted { $0.date < $1.date }
            )
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                YearCalendarSummaryCard(summaries: healthStore.yearSummaries)

                ForEach(monthGroups) { group in
                    CalendarMonthSection(group: group)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(AppColor.screenBackground.ignoresSafeArea())
        .navigationTitle("近一年日历")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Date.self) { date in
            DailyCalendarDetailView(date: date)
        }
    }
}

private struct YearCalendarSummaryCard: View {
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
                Text("每日余量记录")
                    .font(.headline.weight(.semibold))

                Text("已记录 \(recordedDays) 天，超出 \(overBudgetDays) 天")
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
    let summaries: [DailyHealthOverview]

    var id: Date { monthStart }
}

private struct CalendarMonthSection: View {
    let group: YearMonthGroup

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

    private var slots: [DailyHealthOverview?] {
        guard let firstSummary = group.summaries.first else { return [] }
        let calendar = Calendar.current
        let weekdayOffset = calendar.component(.weekday, from: group.monthStart) - 1
        let dayOffset = calendar.component(.day, from: firstSummary.date) - 1
        return Array(repeating: nil, count: weekdayOffset + dayOffset) + group.summaries.map(Optional.some)
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

                ForEach(slots.indices, id: \.self) { index in
                    if let summary = slots[index] {
                        NavigationLink(value: summary.date) {
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
        group.monthStart.formatted(.dateTime.year().month(.wide))
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
                    DetailMetricCard(title: "摄入", value: summary.intakeKcal, unit: "kcal", icon: "fork.knife", tint: AppColor.healthGreen)
                    DetailMetricCard(title: "总消耗", value: summary.totalBurnKcal, unit: "kcal", icon: "flame.fill", tint: AppColor.energyOrange)
                    DetailMetricCard(title: "健身消耗", value: summary.activeEnergyKcal, unit: "kcal", icon: "figure.run", tint: AppColor.skyBlue)
                    DetailMetricCard(
                        title: "基础代谢",
                        value: summary.basalEnergyKcal,
                        unit: "kcal",
                        icon: "person.fill.checkmark",
                        tint: AppColor.violet
                    )
                }

                DetailMetricCard(title: "步数", value: summary.stepCount, unit: "步", icon: "figure.walk", tint: AppColor.healthGreen)

                VStack(alignment: .leading, spacing: 14) {
                    Text("当日饮食")
                        .font(.headline.weight(.semibold))

                    if records.isEmpty {
                        Text("暂无饮食记录")
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
        .navigationTitle(date.formatted(.dateTime.month().day().weekday(.wide)))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DailyBalanceHeaderCard: View {
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
                Text(isOverBudget ? "当日超出" : "当日余量")
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
    let summary: DailyHealthOverview

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("今日建议", systemImage: "lightbulb.max.fill")
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
            return "今天还没有确认保存的饮食记录。你可以到 AI 助手页用自然语言记录一餐，总览会自动更新摄入热量。"
        }

        if summary.balanceKcal >= 250 {
            return "今天热量仍有约 \(Int(summary.balanceKcal.rounded())) kcal 余量。晚餐可以优先选择高蛋白、低油脂食物，并保持轻量活动。"
        }

        if summary.balanceKcal >= 0 {
            return "今天摄入和消耗比较接近。后续记录尽量补充克重或份量，热量估算会更可靠。"
        }

        return "今天摄入已高于消耗约 \(abs(Int(summary.balanceKcal.rounded()))) kcal。可以选择散步或拉伸，不建议用高强度运动强行抵消。"
    }
}

private struct MealHistorySection: View {
    @EnvironmentObject private var healthStore: HealthDashboardStore
    @State private var showsHistory = false

    let records: [SavedMealRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("历史饮食记录")
                        .font(.headline.weight(.semibold))

                    Text(records.isEmpty ? "暂无已确认记录" : "共 \(records.count) 条，可查看和修改")
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
                    Text("查看全部记录")
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

                Text("\(record.consumedAt.formatted(date: .abbreviated, time: .omitted)) · \(record.mealType.title)")
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
    @State private var editingRecord: SavedMealRecord?

    var body: some View {
        NavigationStack {
            List {
                if healthStore.savedMealRecords.isEmpty {
                    ContentUnavailableView("暂无记录", systemImage: "fork.knife", description: Text("在 AI 助手中确认保存后会出现在这里。"))
                } else {
                    ForEach(healthStore.savedMealRecords) { record in
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
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("历史记录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
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
}

private struct MealRecordEditorView: View {
    @Environment(\.dismiss) private var dismiss
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
                            title: "食品",
                            subtitle: "已保存的具体食物",
                            icon: "fork.knife",
                            tint: AppColor.healthGreen,
                            placeholder: "例如 鸡蛋、拿铁、吐司",
                            text: $foodName,
                            keyboard: .text
                        )

                        Divider()

                        EditorTextRow(
                            title: "热量",
                            subtitle: "当餐估算摄入",
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
                            title: "日期",
                            subtitle: "这餐归属的日期",
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
                        Label("删除记录", systemImage: "trash")
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
            .navigationTitle("编辑记录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
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
            sourceName: "用户编辑",
            sourceVersion: "manual",
            assumptions: ["用户手动编辑历史记录。"]
        )
        let calculation = MealCalculationResult(
            id: record.calculation.id,
            createdAt: record.calculation.createdAt,
            items: [item],
            totalEnergyKcal: energy,
            rangeLowKcal: energy,
            rangeHighKcal: energy,
            confidence: record.calculation.confidence,
            assumptions: ["用户手动编辑历史记录。"],
            sourceSummary: "用户编辑"
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
    @StateObject private var viewModel = FoodAssistantViewModel()
    @State private var navigationPath: [AssistantMode] = []
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack(path: $navigationPath) {
            AssistantModeSelectionView { mode in
                viewModel.openMode(mode)
                navigationPath.append(mode)
            }
            .background(AppColor.screenBackground.ignoresSafeArea())
            .navigationTitle("AI 助手")
            .navigationDestination(for: AssistantMode.self) { mode in
                assistantChat(mode: mode)
                    .onAppear {
                        if viewModel.selectedMode != mode {
                            viewModel.openMode(mode)
                        }
                    }
            }
            .onChange(of: navigationPath) { _, path in
                if path.isEmpty {
                    isInputFocused = false
                    viewModel.closeMode()
                }
            }
            .onAppear {
                viewModel.refreshAPIKeyStatus()
            }
        }
    }

    private func assistantChat(mode: AssistantMode) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        AssistantHeader(mode: mode)

                        if mode.supportsMealSaving {
                            MealLoggingContextCard(mode: mode)
                        }

                        QuickPromptRow(mode: mode) { message in
                            isInputFocused = false
                            Task {
                                await viewModel.send(message, dashboardContext: healthStore.assistantContextSummary)
                            }
                        }

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
                        await viewModel.sendDraftMessage(dashboardContext: healthStore.assistantContextSummary)
                    }
                }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
        .navigationTitle(mode.title)
    }
}

private struct AssistantModeSelectionView: View {
    let selectMode: (AssistantMode) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("选择助手")
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
                                Text(mode.title)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text(mode.subtitle)
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

private struct AssistantHeader: View {
    let mode: AssistantMode

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppColor.healthGreen.gradient)
                    .frame(width: 56, height: 56)

                Image(systemName: mode.icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(mode.title)
                    .font(.title3.weight(.bold))

                Text(mode.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
        }
        .healthCard()
    }
}

private struct MealLoggingContextCard: View {
    let mode: AssistantMode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(dateText, systemImage: mode == .historicalFoodLog ? "calendar.badge.clock" : "calendar")
                .font(.subheadline.weight(.semibold))

            Label("餐别：由 AI 确认", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .healthCard()
    }

    private var dateText: String {
        mode == .historicalFoodLog ? "日期：由 AI 确认" : "日期：今天"
    }
}

private struct QuickPromptRow: View {
    let mode: AssistantMode
    let sendAction: (String) -> Void

    private var prompts: [QuickPrompt] {
        switch mode {
        case .foodLog:
            return [
                QuickPrompt(title: "记录一餐", icon: "fork.knife", message: "我吃了一个鸡蛋、一杯拿铁和一片吐司。"),
                QuickPrompt(title: "估算热量", icon: "sparkles", message: "我吃了鸡胸肉沙拉，帮我估算热量。")
            ]
        case .historicalFoodLog:
            return [
                QuickPrompt(title: "补录一餐", icon: "calendar.badge.clock", message: "补录一餐：两个鸡蛋和一杯牛奶。"),
                QuickPrompt(title: "补录昨天", icon: "clock.arrow.circlepath", message: "昨天吃了牛肉饭，大概一碗。")
            ]
        case .healthCoach:
            return [
                QuickPrompt(title: "饮食建议", icon: "leaf.fill", message: "根据我的历史记录，给我今天的饮食建议。"),
                QuickPrompt(title: "减重趋势", icon: "chart.line.downtrend.xyaxis", message: "按最近摄入和消耗，大概能减多少体重？")
            ]
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(prompts) { prompt in
                    Button {
                        sendAction(prompt.message)
                    } label: {
                        Label(prompt.title, systemImage: prompt.icon)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(AppColor.cardBackground, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct APIKeySetupCard: View {
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
                    Text(hasAPIKey ? "DeepSeek 已连接" : "DeepSeek API Key")
                        .font(.headline.weight(.semibold))

                    Text(hasAPIKey ? "密钥保存在系统 Keychain" : "保存后开始真实 AI 对话")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if hasAPIKey {
                Button(role: .destructive, action: deleteAction) {
                    Label("删除密钥", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            } else {
                HStack(spacing: 10) {
                    SecureField("DeepSeek API Key", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)

                    Button(action: saveAction) {
                        Label("保存", systemImage: "lock.fill")
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

                Text("正在分析")
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
    let calculation: MealCalculationResult
    let mealType: MealType?
    let consumedAt: Date?
    let saveAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("待确认记录", systemImage: "doc.badge.clock")
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

                Text("范围 \(Int(calculation.rangeLowKcal.rounded()))-\(Int(calculation.rangeHighKcal.rounded()))")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let consumedAt {
                    Label("日期：\(consumedAt.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
                }

                if let mealType {
                    Label("餐别：\(mealType.title)", systemImage: "sparkles")
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

                        Text("\(item.displayFoodName)：约 \(Int(item.energyKcal.rounded())) kcal")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            Text("来源：\(calculation.sourceSummary)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: saveAction) {
                Label("确认记录", systemImage: "checkmark.circle.fill")
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
        calculation.confidence == "low" ? "低可信度" : "中等可信度"
    }

    private var confidenceColor: Color {
        calculation.confidence == "low" ? AppColor.energyOrange : AppColor.healthGreen
    }
}

private struct ChatInputBar: View {
    @Binding var text: String
    let isSending: Bool
    var isFocused: FocusState<Bool>.Binding
    let sendAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("输入饮食、运动或健康问题", text: $text, axis: .vertical)
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
                        ProfileMetricCard(title: "身高", value: formatNumber(healthStore.profile.heightCm), unit: "cm", icon: "ruler", tint: AppColor.skyBlue)
                        ProfileMetricCard(title: "体重", value: formatNumber(healthStore.profile.weightKg), unit: "kg", icon: "scalemass.fill", tint: AppColor.healthGreen)
                        ProfileMetricCard(title: "年龄", value: formatInteger(healthStore.profile.age), unit: "岁", icon: "calendar", tint: AppColor.energyOrange)
                        ProfileMetricCard(title: "目标体重", value: formatNumber(healthStore.profile.targetWeightKg), unit: "kg", icon: "target", tint: AppColor.violet)
                    }

                    APIKeySetupCard(
                        apiKeyInput: $apiKeyInput,
                        hasAPIKey: hasAPIKey,
                        statusMessage: apiKeyStatusMessage,
                        saveAction: saveAPIKey,
                        deleteAction: deleteAPIKey
                    )

                    syncCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .background(AppColor.screenBackground.ignoresSafeArea())
            .navigationTitle("我的")
            .onAppear {
                hasAPIKey = KeychainAPIKeyStore.shared.hasAPIKey
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isEditingProfile = true
                    } label: {
                        Label("编辑", systemImage: "square.and.pencil")
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

                    Text(healthStore.healthKitStatusMessage)
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
                Label(healthStore.isSyncingHealthKit ? "同步中" : "同步健康与健身数据", systemImage: "arrow.triangle.2.circlepath")
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
            return "上次同步：\(syncedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return "目标：稳步控制热量，建立长期健康记录"
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
            apiKeyStatusMessage = "DeepSeek API key 已保存到系统 Keychain。"
        } catch {
            apiKeyStatusMessage = error.localizedDescription
        }
    }

    private func deleteAPIKey() {
        do {
            try KeychainAPIKeyStore.shared.deleteAPIKey()
            hasAPIKey = false
            apiKeyStatusMessage = "已从 Keychain 删除 DeepSeek API key。"
        } catch {
            apiKeyStatusMessage = error.localizedDescription
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
                            title: "姓名",
                            subtitle: "个人资料显示名称",
                            icon: "person.fill",
                            tint: AppColor.healthGreen,
                            placeholder: "姓名",
                            text: $name,
                            keyboard: .text
                        )

                        Divider()

                        EditorTextRow(
                            title: "身高",
                            subtitle: "用于估算基础代谢",
                            icon: "ruler",
                            tint: AppColor.skyBlue,
                            placeholder: "cm",
                            text: $height,
                            keyboard: .decimal,
                            unit: "cm"
                        )

                        Divider()

                        EditorTextRow(
                            title: "体重",
                            subtitle: "当前体重",
                            icon: "scalemass.fill",
                            tint: AppColor.healthGreen,
                            placeholder: "kg",
                            text: $weight,
                            keyboard: .decimal,
                            unit: "kg"
                        )

                        Divider()

                        EditorTextRow(
                            title: "年龄",
                            subtitle: "用于健康估算",
                            icon: "calendar",
                            tint: AppColor.energyOrange,
                            placeholder: "岁",
                            text: $age,
                            keyboard: .number,
                            unit: "岁"
                        )

                        Divider()

                        EditorTextRow(
                            title: "目标体重",
                            subtitle: "长期目标",
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
            .navigationTitle("编辑资料")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
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
    @Binding var selection: MealType

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorFieldHeader(title: "餐别", subtitle: "这餐属于哪个时段", icon: "sparkles", tint: AppColor.violet)

            Picker("餐别", selection: $selection) {
                ForEach(MealType.allCases) { type in
                    Text(type.title).tag(type)
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
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorFieldHeader(title: "生理性别", subtitle: "用于基础代谢估算", icon: "figure.stand", tint: AppColor.violet)

            Picker("生理性别", selection: $selection) {
                Text("未指定").tag("unspecified")
                Text("男").tag("male")
                Text("女").tag("female")
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

private struct QuickPrompt: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let message: String
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
}
