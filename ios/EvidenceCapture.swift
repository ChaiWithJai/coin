import CoreImage
import Foundation
import UIKit

/// One annotated frame proving a fault: shown during the rest, saved on the phone with the round log.
struct EvidenceCard: Identifiable, Equatable {
    let id = UUID()
    let exchangeID: Int
    let fault: String
    let caption: String
    let image: UIImage
    let fileName: String
    static func == (a: EvidenceCard, b: EvidenceCard) -> Bool { a.id == b.id }
}

/// The last few seconds of low-resolution frames with their pose, so a fault can be shown after it is detected.
final class EvidenceRing {
    private struct Entry { let t: Int; let image: CGImage; var joints: [PoseJoint]? }
    private var entries: [Entry] = []
    private let lock = NSLock()
    private let keepMs: Int
    init(keepMs: Int = 5000) { self.keepMs = keepMs }

    func add(t: Int, image: CGImage) {
        lock.lock(); defer { lock.unlock() }
        entries.append(Entry(t: t, image: image, joints: nil))
        entries.removeAll { $0.t < t - keepMs }
    }
    func setJoints(t: Int, joints: [PoseJoint]) {
        lock.lock(); defer { lock.unlock() }
        if let i = entries.lastIndex(where: { abs($0.t - t) <= 60 }) { entries[i].joints = joints }
    }
    /// The frame with a pose closest to `t`.
    func frame(near t: Int) -> (CGImage, [PoseJoint])? {
        lock.lock(); defer { lock.unlock() }
        return entries.filter { $0.joints?.isEmpty == false }
            .min { abs($0.t - t) < abs($1.t - t) }
            .map { ($0.image, $0.joints!) }
    }
    func clear() { lock.lock(); entries.removeAll(); lock.unlock() }
}

enum EvidenceRenderer {
    static let captions: [String: [String: String]] = [
        "rear_hand_low": ["fr": "Main arrière basse pendant le jab", "en": "Rear hand dropped during the jab"],
        "no_reset": ["fr": "Pas revenu en garde après l'échange", "en": "Not back in guard after the exchange"],
        "no_exit": ["fr": "Resté sur la ligne après la combinaison", "en": "Stayed on the line after the combination"],
    ]

    /// When in the exchange each fault is best seen.
    static func moment(for fault: String, in exchange: LabeledExchange) -> Int {
        switch fault {
        case "rear_hand_low": return exchange.punches.first { $0.rearHandLow }?.atMs ?? exchange.startMs
        case "no_reset": return exchange.endMs + 1500
        default: return exchange.endMs + 900
        }
    }

    static func highlighted(_ fault: String, stance: String) -> [Int] {
        let rear = stance == "southpaw" ? (15, 11) : (16, 12)
        switch fault {
        case "rear_hand_low": return [rear.0, rear.1]
        case "no_reset": return [15, 16]
        default: return [23, 24]
        }
    }

    static func render(_ image: CGImage, joints: [PoseJoint], fault: String, language: String, stance: String) -> UIImage {
        let size = CGSize(width: image.width, height: image.height)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
            let cg = context.cgContext
            func point(_ i: Int) -> CGPoint? {
                guard joints.indices.contains(i), joints[i].visibility >= 0.3 else { return nil }
                return CGPoint(x: joints[i].x * size.width, y: joints[i].y * size.height)
            }
            cg.setLineWidth(max(2, size.width / 160))
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.85).cgColor)
            for (a, b) in PoseOverlayMapping.bodyConnections {
                guard let p = point(a), let q = point(b) else { continue }
                cg.move(to: p); cg.addLine(to: q)
            }
            cg.strokePath()
            let red = UIColor(red: 0.85, green: 0.15, blue: 0.12, alpha: 1)
            cg.setStrokeColor(red.cgColor)
            cg.setLineWidth(max(3, size.width / 90))
            let radius = size.width / 14
            for i in highlighted(fault, stance: stance) {
                guard let p = point(i) else { continue }
                cg.strokeEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
            }
            if fault == "rear_hand_low", let shoulderL = point(11), let shoulderR = point(12) {
                // the guard line: the rear hand should sit above this
                let y = (shoulderL.y + shoulderR.y) / 2
                cg.setLineDash(phase: 0, lengths: [8, 6])
                cg.move(to: CGPoint(x: 0, y: y)); cg.addLine(to: CGPoint(x: size.width, y: y)); cg.strokePath()
                cg.setLineDash(phase: 0, lengths: [])
            }
            let caption = captions[fault]?[language] ?? fault
            let bar = CGRect(x: 0, y: size.height - size.height / 9, width: size.width, height: size.height / 9)
            UIColor.black.withAlphaComponent(0.7).setFill(); cg.fill(bar)
            let font = UIFont.systemFont(ofSize: size.height / 26, weight: .semibold)
            (caption as NSString).draw(in: bar.insetBy(dx: size.width / 30, dy: size.height / 50),
                                       withAttributes: [.font: font, .foregroundColor: UIColor.white])
        }
    }

    /// Builds and saves one card per fault in the exchange.
    static func cards(for exchange: LabeledExchange, ring: EvidenceRing, language: String, stance: String) -> [EvidenceCard] {
        exchange.faults.compactMap { fault in
            guard let (image, joints) = ring.frame(near: moment(for: fault, in: exchange)) else { return nil }
            let annotated = render(image, joints: joints, fault: fault, language: language, stance: stance)
            let name = "evidence-\(Int(Date().timeIntervalSince1970))-\(exchange.id)-\(fault).jpg"
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("RoundLogs/evidence", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let jpeg = annotated.jpegData(compressionQuality: 0.75) { try? jpeg.write(to: folder.appendingPathComponent(name), options: .atomic) }
            return EvidenceCard(exchangeID: exchange.id, fault: fault, caption: captions[fault]?[language] ?? fault, image: annotated, fileName: name)
        }
    }
}
