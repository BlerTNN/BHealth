//
//  ContentView.swift
//  BHealth
//
//  Created by Bill on 2026-06-26.
//

import Charts
import SwiftUI

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
    private let intake = 1680
    private let intakeTarget = 2100
    private let basalBurn = 1560
    private let activeBurn = 540
    private let weeklyEntries = CalorieEntry.sampleWeek

    private var totalBurn: Int {
        basalBurn + activeBurn
    }

    private var calorieBalance: Int {
        totalBurn - intake
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    OverviewHeader()

                    CalorieSummaryCard(
                        intake: intake,
                        intakeTarget: intakeTarget,
                        totalBurn: totalBurn,
                        calorieBalance: calorieBalance
                    )

                    HStack(spacing: 12) {
                        MetricCard(
                            title: "基础代谢",
                            value: "\(basalBurn)",
                            unit: "kcal",
                            systemImage: "person.fill.checkmark",
                            tint: AppColor.healthGreen
                        )

                        MetricCard(
                            title: "运动消耗",
                            value: "\(activeBurn)",
                            unit: "kcal",
                            systemImage: "figure.run",
                            tint: AppColor.energyOrange
                        )
                    }

                    WeeklyChartCard(entries: weeklyEntries)

                    InsightCard()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .background(AppColor.screenBackground.ignoresSafeArea())
            .navigationTitle("今日总览")
        }
    }
}

private struct OverviewHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppColor.healthGreen.opacity(0.16))
                    .frame(width: 48, height: 48)

                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(AppColor.healthGreen)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("BHealth")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)

                Text("本地示例数据 · 稍后接入 Apple Health")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.top, 4)
    }
}

private struct CalorieSummaryCard: View {
    let intake: Int
    let intakeTarget: Int
    let totalBurn: Int
    let calorieBalance: Int

    private var intakeProgress: Double {
        min(Double(intake) / Double(intakeTarget), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 20) {
                ProgressRing(progress: intakeProgress, tint: AppColor.healthGreen) {
                    VStack(spacing: 3) {
                        Text("\(Int(intakeProgress * 100))%")
                            .font(.title3.weight(.bold))
                            .monospacedDigit()

                        Text("摄入目标")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 118, height: 118)

                VStack(alignment: .leading, spacing: 10) {
                    Text("今日热量")
                        .font(.headline.weight(.semibold))

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(intake)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()

                        Text("/ \(intakeTarget) kcal")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Label("净余量 \(calorieBalance) kcal", systemImage: "arrow.down.forward.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.healthGreen)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                CaloriePill(title: "已摄入", value: intake, tint: AppColor.healthGreen, icon: "fork.knife")
                CaloriePill(title: "已消耗", value: totalBurn, tint: AppColor.energyOrange, icon: "flame.fill")
            }
        }
        .healthCard()
    }
}

private struct CaloriePill: View {
    let title: String
    let value: Int
    let tint: Color
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(value) kcal")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(AppColor.softFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

private struct WeeklyChartCard: View {
    let entries: [CalorieEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("近 7 日趋势")
                        .font(.headline.weight(.semibold))

                    Text("摄入与消耗的粗略对比")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColor.healthGreen)
                    .frame(width: 38, height: 38)
                    .background(AppColor.healthGreen.opacity(0.14), in: Circle())
            }

            Chart(entries) { entry in
                BarMark(
                    x: .value("日期", entry.day),
                    y: .value("卡路里", entry.intake)
                )
                .foregroundStyle(by: .value("类型", "摄入"))
                .position(by: .value("类型", "摄入"))
                .cornerRadius(6)

                BarMark(
                    x: .value("日期", entry.day),
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
            .frame(height: 190)
        }
        .healthCard()
    }
}

private struct InsightCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("今日建议", systemImage: "lightbulb.max.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            Text("你今天还有约 420 kcal 的弹性空间。晚餐可以优先选择高蛋白、低油脂食物，并保持 20 分钟轻量活动。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .healthCard()
    }
}

private struct AssistantView: View {
    @StateObject private var viewModel = FoodAssistantViewModel()

    private let quickPrompts: [QuickPrompt] = [
        QuickPrompt(title: "记录饮食", icon: "fork.knife", message: "我早餐吃了一个鸡蛋、一杯拿铁和一片吐司，帮我估算热量。"),
        QuickPrompt(title: "运动建议", icon: "figure.cooldown", message: "今天我只走了 3000 步，晚上适合做什么运动？"),
        QuickPrompt(title: "健康建议", icon: "heart.text.square", message: "根据今天的摄入和消耗，给我一个晚餐建议。")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            AssistantHeader()

                            APIKeySetupCard(
                                apiKeyInput: $viewModel.apiKeyInput,
                                hasAPIKey: viewModel.hasAPIKey,
                                statusMessage: viewModel.apiKeyStatusMessage,
                                saveAction: viewModel.saveAPIKey,
                                deleteAction: viewModel.deleteAPIKey
                            )

                            quickPromptRow

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
                                        saveAction: viewModel.savePendingCalculation
                                    )
                                    .id(calculation.id)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
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
                    sendAction: {
                        Task {
                            await viewModel.sendDraftMessage()
                        }
                    }
                )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial)
            }
            .background(AppColor.screenBackground.ignoresSafeArea())
            .navigationTitle("AI 助手")
        }
    }

    private var quickPromptRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(quickPrompts) { prompt in
                    Button {
                        Task {
                            await viewModel.send(prompt.message)
                        }
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

private struct AssistantHeader: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppColor.healthGreen.gradient)
                    .frame(width: 56, height: 56)

                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("你的健康记录搭档")
                    .font(.title3.weight(.bold))

                Text("告诉我你吃了什么、做了什么运动，我会帮你整理成当天热量记录。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
        }
        .healthCard()
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
                ForEach(calculation.items.prefix(3)) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(AppColor.healthGreen)
                            .padding(.top, 7)

                        Text("\(item.rawText)：\(item.matchedFoodName)，约 \(Int(item.energyKcal.rounded())) kcal")
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
    let sendAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("输入饮食、运动或健康问题", text: $text, axis: .vertical)
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
    @State private var name = "Bill"
    @State private var height = "175"
    @State private var weight = "70"
    @State private var age = "30"
    @State private var targetWeight = "68"
    @State private var isEditingProfile = false
    @State private var showsSyncNotice = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    profileHeader

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ProfileMetricCard(title: "身高", value: height, unit: "cm", icon: "ruler", tint: AppColor.skyBlue)
                        ProfileMetricCard(title: "体重", value: weight, unit: "kg", icon: "scalemass.fill", tint: AppColor.healthGreen)
                        ProfileMetricCard(title: "年龄", value: age, unit: "岁", icon: "calendar", tint: AppColor.energyOrange)
                        ProfileMetricCard(title: "目标体重", value: targetWeight, unit: "kg", icon: "target", tint: AppColor.violet)
                    }

                    syncCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .background(AppColor.screenBackground.ignoresSafeArea())
            .navigationTitle("我的")
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
                    name: $name,
                    height: $height,
                    weight: $weight,
                    age: $age,
                    targetWeight: $targetWeight
                )
            }
            .alert("Apple Health 同步", isPresented: $showsSyncNotice) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("当前版本先完成 UI。下一阶段接入 HealthKit 权限后，会在本地读取并保存身高、体重和运动消耗。")
            }
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppColor.healthGreen.gradient)
                    .frame(width: 78, height: 78)

                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(name)
                    .font(.title2.weight(.bold))

                Text("目标：稳步控制热量，建立长期健康记录")
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
                    Text("Apple Health")
                        .font(.headline.weight(.semibold))

                    Text("稍后接入后，数据只在本地读取与保存")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                showsSyncNotice = true
            } label: {
                Label("从 Apple Health 同步", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.healthGreen)
        }
        .healthCard()
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
    @Binding var name: String
    @Binding var height: String
    @Binding var weight: String
    @Binding var age: String
    @Binding var targetWeight: String

    var body: some View {
        NavigationStack {
            Form {
                Section("个人信息") {
                    TextField("姓名", text: $name)
                    TextField("身高 cm", text: $height)
                    TextField("体重 kg", text: $weight)
                    TextField("年龄", text: $age)
                    TextField("目标体重 kg", text: $targetWeight)
                }
            }
            .navigationTitle("编辑资料")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct ProgressRing<CenterContent: View>: View {
    let progress: Double
    let tint: Color
    @ViewBuilder var centerContent: () -> CenterContent

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColor.softFill, lineWidth: 14)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    tint.gradient,
                    style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))

            centerContent()
        }
        .animation(.snappy, value: progress)
    }
}

private struct CalorieEntry: Identifiable {
    let id = UUID()
    let day: String
    let intake: Int
    let burn: Int

    static let sampleWeek: [CalorieEntry] = [
        CalorieEntry(day: "一", intake: 1980, burn: 2260),
        CalorieEntry(day: "二", intake: 2160, burn: 2140),
        CalorieEntry(day: "三", intake: 1740, burn: 2310),
        CalorieEntry(day: "四", intake: 1880, burn: 2180),
        CalorieEntry(day: "五", intake: 1680, burn: 2100),
        CalorieEntry(day: "六", intake: 2050, burn: 2360),
        CalorieEntry(day: "日", intake: 1920, burn: 2200)
    ]
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

#Preview {
    ContentView()
}
