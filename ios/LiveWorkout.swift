import AVFoundation
import MediaPipeTasksVision
import SwiftUI
import UIKit

struct LivePoseSample {
    let sampledAt: Date
    let landmarkCount: Int
    let visibleLandmarkCount: Int
    let framingReady: Bool
    let captureToPoseMs: Double?
    let wristTravelBodyWidths: Double?
    let squatKneeAngle: Double?
    var lungeKneeAngle: Double? = nil
    let lowerBodyVisible: Bool
}

struct PoseJoint {
    let x: Double
    let y: Double
    let visibility: Double
    var inFrame: Bool { (0...1).contains(x) && (0...1).contains(y) && visibility >= 0.55 }
}

enum PoseFraming {
    static let requiredJoints = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]
    static func fullBodyInFrame(_ joints: [PoseJoint]) -> Bool {
        guard joints.count > 28 else { return false }
        return requiredJoints.allSatisfy { joints[$0].inFrame }
    }
}

enum PoseMotion {
    static func squatKneeAngle(_ joints: [PoseJoint], aspect: Double = 1) -> Double? {
        guard joints.count > 28, aspect.isFinite, aspect > 0 else { return nil }
        func angle(_ hip: Int, _ knee: Int, _ ankle: Int) -> Double? {
            guard [hip, knee, ankle].allSatisfy({ joints[$0].inFrame }) else { return nil }
            let a = ((joints[hip].x - joints[knee].x) * aspect, joints[hip].y - joints[knee].y)
            let b = ((joints[ankle].x - joints[knee].x) * aspect, joints[ankle].y - joints[knee].y)
            let lengths = hypot(a.0, a.1) * hypot(b.0, b.1)
            guard lengths > 0.002 else { return nil }
            return acos(max(-1, min(1, (a.0 * b.0 + a.1 * b.1) / lengths))) * 180 / .pi
        }
        // Side-on framing often hides the far leg: use whichever leg is visible, average when both agree.
        switch (angle(23, 25, 27), angle(24, 26, 28)) {
        case let (left?, right?): return abs(left - right) < 28 ? (left + right) / 2 : min(left, right)
        case let (left?, nil): return left
        case let (nil, right?): return right
        default: return nil
        }
    }
    /// Lunge depth: the most bent visible knee (the front leg), so one leg in view is enough.
    static func lungeKneeAngle(_ joints: [PoseJoint], aspect: Double = 1) -> Double? {
        guard joints.count > 28, aspect.isFinite, aspect > 0 else { return nil }
        func angle(_ hip: Int, _ knee: Int, _ ankle: Int) -> Double? {
            guard [hip, knee, ankle].allSatisfy({ joints[$0].inFrame }) else { return nil }
            let a = ((joints[hip].x - joints[knee].x) * aspect, joints[hip].y - joints[knee].y)
            let b = ((joints[ankle].x - joints[knee].x) * aspect, joints[ankle].y - joints[knee].y)
            let lengths = hypot(a.0, a.1) * hypot(b.0, b.1)
            guard lengths > 0.002 else { return nil }
            return acos(max(-1, min(1, (a.0 * b.0 + a.1 * b.1) / lengths))) * 180 / .pi
        }
        return [angle(23, 25, 27), angle(24, 26, 28)].compactMap { $0 }.min()
    }
    static func wristTravelBodyWidths(previous: [PoseJoint], current: [PoseJoint], aspect: Double = 1) -> Double? {
        let required = [11, 12, 15, 16, 23, 24]
        guard previous.count > 24, current.count > 24, aspect.isFinite, aspect > 0,
              required.allSatisfy({ previous[$0].inFrame && current[$0].inFrame }) else { return nil }
        let widths = [previous, current].map { frame in
            hypot((frame[11].x - frame[12].x) * aspect, frame[11].y - frame[12].y)
        }
        let scale = (widths[0] + widths[1]) / 2
        guard scale >= 0.08 else { return nil }
        func midpoint(_ frame: [PoseJoint], _ a: Int, _ b: Int) -> (Double, Double) {
            ((frame[a].x + frame[b].x) / 2, (frame[a].y + frame[b].y) / 2)
        }
        let oldTorso = midpoint(previous, 23, 24)
        let newTorso = midpoint(current, 23, 24)
        func wristTravel(_ index: Int) -> Double {
            let oldX = previous[index].x - oldTorso.0
            let oldY = previous[index].y - oldTorso.1
            let newX = current[index].x - newTorso.0
            let newY = current[index].y - newTorso.1
            return hypot((newX - oldX) * aspect, newY - oldY) / scale
        }
        let travel = max(wristTravel(15), wristTravel(16))
        return travel.isFinite ? min(10, max(0, travel)) : nil
    }
}

struct SquatTracker {
    private(set) var count = 0
    private var phase = 0
    private var stableFrames = 0
    private var lastSampleAt: Date?

    mutating func observe(angle: Double?, at date: Date) -> Bool {
        defer { lastSampleAt = date }
        guard let angle, angle.isFinite,
              lastSampleAt.map({ date.timeIntervalSince($0) <= 0.5 }) ?? true else {
            phase = 0; stableFrames = 0; return false
        }
        let target = angle >= 150 ? 1 : (angle <= 115 ? 2 : 0)
        guard target != 0 else { stableFrames = 0; return false }
        stableFrames = target == (phase == 2 ? 1 : phase == 1 ? 2 : 1) ? stableFrames + 1 : 1
        guard stableFrames >= 3 else { return false }
        if phase == 0 && target == 1 { phase = 1; stableFrames = 0 }
        else if phase == 1 && target == 2 { phase = 2; stableFrames = 0 }
        else if phase == 2 && target == 1 {
            phase = 1; stableFrames = 0; count += 1; return true
        }
        return false
    }

    mutating func resetPosture() { phase = 0; stableFrames = 0; lastSampleAt = nil }
    mutating func restoreCount(_ value: Int) { count = max(0, value); resetPosture() }
}

enum PoseOverlayMapping {
    static let bodyConnections: [(Int, Int)] = [
        (11, 12), (11, 13), (13, 15), (12, 14), (14, 16),
        (11, 23), (12, 24), (23, 24),
        (23, 25), (25, 27), (24, 26), (26, 28),
    ]
    static func visiblePoints(_ joints: [PoseJoint]) -> [Int: CGPoint] {
        Dictionary(uniqueKeysWithValues: joints.enumerated().compactMap { index, joint in
            joint.inFrame ? (index, CGPoint(x: joint.x, y: joint.y)) : nil
        })
    }
    static func point(_ normalized: CGPoint, preview: CGSize, video: CGSize, mirrored: Bool) -> CGPoint {
        guard preview.width > 0, preview.height > 0, video.width > 0, video.height > 0 else {
            return CGPoint(x: normalized.x * preview.width, y: normalized.y * preview.height)
        }
        let scale = max(preview.width / video.width, preview.height / video.height)
        let shown = CGSize(width: video.width * scale, height: video.height * scale)
        let insetX = (preview.width - shown.width) / 2
        let insetY = (preview.height - shown.height) / 2
        let x = mirrored ? 1 - normalized.x : normalized.x
        return CGPoint(x: insetX + x * shown.width, y: insetY + normalized.y * shown.height)
    }
}

final class WorkoutCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, PoseLandmarkerLiveStreamDelegate {
    let session = AVCaptureSession()
    @Published var stateKey = "camera_starting"
    @Published var landmarks: [Int: CGPoint] = [:]
    @Published var poseStatusKey = "pose_waiting"
    @Published var poseSample: LivePoseSample?
    @Published var position: AVCaptureDevice.Position = .front
    @Published var videoSize: CGSize = .zero
    @Published var latestExchange: LabeledExchange?
    @Published var latestEvidence: [EvidenceCard] = []
    private var tracker = ExchangeTracker()
    let evidence = EvidenceRing()
    private let ciContext = CIContext()
    private var lastSnapshot = 0
    private let queue = DispatchQueue(label: "coin.workout.camera")
    private let frameQueue = DispatchQueue(label: "coin.workout.pose")
    private var landmarker: PoseLandmarker?
    private var cameraInput: AVCaptureDeviceInput?
    private var lastSubmitted = 0
    private var lastVideoSize: CGSize = .zero
    private var framingBeganAtMs: Int?
    private var lastMotionFrame: (timestamp: Int, joints: [PoseJoint], pixelSize: CGSize)?
    private let motionLock = NSLock()
    private let timingLock = NSLock()
    private var submittedAt: [Int: (uptime: TimeInterval, epoch: Int, pixelSize: CGSize)] = [:]
    private var epoch = 0

    func start() {
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil ||
              AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
            stateKey = "camera_unavailable"
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
            guard let self else { return }
            guard allowed else {
                DispatchQueue.main.async { self.stateKey = "camera_permission" }
                return
            }
            self.queue.async {
                guard !self.session.isRunning else { return }
                if let path = Bundle.main.path(forResource: "pose_landmarker_full", ofType: "task") {
                    let options = PoseLandmarkerOptions()
                    options.baseOptions.modelAssetPath = path
                    options.runningMode = .liveStream
                    options.numPoses = 1
                    options.poseLandmarkerLiveStreamDelegate = self
                    self.landmarker = try? PoseLandmarker(options: options)
                }
                if self.landmarker == nil {
                    DispatchQueue.main.async { self.poseStatusKey = "pose_model_unavailable" }
                }
                self.session.beginConfiguration()
                self.session.sessionPreset = .high
                let chosen: AVCaptureDevice.Position = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil ? .front : .back
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: chosen),
                      let input = try? AVCaptureDeviceInput(device: camera), self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.stateKey = "camera_unavailable" }
                    return
                }
                self.session.addInput(input)
                self.cameraInput = input
                let frames = AVCaptureVideoDataOutput()
                frames.alwaysDiscardsLateVideoFrames = true
                frames.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
                frames.setSampleBufferDelegate(self, queue: self.frameQueue)
                if self.session.canAddOutput(frames) { self.session.addOutput(frames) }
                if let connection = frames.connection(with: .video), connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false
                    }
                }
                self.session.commitConfiguration()
                self.session.startRunning()
                DispatchQueue.main.async { self.position = chosen; self.stateKey = "camera_on" }
            }
        }
    }
    func switchCamera() {
        queue.async {
            guard self.session.isRunning, let previous = self.cameraInput else { return }
            let next: AVCaptureDevice.Position = previous.device.position == .front ? .back : .front
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: next),
                  let replacement = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            self.session.removeInput(previous)
            if self.session.canAddInput(replacement) {
                self.session.addInput(replacement)
                self.cameraInput = replacement
                self.timingLock.lock()
                self.epoch += 1
                self.submittedAt.removeAll()
                self.lastSubmitted = 0
                self.timingLock.unlock()
                self.motionLock.lock()
                self.lastMotionFrame = nil
                self.motionLock.unlock()
                DispatchQueue.main.async {
                    self.position = next
                    self.landmarks = [:]
                    self.poseStatusKey = "pose_waiting"
                }
            } else {
                self.session.addInput(previous)
            }
            self.session.commitConfiguration()
        }
    }
    /// Closes any open exchange and hands over the round's exchanges; the tracker starts fresh.
    func takeRoundExchanges() -> [LabeledExchange] {
        motionLock.lock(); defer { motionLock.unlock() }
        _ = tracker.finish(atMs: Int(ProcessInfo.processInfo.systemUptime * 1000))
        let result = tracker.exchanges
        tracker = ExchangeTracker()
        return result
    }
    func resetExchanges() {
        motionLock.lock(); tracker = ExchangeTracker(); motionLock.unlock()
    }
    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            self.motionLock.lock()
            self.lastMotionFrame = nil
            self.motionLock.unlock()
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let landmarker else { return }
        let receivedAt = ProcessInfo.processInfo.systemUptime
        let timestamp = Int(receivedAt * 1000)
        timingLock.lock()
        let shouldSubmit = timestamp > lastSubmitted + 90
        if shouldSubmit { lastSubmitted = timestamp }
        timingLock.unlock()
        guard shouldSubmit else { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        guard size.width > 0, size.height > 0 else { return }
        if size != lastVideoSize {
            lastVideoSize = size
            DispatchQueue.main.async { self.videoSize = size }
        }
        if timestamp - lastSnapshot >= 250 {
            // Low-resolution evidence frames (about 4 per second, last 5 s) so a fault can be shown after the round.
            lastSnapshot = timestamp
            let frame = CIImage(cvPixelBuffer: buffer)
            let scale = 360 / max(frame.extent.width, 1)
            let small = frame.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            if let cg = ciContext.createCGImage(small, from: small.extent) { evidence.add(t: timestamp, image: cg) }
        }
        guard let image = try? MPImage(sampleBuffer: sampleBuffer, orientation: .up) else { return }
        timingLock.lock()
        submittedAt[timestamp] = (receivedAt, epoch, size)
        if submittedAt.count > 32 {
            for old in submittedAt.keys.sorted().prefix(submittedAt.count - 32) { submittedAt.removeValue(forKey: old) }
        }
        timingLock.unlock()
        do {
            try landmarker.detectAsync(image: image, timestampInMilliseconds: timestamp)
        } catch {
            timingLock.lock(); submittedAt.removeValue(forKey: timestamp); timingLock.unlock()
        }
    }
    func poseLandmarker(_ poseLandmarker: PoseLandmarker, didFinishDetection result: PoseLandmarkerResult?, timestampInMilliseconds: Int, error: Error?) {
        timingLock.lock()
        let submitted = submittedAt.removeValue(forKey: timestampInMilliseconds)
        let currentEpoch = epoch
        timingLock.unlock()
        guard let submitted, submitted.epoch == currentEpoch else { return }
        let latencyMs = max(0, (ProcessInfo.processInfo.systemUptime - submitted.uptime) * 1000)
        // MPImage uses the portrait-oriented buffer with .up. Keep image-normalized
        // joints for the overlay; metric calculations use this exact frame's aspect.
        let aspect = Double(submitted.pixelSize.width / submitted.pixelSize.height)
        let joints = result?.landmarks.first?.map { PoseJoint(x: Double($0.x), y: Double($0.y), visibility: $0.visibility?.doubleValue ?? 0) } ?? []
        motionLock.lock()
        let previousFrame = lastMotionFrame
        lastMotionFrame = (timestampInMilliseconds, joints, submitted.pixelSize)
        let exchangeEvents = error == nil ? tracker.feed(timeMs: timestampInMilliseconds, joints: joints) : []
        motionLock.unlock()
        if !joints.isEmpty { evidence.setJoints(t: timestampInMilliseconds, joints: joints) }
        for case .exchange(let exchange) in exchangeEvents {
            DispatchQueue.main.async { self.latestExchange = exchange }
            if !exchange.faults.isEmpty {
                let language = UserDefaults.standard.string(forKey: "language") ?? "fr"
                let cards = EvidenceRenderer.cards(for: exchange, ring: evidence, language: language, stance: "orthodox")
                if !cards.isEmpty { DispatchQueue.main.async { self.latestEvidence = cards } }
            }
        }
        let gap = timestampInMilliseconds - (previousFrame?.timestamp ?? timestampInMilliseconds)
        let wristTravel: Double?
        if let previousFrame, (80...400).contains(gap),
           abs(Double(previousFrame.pixelSize.width / previousFrame.pixelSize.height) - aspect) < 0.000001 {
            wristTravel = PoseMotion.wristTravelBodyWidths(previous: previousFrame.joints, current: joints, aspect: aspect)
        } else {
            wristTravel = nil
        }
        let frameReady = PoseFraming.fullBodyInFrame(joints)
        if frameReady {
            if framingBeganAtMs == nil { framingBeganAtMs = timestampInMilliseconds }
        } else { framingBeganAtMs = nil }
        let sustainedReady = frameReady && timestampInMilliseconds - (framingBeganAtMs ?? timestampInMilliseconds) >= 500
        let points = PoseOverlayMapping.visiblePoints(joints)
        DispatchQueue.main.async {
            self.landmarks = points
            self.poseStatusKey = error != nil ? "pose_error" : (joints.isEmpty ? "pose_absent" : (sustainedReady ? "pose_visible" : "pose_partial"))
            if error == nil {
                let squatAngle = PoseMotion.squatKneeAngle(joints, aspect: aspect)
                let lungeAngle = PoseMotion.lungeKneeAngle(joints, aspect: aspect)
                self.poseSample = LivePoseSample(sampledAt: Date(), landmarkCount: joints.count,
                                                 visibleLandmarkCount: points.count, framingReady: sustainedReady,
                                                 captureToPoseMs: latencyMs,
                                                 wristTravelBodyWidths: wristTravel,
                                                 squatKneeAngle: squatAngle,
                                                 lungeKneeAngle: lungeAngle,
                                                 lowerBodyVisible: squatAngle != nil || lungeAngle != nil)
            }
        }
    }
}

final class CameraLayerView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct WorkoutCameraView: UIViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool
    func makeUIView(context: Context) -> CameraLayerView {
        let view = CameraLayerView()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ view: CameraLayerView, context: Context) {
        if let connection = view.preview.connection {
            if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirrored
            }
        }
    }
}

@MainActor final class WorkoutSpeechController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var fx: AVAudioPlayer?
    private var releaseTask: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
        // Mix with the boxer's own music (Spotify, Apple Music) and dip it only while Coin is speaking.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
    }

    func speak(_ line: String, locale: String, cueKey: String, language: String) {
        player?.stop()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        activate()
        if let url = Bundle.main.url(forResource: "\(language)_\(cueKey)", withExtension: "mp3"),
           let recording = try? AVAudioPlayer(contentsOf: url) {
            player = recording
            recording.delegate = self
            recording.play()
            return
        }
        let utterance = AVSpeechUtterance(string: line)
        utterance.voice = AVSpeechSynthesisVoice(language: locale)
        synthesizer.speak(utterance)
    }

    /// Short tone after each exchange: a high tick when clean, a low double tone when it has a fault.
    func exchangeSound(fault: Bool) {
        guard !synthesizer.isSpeaking, player?.isPlaying != true else { return }
        let data = fault ? Self.tone([(440, 0.09), (0, 0.05), (440, 0.09)]) : Self.tone([(1320, 0.06)])
        guard let sound = try? AVAudioPlayer(data: data) else { return }
        activate()
        fx = sound
        sound.delegate = self
        sound.volume = 0.6
        sound.play()
    }

    func stop() {
        player?.stop()
        fx?.stop()
        synthesizer.stopSpeaking(at: .immediate)
        scheduleRelease()
    }

    private func activate() {
        releaseTask?.cancel()
        try? AVAudioSession.sharedInstance().setActive(true)
    }
    private func scheduleRelease() {
        releaseTask?.cancel()
        releaseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, !synthesizer.isSpeaking, player?.isPlaying != true, fx?.isPlaying != true else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.scheduleRelease() }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.scheduleRelease() }
    }

    /// 16-bit mono WAV built in memory from (frequency Hz, seconds) segments; frequency 0 is silence.
    static func tone(_ segments: [(Double, Double)]) -> Data {
        let rate = 44_100.0
        var samples: [Int16] = []
        for (frequency, seconds) in segments {
            let count = Int(rate * seconds)
            for i in 0..<count {
                let envelope = min(1, Double(i) / 300, Double(count - i) / 300)
                let value = frequency > 0 ? sin(2 * .pi * frequency * Double(i) / rate) * envelope : 0
                samples.append(Int16(value * 12_000))
            }
        }
        var data = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 2)) }
        let bytes = UInt32(samples.count * 2)
        data.append("RIFF".data(using: .ascii)!); u32(36 + bytes); data.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(44_100); u32(88_200); u16(2); u16(16)
        data.append("data".data(using: .ascii)!); u32(bytes)
        samples.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        return data
    }
}

@MainActor final class PoseWindowSender: ObservableObject {
    @Published private(set) var offline = false
    private var uploadTask: Task<Void, Never>?
    private let session: URLSession
    private let endpointOverride: URL?
    private let tokenOverride: String?

    init(session: URLSession = .shared, endpointOverride: URL? = nil, tokenOverride: String? = nil) {
        self.session = session
        self.endpointOverride = endpointOverride
        self.tokenOverride = tokenOverride
    }

    func sendPending(from store: TrainingStore) {
        guard uploadTask == nil, UserDefaults.standard.bool(forKey: "poseTelemetryEnabled") else { return }
        uploadTask = Task {
            defer { uploadTask = nil }
            while !Task.isCancelled && UserDefaults.standard.bool(forKey: "poseTelemetryEnabled"),
                  let pending = store.nextPendingPoseUpload() {
                do {
                    let origin = store.data.sessions.first { $0.id == pending.sessionID }?.runtimeOrigin ?? .unknown
                    let eventID = try await send(pending.sample, sessionID: pending.sessionID, origin: origin)
                    if Task.isCancelled { break }
                    store.recordPoseDelivery(sessionID: pending.sessionID, sampleID: pending.sample.id, eventID: eventID)
                    offline = false
                    try await Task.sleep(nanoseconds: 500_000_000)
                } catch {
                    if !Task.isCancelled { offline = true }
                    break
                }
            }
        }
    }

    func cancel() {
        uploadTask?.cancel()
    }

    private func send(_ sample: PoseSampleRecord, sessionID: UUID, origin: WorkoutRuntimeOrigin) async throws -> String {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let base = environment["COIN_SERVICE_URL"] ?? UserDefaults.standard.string(forKey: "serviceURL") ?? ""
        let credential = environment["COIN_SERVICE_TOKEN"] ?? ServiceCredential.load()
        #else
        let base = UserDefaults.standard.string(forKey: "serviceURL") ?? ""
        let credential = ServiceCredential.load()
        #endif
        guard let token = tokenOverride ?? credential, !token.isEmpty,
              let url = endpointOverride ?? URL(string: base + "/v1/live/pose-window"),
              CoinServer.allowed(url) else {
            throw URLError(.badURL)
        }
        var body: [String: Any] = [
            "request_id": sample.id.uuidString,
            "session_id": sessionID.uuidString,
            "block_id": sample.blockID.uuidString,
            "sequence": Int(sample.sampledAt.timeIntervalSince1970 * 1000),
            "sampled_at_ms": Int(sample.sampledAt.timeIntervalSince1970 * 1000),
            "language": sample.uploadLanguage ?? "fr",
            "landmark_count": sample.landmarkCount,
            "visible_landmark_count": sample.visibleLandmarkCount ?? 0,
            "framing_ready": sample.framingReady ?? false,
            "source_version": sample.sourceVersion,
            "runtime_origin": origin.rawValue,
        ]
        if let activityID = sample.activityInstanceID { body["activity_instance_id"] = activityID.uuidString }
        if let facing = sample.cameraFacing { body["camera_facing"] = facing }
        if let latency = sample.captureToPoseMs { body["capture_to_pose_ms"] = latency }
        if let travel = sample.wristTravelBodyWidths { body["wrist_travel_body_widths"] = travel }
        if let lowerBodyVisible = sample.lowerBodyVisible { body["lower_body_visible"] = lowerBodyVisible }
        let payload = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 3
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["action"] as? String == "silence",
              let eventID = object["event_id"] as? String,
              UUID(uuidString: eventID) != nil else { throw URLError(.badServerResponse) }
        return eventID
    }
}

/// Uses the locally persisted completion receipt as its outbox; failed sends keep the same ID.
@MainActor final class WorkoutCompletionSender: ObservableObject {
    private var uploadTask: Task<Void, Never>?
    private let session: URLSession
    private let endpointOverride: URL?
    private let tokenOverride: String?
    init(session: URLSession = .shared, endpointOverride: URL? = nil, tokenOverride: String? = nil) {
        self.session = session
        self.endpointOverride = endpointOverride
        self.tokenOverride = tokenOverride
    }
    func sendPending(from store: TrainingStore) {
        guard uploadTask == nil else { return }
        uploadTask = Task {
            defer { uploadTask = nil }
            while !Task.isCancelled, let receipt = store.nextPendingWorkoutCompletion() {
                do {
                    let eventID = try await send(receipt)
                    store.recordWorkoutCompletionDelivery(receiptID: receipt.id, eventID: eventID)
                } catch { break }
            }
        }
    }
    private func send(_ receipt: WorkoutCompletionReceipt) async throws -> String {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let base = environment["COIN_SERVICE_URL"] ?? UserDefaults.standard.string(forKey: "serviceURL") ?? ""
        let credential = environment["COIN_SERVICE_TOKEN"] ?? ServiceCredential.load()
        #else
        let base = UserDefaults.standard.string(forKey: "serviceURL") ?? ""
        let credential = ServiceCredential.load()
        #endif
        guard let token = tokenOverride ?? credential, !token.isEmpty,
              let url = endpointOverride ?? URL(string: base + "/v1/workout/completion"), CoinServer.allowed(url) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 3
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: receipt.payload())
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              body["accepted"] as? Bool == true, let eventID = body["event_id"] as? String,
              UUID(uuidString: eventID) == receipt.id else { throw URLError(.badServerResponse) }
        return eventID
    }
}

struct LiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var training: TrainingStore
    @AppStorage("language") private var language = "fr"
    @AppStorage("poseTelemetryEnabled") private var poseTelemetryEnabled = false
    @StateObject private var camera = WorkoutCamera()
    @StateObject private var voice = WorkoutSpeechController()
    @StateObject private var poseSender = PoseWindowSender()
    @StateObject private var completionSender = WorkoutCompletionSender()
    @StateObject private var roundReports = RoundReportClient()
    @State private var cuePolicy = ExchangeCuePolicy()
    @State private var roundExchanges: [LabeledExchange] = []
    @State private var shadowTheme = -1
    @State private var roundEvidence: [EvidenceCard] = []
    @State private var lastEvidence: [EvidenceCard] = []
    @State private var segmentIndex = 0
    @State private var remaining = 0
    @State private var manualElapsed = 0
    @State private var manualAnchor: Date?
    @State private var showSource = false
    @State private var showActivityChoice = false
    @State private var customActivityName = ""
    @State private var running = false
    @State private var muted = false
    @State private var deadline: Date?
    @State private var showFinish = false
    @State private var showRecap = false
    @State private var lastPoseRecordAt: Date?
    @State private var pendingPoseWindows: [PoseSampleRecord] = []
    @State private var motionWindowMax: Double?
    @State private var originalIdleTimerDisabled = false
    @State private var pendingTimedSeconds = 0
    @State private var squatTracker = SquatTracker()
    let sessionID: UUID
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private struct Segment {
        let block: SessionBlock
        let isRest: Bool
        let activity: PreparationActivity?
        let preparationIndex: Int?
        var seconds: Int { activity.map { $0.minutes * 60 } ?? (isRest ? block.effectiveRestSeconds : block.effectiveSeconds) }
        var isManual: Bool { !isRest && activity == nil && block.isManual }
        var activityKey: String? { activity?.key ?? block.sourceActivityKey }
    }
    private var workout: TrainingSession? { training.data.sessions.first { $0.id == sessionID } }
    private var segments: [Segment] {
        workout?.blocks.flatMap { block in
            let work: [Segment] = (block.activities?.isEmpty == false)
                ? (block.activities ?? []).enumerated().map { Segment(block: block, isRest: false, activity: $0.element, preparationIndex: $0.offset) }
                : [Segment(block: block, isRest: false, activity: nil, preparationIndex: nil)]
            return work + (block.effectiveRestSeconds > 0 ? [Segment(block: block, isRest: true, activity: nil, preparationIndex: nil)] : [])
        } ?? []
    }
    private var current: Segment? { segments.indices.contains(segmentIndex) ? segments[segmentIndex] : nil }
    private func activityInstance(for segment: Segment) -> WorkoutActivityInstance? {
        workout?.activityInstance(blockID: segment.block.id, preparationIndex: segment.preparationIndex)
    }
    private func activityKey(for segment: Segment) -> String? {
        if let instance = activityInstance(for: segment) { return instance.exerciseKey }
        return segment.activityKey
    }
    private func loggedActivityKey(for segment: Segment) -> String? {
        let choices = workout?.activityInstances?.filter {
            $0.blockID == segment.block.id && $0.preparationIndex == segment.preparationIndex
        } ?? []
        // A change can occur at any point in the segment. Do not assign the
        // whole elapsed interval to its last selection.
        return choices.count > 1 ? nil : activityKey(for: segment)
    }
    private var canChooseActivity: Bool {
        guard let current, !current.isRest else { return false }
        return current.block.activityChoiceFamily != nil || current.activityKey == "mobility"
    }
    private func tracksExchanges(_ segment: Segment) -> Bool {
        !segment.isRest && WorkoutActivityRouting.allowsExchange(activityInstance(for: segment))
    }
    private func chooseActivity(_ key: String?) {
        captureElapsedFromDeadline()
        let previous = current.flatMap { activityInstance(for: $0) }
        guard let current, training.selectActivity(sessionID: sessionID, blockID: current.block.id,
            preparationIndex: current.preparationIndex, exerciseKey: key,
            customName: key == "custom" ? customActivityName : nil) else { return }
        let selected = activityInstance(for: current)
        if let previous, WorkoutActivityRouting.changed(from: previous, to: selected) {
            recordActivityInterval(for: current, instanceID: previous.id, reason: .choiceChanged)
            if let outgoingID = WorkoutActivityRouting.outgoingExchangeID(from: previous, to: selected) {
                submitRound(current, outgoingInstanceID: outgoingID)
            }
            roundExchanges = []
            roundEvidence = []
            cuePolicy = ExchangeCuePolicy()
            camera.resetExchanges()
            squatTracker = SquatTracker()
        }
        showActivityChoice = false
    }
    private func recordActivityInterval(for segment: Segment, instanceID: UUID? = nil,
                                        reason: ActivityIntervalExitReason) {
        guard !segment.isRest, let instanceID = instanceID ?? activityInstance(for: segment)?.id else { return }
        let elapsed = segment.isManual ? manualElapsed : max(0, segment.seconds - remaining)
        training.recordActivityInterval(sessionID: sessionID, blockID: segment.block.id,
            preparationIndex: segment.preparationIndex, activityInstanceID: instanceID,
            cumulativeElapsedSeconds: elapsed, exitReason: reason)
    }
    private var boxingFocus: String? {
        guard let current, current.block.kind == .boxing, !current.isRest, current.block.sourceTitle == nil else { return nil }
        let key = DrillLibrary.focusCueKey(current.block.drillID ?? "", remainingSeconds: remaining)
        return TrainingCopy.text(key, language)
    }

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.07).ignoresSafeArea()
            WorkoutCameraView(session: camera.session, mirrored: camera.position == .front).ignoresSafeArea()
            GeometryReader { _ in
                Canvas { context, size in
                    for (start, end) in PoseOverlayMapping.bodyConnections {
                        guard let first = camera.landmarks[start], let second = camera.landmarks[end] else { continue }
                        var path = Path()
                        path.move(to: PoseOverlayMapping.point(first, preview: size, video: camera.videoSize,
                                                               mirrored: camera.position == .front))
                        path.addLine(to: PoseOverlayMapping.point(second, preview: size, video: camera.videoSize,
                                                                 mirrored: camera.position == .front))
                        context.stroke(path, with: .color(Noir.gold.opacity(0.48)), lineWidth: 1.5)
                    }
                    for point in camera.landmarks.values {
                        let center = PoseOverlayMapping.point(point, preview: size,
                                                              video: camera.videoSize,
                                                              mirrored: camera.position == .front)
                        let dot = Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4))
                        context.fill(dot, with: .color(Noir.gold.opacity(0.72)))
                    }
                }
            }
            .ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.75), .clear, .clear, .black.opacity(0.80)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Circle().fill(camera.stateKey == "camera_on" ? Noir.red : Noir.muted).frame(width: 7, height: 7)
                    Text(TrainingCopy.text(camera.stateKey, language).uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2)
                    if poseTelemetryEnabled && poseSender.offline {
                        Image(systemName: "wifi.slash").font(.caption2)
                    }
                    Spacer()
                    Button { camera.switchCamera() } label: {
                        Image(systemName: "camera.rotate.fill").frame(width: 28, height: 28)
                    }
                    .disabled(camera.stateKey != "camera_on")
                    .opacity(camera.stateKey == "camera_on" ? 1 : 0.35)
                    .accessibilityLabel(TrainingCopy.text("switch_camera", language))
                    Button {
                        muted.toggle()
                        if muted { voice.stop() }
                    } label: {
                        Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    .accessibilityLabel(TrainingCopy.text(muted ? "unmute" : "mute", language))
                    Button { showFinish = true } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }
                        .accessibilityLabel(TrainingCopy.text("finish", language))
                }
                .foregroundStyle(Noir.ink).padding(.top, 14)
                if camera.stateKey == "camera_on" {
                    Text(TrainingCopy.text(poseStatusForCurrentActivity, language))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Noir.ink.opacity(0.7))
                }
                Spacer()
                if let current, workout?.state == .active {
                    HStack(alignment: .lastTextBaseline) {
                        Text(stageName(current))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2).foregroundStyle(Noir.gold)
                        Spacer()
                        Text(clock(current.isManual ? manualElapsed : remaining))
                            .font(.system(size: 28, weight: .light, design: .monospaced))
                            .monospacedDigit().accessibilityIdentifier("workout-clock")
                    }
                    if !current.isRest, let title = current.block.sourceTitle {
                        Text(title).font(.system(size: 16, weight: .medium, design: .serif)).lineLimit(2).accessibilityIdentifier("workout-source-title")
                        if let prescription = current.block.repetitionText {
                            Text(prescription).font(.caption.monospaced()).foregroundStyle(Noir.gold).lineLimit(2)
                        }
                        Button { pause(); showSource = true } label: {
                            Label(language == "fr" ? "Consigne et démo" : "Instructions & demo", systemImage: "play.rectangle")
                                .font(.caption).foregroundStyle(Noir.gold)
                        }.accessibilityIdentifier("workout-source")
                    }
                    if canChooseActivity {
                        Button { showActivityChoice = true } label: {
                            Label(language == "fr" ? "Mouvement · \(WorkoutActivityCopy.name(activityKey(for: current), customName: activityInstance(for: current)?.customName, language: language))" : "Movement · \(WorkoutActivityCopy.name(activityKey(for: current), customName: activityInstance(for: current)?.customName, language: language))", systemImage: "figure.mixed.cardio")
                                .font(.caption).foregroundStyle(Noir.gold)
                        }.accessibilityIdentifier("workout-activity-choice")
                    }
                    if tracksExchanges(current) {
                        if let boxingFocus {
                            Text(boxingFocus)
                                .font(.system(size: 15, weight: .medium, design: .serif))
                                .foregroundStyle(Noir.ink)
                                .lineLimit(2)
                        }
                        exchangeCounter
                    } else if current.block.kind == .warmup && !current.isRest && current.block.sourceTitle == nil {
                        Text(TrainingCopy.text(activityKey(for: current) ?? "mobility", language))
                            .font(.system(size: 17, weight: .medium, design: .serif))
                        if activityKey(for: current) == "shadowboxing", shadowTheme >= 0 {
                            let theme = ShadowboxingGuide.themes[shadowTheme]
                            Text("\(shadowTheme + 1)/\(ShadowboxingGuide.themes.count) · \(theme.title[language] ?? "")")
                                .font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(Noir.gold)
                            Text(theme.line[language] ?? "").font(.subheadline).lineLimit(3)
                            exchangeCounter
                        }
                        if activityKey(for: current) == "squats" || activityKey(for: current) == "lunges" {
                            Text(TrainingCopy.format(activityKey(for: current) == "lunges" ? "lunge_observed_reps" : "squat_observed_reps", language, squatTracker.count))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                    } else if current.isRest {
                        if let report = roundReports.latest, roundReports.latestSessionID == sessionID.uuidString,
                           roundReports.latestRound == current.block.roundNumber {
                            Text(report.constraint)
                                .font(.system(size: 17, weight: .medium, design: .serif))
                                .lineLimit(3)
                            Text(report.observation).font(.caption).foregroundStyle(Noir.muted).lineLimit(3)
                        } else {
                            Text(TrainingCopy.text("rest_instruction", language)).font(.subheadline)
                        }
                        if !lastEvidence.isEmpty {
                            // What the camera saw: one annotated frame per fault from the last round.
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(lastEvidence) { card in
                                        Image(uiImage: card.image).resizable().scaledToFit()
                                            .frame(height: 170).clipShape(RoundedRectangle(cornerRadius: 6))
                                            .accessibilityLabel(card.caption)
                                    }
                                }
                            }
                        }
                    }
                    if current.block.sourceTitle != nil, !current.isRest,
                       activityKey(for: current) == "squats" || activityKey(for: current) == "lunges" {
                        Text(TrainingCopy.format(activityKey(for: current) == "lunges" ? "lunge_observed_reps" : "squat_observed_reps", language, squatTracker.count))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    HStack(spacing: 14) {
                        Button {
                            if running { pause() }
                            else { begin() }
                        } label: {
                            Label(TrainingCopy.text(running ? "pause" : "start", language), systemImage: running ? "pause.fill" : "play.fill")
                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                                .background(Noir.red, in: RoundedRectangle(cornerRadius: 7))
                        }
                        .accessibilityIdentifier("workout-toggle")
                        if current.isManual {
                            Button { advance(completed: true) } label: {
                                Label(language == "fr" ? "Terminé" : "Done", systemImage: "checkmark")
                                    .padding(10).background(Noir.gold, in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(Noir.black)
                            }.accessibilityIdentifier("complete-manual-step")
                        }
                        Button { advance() } label: {
                            Image(systemName: "forward.end.fill").padding(9)
                                .background(Noir.panel, in: RoundedRectangle(cornerRadius: 7))
                        }
                        .accessibilityLabel(TrainingCopy.text("skip", language))
                    }
                    .font(.subheadline.weight(.semibold))
                } else {
                    Text(TrainingCopy.text("workout_complete", language))
                        .font(.system(size: 38, weight: .regular, design: .serif))
                    Button(TrainingCopy.text("recap_view_log", language)) { showRecap = true }
                        .font(.headline).padding(16)
                        .background(Noir.red, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .foregroundStyle(.white)
            .padding(24)
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            training.ensureActivityInstances(sessionID: sessionID)
            originalIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            if workout?.state == .active { camera.start() }
            if poseTelemetryEnabled { poseSender.sendPending(from: training) }
            completionSender.sendPending(from: training)
            roundReports.flush()
            if let workout {
                segmentIndex = workout.runtimeSegmentIndex ?? 0
                remaining = workout.runtimeRemainingSeconds ?? (current?.seconds ?? 0)
                manualElapsed = workout.runtimeElapsedSeconds ?? 0
                if let current, let key = activityKey(for: current), key == "squats" || key == "lunges" {
                    squatTracker = SquatTracker()
                    squatTracker.restoreCount((workout.exerciseReps ?? []).filter {
                        $0.blockID == current.block.id && $0.activityKey == key
                            && ($0.activityInstanceID == nil || $0.activityInstanceID == activityInstance(for: current)?.id)
                    }.count)
                }
            }
        }
        .onDisappear {
            camera.stop()
            poseSender.cancel()
            pause()
            voice.stop()
            UIApplication.shared.isIdleTimerDisabled = originalIdleTimerDisabled
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { pause() }
            else { roundReports.flush(); completionSender.sendPending(from: training) }
        }
        .onChange(of: poseTelemetryEnabled) { enabled in
            if enabled { poseSender.sendPending(from: training) }
            else { poseSender.cancel() }
        }
        .onChange(of: camera.position) { _ in motionWindowMax = nil; squatTracker.resetPosture() }
        .onReceive(timer) { now in
            if running, current?.isManual == true {
                captureManualElapsed(at: now)
                if pendingTimedSeconds >= 5 {
                    flushTimedSeconds()
                    training.saveRuntime(sessionID: sessionID, segmentIndex: segmentIndex, remainingSeconds: 0, elapsedSeconds: manualElapsed)
                }
                return
            }
            guard running, let deadline else { return }
            let updated = max(0, Int(ceil(deadline.timeIntervalSince(now))))
            guard updated != remaining else { return }
            let previous = remaining
            remaining = updated
            pendingTimedSeconds += max(0, previous - updated)
            if pendingTimedSeconds >= 5 { flushTimedSeconds() }
            if remaining == 0 { advance() }
            else {
                if let current, activityKey(for: current) == "shadowboxing", !current.isRest, current.block.sourceTitle == nil {
                    let index = ShadowboxingGuide.index(elapsed: current.seconds - remaining, total: current.seconds)
                    if index != shadowTheme {
                        shadowTheme = index
                        let theme = ShadowboxingGuide.themes[index]
                        speak(theme.line[language] ?? "", cueKey: theme.key, trigger: "shadowboxing_theme")
                    }
                }
                if let current, current.block.kind == .boxing, !current.isRest, current.block.sourceTitle == nil {
                    for boundary in [120, 60] where previous > boundary && updated <= boundary {
                        if let key = DrillLibrary.pacingCueKey(current.block.drillID ?? "", remainingSeconds: boundary) {
                            speak(TrainingCopy.text(key, language), cueKey: key, trigger: "timer_pacing")
                        }
                    }
                }
                if remaining % 5 == 0 { training.saveRuntime(sessionID: sessionID, segmentIndex: segmentIndex, remainingSeconds: remaining) }
            }
        }
        .onReceive(camera.$latestExchange) { exchange in
            guard let exchange, running, let current, tracksExchanges(current) else { return }
            if activityKey(for: current) == "shadowboxing" { roundExchanges.append(exchange); voice.exchangeSound(fault: current.block.sourceTitle == nil && !exchange.faults.isEmpty); return }
            var labeled = exchange
            if current.block.drillID == "probe-combine-angle-v1",
               let key = cuePolicy.cue(for: exchange, nowMs: Int(ProcessInfo.processInfo.systemUptime * 1000)),
               let line = ExchangeCuePolicy.lines[key]?[language] {
                speak(line, cueKey: key, trigger: "exchange_rule")
                labeled.cue = key
            }
            if labeled.cue == nil { voice.exchangeSound(fault: current.block.drillID == "probe-combine-angle-v1" && !exchange.faults.isEmpty) }
            roundExchanges.append(labeled)
        }
        .onReceive(camera.$latestEvidence) { cards in
            guard let current, tracksExchanges(current),
                  current.block.drillID == "probe-combine-angle-v1" else { return }
            roundEvidence += cards
        }
        .onReceive(roundReports.$latest) { report in
            guard let report, let current, current.isRest,
                  roundReports.latestSessionID == sessionID.uuidString,
                  roundReports.latestRound == current.block.roundNumber else { return }
            speak(report.constraint, cueKey: "round_report", trigger: "round_report")
        }
        .onReceive(camera.$stateKey) { state in
            if state == "camera_on", scenePhase == .active, workout?.state == .active { begin() }
        }
        .onReceive(camera.$poseSample) { sample in
            guard running, let current, !current.isRest, let sample else { return }
            if let key = activityKey(for: current), key == "squats" || key == "lunges" {
                let angle = key == "lunges" ? sample.lungeKneeAngle : sample.squatKneeAngle
                if squatTracker.observe(angle: angle, at: sample.sampledAt) {
                    training.recordExerciseRep(sessionID: sessionID, blockID: current.block.id,
                                               activityKey: key, sourceVersion: "mediapipe-\(key == "lunges" ? "lunge" : "squat")-angle-v1",
                                               activityInstanceID: activityInstance(for: current)?.id,
                                               at: sample.sampledAt)
                }
            }
            if let motion = sample.wristTravelBodyWidths {
                motionWindowMax = max(motionWindowMax ?? 0, motion)
            }
            if let last = lastPoseRecordAt, sample.sampledAt.timeIntervalSince(last) < 2 { return }
            lastPoseRecordAt = sample.sampledAt
            pendingPoseWindows.append(PoseSampleRecord(blockID: current.block.id, sampledAt: sample.sampledAt,
                                                  activityInstanceID: WorkoutActivityRouting.poseOwner(activityInstance(for: current), sampledAt: sample.sampledAt),
                                                  landmarkCount: sample.landmarkCount, sourceVersion: "mediapipe-pose-full-v1",
                                                  visibleLandmarkCount: sample.visibleLandmarkCount, framingReady: sample.framingReady,
                                                  captureToPoseMs: sample.captureToPoseMs,
                                                  wristTravelBodyWidths: motionWindowMax,
                                                  lowerBodyVisible: sample.lowerBodyVisible,
                                                  cameraFacing: camera.position == .front ? "front" : "back"))
            motionWindowMax = nil
            if pendingPoseWindows.count >= 5 { flushPoseWindows() }
        }
        .confirmationDialog(TrainingCopy.text("finish_workout_question", language), isPresented: $showFinish) {
            Button(TrainingCopy.text("finish_now", language)) {
                finishWorkout()
            }
        }
        .sheet(isPresented: $showSource) {
            NavigationStack {
                ScrollView {
                    if let block = current?.block {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(block.sourceTitle ?? "").font(.title2)
                            Text(block.sourceInstructions ?? "").textSelection(.enabled)
                            if let address = block.sourceURL, let url = URL(string: address) {
                                Link(language == "fr" ? "Voir la séance source" : "View source workout", destination: url)
                            }
                            ForEach(Array((block.sourceDemoURLs ?? []).enumerated()), id: \.offset) { index, address in
                                if let url = URL(string: address) {
                                    Link(language == "fr" ? "Démonstration \(index + 1)" : "Demonstration \(index + 1)", destination: url)
                                }
                            }
                        }.padding(24)
                    }
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(language == "fr" ? "Fermer" : "Close") { showSource = false } } }
            }.tint(Noir.gold).preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showActivityChoice) {
            NavigationStack {
                List {
                    Section(language == "fr" ? "Mouvement pour ce segment" : "Movement for this segment") {
                        ForEach(WorkoutMovementDefinition.choices(for: current?.block.activityChoiceFamily ?? (current?.activityKey == "mobility" ? "mobility" : nil)), id: \.key) { movement in
                            Button {
                                chooseActivity(movement.key)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(activityLabel(movement.key))
                                    Text(ActivityMeasurementRecipe.forExercise(movement.key).capability == .repCandidate
                                         ? (language == "fr" ? "Répétitions candidates · non validées" : "Candidate reps · unvalidated")
                                         : ActivityMeasurementRecipe.forExercise(movement.key).capability == .exchangeCandidate
                                         ? (language == "fr" ? "Échanges candidats · non validés" : "Candidate exchanges · unvalidated")
                                         : (language == "fr" ? "Durée seulement · aucun comptage de pose" : "Time only · no pose count"))
                                        .font(.caption).foregroundStyle(Noir.muted)
                                }
                            }
                        }
                        TextField(language == "fr" ? "Autre mouvement" : "Other movement", text: $customActivityName)
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("custom-activity-name")
                        Button(language == "fr" ? "Choisir mon mouvement" : "Choose my movement") { chooseActivity("custom") }
                            .disabled(customActivityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Section {
                        Text(language == "fr" ? "Le choix précise ce que tu fais. La consigne d'origine reste visible. « Libre » mesure la durée, pas le mouvement." : "Your choice names the movement. The original instruction remains visible. Custom tracks time, not movement.")
                            .font(.caption).foregroundStyle(Noir.muted)
                    }
                }
                .navigationTitle(language == "fr" ? "Choisir le mouvement" : "Choose movement")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(language == "fr" ? "Fermer" : "Close") { showActivityChoice = false } } }
            }.tint(Noir.gold).preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showRecap) {
            WorkoutRecapView(sessionID: sessionID) {
                showRecap = false
                dismiss()
            }
            .environmentObject(training)
        }
    }

    private func stageName(_ segment: Segment) -> String {
        if segment.isRest { return TrainingCopy.text("rest_title", language) }
        switch segment.block.kind {
        case .warmup: return TrainingCopy.text("warmup_title", language)
        case .cooldown: return TrainingCopy.text("cooldown_title", language)
        case .boxing: return TrainingCopy.format("round_title", language, segment.block.roundNumber ?? 0)
        case .exercise: return language == "fr" ? "EXERCICE" : "EXERCISE"
        case .recovery: return language == "fr" ? "RÉCUPÉRATION" : "RECOVERY"
        }
    }
    private var poseStatusForCurrentActivity: String {
        guard let current, activityKey(for: current) == "squats" || activityKey(for: current) == "lunges",
              camera.poseStatusKey == "pose_partial" || camera.poseStatusKey == "pose_visible" else {
            return camera.poseStatusKey
        }
        return camera.poseSample?.lowerBodyVisible == true ? "pose_legs_visible" : "pose_show_legs"
    }
    private func activityLabel(_ key: String) -> String {
        WorkoutActivityCopy.name(key, language: language)
    }
    private func clock(_ seconds: Int) -> String { String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60) }
    private func announceCurrent() {
        guard let current else { return }
        let line: String
        let key: String
        if current.isRest { key = "rest_speech"; line = TrainingCopy.text(key, language) }
        else if let title = current.block.sourceTitle {
            if let instance = activityInstance(for: current), instance.selectionProvenance == .userSelected {
                let movement = instance.customName ?? activityLabel(instance.exerciseKey ?? "custom")
                speak(language == "fr" ? "Commence : \(movement)." : "Begin: \(movement).",
                      cueKey: "activity_selected", trigger: "stage_start")
                return
            }
            let instruction = [title, current.block.repetitionText].compactMap { $0 }.joined(separator: ". ")
            // Original program copy is English. Keep its voice locale explicit.
            guard !muted else { return }
            voice.speak(instruction, locale: "en-US", cueKey: "source_instruction", language: "en")
            training.recordCueRequest(sessionID: sessionID, blockID: current.block.id, cueKey: "source_instruction", language: "en", trigger: "stage_start")
            return
        }
        else if activityKey(for: current) == "shadowboxing" {
            let theme = ShadowboxingGuide.themes[ShadowboxingGuide.index(elapsed: current.seconds - remaining, total: current.seconds)]
            shadowTheme = ShadowboxingGuide.themes.firstIndex { $0.key == theme.key } ?? 0
            key = theme.key; line = theme.line[language] ?? ""
        }
        else if current.block.kind == .warmup {
            if let instance = activityInstance(for: current), instance.selectionProvenance == .userSelected {
                key = "activity_selected"
                let movement = instance.customName ?? activityLabel(instance.exerciseKey ?? "custom")
                line = language == "fr" ? "Commence : \(movement)." : "Begin: \(movement)."
            } else {
                key = "\(activityKey(for: current) ?? "mobility")_cue"
                line = TrainingCopy.text(key, language)
            }
        }
        else if current.block.kind == .cooldown { key = "cooldown_speech"; line = TrainingCopy.text(key, language) }
        else { key = DrillLibrary.speechKey(current.block.drillID ?? ""); line = TrainingCopy.text(key, language) }
        speak(line, cueKey: key, trigger: "stage_start")
    }
    private func speak(_ line: String, cueKey: String, trigger: String) {
        guard !muted else { return }
        voice.speak(line, locale: TrainingCopy.text("speech_locale", language), cueKey: cueKey, language: language)
        if let current {
            training.recordCueRequest(sessionID: sessionID, blockID: current.block.id,
                                      cueKey: cueKey, language: language, trigger: trigger)
        }
    }
    private func advance(completed: Bool = false) {
        guard let current else { return }
        captureElapsedFromDeadline()
        recordActivityInterval(for: current, reason: .segmentEnded)
        flushTimedSeconds()
        training.recordSegment(sessionID: sessionID, blockID: current.block.id,
                               activityKey: loggedActivityKey(for: current), isRest: current.isRest,
                               plannedSeconds: current.seconds,
                               elapsedSeconds: current.isManual ? manualElapsed : max(0, current.seconds - remaining),
                               exitReason: current.isManual ? (completed ? "manual_completed" : "skipped") : (remaining == 0 ? "timer_elapsed" : "skipped"))
        voice.stop()
        flushPoseWindows()
        if tracksExchanges(current) { submitRound(current) }
        if (current.isManual && completed) || (!current.isManual && remaining <= 0) {
            if current.isRest { training.recordRestElapsed(sessionID: sessionID, blockID: current.block.id) }
            else if !segments.indices.contains(segmentIndex + 1) || segments[segmentIndex + 1].block.id != current.block.id || segments[segmentIndex + 1].isRest {
                training.completeBlock(sessionID: sessionID, blockID: current.block.id, source: current.isManual ? "manual_completed" : "timer_elapsed")
            }
        }
        segmentIndex += 1
        squatTracker = SquatTracker()
        shadowTheme = -1
        if let next = self.current, tracksExchanges(next) {
            camera.resetExchanges(); roundExchanges = []; cuePolicy = ExchangeCuePolicy()
        }
        remaining = self.current?.seconds ?? 0
        manualElapsed = 0
        manualAnchor = running && self.current?.isManual == true ? Date() : nil
        deadline = running && self.current?.isManual != true ? Date().addingTimeInterval(TimeInterval(remaining)) : nil
        training.saveRuntime(sessionID: sessionID, segmentIndex: segmentIndex, remainingSeconds: remaining, elapsedSeconds: 0)
        if self.current == nil {
            finishWorkout()
        } else if running { announceCurrent() }
    }
    /// Big enough to read from across the room while boxing.
    private var exchangeCounter: some View {
        let judgingDrill = current?.block.drillID == "probe-combine-angle-v1"
        let faults = judgingDrill ? roundExchanges.filter { !$0.faults.isEmpty }.count : 0
        let lastFault = judgingDrill && (roundExchanges.last.map { !$0.faults.isEmpty } ?? false)
        return HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(roundExchanges.count)")
                .font(.system(size: 64, weight: .bold, design: .monospaced)).monospacedDigit()
                .foregroundStyle(lastFault ? Noir.red : Noir.gold)
                .contentTransition(.numericText())
            VStack(alignment: .leading, spacing: 2) {
                Text(language == "fr" ? "ÉCHANGES" : "EXCHANGES")
                    .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2)
                Text(!judgingDrill ? (language == "fr" ? "à ton rythme" : "your rhythm") : (language == "fr" ? "\(faults) avec faute" : "\(faults) with a fault"))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(faults > 0 ? Noir.red : Noir.muted)
                if judgingDrill {
                    Text(roundExchanges.last.map { language == "fr" ? ($0.opener == "probe" ? "dernier : sonde" : "dernier : engagement") : "last: \($0.opener)" } ?? " ")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Noir.muted)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: roundExchanges.count)
    }
    private var exchangeLine: String {
        let faults = roundExchanges.flatMap(\.faults).count
        let last = roundExchanges.last.map { language == "fr" ? ($0.opener == "probe" ? "sonde" : "engagement") : $0.opener } ?? "—"
        return language == "fr" ? "ÉCHANGES \(roundExchanges.count) · DERNIER \(last) · FAUTES \(faults)"
                                : "EXCHANGES \(roundExchanges.count) · LAST \(last) · FAULTS \(faults)"
    }
    /// Sends the finished round's exchanges to the harness; never blocks the workout.
    private func submitRound(_ segment: Segment, outgoingInstanceID: UUID? = nil) {
        guard outgoingInstanceID != nil || tracksExchanges(segment) else { return }
        let instanceID = outgoingInstanceID ?? activityInstance(for: segment)?.id
        var byID = Dictionary(uniqueKeysWithValues: roundExchanges.map { ($0.id, $0) })
        for exchange in camera.takeRoundExchanges() where byID[exchange.id] == nil { byID[exchange.id] = exchange }
        let exchanges = byID.values.sorted { $0.id < $1.id }
        roundExchanges = []; cuePolicy = ExchangeCuePolicy()
        lastEvidence = roundEvidence; roundEvidence = []
        guard !exchanges.isEmpty else { return }
        roundReports.submit(RoundSummary(requestID: UUID().uuidString, language: language, stance: "orthodox",
                                         drillID: segment.block.drillID, round: segment.block.roundNumber ?? 0,
                                         durationS: instanceID.map { workout?.activityElapsedSeconds(instanceID: $0) ?? 0 } ?? 0,
                                         exchanges: exchanges,
                                         sessionID: sessionID.uuidString,
                                         workoutMode: segment.block.sourceURL != nil ? "program" : (segment.block.drillID == "free-boxing-v1" ? "freestyle" : "drill"),
                                         sourceTitle: segment.block.sourceTitle,
                                         sourceInstructions: segment.block.sourceInstructions.map { String($0.prefix(6000)) },
                                         sourceID: segment.block.sourceBlockID,
                                         activityInstanceID: instanceID?.uuidString))
    }
    private func finishWorkout() {
        guard workout?.state == .active else { return }
        captureElapsedFromDeadline()
        if let current { recordActivityInterval(for: current, reason: .sessionFinished) }
        if let current, tracksExchanges(current) { submitRound(current) }
        flushTimedSeconds()
        if let current {
            let alreadyLogged = workout?.segmentLogs?.last.map {
                $0.blockID == current.block.id && $0.activityKey == loggedActivityKey(for: current)
                    && $0.isRest == current.isRest && $0.exitReason == "timer_elapsed"
            } ?? false
            if !alreadyLogged {
                training.recordSegment(sessionID: sessionID, blockID: current.block.id,
                                       activityKey: loggedActivityKey(for: current), isRest: current.isRest,
                                       plannedSeconds: current.seconds,
                                       elapsedSeconds: current.isManual ? manualElapsed : max(0, current.seconds - remaining),
                                       exitReason: "session_finished")
            }
        }
        running = false
        deadline = nil
        UIApplication.shared.isIdleTimerDisabled = originalIdleTimerDisabled
        voice.stop()
        flushPoseWindows()
        training.finish(sessionID, reflection: "")
        completionSender.sendPending(from: training)
        camera.stop()
        poseSender.cancel()
        showRecap = true
    }
    private func pause() {
        captureElapsedFromDeadline()
        if let current { recordActivityInterval(for: current, reason: .paused) }
        flushTimedSeconds()
        if let deadline { remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow))) }
        deadline = nil
        manualAnchor = nil
        running = false
        UIApplication.shared.isIdleTimerDisabled = originalIdleTimerDisabled
        voice.stop()
        flushPoseWindows()
        motionWindowMax = nil
        squatTracker.resetPosture()
        training.saveRuntime(sessionID: sessionID, segmentIndex: segmentIndex, remainingSeconds: remaining, elapsedSeconds: manualElapsed)
    }
    private func begin() {
        guard !running, let current, remaining > 0 || current.isManual else { return }
        announceCurrent()
        running = true
        UIApplication.shared.isIdleTimerDisabled = true
        deadline = current.isManual ? nil : Date().addingTimeInterval(TimeInterval(remaining))
        manualAnchor = current.isManual ? Date() : nil
    }
    private func flushPoseWindows() {
        guard !pendingPoseWindows.isEmpty else { return }
        if poseTelemetryEnabled { pendingPoseWindows[pendingPoseWindows.count - 1].uploadLanguage = language }
        training.recordPoseWindows(sessionID: sessionID, windows: pendingPoseWindows)
        if poseTelemetryEnabled { poseSender.sendPending(from: training) }
        pendingPoseWindows.removeAll()
    }
    private func captureManualElapsed(at now: Date = Date()) {
        guard running, current?.isManual == true, let anchor = manualAnchor else { return }
        let delta = max(0, Int(now.timeIntervalSince(anchor)))
        manualElapsed += delta
        pendingTimedSeconds += delta
        manualAnchor = anchor.addingTimeInterval(TimeInterval(delta))
    }
    private func captureElapsedFromDeadline() {
        if current?.isManual == true { captureManualElapsed(); return }
        guard running, let deadline else { return }
        let updated = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
        if updated < remaining {
            pendingTimedSeconds += remaining - updated
            remaining = updated
        }
    }
    private func flushTimedSeconds() {
        while pendingTimedSeconds > 0 {
            let batch = min(pendingTimedSeconds, 300)
            training.recordTimedSeconds(sessionID: sessionID, seconds: batch)
            pendingTimedSeconds -= batch
        }
    }
}
