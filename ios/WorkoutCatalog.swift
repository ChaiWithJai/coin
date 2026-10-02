import Foundation

/// A checked-in snapshot of the workout source. Importing a prescription never
/// turns it into evidence that the boxer performed the exercise.
struct WorkoutCatalog: Decodable {
    let schemaVersion: Int
    let workouts: [WorkoutLesson]
    var lessons: [WorkoutLesson] { workouts }
    var error: String? = nil

    enum CodingKeys: String, CodingKey { case schemaVersion, workouts }

    static let shared: WorkoutCatalog = {
        guard let url = Bundle.main.url(forResource: "WorkoutCatalog", withExtension: "json") else {
            return WorkoutCatalog(schemaVersion: 1, workouts: [], error: "WorkoutCatalog.json is missing.")
        }
        do { return try load(Data(contentsOf: url)) }
        catch { return WorkoutCatalog(schemaVersion: 1, workouts: [], error: error.localizedDescription) }
    }()

    static func load(_ data: Data) throws -> WorkoutCatalog {
        let catalog = try JSONDecoder().decode(WorkoutCatalog.self, from: data)
        guard catalog.schemaVersion == 1,
              Set(catalog.workouts.map(\.id)).count == catalog.workouts.count else {
            throw CatalogError.invalid("Unsupported catalog version or duplicate workout identifiers.")
        }
        for lesson in catalog.workouts {
            guard !lesson.id.isEmpty, !lesson.title.isEmpty, !lesson.blocks.isEmpty,
                  URL(string: lesson.sourceURL)?.scheme == "https" else {
                throw CatalogError.invalid("Incomplete source workout: \(lesson.id)")
            }
            for block in lesson.blocks {
                guard !block.title.isEmpty, !block.instructions.isEmpty,
                      (1...100).contains(block.rounds ?? 1),
                      (0...3600).contains(block.restSeconds ?? 0),
                      block.completion != .timed || (1...7200).contains(block.durationSeconds ?? 0) else {
                    throw CatalogError.invalid("Invalid block in \(lesson.id): \(block.id)")
                }
            }
        }
        return catalog
    }

    enum CatalogError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
    }
}

struct WorkoutLesson: Decodable, Identifiable {
    let id: String
    let program: String
    let week: Int
    let day: Int
    let title: String
    let focus: String?
    let sourceURL: String
    let sourcePDFURL: String?
    let sourceSHA256: String
    let blocks: [WorkoutSourceBlock]
    var programID: String { program }

    func template() -> TrainingTemplate {
        var roundNumber = 0
        let sessionBlocks = blocks.flatMap { source -> [SessionBlock] in
            let count = source.completion == .timed ? (source.rounds ?? 1) : 1
            return (0..<count).map { repetition in
                if source.kind == .boxing { roundNumber += 1 }
                // Rest belongs between repetitions. Do not invent a final rest
                // before the next source section, or a duration for rep work.
                let seconds = source.completion == .timed ? (source.durationSeconds ?? 0) : 0
                let rest = repetition < count - 1 ? (source.restSeconds ?? 0) : 0
                let prescription = [source.sets.map { "\($0) sets" }, source.reps]
                    .compactMap { $0 }.joined(separator: " · ")
                return SessionBlock(kind: source.kind ?? .exercise, minutes: seconds / 60,
                                    roundNumber: source.kind == .boxing ? roundNumber : nil,
                                    drillID: source.drillID, restAfterMinutes: rest / 60,
                                    durationSeconds: seconds, restAfterSeconds: rest,
                                    sourceTitle: source.title, sourceInstructions: source.instructions,
                                    sourceURL: source.sourceURL ?? sourceURL, sourceDemoURLs: source.demoURLs,
                                    sourceActivityKey: source.activityKey,
                                    sourceBlockID: source.id,
                                    repetitionText: prescription.isEmpty ? nil : prescription,
                                    completionMode: source.completion)
            }
        }
        let seconds = sessionBlocks.reduce(0) { $0 + $1.effectiveSeconds + $1.effectiveRestSeconds }
        return TrainingTemplate(id: id, durationMinutes: Int(ceil(Double(seconds) / 60)),
                                blocks: sessionBlocks, sourceTitle: title,
                                sourceURL: sourceURL, sourceVersion: sourceSHA256)
    }
}

struct WorkoutSourceBlock: Decodable, Identifiable {
    let id: String
    let title: String
    let instructions: String
    let kind: SessionBlockKind?
    let drillID: String?
    let activityKey: String?
    let rounds: Int?
    let durationSeconds: Int?
    let restSeconds: Int?
    let reps: String?
    let sets: Int?
    let completion: BlockCompletionMode
    let demoURLs: [String]?
    let sourceText: String?
    let sourceSectionIndex: Int?
    let sourceURL: String?
}
