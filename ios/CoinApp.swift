import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct FilmNote: Codable, Identifiable {
    var id = UUID()
    var seconds: Double
    var text: String
}
struct Round: Codable, Identifiable {
    var id = UUID()
    var title: String
    var filename: String
    var notes: [FilmNote] = []
    var review: CoachingReview?
    var roundStart: Double?
    var roundEnd: Double?
    var guardAnalysis: GuardAnalysis?
    var guardLabels: [GuardLabel]?
}
@MainActor final class FilmStore: ObservableObject {
    @Published var rounds: [Round] = []
    @Published var error: String?
    @Published var isImporting = false
    let folder: URL
    init() {
        folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Rounds", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let index = folder.appendingPathComponent("index.json")
            if FileManager.default.fileExists(atPath: index.path) { rounds = try JSONDecoder().decode([Round].self, from: Data(contentsOf: index)) }
        } catch { self.error = error.localizedDescription }
    }
    func save() {
        do { try JSONEncoder().encode(rounds).write(to: folder.appendingPathComponent("index.json"), options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
    func importFilm(_ url: URL) async {
        guard !isImporting else { return }
        isImporting = true
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() }; isImporting = false }
        let name = UUID().uuidString + "." + url.pathExtension
        let destination = folder.appendingPathComponent(name)
        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard duration.seconds.isFinite, duration.seconds > 0, !tracks.isEmpty else {
                throw NSError(domain: "Coin", code: 1, userInfo: [NSLocalizedDescriptionKey: "This file does not contain a playable video."])
            }
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.copyItem(at: url, to: destination)
            }.value
            rounds.insert(Round(title: url.deletingPathExtension().lastPathComponent, filename: name), at: 0)
            save()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            self.error = error.localizedDescription
        }
    }
    func addNote(_ id: UUID, seconds: Double, text: String) {
        guard let index = rounds.firstIndex(where: {$0.id == id}), seconds.isFinite else { return }
        rounds[index].notes.append(FilmNote(seconds: max(0, seconds), text: text))
        save()
    }
    func saveReview(_ id: UUID, review: CoachingReview) {
        guard let index = rounds.firstIndex(where: {$0.id == id}) else { return }
        rounds[index].review = review; save()
    }
    func delete(_ offsets: IndexSet) {
        let ids = offsets.map { rounds[$0].id }
        for id in ids {
            guard let index = rounds.firstIndex(where: { $0.id == id }) else { continue }
            do {
                let path = folder.appendingPathComponent(rounds[index].filename)
                if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
                let requests = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ReviewRequests").appendingPathComponent(id.uuidString)
                if FileManager.default.fileExists(atPath: requests.path) { try FileManager.default.removeItem(at: requests) }
                rounds.remove(at: index)
                save()
            } catch { self.error = error.localizedDescription; return }
        }
    }
}
/// Where the phone finds the private coaching server. HTTPS anywhere; plain HTTP only on this phone (127.0.0.1),
/// on a private home network (192.168.x, 10.x, 172.16-31.x), or over Tailscale (100.x).
enum CoinServer {
    static func allowed(_ url: URL) -> Bool {
        if url.scheme == "https" { return true }
        guard url.scheme == "http", let host = url.host else { return false }
        if host == "127.0.0.1" || host.hasPrefix("100.") || host.hasPrefix("192.168.") || host.hasPrefix("10.") { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        return parts.count == 4 && parts[0] == 172 && (16...31).contains(parts[1])
    }
    /// Seeds the server address and token from a bundled LocalConfig.json (git-ignored), so the phone needs no setup.
    static func seedFromBundle() {
        guard let url = Bundle.main.url(forResource: "LocalConfig", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
        if let service = config["service_url"], UserDefaults.standard.string(forKey: "seededServiceURL") != service {
            UserDefaults.standard.set(service, forKey: "serviceURL")
            UserDefaults.standard.set(service, forKey: "seededServiceURL")
        }
        if ServiceCredential.load() == nil, let token = config["service_token"] { ServiceCredential.save(token) }
    }
}

@main struct CoinApp: App {
    @StateObject private var store = FilmStore()
    @StateObject private var training: TrainingStore = {
        #if DEBUG
        if let token = ProcessInfo.processInfo.environment["COIN_TRAINING_DIRECTORY"],
           !token.isEmpty, token.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            return TrainingStore(directory: root.appendingPathComponent("UITests").appendingPathComponent(token))
        }
        #endif
        return TrainingStore()
    }()
    init() { CoinServer.seedFromBundle() }
    var body: some Scene { WindowGroup { TrainingRootView().environmentObject(store).environmentObject(training) } }
}
struct HomeView: View {
    @EnvironmentObject var store: FilmStore
    @AppStorage("language") private var language = "fr"
    @State private var importing = false
    @State private var recording = false
    @State private var settings = false
    @State private var editMode = EditMode.inactive
    var french: Bool { language == "fr" }
    private func copy(_ key: String) -> String { TrainingCopy.text(key, language) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(copy("film_headline"))
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .foregroundStyle(Noir.ink).listRowBackground(Color.clear)
                    Text(copy("film_intro"))
                        .font(.subheadline).foregroundStyle(Noir.muted).listRowBackground(Color.clear)
                    Button { recording = true } label: { Label(copy("film_record"), systemImage: "video.fill").font(.subheadline.weight(.semibold)) }.disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    Button { importing = true } label: { Label(copy("film_import"), systemImage: "plus.circle.fill").font(.subheadline) }
                }
                Section(copy("film_my_rounds")) {
                    if store.rounds.isEmpty {
                        VStack(alignment: .leading, spacing: 12) { Image(systemName: "figure.boxing").font(.largeTitle); Text(copy("film_empty_headline")).font(.headline); Text(copy("film_empty_detail")).foregroundStyle(.secondary) }.padding(.vertical, 20)
                    }
                    ForEach(store.rounds) { round in
                        NavigationLink { ReviewView(roundID: round.id, french: french) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(round.title).font(.headline)
                                Text("\(round.notes.count) " + (round.notes.count == 1 ? "note" : "notes")).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                        }
                    }.onDelete(perform: store.delete)
                }
            }
            .id(language)
            .listStyle(.plain)
            .listRowBackground(Noir.black)
            .scrollContentBackground(.hidden).background(Noir.black)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 76) }
            .overlay { if store.isImporting { ProgressView(copy("film_importing")).padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .disabled(store.isImporting)
            .navigationTitle("Coin").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel(copy("film_settings")) }; ToolbarItem(placement: .navigationBarTrailing) { Button(copy(editMode.isEditing ? "film_done" : "film_edit")) { editMode = editMode.isEditing ? .inactive : .active } } }
            .environment(\.editMode, $editMode)
            .environment(\.locale, Locale(identifier: language))
            .sheet(isPresented: $settings) { ConnectionSettings(french: french) }
            .sheet(isPresented: $recording) { CameraRecorder { url in if let url { Task { await store.importFilm(url) } }; recording = false }.ignoresSafeArea() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.movie]) { result in
                switch result { case .success(let url): Task { await store.importFilm(url) }; case .failure(let error): store.error = error.localizedDescription }
            }
            .alert(copy("film_error_title"), isPresented: Binding(get: {store.error != nil}, set: {if !$0 {store.error = nil}})) { Button("OK") {store.error = nil} } message: {Text(copy("film_error_detail"))}
        }
    }
}
struct ReviewView: View {
    @EnvironmentObject var store: FilmStore
    let roundID: UUID
    let french: Bool
    @State private var player: AVPlayer?
    @State private var text = ""
    @StateObject private var coach = CoachingClient()
    var round: Round? {store.rounds.first(where: {$0.id == roundID})}
    private var language: String { french ? "fr" : "en" }
    private func copy(_ key: String) -> String { TrainingCopy.text(key, language) }
    var body: some View {
        ScrollView { VStack(spacing: 16) {
            if let round {
                VideoPlayer(player: player).frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 16))
                HStack {
                    TextField(copy("film_note_placeholder"), text: $text).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                    Button { 
                        let seconds = player?.currentTime().seconds ?? 0
                        store.addNote(roundID, seconds: seconds, text: text.trimmingCharacters(in: .whitespacesAndNewlines)); text = ""
                    } label: {Image(systemName: "bookmark.fill")}.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(copy("film_mark_moment"))
                }
                Text(copy("film_notes_help")).font(.caption).foregroundStyle(.secondary)
                if let review = round.review {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(copy("film_next_focus")).font(.headline)
                        Text(CoachingCopy.drill(id: review.drill_id, original: review.drill, language: language) ?? copy("film_legacy_plan")).fixedSize(horizontal: false, vertical: true)
                        Text(copy("film_limitation")).font(.caption).foregroundStyle(.secondary)
                    }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                GuardReviewSection(round: round, french: french, player: player)
                Button {
                    Task { if let result = await coach.review(round: round, language: language) { store.saveReview(roundID, review: result) } }
                } label: {
                    if coach.working { ProgressView() } else { Label(copy("film_plan_next"), systemImage: "sparkles") }
                }.disabled(round.notes.isEmpty || coach.working)
                Text(copy("film_send_note")).font(.caption2).foregroundStyle(.secondary)
                if let error = coach.error { Text(error).font(.caption).foregroundStyle(.red) }
                LazyVStack(alignment: .leading, spacing: 16) { ForEach(round.notes) { note in
                    Button {player?.seek(to: CMTime(seconds: note.seconds, preferredTimescale: 600))} label: {
                        HStack(alignment: .top) {Text(String(format: "%02d:%02d", Int(note.seconds)/60, Int(note.seconds)%60)).monospacedDigit(); Text(note.text)}
                    }
                Divider()
                } }
            }
        }.padding() }.navigationTitle(round?.title ?? copy("film_round_title")).navigationBarTitleDisplayMode(.inline)
        .onAppear { if let round {player = AVPlayer(url: store.folder.appendingPathComponent(round.filename))} }
        .onDisappear {player?.pause(); player = nil}
    }
}

struct CameraRecorder: UIViewControllerRepresentable {
    let finished: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.cameraCaptureMode = .video
        picker.videoQuality = .typeMedium
        picker.videoMaximumDuration = 180
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let finished: (URL?) -> Void
        init(finished: @escaping (URL?) -> Void) { self.finished = finished }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { finished(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { finished(info[.mediaURL] as? URL) }
    }
}

struct ConnectionSettings: View {
    let french: Bool
    @Environment(\.dismiss) private var dismiss
    @AppStorage("serviceURL") private var savedURL = ""
    @AppStorage("poseTelemetryEnabled") private var poseTelemetryEnabled = false
    @AppStorage("stance") private var stance = "orthodox"
    @State private var address = ""
    @State private var token = ""
    @State private var error: String?
    private func copy(_ key: String) -> String { TrainingCopy.text(key, french ? "fr" : "en") }
    var body: some View {
        NavigationStack {
            Form {
                Section(copy("film_stance")) {
                    Picker(copy("film_stance"), selection: $stance) {
                        Text(copy("film_orthodox")).tag("orthodox")
                        Text(copy("film_southpaw")).tag("southpaw")
                    }
                    .pickerStyle(.segmented)
                }
                Section(copy("connection_private_server")) {
                    TextField("https://…", text: $address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(copy("connection_access_key"), text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text(copy("connection_key_note")).font(.caption).foregroundStyle(.secondary)
                }
                Section(copy("connection_pose_tracking")) {
                    Toggle(copy("connection_pose_share"), isOn: $poseTelemetryEnabled)
                    Text(copy("connection_pose_note"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button(copy("save")) {
                    let value = address.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    guard let url = URL(string: value), url.host != nil, CoinServer.allowed(url) else {
                        error = copy("connection_https_error"); return
                    }
                    if !token.isEmpty && !ServiceCredential.save(token) { error = copy("connection_key_error"); return }
                    savedURL = value; dismiss()
                }
            }.navigationTitle(copy("connection_title"))
            .toolbar { Button(copy("connection_close")) { dismiss() } }
            .onAppear { address = savedURL }
        }
    }
}
