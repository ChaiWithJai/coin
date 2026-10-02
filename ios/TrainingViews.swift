import SwiftUI

enum Noir {
    static let black = Color(red: 0.035, green: 0.038, blue: 0.045)
    static let panel = Color(red: 0.085, green: 0.09, blue: 0.10)
    static let ink = Color(red: 0.95, green: 0.92, blue: 0.85)
    static let muted = Color(red: 0.58, green: 0.58, blue: 0.56)
    static let gold = Color(red: 0.86, green: 0.67, blue: 0.39)
    static let red = Color(red: 0.72, green: 0.19, blue: 0.15)
}

private enum SessionCopy {
    static func milestone(_ kind: CampMilestoneKind, language: String) -> String {
        switch kind {
        case .weighIn: return TrainingCopy.text("milestone_weigh_in", language)
        case .readinessCheck: return TrainingCopy.text("milestone_readiness_check", language)
        case .fightDate: return TrainingCopy.text("milestone_fight_date", language)
        case .weightClassCampaign: return TrainingCopy.text("milestone_weight_class", language)
        }
    }
}

struct TrainingRootView: View {
    @EnvironmentObject var films: FilmStore
    @EnvironmentObject var training: TrainingStore
    @AppStorage("language") private var language = "fr"
    var body: some View {
        TabView {
            TrainingHomeView()
                .tabItem { Label(TrainingCopy.text("tab_sessions", language), systemImage: "timer") }
            HomeView()
                .tabItem { Label(TrainingCopy.text("tab_videos", language), systemImage: "play.rectangle") }
            TrainingCalendarView()
                .tabItem { Label(TrainingCopy.text("tab_calendar", language), systemImage: "calendar") }
        }
        .environmentObject(films)
        .environmentObject(training)
        .environment(\.locale, Locale(identifier: language))
        .tint(Noir.gold)
        .preferredColorScheme(.dark)
    }
}

struct TrainingHomeView: View {
    @EnvironmentObject var training: TrainingStore
    @AppStorage("language") private var language = "fr"
    @State private var path: [UUID] = []
    @State private var selectedMinutes = 30
    @StateObject private var voice = WorkoutSpeechController()
    private var selectedTemplate: TrainingTemplate { SessionTemplates.all.first { $0.durationMinutes == selectedMinutes } ?? SessionTemplates.all[0] }
    private var activeSession: TrainingSession? { training.data.sessions.first { $0.state == .active } }
    private var shownDrillID: String { activeSession?.blocks.first(where: { $0.kind == .boxing })?.drillID ?? "probe-combine-angle-v1" }
    private var shownRoundCount: Int { activeSession?.blocks.filter { $0.kind == .boxing }.count ?? selectedTemplate.boxingRounds }
    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Image("CornerMark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .accessibilityHidden(true)
                        Text("COIN").font(.system(size: 16, weight: .black, design: .serif)).tracking(5)
                        Spacer()
                        HStack(spacing: 14) {
                            ForEach(["fr", "en"], id: \.self) { option in
                                Button(option.uppercased()) { language = option; voice.stop() }
                                    .foregroundStyle(language == option ? Noir.gold : Noir.muted)
                                    .accessibilityLabel(option == "fr" ? "Français" : "English")
                            }
                        }.font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1)
                    }
                    .padding(.top, 10)
                    Rectangle().fill(Noir.gold.opacity(0.3)).frame(height: 1).padding(.top, 12)
                    Spacer(minLength: 18)
                    Text(TrainingCopy.text("home_eyebrow", language))
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(3).foregroundStyle(Noir.gold)
                    Text(TrainingCopy.text("home_cinema_title", language))
                        .font(.system(size: 29, weight: .regular, design: .serif))
                        .tracking(-1).foregroundStyle(Noir.ink)
                        .minimumScaleFactor(0.85).padding(.top, 9)
                    Text(TrainingCopy.text("home_cinema_subtitle", language))
                        .font(.system(size: 14)).foregroundStyle(Noir.muted)
                        .lineSpacing(2).padding(.top, 8)
                    Spacer(minLength: 18)
                    if activeSession == nil {
                        Text(TrainingCopy.text("choose_duration", language).uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(Noir.muted)
                        HStack(spacing: 8) {
                            ForEach(SessionTemplates.all) { template in
                                Button { selectedMinutes = template.durationMinutes } label: {
                                    Text("\(template.durationMinutes)").font(.system(size: 14, weight: .semibold, design: .monospaced))
                                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                                        .background(selectedMinutes == template.durationMinutes ? Noir.gold : Noir.panel)
                                        .foregroundStyle(selectedMinutes == template.durationMinutes ? Noir.black : Noir.ink)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }.accessibilityLabel("\(template.durationMinutes) min")
                            }
                        }.padding(.top, 8)
                    }
                    Button { path.append(training.resumeOrStart(selectedTemplate)) } label: {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text(activeSession.map { TrainingCopy.format("resume_session", language, $0.plannedMinutes) }
                                 ?? TrainingCopy.text("home_enter", language)).tracking(1)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 13)
                        .background(Noir.red, in: RoundedRectangle(cornerRadius: 8))
                    }.padding(.top, 12)
                    Text(TrainingCopy.text(activeSession == nil ? "home_tonight" : "home_active_session", language))
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2.5).foregroundStyle(Noir.gold)
                        .padding(.top, 22)
                    HStack(alignment: .firstTextBaseline) {
                        Text(DrillLibrary.name(shownDrillID, language: language))
                            .font(.system(size: 20, weight: .medium, design: .serif)).foregroundStyle(Noir.ink)
                        Spacer()
                        Text(TrainingCopy.format("round_count", language, shownRoundCount))
                            .font(.caption.monospaced()).foregroundStyle(Noir.muted)
                    }.padding(.top, 6)
                    if shownDrillID == "probe-combine-angle-v1" {
                        Text(TrainingCopy.text("home_drill_flow", language))
                            .font(.caption.monospaced()).foregroundStyle(Noir.muted).padding(.top, 4)
                    }
                    Button {
                        voice.speak(TrainingCopy.text("home_opening_speech", language),
                                    locale: TrainingCopy.text("speech_locale", language),
                                    cueKey: "opening", language: language)
                    } label: {
                        Label(TrainingCopy.text("home_listen", language), systemImage: "waveform")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1.5).foregroundStyle(Noir.gold)
                    }.padding(.top, 12)
                    Text(TrainingCopy.text("home_placement", language))
                        .font(.caption).foregroundStyle(Noir.muted).padding(.top, 12)
                        .fixedSize(horizontal: false, vertical: true)
                    let completed = training.data.sessions.filter { $0.state == .completed || $0.state == .interrupted }
                    if !completed.isEmpty {
                        Text(TrainingCopy.text("training_log", language).uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(Noir.muted)
                            .padding(.top, 40)
                        ForEach(completed.prefix(1)) { session in
                            NavigationLink { TrainingSessionView(sessionID: session.id) } label: {
                                HStack {
                                    Text((session.startedAt ?? session.createdAt).formatted(Date.FormatStyle().day().month(.abbreviated).year().locale(Locale(identifier: language))))
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                }.font(.caption).foregroundStyle(Noir.ink).padding(.vertical, 15)
                            }
                            Rectangle().fill(Noir.gold.opacity(0.2)).frame(height: 1)
                        }
                    }
                }.padding(.horizontal, 24).padding(.bottom, 130).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Noir.black.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { sessionID in
                LiveWorkoutView(sessionID: sessionID)
            }
        }
    }
}

struct TrainingSessionView: View {
    @EnvironmentObject var training: TrainingStore
    @EnvironmentObject var films: FilmStore
    @AppStorage("language") private var language = "fr"
    let sessionID: UUID
    @State private var reflection = ""
    @State private var showingFinish = false
    @State private var showUntouched = false
    @State private var showVideoLinking = false
    var session: TrainingSession? { training.data.sessions.first(where: { $0.id == sessionID }) }
    var body: some View {
        List {
            if let session {
                Section {
                    Text(TrainingCopy.format("recap_clock_summary", language, session.elapsedClock, session.plannedMinutes, session.timedRoundCount))
                        .font(.headline)
                    Text(TrainingCopy.text("session_evidence_note", language))
                        .font(.caption).foregroundStyle(.secondary)
                    if let latency = session.poseLatencyP95Ms {
                        Text(TrainingCopy.format("pose_processing_p95", language, Int(latency.rounded())))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    let uploads = session.poseUploadEvidence
                    if uploads.selected > 0 {
                        Text(TrainingCopy.format("pose_upload_receipts", language, uploads.acknowledged, uploads.selected))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if session.state == .interrupted {
                        Text(TrainingCopy.text("interrupted_note", language)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                let observed = session.blocks.filter { block in
                    session.completedBlockIDs.contains(block.id)
                        || (session.segmentLogs ?? []).contains { $0.blockID == block.id }
                        || (session.poseWindows ?? []).contains { $0.blockID == block.id }
                        || (session.cueRequests ?? []).contains { $0.blockID == block.id }
                }
                Section(TrainingCopy.text("session_observed", language)) {
                    if observed.isEmpty {
                        Text(TrainingCopy.text("session_no_observed", language))
                            .foregroundStyle(Noir.muted)
                    }
                    ForEach(observed) { block in blockRow(block, session: session) }
                }
                let untouched = session.blocks.filter { block in !observed.contains { $0.id == block.id } }
                if !untouched.isEmpty {
                    Section {
                        DisclosureGroup(TrainingCopy.text("session_remaining_plan", language), isExpanded: $showUntouched) {
                            ForEach(untouched) { block in blockRow(block, session: session) }
                        }
                    }
                }
                Section(TrainingCopy.text("session_videos", language)) {
                    let linked = films.rounds.filter { session.linkedRoundIDs.contains($0.id) }
                    if linked.isEmpty {
                        Text(TrainingCopy.text("session_no_linked_video", language))
                            .font(.caption).foregroundStyle(Noir.muted)
                    }
                    ForEach(linked) { round in Text(round.title).foregroundStyle(Noir.ink) }
                    let unlinked = films.rounds.filter { !session.linkedRoundIDs.contains($0.id) }
                    if !unlinked.isEmpty {
                        DisclosureGroup(TrainingCopy.text("session_link_video", language), isExpanded: $showVideoLinking) {
                            ForEach(unlinked) { round in
                                Button(round.title) { training.linkRound(sessionID: sessionID, roundID: round.id) }
                            }
                        }
                    }
                }
                Section(TrainingCopy.text("reflection", language)) {
                    Text(TrainingCopy.text("review_evidence_note", language))
                        .font(.caption).foregroundStyle(.secondary)
                    if session.state == .active {
                        Button(TrainingCopy.text("finish_save_log", language)) { showingFinish = true }
                    } else {
                        Text(session.reflection.isEmpty ? TrainingCopy.text("no_reflection", language) : session.reflection)
                        if let ended = session.endedAt {
                            Text(ended.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Noir.black.ignoresSafeArea())
        .navigationTitle(TrainingCopy.text("session_title", language))
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if session?.state == .active {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(TrainingCopy.text("finish", language)) { showingFinish = true }
                }
            }
        }
        .sheet(isPresented: $showingFinish) {
            NavigationStack {
                Form {
                    Section(TrainingCopy.text("worked_on", language)) {
                        TextField(TrainingCopy.text("reflection_placeholder", language), text: $reflection, axis: .vertical)
                    }
                    Section {
                        Text(TrainingCopy.text("finish_note", language))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle(TrainingCopy.text("finish_session", language))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(TrainingCopy.text("cancel", language)) { showingFinish = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(TrainingCopy.text("save", language)) {
                            training.finish(sessionID, reflection: reflection)
                            showingFinish = false
                        }
                    }
                }
            }
        }
    }

    private func blockRow(_ block: SessionBlock, session: TrainingSession) -> some View {
        let segments = (session.segmentLogs ?? []).filter { $0.blockID == block.id }
        let seconds = segments.reduce(0) { $0 + $1.elapsedSeconds }
        let skipped = segments.filter { $0.exitReason == "skipped" }.count
        let pose = session.poseEvidence(for: block.id)
        let cueCount = (session.cueRequests ?? []).filter { $0.blockID == block.id }.count
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: session.completedBlockIDs.contains(block.id) ? "checkmark.circle.fill" : "circle.dotted")
                .font(.system(size: 17)).foregroundStyle(session.completedBlockIDs.contains(block.id) ? Noir.gold : Noir.muted)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(block.kind == .boxing
                     ? TrainingCopy.format("round_drill", language, block.roundNumber ?? 0,
                                           DrillLibrary.name(block.drillID ?? "", language: language))
                     : TrainingCopy.text(block.kind.rawValue, language))
                    .font(.system(size: 16, weight: .medium, design: .serif))
                    .foregroundStyle(Noir.ink)
                if !segments.isEmpty {
                    Text(skipped == 0
                         ? TrainingCopy.format("segment_time_only", language, seconds / 60, seconds % 60)
                         : TrainingCopy.format("segment_timing", language, seconds / 60, seconds % 60, skipped))
                        .font(.caption).foregroundStyle(Noir.muted)
                } else {
                    Text("\(block.minutes) min").font(.caption).foregroundStyle(Noir.muted)
                }
                if pose.sampled > 0 {
                    Text(TrainingCopy.format("pose_samples", language, pose.visible, pose.sampled))
                        .font(.caption2).foregroundStyle(Noir.muted)
                }
                if cueCount > 0 {
                    Text(cueCount == 1 ? TrainingCopy.text("cue_request_one", language)
                         : TrainingCopy.format("cue_requests", language, cueCount))
                        .font(.caption2).foregroundStyle(Noir.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .listRowBackground(Noir.black)
    }
}

struct WorkoutRecapView: View {
    @EnvironmentObject var training: TrainingStore
    @EnvironmentObject var films: FilmStore
    @AppStorage("language") private var language = "fr"
    let sessionID: UUID
    let onDone: () -> Void
    @State private var reflection = ""
    private var session: TrainingSession? { training.data.sessions.first { $0.id == sessionID } }
    private var fullyTimed: Bool {
        guard let session, let seconds = session.timerElapsedSeconds else { return false }
        return seconds >= session.plannedMinutes * 60
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(TrainingCopy.text("recap_eyebrow", language))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(3).foregroundStyle(Noir.gold)
                    Text(TrainingCopy.text(fullyTimed ? "recap_title" : "recap_early_title", language))
                        .font(.system(size: 38, weight: .regular, design: .serif)).foregroundStyle(Noir.ink)
                    if let session {
                        Text(TrainingCopy.format("recap_clock_summary", language,
                                                 session.elapsedClock, session.plannedMinutes, session.timedRoundCount))
                            .font(.title3).foregroundStyle(Noir.ink)
                        Rectangle().fill(Noir.gold.opacity(0.4)).frame(height: 1)
                        let reachedRounds = session.blocks.filter { block in
                            block.kind == .boxing && (session.segmentLogs ?? []).contains { $0.blockID == block.id && !$0.isRest && $0.elapsedSeconds > 0 }
                        }
                        if !reachedRounds.isEmpty {
                            Text(TrainingCopy.text("recap_drills", language))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(2).foregroundStyle(Noir.gold)
                                .padding(.top, 8)
                            ForEach(reachedRounds) { block in
                                if let record = session.segmentLogs?.last(where: { $0.blockID == block.id && !$0.isRest }) {
                                    HStack(alignment: .top, spacing: 12) {
                                        Text(String(format: "%02d", block.roundNumber ?? 0))
                                            .font(.system(size: 25, weight: .light, design: .monospaced))
                                            .foregroundStyle(Noir.gold)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(DrillLibrary.name(block.drillID ?? "", language: language))
                                                .font(.system(size: 17, weight: .medium, design: .serif))
                                                .foregroundStyle(Noir.ink)
                                            let elapsed = String(format: "%02d:%02d", record.elapsedSeconds / 60, record.elapsedSeconds % 60)
                                            let statusKey = record.exitReason == "timer_elapsed" ? "recap_round_elapsed" :
                                                (record.exitReason == "skipped" ? "recap_round_skipped" : "recap_round_early")
                                            Text(TrainingCopy.format(statusKey, language, elapsed))
                                                .font(.caption.monospaced()).foregroundStyle(Noir.muted)
                                        }
                                        Spacer()
                                    }
                                    .padding(14)
                                    .background(Noir.panel, in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                        HStack(alignment: .top, spacing: 18) {
                            recapStat("recap_camera", value: session.poseWindows?.count ?? 0)
                            recapStat("recap_cues", value: session.cueRequests?.count ?? 0)
                        }
                        Text(TrainingCopy.text("recap_evidence", language))
                            .font(.caption).foregroundStyle(Noir.muted)
                        Text(TrainingCopy.text("recap_reflection", language))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .tracking(2).foregroundStyle(Noir.gold).padding(.top, 8)
                        TextField(TrainingCopy.text("recap_placeholder", language), text: $reflection, axis: .vertical)
                            .lineLimit(3...5).padding(14)
                            .background(Noir.panel, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(Noir.ink)
                        NavigationLink { TrainingSessionView(sessionID: sessionID) } label: {
                            HStack {
                                Text(TrainingCopy.text("recap_view_log", language))
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }.font(.headline).foregroundStyle(Noir.ink)
                                .padding(18).background(Noir.panel, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
            .background(Noir.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(TrainingCopy.text("film_done", language)) {
                        training.updateReflection(sessionID, text: reflection)
                        onDone()
                    }
                        .foregroundStyle(Noir.gold)
                }
            }
            .onAppear { reflection = session?.reflection ?? "" }
            .onDisappear { training.updateReflection(sessionID, text: reflection) }
        }
        .environmentObject(films)
        .preferredColorScheme(.dark)
    }

    private func recapStat(_ key: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("\(value)").font(.system(size: 32, weight: .light, design: .monospaced)).foregroundStyle(Noir.ink)
            Text(TrainingCopy.text(key, language))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Noir.muted)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TrainingCalendarView: View {
    @EnvironmentObject var training: TrainingStore
    @AppStorage("language") private var language = "fr"
    @State private var selected = Date()
    @State private var kind = CampMilestoneKind.fightDate
    @State private var date = Date()
    @State private var title = ""
    @State private var weightClass = ""
    @State private var weight = ""
    @State private var weightUnit = "kg"
    @State private var showPlanning = false
    private var recentDays: [Date] {
        var seen = Set<Date>()
        return training.data.sessions.compactMap { session -> Date? in
            let day = Calendar.current.startOfDay(for: session.startedAt ?? session.createdAt)
            return seen.insert(day).inserted ? day : nil
        }.sorted(by: >).prefix(6).map { $0 }
    }
    var body: some View {
        NavigationStack {
            List {
                Text(TrainingCopy.text("tab_calendar", language))
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .foregroundStyle(Noir.ink)
                    .listRowBackground(Color.clear)
                Section(TrainingCopy.text("training_days", language)) {
                    DatePicker(TrainingCopy.text("day", language), selection: $selected, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    if !recentDays.isEmpty {
                        Text(TrainingCopy.text("recent_training_days", language))
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(recentDays, id: \.self) { day in
                                    Button(day.formatted(Date.FormatStyle().month(.abbreviated).day().locale(Locale(identifier: language)))) { selected = day }
                                        .buttonStyle(.bordered)
                                        .tint(Calendar.current.isDate(day, inSameDayAs: selected) ? Noir.gold : Noir.muted)
                                }
                            }
                        }
                    }
                    let sessions = training.sessions(on: selected).sorted {
                        let left = $0.timerElapsedSeconds ?? 0
                        let right = $1.timerElapsedSeconds ?? 0
                        return left == right ? ($0.startedAt ?? $0.createdAt) > ($1.startedAt ?? $1.createdAt) : left > right
                    }
                    if sessions.isEmpty {
                        Text(TrainingCopy.text("no_session_day", language))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sessions.prefix(1)) { session in
                        NavigationLink { TrainingSessionView(sessionID: session.id) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(TrainingCopy.format("calendar_elapsed", language, session.elapsedClock))
                                    .font(.headline).foregroundStyle(Noir.ink)
                                Text(TrainingCopy.format("calendar_session_line", language, session.timedRoundCount,
                                                         TrainingCopy.text(session.state == .completed ? "completed" : (session.state == .interrupted ? "interrupted" : "ongoing"), language)))
                                    .font(.caption).foregroundStyle(Noir.muted)
                            }
                        }
                    }
                    if sessions.count > 1 {
                        NavigationLink {
                            TrainingDayLogView(day: selected)
                        } label: {
                            Text(TrainingCopy.format("all_sessions_day", language, sessions.count))
                        }
                    }
                }
                Button {
                    showPlanning.toggle()
                } label: {
                    HStack {
                        Text(TrainingCopy.text("calendar_planning", language))
                        Spacer()
                        Image(systemName: showPlanning ? "chevron.up" : "chevron.down")
                    }
                    .foregroundStyle(Noir.gold)
                }
                if showPlanning {
                Section(TrainingCopy.text("camp_dates", language)) {
                    ForEach(training.data.milestones) { milestone in
                        VStack(alignment: .leading) {
                            Text(milestone.title).font(.headline)
                            Text("\(SessionCopy.milestone(milestone.kind, language: language)) · \(milestone.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                            if let weightClass = milestone.weightClass { Text(weightClass).font(.caption) }
                        }
                    }
                }
                Section(TrainingCopy.text("weight_log", language)) {
                    if let latest = training.data.weightRecords?.first {
                        Text(TrainingCopy.format("latest_weight", language, latest.amount.formatted(), latest.unit, latest.recordedAt.formatted(date: .abbreviated, time: .omitted)))
                    }
                    HStack {
                        TextField(TrainingCopy.text("measured_weight", language), text: $weight).keyboardType(.decimalPad)
                        Picker(TrainingCopy.text("unit", language), selection: $weightUnit) {
                            Text("kg").tag("kg"); Text("lb").tag("lb")
                        }.pickerStyle(.segmented).frame(width: 120)
                    }
                    Button(TrainingCopy.text("log_weight", language)) {
                        let value = Double(weight.replacingOccurrences(of: ",", with: ".")) ?? 0
                        training.addWeight(value, unit: weightUnit)
                        weight = ""
                    }.disabled(Double(weight.replacingOccurrences(of: ",", with: ".")) == nil)
                    Text(TrainingCopy.text("weight_note", language))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(TrainingCopy.text("add_camp_date", language)) {
                    Picker(TrainingCopy.text("type", language), selection: $kind) {
                        ForEach(CampMilestoneKind.allCases, id: \.self) { value in
                            Text(SessionCopy.milestone(value, language: language)).tag(value)
                        }
                    }
                    DatePicker(TrainingCopy.text("date", language), selection: $date, displayedComponents: .date)
                    TextField(TrainingCopy.text("camp_date_name", language), text: $title)
                    TextField(TrainingCopy.text("weight_class_optional", language), text: $weightClass)
                    Button(TrainingCopy.text("save_date", language)) {
                        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        training.addMilestone(kind: kind, date: date, title: name, weightClass: weightClass)
                        title = ""; weightClass = ""
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section {
                    Text(TrainingCopy.text("pre_sparring_note", language))
                        .font(.caption).foregroundStyle(.secondary)
                }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Noir.black.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { Noir.black.frame(height: 128) }
        }
    }
}

struct TrainingDayLogView: View {
    @EnvironmentObject var training: TrainingStore
    @AppStorage("language") private var language = "fr"
    let day: Date
    private var sessions: [TrainingSession] {
        training.sessions(on: day).sorted {
            let left = $0.timerElapsedSeconds ?? 0
            let right = $1.timerElapsedSeconds ?? 0
            return left == right ? ($0.startedAt ?? $0.createdAt) > ($1.startedAt ?? $1.createdAt) : left > right
        }
    }
    var body: some View {
        List {
            ForEach(sessions) { session in
                NavigationLink { TrainingSessionView(sessionID: session.id) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(TrainingCopy.format("calendar_elapsed", language, session.elapsedClock))
                            .font(.headline).foregroundStyle(Noir.ink)
                        Text(TrainingCopy.format("calendar_session_line", language, session.timedRoundCount,
                                                 TrainingCopy.text(session.state == .completed ? "completed" : (session.state == .interrupted ? "interrupted" : "ongoing"), language)))
                            .font(.caption).foregroundStyle(Noir.muted)
                    }
                }
            }
        }
        .navigationTitle(day.formatted(Date.FormatStyle().day().month(.wide).year().locale(Locale(identifier: language))))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}
