import SwiftUI

struct GroupEditorSheet: View {
    @ObservedObject var store: GatewayStore
    let existing: RemoteRoutingGroup?
    @Environment(\.dismiss) private var dismiss

    enum EditorSection: String, CaseIterable {
        case basic = "成员与策略"
        case rules = "分流规则"
        case limits = "超时与上下文"
    }

    @State private var activeSection: EditorSection = .basic
    @State private var name = ""
    @State private var groupID = ""
    @State private var note = ""
    @State private var routing = ""
    @State private var affinity = ""
    @State private var sinkMode = 0 // 0=default, 1=on, 2=off
    @State private var members: [String] = []
    @State private var offMembers: Set<String> = []
    @State private var fastMembers: Set<String> = []
    @State private var ultraMembers: Set<String> = []
    @State private var matchPatterns: [String] = []
    @State private var newPattern = ""
    @State private var rules: [RemoteGroupRule] = []
    @State private var classifier = ""
    @State private var autoEffort = false
    @State private var firstTokenText = ""
    @State private var patienceText = ""
    @State private var contextMode = 0 // 0=largest, -1=smallest, 1=custom
    @State private var contextCustomText = ""
    @State private var compactText = ""
    @State private var unlists = false

    @State private var showingMemberPicker = false
    @State private var memberSearch = ""
    @State private var showingRuleEditor = false
    @State private var isSaving = false
    @State private var errorMsg: String?

    // Rule editor drafts
    @State private var ruleUse = ""
    @State private var ruleUseEffort = ""
    @State private var rulePause = false
    @State private var ruleMinTokens = ""
    @State private var ruleImages = false
    @State private var ruleCompact = false
    @State private var ruleEffort = ""
    @State private var ruleAgentsText = ""
    @State private var ruleIntent = ""
    @State private var ruleUseTime = false
    @State private var ruleTimeFrom = "09:00"
    @State private var ruleTimeTo = "18:00"

    private let routingModes: [(id: String, title: String)] = [
        ("", "Smart 智能"),
        ("order", "Order 顺序"),
        ("drain", "Drain 耗尽"),
        ("rotate", "Rotate 轮询"),
        ("usage", "Usage 均衡"),
        ("pace", "Pace 速率"),
        ("free", "Free 免费优先"),
        ("expiring", "Expiring 快过期优先"),
        ("fast", "Fast 最快"),
        ("cheap", "Cheap 最便宜"),
        ("manual", "Manual 手动切换")
    ]

    private let affinityModes: [(id: String, title: String)] = [
        ("", "自动"),
        ("session", "整会话"),
        ("turn", "单轮"),
        ("off", "不粘性"),
        ("strict", "严格锁定")
    ]

    private let effortChoices = ["", "low", "medium", "high", "xhigh", "max"]

    var body: some View {
        ZStack {
            MagpieTheme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                sectionBar

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        if let err = errorMsg {
                            MagpieErrorBanner(title: "保存失败", message: err)
                        }

                        switch activeSection {
                        case .basic:
                            basicAndMembersSection
                        case .rules:
                            rulesSection
                        case .limits:
                            limitsSection
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear(perform: loadExisting)
        .sheet(isPresented: $showingMemberPicker) {
            memberPickerSheet
        }
        .sheet(isPresented: $showingRuleEditor) {
            ruleEditorSheet
        }
    }

    private var headerBar: some View {
        HStack {
            Button("取消") { dismiss() }
                .font(.system(size: 14))
                .foregroundColor(MagpieTheme.textSecondary)
            Spacer()
            Text(existing == nil ? "新建路由组" : "编辑路由组")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(MagpieTheme.ink)
            Spacer()
            Button(isSaving ? "保存中…" : "保存") { commitSave() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MagpieTheme.ink)
                .disabled(isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(MagpieTheme.surface)
        .overlay(Rectangle().fill(MagpieTheme.hairline).frame(height: 1), alignment: .bottom)
    }

    private var sectionBar: some View {
        HStack(spacing: 8) {
            ForEach(EditorSection.allCases, id: \.self) { sec in
                let selected = activeSection == sec
                Button(sec.rawValue) {
                    activeSection = sec
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(selected ? MagpieTheme.surface : MagpieTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? MagpieTheme.ink : MagpieTheme.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(MagpieTheme.hairline, lineWidth: selected ? 0 : 1))
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Section 1: Basic, Routing, Members & Patterns

    private var basicAndMembersSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            MinimalSection(title: "路由组信息", trailingText: existing?.ref) {
                MagpieInputField(label: "路由组名称", placeholder: "例如：主力编程组 / 省钱兜底组", text: $name)
                MagpieInputField(
                    label: "Group ID（可选，留空自动从名称生成）",
                    placeholder: "例如：coding-fast",
                    text: $groupID,
                    monospaced: true,
                    helperText: "仅限小写字母、数字、点与短横线；Agent 引用名为 group/<id>"
                )
                MagpieInputField(label: "备注说明（可选）", placeholder: "仅展示在控制台", text: $note)
            }

            MinimalSection(title: "调度策略与会话粘性") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("路由策略")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MagpieTheme.textSecondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(routingModes, id: \.id) { mode in
                                let selected = routing == mode.id
                                Button(mode.title) { routing = mode.id }
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(selected ? MagpieTheme.surface : MagpieTheme.ink)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(selected ? MagpieTheme.ink : MagpieTheme.canvas)
                                    .clipShape(Capsule())
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text("会话粘性")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MagpieTheme.textSecondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(affinityModes, id: \.id) { mode in
                                let selected = affinity == mode.id
                                Button(mode.title) { affinity = mode.id }
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(selected ? MagpieTheme.surface : MagpieTheme.ink)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(selected ? MagpieTheme.ink : MagpieTheme.canvas)
                                    .clipShape(Capsule())
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Rectangle().fill(MagpieTheme.hairline).frame(height: 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text("429 限流沉底")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MagpieTheme.textSecondary)
                    HStack(spacing: 8) {
                        ForEach([(0, "跟随全局默认"), (1, "强制开启"), (2, "强制关闭")], id: \.0) { item in
                            let selected = sinkMode == item.0
                            Button(item.1) { sinkMode = item.0 }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(selected ? MagpieTheme.surface : MagpieTheme.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selected ? MagpieTheme.ink : MagpieTheme.canvas)
                                .clipShape(Capsule())
                                .buttonStyle(.plain)
                        }
                    }
                }
            }

            MinimalSection(title: "成员列表 (\(members.count))") {
                HStack {
                    Button("+ 添加模型或子路由组") {
                        memberSearch = ""
                        showingMemberPicker = true
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                    Spacer()
                }

                if members.isEmpty {
                    Text("尚未选择成员，至少添加一个模型或下方匹配通配符。")
                        .font(.system(size: 12.5))
                        .foregroundColor(MagpieTheme.textMuted)
                } else {
                    ForEach(Array(members.enumerated()), id: \.offset) { idx, member in
                        if idx > 0 {
                            Rectangle().fill(MagpieTheme.hairline).frame(height: 1)
                        }
                        memberRow(index: idx, member: member)
                    }
                }
            }

            MinimalSection(title: "通配符自动匹配 (\(matchPatterns.count))", trailingText: "Match") {
                ForEach(matchPatterns, id: \.self) { pat in
                    HStack {
                        Text(pat)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundColor(MagpieTheme.ink)
                        Spacer()
                        Button("移除") {
                            matchPatterns.removeAll { $0 == pat }
                        }
                        .font(.system(size: 12))
                        .foregroundColor(MagpieTheme.err)
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 8) {
                    TextField("如 openrouter/*:free 或 re:claude-.*", text: $newPattern)
                        .font(.system(size: 12.5, design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(9)
                        .background(MagpieTheme.canvas)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Button("添加") {
                        let p = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !p.isEmpty else { return }
                        if !matchPatterns.contains(p) {
                            matchPatterns.append(p)
                        }
                        newPattern = ""
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .secondary, compact: true))
                }
            }
        }
    }

    private func memberRow(index: Int, member: String) -> some View {
        let isPaused = offMembers.contains(member)
        let isFast = fastMembers.contains(member)
        let isUltra = ultraMembers.contains(member)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(index + 1).")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(MagpieTheme.textMuted)
                Text(member)
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundColor(isPaused ? MagpieTheme.textMuted : MagpieTheme.ink)
                    .lineLimit(1)
                Spacer()
                if isPaused { MagpieTag(text: "已暂停", tone: MagpieTheme.warn) }
                if isUltra { MagpieTag(text: "Ultra", tone: MagpieTheme.ok) }
                else if isFast { MagpieTag(text: "Fast", tone: MagpieTheme.ok) }
            }

            HStack(spacing: 8) {
                if index > 0 {
                    Button("上移") {
                        members.swapAt(index, index - 1)
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                }
                if index < members.count - 1 {
                    Button("下移") {
                        members.swapAt(index, index + 1)
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                }

                Button(isPaused ? "恢复" : "暂停") {
                    if isPaused { offMembers.remove(member) } else { offMembers.insert(member) }
                }
                .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))

                Button(isFast ? "取消Fast" : "Fast") {
                    if isFast {
                        fastMembers.remove(member)
                        ultraMembers.remove(member)
                    } else {
                        fastMembers.insert(member)
                    }
                }
                .buttonStyle(MagpieButtonStyle(tone: isFast ? .primary : .subtle, compact: true))

                Spacer()

                Button("移除") {
                    members.remove(at: index)
                    offMembers.remove(member)
                    fastMembers.remove(member)
                    ultraMembers.remove(member)
                }
                .font(.system(size: 12))
                .foregroundColor(MagpieTheme.err)
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Section 2: Rules & Intent Classifier

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            MinimalSection(title: "条件分流规则 (\(rules.count))") {
                HStack {
                    Button("+ 新增分流规则") {
                        ruleUse = members.first ?? store.groupModels.first?.id ?? ""
                        ruleUseEffort = ""
                        rulePause = false
                        ruleMinTokens = ""
                        ruleImages = false
                        ruleCompact = false
                        ruleEffort = ""
                        ruleAgentsText = ""
                        ruleIntent = ""
                        ruleUseTime = false
                        showingRuleEditor = true
                    }
                    .buttonStyle(MagpieButtonStyle(tone: .primary, compact: true))
                    .disabled(members.isEmpty && store.groupModels.isEmpty)
                    Spacer()
                }

                if rules.isEmpty {
                    Text("暂无分流规则。可按请求 Tokens 长度、含图片、推理强度、Agent 来源、时间段或语义意图优先路由到指定成员。")
                        .font(.system(size: 12.5))
                        .foregroundColor(MagpieTheme.textMuted)
                } else {
                    ForEach(Array(rules.enumerated()), id: \.offset) { idx, rule in
                        if idx > 0 {
                            Rectangle().fill(MagpieTheme.hairline).frame(height: 1)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    MagpieTag(text: rule.pause ? "暂停" : "→ \(rule.use)", tone: rule.pause ? MagpieTheme.warn : MagpieTheme.ink, monospaced: !rule.pause)
                                    if let ue = rule.useEffort, !ue.isEmpty {
                                        MagpieTag(text: "思考:\(ue)", monospaced: true)
                                    }
                                }
                                Text(rule.summaryText)
                                    .font(.system(size: 12))
                                    .foregroundColor(MagpieTheme.textSecondary)
                            }
                            Spacer()
                            if idx > 0 {
                                Button("上移") { rules.swapAt(idx, idx - 1) }
                                    .buttonStyle(MagpieButtonStyle(tone: .subtle, compact: true))
                            }
                            Button("删除") {
                                rules.remove(at: idx)
                            }
                            .font(.system(size: 12))
                            .foregroundColor(MagpieTheme.err)
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            MinimalSection(title: "意图分类器与自动思考", trailingText: "Classifier") {
                MagpieInputField(
                    label: "分类器模型（用于意图规则与自动思考分级）",
                    placeholder: "例如：deepseek/deepseek-chat 或 group/fast",
                    text: $classifier,
                    monospaced: true
                )

                if !store.groupDeciders.isEmpty || !store.groupModels.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach((store.groupDeciders + store.groupModels).prefix(12)) { m in
                                Button(m.id) { classifier = m.id }
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundColor(classifier == m.id ? MagpieTheme.surface : MagpieTheme.ink)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(classifier == m.id ? MagpieTheme.ink : MagpieTheme.canvas)
                                    .clipShape(Capsule())
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自动判定推理强度 (Effort Auto)")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundColor(MagpieTheme.ink)
                        Text("每轮开始前由分类器按问题难度自动选择推理深度")
                            .font(.system(size: 11.5))
                            .foregroundColor(MagpieTheme.textMuted)
                    }
                    Spacer()
                    MagpieToggle(isOn: $autoEffort)
                }
            }
        }
    }

    // MARK: - Section 3: Timeouts & Context

    private var limitsSection: some View {
        MinimalSection(title: "超时、窗口与暴露开关") {
            MagpieInputField(
                label: "首字超时秒数 (FirstToken，0=跟随全局，-1=一直等待)",
                placeholder: "0",
                text: $firstTokenText,
                monospaced: true,
                keyboardType: .numbersAndPunctuation
            )

            MagpieInputField(
                label: "故障等待耐心秒数 (Patience，0=全局60s，-1=不等待)",
                placeholder: "0",
                text: $patienceText,
                monospaced: true,
                keyboardType: .numbersAndPunctuation
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("上报给 Agent 的上下文窗口 (Context)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MagpieTheme.textSecondary)
                HStack(spacing: 8) {
                    ForEach([(0, "取最大成员"), (-1, "取最小成员"), (1, "自定义")], id: \.0) { item in
                        let selected = contextMode == item.0
                        Button(item.1) { contextMode = item.0 }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(selected ? MagpieTheme.surface : MagpieTheme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selected ? MagpieTheme.ink : MagpieTheme.canvas)
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                    }
                }
                if contextMode == 1 {
                    MagpieInputField(label: "上下文 Token 数", placeholder: "128000", text: $contextCustomText, monospaced: true, keyboardType: .numberPad)
                }
            }

            MagpieInputField(
                label: "自动压缩触发阈值 (Compact Tokens，0=跟随成员)",
                placeholder: "0",
                text: $compactText,
                monospaced: true,
                keyboardType: .numberPad
            )

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("从 Agent 模型列表隐藏 (Unlists)")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(MagpieTheme.ink)
                    Text("仅在代码/配置中直接按 group/<id> 调用，不在列表展示")
                        .font(.system(size: 11.5))
                        .foregroundColor(MagpieTheme.textMuted)
                }
                Spacer()
                MagpieToggle(isOn: $unlists)
            }
        }
    }

    // MARK: - Sub Sheets

    private var memberPickerSheet: some View {
        let q = memberSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let modelCandidates = store.groupModels.filter { m in
            q.isEmpty || m.id.lowercased().contains(q) || m.name.lowercased().contains(q) || m.providerName.lowercased().contains(q)
        }
        let otherGroups = store.groups.filter { g in
            g.id != existing?.id && (q.isEmpty || g.name.lowercased().contains(q) || g.ref.lowercased().contains(q))
        }

        return ZStack {
            MagpieTheme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button("关闭") { showingMemberPicker = false }
                        .foregroundColor(MagpieTheme.textSecondary)
                    Spacer()
                    Text("添加路由组成员")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Color.clear.frame(width: 36, height: 1)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(MagpieTheme.surface)
                .overlay(Rectangle().fill(MagpieTheme.hairline).frame(height: 1), alignment: .bottom)

                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(MagpieTheme.textMuted)
                        TextField("搜索模型或路由组…", text: $memberSearch)
                            .font(.system(size: 13, design: .monospaced))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    .padding(10)
                    .background(MagpieTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(MagpieTheme.hairline, lineWidth: 1))
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        if !otherGroups.isEmpty {
                            MinimalSection(title: "嵌套子路由组") {
                                ForEach(otherGroups) { g in
                                    let added = members.contains(g.ref)
                                    Button {
                                        if !added { members.append(g.ref) }
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(g.name)
                                                    .font(.system(size: 13.5, weight: .medium))
                                                    .foregroundColor(MagpieTheme.ink)
                                                Text(g.ref)
                                                    .font(.system(size: 11.5, design: .monospaced))
                                                    .foregroundColor(MagpieTheme.textMuted)
                                            }
                                            Spacer()
                                            MagpieTag(text: added ? "已添加" : "添加", tone: added ? MagpieTheme.ok : MagpieTheme.ink)
                                        }
                                        .padding(.vertical, 3)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        MinimalSection(title: "可用模型 (\(modelCandidates.count))") {
                            if modelCandidates.isEmpty {
                                Text("没有匹配的模型")
                                    .font(.system(size: 12.5))
                                    .foregroundColor(MagpieTheme.textMuted)
                            } else {
                                ForEach(Array(modelCandidates.enumerated()), id: \.element.id) { idx, m in
                                    if idx > 0 {
                                        Rectangle().fill(MagpieTheme.hairline).frame(height: 1)
                                    }
                                    let added = members.contains(m.id)
                                    Button {
                                        if added {
                                            members.removeAll { $0 == m.id }
                                        } else {
                                            members.append(m.id)
                                        }
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(m.id)
                                                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                                                    .foregroundColor(MagpieTheme.ink)
                                                    .lineLimit(1)
                                                HStack(spacing: 6) {
                                                    Text(m.providerName)
                                                        .font(.system(size: 11))
                                                        .foregroundColor(MagpieTheme.textMuted)
                                                    if m.free || m.zero {
                                                        MagpieTag(text: "免费", tone: MagpieTheme.ok)
                                                    }
                                                }
                                            }
                                            Spacer()
                                            Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                                                .font(.system(size: 18))
                                                .foregroundColor(added ? MagpieTheme.ok : MagpieTheme.ink)
                                        }
                                        .padding(.vertical, 3)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var ruleEditorSheet: some View {
        let candidateTargets = Array(Set(members + store.groupModels.map(\.id))).sorted()
        return ZStack {
            MagpieTheme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button("取消") { showingRuleEditor = false }
                        .foregroundColor(MagpieTheme.textSecondary)
                    Spacer()
                    Text("新增分流规则")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button("添加") {
                        let target = ruleUse.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !target.isEmpty else { return }
                        let agents = ruleAgentsText
                            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " })
                            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        let tw = ruleUseTime
                            ? RemoteGroupTimeWindow(
                                from: ruleTimeFrom.trimmingCharacters(in: .whitespacesAndNewlines),
                                to: ruleTimeTo.trimmingCharacters(in: .whitespacesAndNewlines),
                                zone: TimeZone.current.identifier
                            )
                            : nil
                        let rule = RemoteGroupRule(
                            use: target,
                            useEffort: rulePause || ruleUseEffort.isEmpty ? nil : ruleUseEffort,
                            tokens: Int(ruleMinTokens),
                            images: ruleImages,
                            effort: ruleEffort.isEmpty ? nil : ruleEffort,
                            agents: agents.isEmpty ? nil : agents,
                            intent: ruleIntent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : ruleIntent.trimmingCharacters(in: .whitespacesAndNewlines),
                            compact: ruleCompact,
                            time: tw,
                            pause: rulePause
                        )
                        rules.append(rule)
                        showingRuleEditor = false
                    }
                    .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(MagpieTheme.surface)
                .overlay(Rectangle().fill(MagpieTheme.hairline).frame(height: 1), alignment: .bottom)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        MinimalSection(title: "目标成员与动作") {
                            MagpieInputField(label: "命中成员 ID", placeholder: "provider/model", text: $ruleUse, monospaced: true)
                            if !candidateTargets.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(candidateTargets.prefix(15), id: \.self) { m in
                                            Button(m) { ruleUse = m }
                                                .font(.system(size: 11.5, design: .monospaced))
                                                .foregroundColor(ruleUse == m ? MagpieTheme.surface : MagpieTheme.ink)
                                                .padding(.horizontal, 9)
                                                .padding(.vertical, 5)
                                                .background(ruleUse == m ? MagpieTheme.ink : MagpieTheme.canvas)
                                                .clipShape(Capsule())
                                                .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }

                            HStack {
                                Text("暂停规则（命中时不分发给该成员）")
                                    .font(.system(size: 13.5))
                                Spacer()
                                MagpieToggle(isOn: $rulePause)
                            }

                            if !rulePause {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("覆盖思考档位 (UseEffort)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(MagpieTheme.textSecondary)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(effortChoices, id: \.self) { lvl in
                                                Button(lvl.isEmpty ? "跟随客户端" : lvl) { ruleUseEffort = lvl }
                                                    .font(.system(size: 12, design: .monospaced))
                                                    .foregroundColor(ruleUseEffort == lvl ? MagpieTheme.surface : MagpieTheme.ink)
                                                    .padding(.horizontal, 9)
                                                    .padding(.vertical, 5)
                                                    .background(ruleUseEffort == lvl ? MagpieTheme.ink : MagpieTheme.canvas)
                                                    .clipShape(Capsule())
                                                    .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        MinimalSection(title: "触发条件（满足全部已设条件时命中）") {
                            MagpieInputField(label: "最小上下文 Tokens", placeholder: "例如：32000", text: $ruleMinTokens, monospaced: true, keyboardType: .numberPad)
                            MagpieInputField(label: "指定客户端 Agent（逗号分隔）", placeholder: "如 codex, claude-code", text: $ruleAgentsText, monospaced: true)

                            if !rulePause {
                                MagpieInputField(label: "语义意图（需配置分类器）", placeholder: "如：快速问答 / 复杂架构重构", text: $ruleIntent)

                                HStack {
                                    Text("请求携带图片")
                                        .font(.system(size: 13.5))
                                    Spacer()
                                    MagpieToggle(isOn: $ruleImages)
                                }

                                HStack {
                                    Text("上下文压缩请求 (/compact)")
                                        .font(.system(size: 13.5))
                                    Spacer()
                                    MagpieToggle(isOn: $ruleCompact)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("要求客户端思考强度不低于")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(MagpieTheme.textSecondary)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(["", "on", "low", "medium", "high", "xhigh", "max"], id: \.self) { lvl in
                                                Button(lvl.isEmpty ? "不限" : lvl) { ruleEffort = lvl }
                                                    .font(.system(size: 12, design: .monospaced))
                                                    .foregroundColor(ruleEffort == lvl ? MagpieTheme.surface : MagpieTheme.ink)
                                                    .padding(.horizontal, 9)
                                                    .padding(.vertical, 5)
                                                    .background(ruleEffort == lvl ? MagpieTheme.ink : MagpieTheme.canvas)
                                                    .clipShape(Capsule())
                                                    .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                            }

                            HStack {
                                Text("限定每日时段")
                                    .font(.system(size: 13.5))
                                Spacer()
                                MagpieToggle(isOn: $ruleUseTime)
                            }
                            if ruleUseTime {
                                HStack(spacing: 10) {
                                    MagpieInputField(label: "开始 (HH:MM)", placeholder: "09:00", text: $ruleTimeFrom, monospaced: true)
                                    MagpieInputField(label: "结束 (HH:MM)", placeholder: "18:00", text: $ruleTimeTo, monospaced: true)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Load & Commit

    private func loadExisting() {
        guard let g = existing else { return }
        name = g.name
        groupID = g.id
        note = g.note ?? ""
        routing = g.routing
        affinity = g.affinity
        if g.sink { sinkMode = 1 } else if g.noSink { sinkMode = 2 } else { sinkMode = 0 }
        let matchedSet = Set(g.matched)
        members = g.members.filter { !matchedSet.contains($0) }
        offMembers = Set(g.offMembers)
        fastMembers = Set(g.fast)
        ultraMembers = Set(g.ultra)
        matchPatterns = g.match
        rules = g.rules
        classifier = g.classifier ?? ""
        autoEffort = (g.effort == "auto")
        firstTokenText = g.firstToken == 0 ? "" : String(g.firstToken)
        patienceText = g.patience == 0 ? "" : String(g.patience)
        if g.context < 0 {
            contextMode = -1
        } else if g.context > 0 {
            contextMode = 1
            contextCustomText = String(g.context)
        } else {
            contextMode = 0
        }
        compactText = g.compact == 0 ? "" : String(g.compact)
        unlists = g.unlists
    }

    private func commitSave() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanID = groupID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleanName.isEmpty && cleanID.isEmpty {
            errorMsg = "请填写路由组名称或 ID"
            return
        }
        if members.isEmpty && matchPatterns.isEmpty {
            errorMsg = "请至少添加一个模型成员或通配符匹配模式"
            return
        }
        errorMsg = nil
        isSaving = true

        var payload: [String: Any] = [
            "id": cleanID,
            "name": cleanName.isEmpty ? cleanID : cleanName,
            "note": note.trimmingCharacters(in: .whitespacesAndNewlines),
            "members": members,
            "routing": routing,
            "affinity": affinity,
            "off": Array(offMembers),
            "fast": Array(fastMembers),
            "ultra": Array(ultraMembers),
            "match": matchPatterns,
            "rules": rules.map { $0.toDictionary() },
            "classifier": classifier.trimmingCharacters(in: .whitespacesAndNewlines),
            "effort": autoEffort ? "auto" : "",
            "firstToken": Int(firstTokenText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0,
            "patience": Int(patienceText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0,
            "compact": Int(compactText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0,
            "unlists": unlists
        ]
        if let existing = existing {
            payload["from"] = existing.id
            payload["disabled"] = existing.disabled
            payload["redact"] = existing.redact
            payload["levels"] = existing.levels
            if let sure = existing.intentSure { payload["intentSure"] = sure }
            if !existing.pick.isNilOrEmpty {
                payload["pick"] = existing.pick!
            }
        }
        if sinkMode == 1 {
            payload["sink"] = true
            payload["noSink"] = false
        } else if sinkMode == 2 {
            payload["sink"] = false
            payload["noSink"] = true
        }
        if contextMode == -1 {
            payload["context"] = -1
        } else if contextMode == 1, let ctx = Int(contextCustomText.trimmingCharacters(in: .whitespacesAndNewlines)), ctx > 0 {
            payload["context"] = ctx
        } else {
            payload["context"] = 0
        }

        Task {
            let ok = await store.saveGroup(payload: payload, toast: existing == nil ? "已创建路由组「\(cleanName)」" : "已更新路由组「\(cleanName)」")
            isSaving = false
            if ok {
                dismiss()
            } else {
                errorMsg = store.lastActionError
            }
        }
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}
