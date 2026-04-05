import SwiftUI
import HealthKit
import Charts
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Data Models

enum CorrelationSource: String, Codable, Hashable {
    case aiDetected
    case userAdded
    case healthKit
}

enum PathfinderMode: String, CaseIterable, Identifiable {
    case reflect = "Reflect"
    case optimize = "Optimize"
    case express = "Express"
    case analyze = "Analyze"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .reflect: return "brain.head.profile"
        case .optimize: return "bolt.fill"
        case .express: return "lightbulb.fill"
        case .analyze: return "chart.bar.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .reflect: return "thoughts, emotions, meaning"
        case .optimize: return "habits, energy, experiments"
        case .express: return "ideas, unspoken things"
        case .analyze: return "problems, decisions, time"
        }
    }
}

enum NutrivanceAssociation: String, Codable, CaseIterable, Hashable, Identifiable {
    // HK-mapped
    case health, fitness, selfCare, hobbies, identity, spirituality
    case community, family, friends, partner, dating
    case tasks, work, education, travel, weather, currentEvents, money

    // Reflect
    case thoughtLoops, beliefsChallenged, mentalClarity
    case alignment, unexpressed, solitude, innerWorld

    // Optimize
    case energyLevels, focusQuality, motivation
    case habitsSystems, experiments, recovery

    // Express
    case ideas, curiosity, creativeSparks, suppressedReactions

    // Analyze
    case problems, decisions, timePerception
    case constraints, inputsInfluences, learning

    // Broadened workout
    case physicalOutput, bodyAwareness, goalsDirection, progressDrift

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .health: return "Health"
        case .fitness: return "Fitness"
        case .selfCare: return "Self-Care"
        case .hobbies: return "Hobbies"
        case .identity: return "Identity"
        case .spirituality: return "Spirituality"
        case .community: return "Community"
        case .family: return "Family"
        case .friends: return "Friends"
        case .partner: return "Partner"
        case .dating: return "Dating"
        case .tasks: return "Tasks"
        case .work: return "Work"
        case .education: return "Education"
        case .travel: return "Travel"
        case .weather: return "Weather"
        case .currentEvents: return "Current Events"
        case .money: return "Money"
        case .thoughtLoops: return "Thought Loops"
        case .beliefsChallenged: return "Beliefs Challenged"
        case .mentalClarity: return "Mental Clarity"
        case .alignment: return "Alignment & Meaning"
        case .unexpressed: return "Unexpressed Things"
        case .solitude: return "Solitude"
        case .innerWorld: return "Inner World"
        case .energyLevels: return "Energy Levels"
        case .focusQuality: return "Focus Quality"
        case .motivation: return "Motivation"
        case .habitsSystems: return "Habits & Systems"
        case .experiments: return "Experiments"
        case .recovery: return "Recovery"
        case .ideas: return "Ideas"
        case .curiosity: return "Curiosity"
        case .creativeSparks: return "Creative Sparks"
        case .suppressedReactions: return "Suppressed Reactions"
        case .problems: return "Problems & Friction"
        case .decisions: return "Decisions"
        case .timePerception: return "Time Perception"
        case .constraints: return "Constraints"
        case .inputsInfluences: return "Inputs & Influences"
        case .learning: return "Learning"
        case .physicalOutput: return "Physical Output"
        case .bodyAwareness: return "Body Awareness"
        case .goalsDirection: return "Goals & Direction"
        case .progressDrift: return "Progress vs Drift"
        }
    }

    var icon: String {
        switch self {
        case .health: return "heart.fill"
        case .fitness: return "figure.run"
        case .selfCare: return "sparkles"
        case .hobbies: return "paintpalette.fill"
        case .identity: return "person.fill"
        case .spirituality: return "leaf.fill"
        case .community: return "person.3.fill"
        case .family: return "house.fill"
        case .friends: return "person.2.fill"
        case .partner: return "heart.circle.fill"
        case .dating: return "heart.text.clipboard.fill"
        case .tasks: return "checkmark.circle.fill"
        case .work: return "briefcase.fill"
        case .education: return "graduationcap.fill"
        case .travel: return "airplane"
        case .weather: return "cloud.sun.fill"
        case .currentEvents: return "newspaper.fill"
        case .money: return "banknote.fill"
        case .thoughtLoops: return "arrow.triangle.2.circlepath"
        case .beliefsChallenged: return "exclamationmark.bubble.fill"
        case .mentalClarity: return "brain.head.profile"
        case .alignment: return "compass.drawing"
        case .unexpressed: return "mouth.fill"
        case .solitude: return "person.fill.questionmark"
        case .innerWorld: return "eye.fill"
        case .energyLevels: return "bolt.fill"
        case .focusQuality: return "scope"
        case .motivation: return "flame.fill"
        case .habitsSystems: return "repeat"
        case .experiments: return "flask.fill"
        case .recovery: return "bed.double.fill"
        case .ideas: return "lightbulb.fill"
        case .curiosity: return "questionmark.circle.fill"
        case .creativeSparks: return "wand.and.stars"
        case .suppressedReactions: return "hand.raised.fill"
        case .problems: return "exclamationmark.triangle.fill"
        case .decisions: return "arrow.triangle.branch"
        case .timePerception: return "clock.fill"
        case .constraints: return "lock.fill"
        case .inputsInfluences: return "arrow.down.circle.fill"
        case .learning: return "book.fill"
        case .physicalOutput: return "figure.strengthtraining.traditional"
        case .bodyAwareness: return "figure.mind.and.body"
        case .goalsDirection: return "target"
        case .progressDrift: return "chart.line.uptrend.xyaxis"
        }
    }

    var mode: PathfinderMode {
        switch self {
        case .thoughtLoops, .beliefsChallenged, .mentalClarity,
             .alignment, .unexpressed, .solitude, .innerWorld:
            return .reflect
        case .energyLevels, .focusQuality, .motivation,
             .habitsSystems, .experiments, .recovery:
            return .optimize
        case .ideas, .curiosity, .creativeSparks, .suppressedReactions:
            return .express
        case .problems, .decisions, .timePerception,
             .constraints, .inputsInfluences, .learning:
            return .analyze
        default:
            if Self.hkMappedCases.contains(self) { return .reflect }
            return .optimize
        }
    }

    static let hkMappedCases: Set<NutrivanceAssociation> = [
        .health, .fitness, .selfCare, .hobbies, .identity, .spirituality,
        .community, .family, .friends, .partner, .dating,
        .tasks, .work, .education, .travel, .weather, .currentEvents, .money
    ]

    static func associations(for mode: PathfinderMode) -> [NutrivanceAssociation] {
        allCases.filter { $0.mode == mode }
    }

    static func fromHKAssociation(_ hk: HKStateOfMind.Association) -> NutrivanceAssociation {
        switch hk {
        case .health: return .health
        case .fitness: return .fitness
        case .selfCare: return .selfCare
        case .hobbies: return .hobbies
        case .identity: return .identity
        case .spirituality: return .spirituality
        case .community: return .community
        case .family: return .family
        case .friends: return .friends
        case .partner: return .partner
        case .dating: return .dating
        case .tasks: return .tasks
        case .work: return .work
        case .education: return .education
        case .travel: return .travel
        case .weather: return .weather
        case .currentEvents: return .currentEvents
        case .money: return .money
        @unknown default: return .health
        }
    }
}

struct EmotionCorrelation: Identifiable, Codable, Hashable {
    let id: UUID
    var journalEntryID: UUID?
    var date: Date
    var emotionLabel: String
    var estimatedValence: Double
    var association: NutrivanceAssociation
    var contextNotes: String
    var source: CorrelationSource
    var isHKSynced: Bool

    init(
        id: UUID = UUID(),
        journalEntryID: UUID? = nil,
        date: Date = Date(),
        emotionLabel: String,
        estimatedValence: Double,
        association: NutrivanceAssociation,
        contextNotes: String = "",
        source: CorrelationSource = .aiDetected,
        isHKSynced: Bool = false
    ) {
        self.id = id
        self.journalEntryID = journalEntryID
        self.date = date
        self.emotionLabel = emotionLabel
        self.estimatedValence = estimatedValence
        self.association = association
        self.contextNotes = contextNotes
        self.source = source
        self.isHKSynced = isHKSynced
    }

    var valenceCategory: ValenceCategory {
        if estimatedValence > 0.2 { return .pleasant }
        if estimatedValence < -0.2 { return .unpleasant }
        return .neutral
    }

    enum ValenceCategory: String {
        case pleasant, unpleasant, neutral

        var color: Color {
            switch self {
            case .pleasant: return .green
            case .unpleasant: return .red
            case .neutral: return .gray
            }
        }

        var label: String { rawValue.capitalized }
    }
}

// MARK: - Correlation Store

@MainActor
final class CorrelationStore: ObservableObject {
    static let shared = CorrelationStore()

    @Published private(set) var correlations: [EmotionCorrelation] = []

    private let defaults = UserDefaults.standard
    private let cloud = NSUbiquitousKeyValueStore.default
    private let storageKey = "pathfinder_correlations_v1"

    private init() { load() }

    func load() {
        cloud.synchronize()
        let cloudEntries = decodeFrom(cloud.data(forKey: storageKey))
        let localEntries = decodeFrom(defaults.data(forKey: storageKey))
        correlations = mergeCorrelations(cloudEntries, localEntries)
    }

    func append(_ correlation: EmotionCorrelation) {
        let cloudEntries = decodeFrom(cloud.data(forKey: storageKey))
        let localEntries = decodeFrom(defaults.data(forKey: storageKey))
        correlations = mergeCorrelations(correlations, cloudEntries, localEntries, [correlation])
        save()
    }

    func appendBatch(_ newCorrelations: [EmotionCorrelation]) {
        guard !newCorrelations.isEmpty else { return }
        let cloudEntries = decodeFrom(cloud.data(forKey: storageKey))
        let localEntries = decodeFrom(defaults.data(forKey: storageKey))
        correlations = mergeCorrelations(correlations, cloudEntries, localEntries, newCorrelations)
        save()
    }

    func update(_ correlation: EmotionCorrelation) {
        if let idx = correlations.firstIndex(where: { $0.id == correlation.id }) {
            correlations[idx] = correlation
            save()
        }
    }

    func delete(_ id: UUID) {
        correlations.removeAll { $0.id == id }
        save()
    }

    func correlations(in range: ClosedRange<Date>) -> [EmotionCorrelation] {
        correlations.filter { range.contains($0.date) }
    }

    func correlations(for association: NutrivanceAssociation) -> [EmotionCorrelation] {
        correlations.filter { $0.association == association }
    }

    func correlations(forJournal entryID: UUID) -> [EmotionCorrelation] {
        correlations.filter { $0.journalEntryID == entryID }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(correlations) else { return }
        defaults.set(data, forKey: storageKey)
        cloud.set(data, forKey: storageKey)
        cloud.synchronize()
    }

    private func decodeFrom(_ data: Data?) -> [EmotionCorrelation] {
        guard let data, let decoded = try? JSONDecoder().decode([EmotionCorrelation].self, from: data) else { return [] }
        return decoded
    }

    private func mergeCorrelations(_ inputs: [EmotionCorrelation]...) -> [EmotionCorrelation] {
        var map: [UUID: EmotionCorrelation] = [:]
        for source in inputs {
            for c in source { map[c.id] = c }
        }
        return map.values.sorted { $0.date > $1.date }
    }
}

// MARK: - Correlation Detection Engine

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(
    description: "One emotional correlation from journal text. emotion: standard word. valence: -1.0 to 1.0. associationKey: one raw key from health, fitness, selfCare, hobbies, identity, spirituality, community, family, friends, partner, dating, tasks, work, education, travel, weather, currentEvents, money, thoughtLoops, beliefsChallenged, mentalClarity, alignment, unexpressed, solitude, innerWorld, energyLevels, focusQuality, motivation, habitsSystems, experiments, recovery, ideas, curiosity, creativeSparks, suppressedReactions, problems, decisions, timePerception, constraints, inputsInfluences, learning, physicalOutput, bodyAwareness, goalsDirection, progressDrift. contextSummary: one brief sentence."
)
struct DetectedCorrelationItem {
    var emotion: String
    var valence: Double
    var associationKey: String
    var contextSummary: String
}

@available(iOS 26.0, *)
@Generable(description: "A named person mentioned in the journal (not generic groups).")
struct DetectedPersonItem {
    var name: String
    var mentionContext: String
}

@available(iOS 26.0, *)
@Generable(description: "A short follow-up to disambiguate people or life areas. choiceAssociationKeys must parallel choiceLabels; use skip when that choice should not change correlation buckets.")
struct FollowUpClarifierItem {
    var question: String
    var choiceLabels: [String]
    var choiceAssociationKeys: [String]
    var linkedContextHint: String
    var linkedPersonName: String
}

@available(iOS 26.0, *)
@Generable(description: "Emotional correlations, named people, and quick-check follow-ups from a journal entry.")
struct DetectedCorrelationOutput {
    var correlations: [DetectedCorrelationItem]
    var mentionedPeople: [DetectedPersonItem]
    var followUpClarifiers: [FollowUpClarifierItem]
}
#endif

// MARK: - Journal correlation UI models (people + clarifiers)

struct JournalSuggestedPerson: Identifiable, Hashable {
    let id: UUID
    var name: String
    var mentionContext: String

    init(id: UUID = UUID(), name: String, mentionContext: String) {
        self.id = id
        self.name = name
        self.mentionContext = mentionContext
    }
}

struct JournalCorrelationClarifier: Identifiable, Hashable {
    let id: UUID
    var question: String
    var choices: [String]
    /// Parallel to choices: NutrivanceAssociation rawValue, or skip / empty.
    var associationKeys: [String]
    var linkedPersonName: String?
    var linkedContextHint: String
    /// Correlations this clarifier is meant to refine (may be empty → infer by name/hint on apply).
    var targetCorrelationIDs: [UUID]

    init(
        id: UUID = UUID(),
        question: String,
        choices: [String],
        associationKeys: [String],
        linkedPersonName: String?,
        linkedContextHint: String,
        targetCorrelationIDs: [UUID] = []
    ) {
        self.id = id
        self.question = question
        self.choices = choices
        self.associationKeys = associationKeys
        self.linkedPersonName = linkedPersonName
        self.linkedContextHint = linkedContextHint
        self.targetCorrelationIDs = targetCorrelationIDs
    }
}

@MainActor
final class JournalCorrelationEngine: ObservableObject {
    @Published var detectedCorrelations: [EmotionCorrelation] = []
    @Published var suggestedPeople: [JournalSuggestedPerson] = []
    @Published var correlationClarifiers: [JournalCorrelationClarifier] = []
    private var analysisTask: Task<Void, Never>?

    func analyzeText(_ text: String, journalEntryID: UUID?, referenceDate: Date) {
        analysisTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 15 else {
            withAnimation {
                detectedCorrelations = []
                suggestedPeople = []
                correlationClarifiers = []
            }
            return
        }

        analysisTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }

            var results: [EmotionCorrelation] = []
            var people: [JournalSuggestedPerson] = []
            var clarifiers: [JournalCorrelationClarifier] = []

            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                let model = SystemLanguageModel(useCase: .general)
                if model.isAvailable {
                    if let pack = await analyzeWithFoundationModels(text: trimmed, journalEntryID: journalEntryID, referenceDate: referenceDate) {
                        results = pack.correlations
                        people = pack.people
                        clarifiers = pack.clarifiers
                    }
                }
            }
            #endif

            if results.isEmpty {
                results = analyzeWithRegex(text: trimmed, journalEntryID: journalEntryID, referenceDate: referenceDate)
            }
            if people.isEmpty {
                people = extractPeopleHeuristic(from: trimmed)
            }
            clarifiers = Self.resolveClarifierTargets(clarifiers, correlations: results)

            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                detectedCorrelations = results
                suggestedPeople = people
                correlationClarifiers = clarifiers
            }
        }
    }

    func clear() {
        analysisTask?.cancel()
        withAnimation {
            detectedCorrelations = []
            suggestedPeople = []
            correlationClarifiers = []
        }
    }

    // MARK: - Foundation Models Path

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func analyzeWithFoundationModels(
        text: String,
        journalEntryID: UUID?,
        referenceDate: Date
    ) async -> (correlations: [EmotionCorrelation], people: [JournalSuggestedPerson], clarifiers: [JournalCorrelationClarifier])? {
        let model = SystemLanguageModel(useCase: .general)
        guard model.isAvailable else { return nil }

        do {
            let session = LanguageModelSession(
                model: model,
                instructions: """
                You are an emotional intelligence analyst for journal entries.

                correlations: For each distinct emotion expressed or implied, output emotion, valence (-1…1), associationKey (exact raw key from the allowed set), and a brief contextSummary (quote-like snippet from the entry).
                School, class, teacher, professor, homework, lecture, exam, study session → associationKey education (not work). Job, boss, office, deadline without school context → work.
                Only extract emotions clearly present. At most 5 correlations.

                mentionedPeople: Proper names and titled names (e.g. Frank, Mr. Hale). Skip vague "someone". mentionContext: short phrase showing how they appear (≤120 chars).

                followUpClarifiers: 2–6 quick checks the app will show as multiple choice. Include:
                - For each important person: "Who is [Name] to you?" (or similar) with choices like Friend, Family, Teacher/professor, Coworker, Partner, Not sure.
                - When school vs work could be confused (e.g. "Mr. Hale's class", "meeting about grades"): ask which bucket fits with 3–5 choices (Education, Work, Friends/social, Other, Not sure).
                - When a relationship affects how to read the entry, add one disambiguation question.
                choiceLabels: 3–5 short options (≤6 words each). choiceAssociationKeys must parallel choiceLabels: use friends, family, partner, work, education, skip. Use skip for "Not sure" or when picking that option should not set a life-area bucket. Use education for teacher/classmate/study; work for job/coworker; friends for friend/social.
                linkedPersonName: the person's name if the question is about them, else empty string.
                linkedContextHint: a distinctive substring from the entry that identifies which sentence/clause this question clarifies (so the app can match correlations); empty string if not needed.
                """
            )

            let truncated = String(text.prefix(2000))
            let response = try await session.respond(to: truncated, generating: DetectedCorrelationOutput.self)
            let content = response.content

            let correlations: [EmotionCorrelation] = content.correlations.prefix(5).compactMap { item in
                let assoc = NutrivanceAssociation(rawValue: item.associationKey) ?? guessAssociation(from: item.contextSummary)
                return EmotionCorrelation(
                    journalEntryID: journalEntryID,
                    date: referenceDate,
                    emotionLabel: item.emotion.lowercased(),
                    estimatedValence: max(-1, min(1, item.valence)),
                    association: assoc,
                    contextNotes: item.contextSummary,
                    source: .aiDetected
                )
            }

            let people: [JournalSuggestedPerson] = content.mentionedPeople.prefix(6).compactMap { p in
                let name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard name.count >= 2 else { return nil }
                let ctx = String(p.mentionContext.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
                return JournalSuggestedPerson(name: name, mentionContext: ctx)
            }

            let clarifiers: [JournalCorrelationClarifier] = content.followUpClarifiers.prefix(8).compactMap { item in
                Self.clarifierFromModelItem(item)
            }

            return (correlations, people, clarifiers)
        } catch {
            return nil
        }
    }

    private static func clarifierFromModelItem(_ item: FollowUpClarifierItem) -> JournalCorrelationClarifier? {
        let labels = item.choiceLabels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard labels.count >= 2, labels.count <= 6 else { return nil }

        var keys = item.choiceAssociationKeys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        while keys.count < labels.count { keys.append("skip") }
        keys = keys.prefix(labels.count).map { raw in
            if raw.isEmpty || raw == "none" { return "skip" }
            if raw == "skip" { return "skip" }
            if NutrivanceAssociation(rawValue: raw) != nil { return raw }
            return "skip"
        }

        let person = item.linkedPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
        let hint = item.linkedContextHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = item.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }

        return JournalCorrelationClarifier(
            question: q,
            choices: Array(labels.prefix(6)),
            associationKeys: Array(keys.prefix(labels.count)),
            linkedPersonName: person.isEmpty ? nil : person,
            linkedContextHint: hint,
            targetCorrelationIDs: []
        )
    }
    #endif

    private static func resolveClarifierTargets(_ items: [JournalCorrelationClarifier], correlations: [EmotionCorrelation]) -> [JournalCorrelationClarifier] {
        items.map { c in
            var copy = c
            if copy.targetCorrelationIDs.isEmpty {
                copy.targetCorrelationIDs = correlationIDs(matching: c, in: correlations)
            }
            return copy
        }
    }

    private static func correlationIDs(matching clarifier: JournalCorrelationClarifier, in correlations: [EmotionCorrelation]) -> [UUID] {
        let hint = clarifier.linkedContextHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let person = clarifier.linkedPersonName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var ids: [UUID] = []
        if hint.count >= 3 {
            ids = correlations.filter { $0.contextNotes.localizedCaseInsensitiveContains(hint) }.map(\.id)
        }
        if ids.isEmpty, person.count >= 2 {
            ids = correlations.filter { $0.contextNotes.localizedCaseInsensitiveContains(person) }.map(\.id)
        }
        return Array(Set(ids))
    }

    private func extractPeopleHeuristic(from text: String) -> [JournalSuggestedPerson] {
        var out: [JournalSuggestedPerson] = []
        let ns = text as NSString

        let titled = try? NSRegularExpression(pattern: #"\b(Mr|Mrs|Ms|Dr)\.?\s+([A-Z][a-z]+)\b"#, options: [])
        titled?.enumerateMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }
            let last = ns.substring(with: match.range(at: 2))
            let full = ns.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            if last.count >= 2 {
                out.append(JournalSuggestedPerson(name: full, mentionContext: String(full.prefix(80))))
            }
        }

        let friend = try? NSRegularExpression(pattern: #"\bfriend\s+([A-Z][a-z]+)\b"#, options: .caseInsensitive)
        friend?.enumerateMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let name = ns.substring(with: match.range(at: 1))
            if name.count >= 2 {
                out.append(JournalSuggestedPerson(name: name, mentionContext: "friend \(name)"))
            }
        }

        var seen = Set<String>()
        return out.filter { seen.insert($0.name.lowercased()).inserted }
    }

    // MARK: - Regex Fallback

    private func analyzeWithRegex(text: String, journalEntryID: UUID?, referenceDate: Date) -> [EmotionCorrelation] {
        let lower = text.lowercased()
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var results: [EmotionCorrelation] = []
        var usedAssociations: Set<NutrivanceAssociation> = []

        let emotionPatterns: [(keywords: [String], emotion: String, valence: Double)] = [
            (["wonderful", "amazing", "fantastic", "incredible", "awesome"], "joyful", 0.9),
            (["great", "excellent", "brilliant"], "happy", 0.8),
            (["good", "nice", "pleasant", "fine"], "content", 0.5),
            (["happy", "glad", "pleased", "delighted"], "happy", 0.75),
            (["grateful", "thankful", "blessed", "appreciative"], "grateful", 0.8),
            (["excited", "thrilled", "pumped", "hyped", "stoked"], "excited", 0.85),
            (["proud", "accomplished", "achieved"], "proud", 0.7),
            (["peaceful", "serene", "tranquil", "calm", "relaxed"], "peaceful", 0.6),
            (["hopeful", "optimistic", "looking forward"], "hopeful", 0.6),
            (["fun", "enjoyable", "blast", "hilarious", "entertaining"], "joyful", 0.7),
            (["okay", "alright", "decent", "so-so", "meh"], "indifferent", 0.0),
            (["tired", "exhausted", "drained", "fatigued", "burnt out", "burnout"], "drained", -0.5),
            (["stressed", "overwhelmed", "anxious", "tense", "worried"], "stressed", -0.6),
            (["sad", "down", "unhappy", "depressed", "miserable"], "sad", -0.7),
            (["angry", "furious", "mad", "pissed", "irritated", "annoyed"], "angry", -0.7),
            (["frustrated", "stuck", "struggling"], "frustrated", -0.5),
            (["lonely", "alone", "isolated"], "lonely", -0.6),
            (["disappointed", "letdown", "let down"], "disappointed", -0.5),
            (["scared", "afraid", "frightened", "terrified"], "scared", -0.7),
            (["boring", "bored", "tedious", "monotonous"], "bored", -0.3),
            (["sucks", "terrible", "horrible", "awful", "worst"], "disappointed", -0.8),
            (["challenging", "tough", "hard", "difficult"], "determined", -0.2),
            (["disaster", "catastrophe", "ruined"], "overwhelmed", -0.85),
        ]

        let associationKeywords: [(keywords: [String], association: NutrivanceAssociation)] = [
            (["friend", "friends", "buddy", "mates", "hangout", "hang out"], .friends),
            (["family", "mom", "dad", "parent", "sibling", "brother", "sister", "son", "daughter"], .family),
            (["partner", "wife", "husband", "spouse", "bf", "gf", "boyfriend", "girlfriend"], .partner),
            (["date", "dating", "tinder", "bumble"], .dating),
            (["work", "office", "job", "boss", "colleague", "meeting", "deadline"], .work),
            (["school", "class", "study", "exam", "university", "college", "homework", "lecture"], .education),
            (["cycling", "running", "swimming", "workout", "gym", "exercise", "training", "lifting", "hiking"], .fitness),
            (["sleep", "slept", "nap", "insomnia", "rest", "bedtime"], .health),
            (["travel", "trip", "vacation", "holiday", "flight", "hotel"], .travel),
            (["money", "budget", "salary", "expensive", "cost", "financial", "debt", "savings"], .money),
            (["hobby", "paint", "draw", "music", "guitar", "piano", "game", "gaming", "reading", "cook"], .hobbies),
            (["pray", "church", "meditat", "spiritual", "temple", "mosque", "faith"], .spirituality),
            (["community", "volunteer", "neighborhood", "social"], .community),
            (["weather", "rain", "sunny", "cold", "hot", "storm"], .weather),
            (["news", "politics", "election", "war", "climate"], .currentEvents),
            (["think", "thought", "mind", "mental", "overthink", "ruminating"], .thoughtLoops),
            (["decision", "chose", "choice", "deciding", "dilemma"], .decisions),
            (["energy", "energized", "sluggish", "lethargic", "wired"], .energyLevels),
            (["focus", "concentrate", "distracted", "productive", "flow"], .focusQuality),
            (["idea", "inspiration", "creative", "brainstorm", "eureka"], .ideas),
            (["habit", "routine", "consistency", "discipline"], .habitsSystems),
            (["goal", "ambition", "dream", "aspiration", "purpose"], .goalsDirection),
            (["time", "rushed", "slow", "fast", "hours flew", "dragged"], .timePerception),
            (["problem", "issue", "annoy", "friction", "bottleneck"], .problems),
            (["learn", "realized", "insight", "mistake", "lesson"], .learning),
            (["identity", "myself", "who i am", "self", "character"], .identity),
            (["health", "sick", "doctor", "medicine", "pain", "ill"], .health),
            (["eating", "food", "meal", "restaurant", "dining", "lunch", "dinner", "breakfast"], .selfCare),
        ]

        for sentence in sentences {
            let sentLower = sentence.lowercased()
            var bestEmotion: (emotion: String, valence: Double)? = nil
            var bestConfidence = 0

            for pattern in emotionPatterns {
                let matchCount = pattern.keywords.filter { sentLower.contains($0) }.count
                if matchCount > bestConfidence {
                    bestConfidence = matchCount
                    bestEmotion = (pattern.emotion, pattern.valence)
                }
            }

            guard let emotion = bestEmotion, bestConfidence > 0 else { continue }

            var assoc: NutrivanceAssociation = .health
            var assocScore = 0
            for ak in associationKeywords {
                let score = ak.keywords.filter { sentLower.contains($0) }.count
                if score > assocScore {
                    assocScore = score
                    assoc = ak.association
                }
            }

            guard !usedAssociations.contains(assoc) || assocScore > 1 else { continue }
            usedAssociations.insert(assoc)

            let contextNote = sentence.count > 80 ? String(sentence.prefix(77)) + "..." : sentence
            results.append(EmotionCorrelation(
                journalEntryID: journalEntryID,
                date: referenceDate,
                emotionLabel: emotion.emotion,
                estimatedValence: emotion.valence,
                association: assoc,
                contextNotes: contextNote,
                source: .aiDetected
            ))

            if results.count >= 5 { break }
        }

        return results
    }

    private func guessAssociation(from text: String) -> NutrivanceAssociation {
        let lower = text.lowercased()
        let quickMap: [(String, NutrivanceAssociation)] = [
            ("friend", .friends), ("family", .family), ("work", .work),
            ("fitness", .fitness), ("exercise", .fitness), ("workout", .fitness),
            ("health", .health), ("sleep", .health), ("school", .education),
            ("money", .money), ("travel", .travel), ("partner", .partner),
            ("hobby", .hobbies), ("identity", .identity), ("spiritual", .spirituality),
        ]
        for (key, assoc) in quickMap {
            if lower.contains(key) { return assoc }
        }
        return .health
    }
}

// MARK: - HK Deduplication

struct SynthesizedCorrelation: Identifiable {
    let id: UUID
    let correlation: EmotionCorrelation
    let isDuplicate: Bool

    init(correlation: EmotionCorrelation, isDuplicate: Bool = false) {
        self.id = correlation.id
        self.correlation = correlation
        self.isDuplicate = isDuplicate
    }
}

@MainActor
func synthesizeCorrelations(local: [EmotionCorrelation], hkStates: [HKStateOfMind]) -> [SynthesizedCorrelation] {
    var results: [SynthesizedCorrelation] = []
    var usedHKDates: Set<String> = []

    let dateFormatter = ISO8601DateFormatter()
    dateFormatter.formatOptions = [.withFullDate, .withTime]

    for corr in local {
        results.append(SynthesizedCorrelation(correlation: corr))
        let key = "\(dateFormatter.string(from: corr.date))|\(corr.emotionLabel)"
        usedHKDates.insert(key)
    }

    for state in hkStates {
        let stateDate = state.startDate
        let label = hkLabelString(state.labels.first)
        let key = "\(dateFormatter.string(from: stateDate))|\(label)"

        let isDup = local.contains { corr in
            abs(corr.date.timeIntervalSince(stateDate)) < 3600
                && corr.emotionLabel == label
                && abs(corr.estimatedValence - state.valence) < 0.2
        }

        if !isDup {
            let assoc: NutrivanceAssociation = state.associations.first.map { NutrivanceAssociation.fromHKAssociation($0) } ?? .health
            let hkCorr = EmotionCorrelation(
                date: stateDate,
                emotionLabel: label,
                estimatedValence: state.valence,
                association: assoc,
                contextNotes: "Logged via HealthKit",
                source: .healthKit,
                isHKSynced: true
            )
            results.append(SynthesizedCorrelation(correlation: hkCorr))
        }
    }

    return results.sorted { $0.correlation.date > $1.correlation.date }
}

private func hkLabelString(_ label: HKStateOfMind.Label?) -> String {
    guard let label else { return "unknown" }
    switch label {
    case .amazed: return "amazed"
    case .amused: return "amused"
    case .angry: return "angry"
    case .anxious: return "anxious"
    case .ashamed: return "ashamed"
    case .brave: return "brave"
    case .calm: return "calm"
    case .confident: return "confident"
    case .content: return "content"
    case .disappointed: return "disappointed"
    case .discouraged: return "discouraged"
    case .disgusted: return "disgusted"
    case .drained: return "drained"
    case .embarrassed: return "embarrassed"
    case .excited: return "excited"
    case .frustrated: return "frustrated"
    case .grateful: return "grateful"
    case .guilty: return "guilty"
    case .happy: return "happy"
    case .hopeful: return "hopeful"
    case .hopeless: return "hopeless"
    case .indifferent: return "indifferent"
    case .irritated: return "irritated"
    case .jealous: return "jealous"
    case .joyful: return "joyful"
    case .lonely: return "lonely"
    case .overwhelmed: return "overwhelmed"
    case .passionate: return "passionate"
    case .peaceful: return "peaceful"
    case .proud: return "proud"
    case .relieved: return "relieved"
    case .sad: return "sad"
    case .satisfied: return "satisfied"
    case .scared: return "scared"
    case .stressed: return "stressed"
    case .surprised: return "surprised"
    case .worried: return "worried"
    case .annoyed: return "annoyed"
    @unknown default: return "unknown"
    }
}

// MARK: - Emotion Helpers

func emotionIcon(for label: String) -> String {
    switch label.lowercased() {
    case "happy", "joyful": return "face.smiling.inverse"
    case "content", "satisfied", "relieved": return "face.smiling"
    case "excited", "passionate", "amazed": return "star.fill"
    case "grateful", "hopeful", "proud": return "heart.fill"
    case "calm", "peaceful": return "leaf.fill"
    case "brave", "confident", "determined": return "shield.fill"
    case "sad", "disappointed", "discouraged", "hopeless": return "cloud.rain.fill"
    case "angry", "frustrated", "irritated", "annoyed": return "flame.fill"
    case "anxious", "worried", "stressed", "overwhelmed", "scared": return "exclamationmark.triangle.fill"
    case "lonely", "isolated": return "person.fill.questionmark"
    case "drained", "exhausted", "bored": return "battery.25percent"
    case "indifferent": return "minus.circle"
    case "guilty", "ashamed", "embarrassed": return "eye.slash.fill"
    default: return "circle.fill"
    }
}

// MARK: - Date Range

enum PathfinderDateRange: String, CaseIterable, Identifiable {
    case day = "1D"
    case week = "1W"
    case month = "1M"
    case custom = "Custom"

    var id: String { rawValue }

    func dateRange(from anchor: Date) -> ClosedRange<Date> {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: anchor)) ?? anchor
        let start: Date
        switch self {
        case .day: start = cal.startOfDay(for: anchor)
        case .week: start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: anchor)) ?? anchor
        case .month: start = cal.date(byAdding: .month, value: -1, to: cal.startOfDay(for: anchor)) ?? anchor
        case .custom: start = cal.date(byAdding: .month, value: -1, to: cal.startOfDay(for: anchor)) ?? anchor
        }
        return start...end
    }
}

// MARK: - PathfinderView

struct PathfinderView: View {
    @StateObject private var store = CorrelationStore.shared
    @State private var selectedMode: PathfinderMode? = nil
    @State private var selectedDateRange: PathfinderDateRange = .week
    @State private var anchorDate = Date()
    @State private var searchText = ""
    @State private var hkStates: [HKStateOfMind] = []
    @State private var showAddSheet = false
    @State private var editingCorrelation: EmotionCorrelation? = nil
    @State private var showDatePicker = false

    private var dateRange: ClosedRange<Date> {
        selectedDateRange.dateRange(from: anchorDate)
    }

    private var filteredCorrelations: [SynthesizedCorrelation] {
        let local = store.correlations(in: dateRange)
        let hkInRange = hkStates.filter { dateRange.contains($0.startDate) }
        var synth = synthesizeCorrelations(local: local, hkStates: hkInRange)

        if let mode = selectedMode {
            let modeAssociations = Set(NutrivanceAssociation.associations(for: mode))
            synth = synth.filter { modeAssociations.contains($0.correlation.association) }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            synth = synth.filter {
                $0.correlation.emotionLabel.lowercased().contains(query)
                || $0.correlation.association.displayName.lowercased().contains(query)
                || $0.correlation.contextNotes.lowercased().contains(query)
            }
        }

        return synth
    }

    private var statsCorrelations: [EmotionCorrelation] {
        filteredCorrelations.map(\.correlation)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackgrounds().programBuilderMeshBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        searchBar
                        dateRangeSection
                        modeTabsSection

                        phase2QuestSection
                        journalNudge
                        phase3GemSection
                        phase2AISection

                        statsSection
                        phase3StatSection

                        correlationListSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Pathfinder")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddCorrelationSheet { correlation in
                    store.append(correlation)
                }
            }
            .sheet(item: $editingCorrelation) { correlation in
                EditCorrelationSheet(correlation: correlation) { updated in
                    store.update(updated)
                }
            }
            .sheet(isPresented: $showDatePicker) {
                DatePicker("Select Date", selection: $anchorDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .presentationDetents([.medium])
            }
            .task { await loadHKStates() }
            .onChange(of: anchorDate) { _, _ in Task { await loadHKStates() } }
            .onChange(of: selectedDateRange) { _, _ in Task { await loadHKStates() } }
            .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
                store.load()
            }
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search correlations...", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Date Range

    private var dateRangeSection: some View {
        HStack(spacing: 8) {
            ForEach(PathfinderDateRange.allCases) { range in
                Button {
                    if range == .custom {
                        showDatePicker = true
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) {
                            selectedDateRange = range
                            anchorDate = Date()
                        }
                    }
                } label: {
                    Text(range.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            selectedDateRange == range
                            ? AnyShapeStyle(Color.orange)
                            : AnyShapeStyle(Color.white.opacity(0.08)),
                            in: Capsule()
                        )
                        .foregroundStyle(selectedDateRange == range ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Mode Tabs

    private var modeTabsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                modeChip(nil, label: "All", icon: "square.grid.2x2.fill")
                ForEach(PathfinderMode.allCases) { mode in
                    modeChip(mode, label: mode.rawValue, icon: mode.icon)
                }
            }
        }
    }

    private func modeChip(_ mode: PathfinderMode?, label: String, icon: String) -> some View {
        let isSelected = selectedMode == mode
        return Button {
            withAnimation(.easeOut(duration: 0.2)) {
                selectedMode = mode
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected ? AnyShapeStyle(Color.orange.opacity(0.8)) : AnyShapeStyle(Color.white.opacity(0.08)),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Emotional Overview")
                .font(.headline)

            if statsCorrelations.isEmpty {
                Text("No data for this period. Write in your journal to detect correlations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                valenceBreakdownBar
                topAssociationsSection
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var valenceBreakdownBar: some View {
        let total = Double(statsCorrelations.count)
        let pleasant = Double(statsCorrelations.filter { $0.valenceCategory == .pleasant }.count)
        let unpleasant = Double(statsCorrelations.filter { $0.valenceCategory == .unpleasant }.count)
        let neutral = Double(statsCorrelations.filter { $0.valenceCategory == .neutral }.count)

        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    if pleasant > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green)
                            .frame(width: geo.size.width * (pleasant / total))
                    }
                    if neutral > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray)
                            .frame(width: geo.size.width * (neutral / total))
                    }
                    if unpleasant > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red)
                            .frame(width: geo.size.width * (unpleasant / total))
                    }
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())

            HStack(spacing: 16) {
                statLabel("Pleasant", count: Int(pleasant), total: Int(total), color: .green)
                statLabel("Neutral", count: Int(neutral), total: Int(total), color: .gray)
                statLabel("Unpleasant", count: Int(unpleasant), total: Int(total), color: .red)
            }
            .font(.caption)
        }
    }

    private func statLabel(_ title: String, count: Int, total: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(title) \(total > 0 ? "\(count * 100 / total)%" : "0%")")
                .foregroundStyle(.secondary)
        }
    }

    private var topAssociationsSection: some View {
        let grouped = Dictionary(grouping: statsCorrelations, by: \.association)
        let sorted = grouped.sorted { $0.value.count > $1.value.count }.prefix(5)
        let total = Double(statsCorrelations.count)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Top Contributors")
                .font(.subheadline.weight(.semibold))

            ForEach(Array(sorted), id: \.key) { assoc, items in
                let pct = total > 0 ? Double(items.count) / total : 0
                let avgValence = items.map(\.estimatedValence).reduce(0, +) / Double(items.count)
                let valColor: Color = avgValence > 0.2 ? .green : (avgValence < -0.2 ? .red : .gray)

                HStack(spacing: 8) {
                    Image(systemName: assoc.icon)
                        .font(.caption)
                        .foregroundStyle(valColor)
                        .frame(width: 20)
                    Text(assoc.displayName)
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(pct * 100))%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(valColor)
                }

                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(valColor.opacity(0.4))
                        .frame(width: geo.size.width * pct)
                }
                .frame(height: 4)
            }
        }
    }

    // MARK: - Correlation List

    private var correlationListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Correlations")
                    .font(.headline)
                Spacer()
                Text("\(filteredCorrelations.count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1), in: Capsule())
            }

            if filteredCorrelations.isEmpty {
                Text("No correlations found for this period and filter.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(filteredCorrelations) { synth in
                    CorrelationCardView(
                        correlation: synth.correlation,
                        onEdit: { editingCorrelation = synth.correlation },
                        onDelete: {
                            if synth.correlation.source != .healthKit {
                                store.delete(synth.correlation.id)
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - HK Loading

    private func loadHKStates() async {
        let range = dateRange
        let hkm = HealthKitManager()
        hkStates = await hkm.fetchStateOfMindSamples(from: range.lowerBound, to: range.upperBound)
    }
}

// MARK: - Correlation Card

struct CorrelationCardView: View {
    let correlation: EmotionCorrelation
    var onEdit: () -> Void
    var onDelete: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: emotionIcon(for: correlation.emotionLabel))
                    .font(.title3)
                    .foregroundStyle(correlation.valenceCategory.color)
                    .frame(width: 32, height: 32)
                    .background(correlation.valenceCategory.color.opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(correlation.emotionLabel.capitalized)
                            .font(.subheadline.weight(.semibold))

                        Text(correlation.association.displayName)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    }

                    Text(correlation.date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                sourceBadge

                valenceIndicator
            }

            if isExpanded && !correlation.contextNotes.isEmpty {
                Text(correlation.contextNotes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 42)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { isExpanded.toggle() } }
        .contextMenu {
            Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            if correlation.source != .healthKit {
                Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .swipeActions(edge: .trailing) {
            if correlation.source != .healthKit {
                Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    private var sourceBadge: some View {
        Group {
            switch correlation.source {
            case .aiDetected:
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.purple)
            case .userAdded:
                Image(systemName: "person.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            case .healthKit:
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.pink)
            }
        }
    }

    private var valenceIndicator: some View {
        let v = correlation.estimatedValence
        return Text(v >= 0 ? String(format: "+%.1f", v) : String(format: "%.1f", v))
            .font(.caption.monospaced())
            .foregroundStyle(correlation.valenceCategory.color)
    }
}

// MARK: - Add Correlation Sheet

struct AddCorrelationSheet: View {
    var onSave: (EmotionCorrelation) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var emotionLabel = "happy"
    @State private var valence = 0.5
    @State private var selectedAssociation: NutrivanceAssociation = .health
    @State private var contextNotes = ""
    @State private var selectedMode: PathfinderMode = .reflect

    private let emotionOptions = [
        "happy", "content", "excited", "grateful", "proud", "calm", "peaceful", "hopeful", "joyful",
        "indifferent", "bored",
        "sad", "angry", "anxious", "stressed", "frustrated", "lonely", "disappointed", "drained", "overwhelmed"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Emotion") {
                    Picker("Emotion", selection: $emotionLabel) {
                        ForEach(emotionOptions, id: \.self) { e in
                            HStack {
                                Image(systemName: emotionIcon(for: e))
                                Text(e.capitalized)
                            }
                            .tag(e)
                        }
                    }
                }

                Section("Valence") {
                    VStack {
                        Slider(value: $valence, in: -1...1, step: 0.1)
                        HStack {
                            Text("Very Negative")
                                .font(.caption2)
                                .foregroundStyle(.red)
                            Spacer()
                            Text(String(format: "%.1f", valence))
                                .font(.caption.monospaced().weight(.semibold))
                            Spacer()
                            Text("Very Positive")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                }

                Section("Association") {
                    Picker("Mode", selection: $selectedMode) {
                        ForEach(PathfinderMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    let associations = NutrivanceAssociation.associations(for: selectedMode)
                    Picker("Category", selection: $selectedAssociation) {
                        ForEach(associations) { assoc in
                            HStack {
                                Image(systemName: assoc.icon)
                                Text(assoc.displayName)
                            }
                            .tag(assoc)
                        }
                    }
                }

                Section("Notes") {
                    TextField("What's the context?", text: $contextNotes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Correlation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let correlation = EmotionCorrelation(
                            date: Date(),
                            emotionLabel: emotionLabel,
                            estimatedValence: valence,
                            association: selectedAssociation,
                            contextNotes: contextNotes,
                            source: .userAdded
                        )
                        onSave(correlation)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Edit Correlation Sheet

struct EditCorrelationSheet: View {
    @State var correlation: EmotionCorrelation
    var onSave: (EmotionCorrelation) -> Void
    @Environment(\.dismiss) private var dismiss

    private let emotionOptions = [
        "happy", "content", "excited", "grateful", "proud", "calm", "peaceful", "hopeful", "joyful",
        "indifferent", "bored",
        "sad", "angry", "anxious", "stressed", "frustrated", "lonely", "disappointed", "drained", "overwhelmed"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Emotion") {
                    Picker("Emotion", selection: $correlation.emotionLabel) {
                        ForEach(emotionOptions, id: \.self) { e in
                            HStack {
                                Image(systemName: emotionIcon(for: e))
                                Text(e.capitalized)
                            }
                            .tag(e)
                        }
                    }
                }

                Section("Valence") {
                    VStack {
                        Slider(value: $correlation.estimatedValence, in: -1...1, step: 0.1)
                        HStack {
                            Text("Very Negative").font(.caption2).foregroundStyle(.red)
                            Spacer()
                            Text(String(format: "%.1f", correlation.estimatedValence))
                                .font(.caption.monospaced().weight(.semibold))
                            Spacer()
                            Text("Very Positive").font(.caption2).foregroundStyle(.green)
                        }
                    }
                }

                Section("Association") {
                    Picker("Category", selection: $correlation.association) {
                        ForEach(NutrivanceAssociation.allCases) { assoc in
                            HStack {
                                Image(systemName: assoc.icon)
                                Text(assoc.displayName)
                            }
                            .tag(assoc)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Context notes", text: $correlation.contextNotes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Correlation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(correlation)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Phase 2: Path Quest System

enum PathChoice: String, Codable, CaseIterable, Identifiable {
    case recover = "Recover"
    case push = "Push"
    case reset = "Reset"
    case explore = "Explore"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .recover: return "bed.double.fill"
        case .push: return "flame.fill"
        case .reset: return "arrow.counterclockwise"
        case .explore: return "safari.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .recover: return "Prioritize sleep + low strain"
        case .push: return "Lean into high performance"
        case .reset: return "Fix inconsistency"
        case .explore: return "Try something different"
        }
    }

    var accentColor: Color {
        switch self {
        case .recover: return .blue
        case .push: return .orange
        case .reset: return .purple
        case .explore: return .green
        }
    }
}

struct PathSubQuest: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var progress: Double
    var isCompleted: Bool
    var trackedByNutrivance: Bool

    init(id: UUID = UUID(), title: String, progress: Double = 0, isCompleted: Bool = false, trackedByNutrivance: Bool = false) {
        self.id = id
        self.title = title
        self.progress = progress
        self.isCompleted = isCompleted
        self.trackedByNutrivance = trackedByNutrivance
    }
}

struct PathQuest: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var pathChoice: String
    var focusAreas: [String]
    var subQuests: [PathSubQuest]
    var aiEncouragement: String
    var createdAt: Date
    var isActive: Bool

    init(id: UUID = UUID(), title: String, pathChoice: PathChoice, focusAreas: [NutrivanceAssociation], subQuests: [PathSubQuest] = [], aiEncouragement: String = "", isActive: Bool = true) {
        self.id = id
        self.title = title
        self.pathChoice = pathChoice.rawValue
        self.focusAreas = focusAreas.map(\.rawValue)
        self.subQuests = subQuests
        self.aiEncouragement = aiEncouragement
        self.createdAt = Date()
        self.isActive = isActive
    }

    var choice: PathChoice { PathChoice(rawValue: pathChoice) ?? .explore }
    var associations: [NutrivanceAssociation] { focusAreas.compactMap { NutrivanceAssociation(rawValue: $0) } }
    var overallProgress: Double {
        guard !subQuests.isEmpty else { return 0 }
        return subQuests.map(\.progress).reduce(0, +) / Double(subQuests.count)
    }
}

// MARK: - Phase 3: Stat / Gem System

struct PathfinderGem: Identifiable, Codable, Hashable {
    let id: UUID
    var label: String
    var associationKey: String
    var charge: Double

    init(id: UUID = UUID(), label: String, association: NutrivanceAssociation, charge: Double = 0) {
        self.id = id
        self.label = label
        self.associationKey = association.rawValue
        self.charge = charge
    }

    var association: NutrivanceAssociation { NutrivanceAssociation(rawValue: associationKey) ?? .health }
    var isCharged: Bool { charge >= 1.0 }
}

struct PathfinderStat: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var associationKey: String
    var level: Int
    var isFocused: Bool

    init(id: UUID = UUID(), name: String, association: NutrivanceAssociation, level: Int = 1, isFocused: Bool = false) {
        self.id = id
        self.name = name
        self.associationKey = association.rawValue
        self.level = level
        self.isFocused = isFocused
    }

    var association: NutrivanceAssociation { NutrivanceAssociation(rawValue: associationKey) ?? .health }
}

// MARK: - Path Quest Store

@MainActor
final class PathQuestStore: ObservableObject {
    static let shared = PathQuestStore()

    @Published var activeQuest: PathQuest?
    @Published var questHistory: [PathQuest] = []
    @Published var gems: [PathfinderGem] = []
    @Published var stats: [PathfinderStat] = []
    @Published var aiAdvice: String = ""
    @Published var isGeneratingAdvice = false

    private let defaults = UserDefaults.standard
    private let cloud = NSUbiquitousKeyValueStore.default
    private let questKey = "pathfinder_quests_v1"
    private let gemsKey = "pathfinder_gems_v1"
    private let statsKey = "pathfinder_stats_v1"

    private init() { load() }

    func load() {
        cloud.synchronize()
        let allQuests = mergeEntries(
            decodeFrom(cloud.data(forKey: questKey), as: [PathQuest].self),
            decodeFrom(defaults.data(forKey: questKey), as: [PathQuest].self)
        )
        activeQuest = allQuests.first(where: \.isActive)
        questHistory = allQuests.filter { !$0.isActive }
        gems = mergeById(
            decodeFrom(cloud.data(forKey: gemsKey), as: [PathfinderGem].self),
            decodeFrom(defaults.data(forKey: gemsKey), as: [PathfinderGem].self)
        )
        stats = mergeById(
            decodeFrom(cloud.data(forKey: statsKey), as: [PathfinderStat].self),
            decodeFrom(defaults.data(forKey: statsKey), as: [PathfinderStat].self)
        )
    }

    func commitToPath(_ choice: PathChoice, focusAreas: [NutrivanceAssociation], correlations: [EmotionCorrelation]) {
        if var old = activeQuest {
            old.isActive = false
            questHistory.insert(old, at: 0)
        }

        let subQuests = generateSubQuests(choice: choice, focusAreas: focusAreas)
        let quest = PathQuest(
            title: "\(choice.rawValue) Path",
            pathChoice: choice,
            focusAreas: focusAreas,
            subQuests: subQuests,
            aiEncouragement: "You've chosen to \(choice.rawValue.lowercased()). Let's begin."
        )
        activeQuest = quest

        gems = focusAreas.prefix(3).map { assoc in
            PathfinderGem(label: assoc.displayName, association: assoc)
        }

        save()
    }

    func updateSubQuestProgress(_ questID: UUID, subQuestID: UUID, progress: Double) {
        guard var quest = activeQuest, quest.id == questID else { return }
        if let idx = quest.subQuests.firstIndex(where: { $0.id == subQuestID }) {
            quest.subQuests[idx].progress = min(1, max(0, progress))
            quest.subQuests[idx].isCompleted = quest.subQuests[idx].progress >= 1.0
            activeQuest = quest

            for i in gems.indices {
                let gemAssoc = gems[i].association
                let related = quest.subQuests.filter { sub in
                    quest.associations.contains(gemAssoc)
                }
                if !related.isEmpty {
                    gems[i].charge = min(1, related.map(\.progress).reduce(0, +) / Double(related.count))
                }
            }

            save()
        }
    }

    func toggleStatFocus(_ statID: UUID) {
        if let idx = stats.firstIndex(where: { $0.id == statID }) {
            stats[idx].isFocused.toggle()
            save()
        }
    }

    func levelUpStat(_ statID: UUID) {
        if let idx = stats.firstIndex(where: { $0.id == statID }) {
            stats[idx].level += 1
            save()
        }
    }

    func ensureDefaultStats() {
        guard stats.isEmpty else { return }
        let defaultAssociations: [(String, NutrivanceAssociation)] = [
            ("Fitness", .fitness), ("Recovery", .recovery), ("Focus", .focusQuality),
            ("Social", .friends), ("Growth", .learning), ("Energy", .energyLevels),
            ("Mindset", .mentalClarity), ("Purpose", .alignment)
        ]
        stats = defaultAssociations.map { PathfinderStat(name: $0.0, association: $0.1) }
        save()
    }

    func generateAIAdvice(correlations: [EmotionCorrelation]) {
        isGeneratingAdvice = true

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            Task {
                let model = SystemLanguageModel(useCase: .general)
                if model.isAvailable {
                    do {
                        let session = LanguageModelSession(
                            model: model,
                            instructions: """
                            You are a compassionate life advisor. Analyze emotional patterns and provide brief, actionable advice.
                            Be warm, specific, and practical. Focus on the top 2-3 patterns you notice.
                            Keep total response under 200 words. No bullet points, write in flowing paragraphs.
                            Do not diagnose medical or mental health conditions.
                            """
                        )
                        let summary = correlationSummary(correlations)
                        let response = try await session.respond(to: "Here are recent emotional patterns:\n\(summary)\n\nWhat patterns do you notice, and what gentle suggestions would you offer?")
                        await MainActor.run {
                            aiAdvice = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                            isGeneratingAdvice = false
                        }
                        return
                    } catch {}
                }
                await MainActor.run { generateFallbackAdvice(correlations); isGeneratingAdvice = false }
            }
            return
        }
        #endif

        generateFallbackAdvice(correlations)
        isGeneratingAdvice = false
    }

    func generateQuestEncouragement() {
        guard var quest = activeQuest else { return }
        let progress = quest.overallProgress

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            Task {
                let model = SystemLanguageModel(useCase: .general)
                if model.isAvailable {
                    do {
                        let session = LanguageModelSession(
                            model: model,
                            instructions: "You are an encouraging quest companion in a life-improvement RPG. Write 1-2 sentences of encouragement based on quest progress. Be warm, specific, and use the quest context. No emojis."
                        )
                        let context = "Quest: \(quest.title). Progress: \(Int(progress * 100))%. Sub-quests: \(quest.subQuests.map { "\($0.title): \(Int($0.progress * 100))%" }.joined(separator: ", ")). Focus: \(quest.associations.map(\.displayName).joined(separator: ", "))."
                        let response = try await session.respond(to: context)
                        await MainActor.run {
                            quest.aiEncouragement = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                            activeQuest = quest
                            save()
                        }
                        return
                    } catch {}
                }
                await MainActor.run { quest.aiEncouragement = fallbackEncouragement(progress: progress); activeQuest = quest; save() }
            }
            return
        }
        #endif

        quest.aiEncouragement = fallbackEncouragement(progress: progress)
        activeQuest = quest
        save()
    }

    private func fallbackEncouragement(progress: Double) -> String {
        if progress >= 0.8 { return "You're nearly there. The finish line is within reach — keep this momentum going." }
        if progress >= 0.5 { return "Solid progress. You've crossed the halfway mark. Stay consistent and the results will follow." }
        if progress >= 0.2 { return "You've taken the first steps. Every small action compounds over time." }
        return "The path begins with a single choice. You've already made yours — now let's build on it."
    }

    private func generateFallbackAdvice(_ correlations: [EmotionCorrelation]) {
        let pleasant = correlations.filter { $0.valenceCategory == .pleasant }
        let unpleasant = correlations.filter { $0.valenceCategory == .unpleasant }

        var advice = ""
        if !pleasant.isEmpty {
            let topPositive = Dictionary(grouping: pleasant, by: \.association).max(by: { $0.value.count < $1.value.count })
            if let top = topPositive {
                advice += "Your most positive moments are connected to \(top.key.displayName.lowercased()). Consider making more space for this in your routine. "
            }
        }
        if !unpleasant.isEmpty {
            let topNegative = Dictionary(grouping: unpleasant, by: \.association).max(by: { $0.value.count < $1.value.count })
            if let top = topNegative {
                advice += "You've been experiencing some tension around \(top.key.displayName.lowercased()). A small adjustment here could make a meaningful difference. "
            }
        }
        if advice.isEmpty {
            advice = "Keep journaling to build a clearer picture of your emotional patterns. The more you write, the better the insights become."
        }
        aiAdvice = advice
    }

    private func correlationSummary(_ correlations: [EmotionCorrelation]) -> String {
        let grouped = Dictionary(grouping: correlations, by: \.association)
        var lines: [String] = []
        for (assoc, items) in grouped.sorted(by: { $0.value.count > $1.value.count }).prefix(8) {
            let avgValence = items.map(\.estimatedValence).reduce(0, +) / Double(items.count)
            let emotions = Set(items.map(\.emotionLabel)).prefix(3).joined(separator: ", ")
            lines.append("\(assoc.displayName): \(items.count) moments, avg valence \(String(format: "%.1f", avgValence)), emotions: \(emotions)")
        }
        return lines.joined(separator: "\n")
    }

    private func generateSubQuests(choice: PathChoice, focusAreas: [NutrivanceAssociation]) -> [PathSubQuest] {
        var quests: [PathSubQuest] = []
        for area in focusAreas.prefix(3) {
            let tracked = NutrivanceAssociation.hkMappedCases.contains(area) || [.recovery, .energyLevels, .focusQuality].contains(area)
            switch choice {
            case .recover:
                quests.append(PathSubQuest(title: "Improve \(area.displayName.lowercased()) awareness", trackedByNutrivance: tracked))
            case .push:
                quests.append(PathSubQuest(title: "Push boundaries in \(area.displayName.lowercased())", trackedByNutrivance: tracked))
            case .reset:
                quests.append(PathSubQuest(title: "Rebuild consistency in \(area.displayName.lowercased())", trackedByNutrivance: tracked))
            case .explore:
                quests.append(PathSubQuest(title: "Explore new approaches to \(area.displayName.lowercased())", trackedByNutrivance: tracked))
            }
        }
        return quests
    }

    private func save() {
        var all = questHistory
        if let active = activeQuest { all.insert(active, at: 0) }
        encode(all, key: questKey)
        encode(gems, key: gemsKey)
        encode(stats, key: statsKey)
    }

    private func encode<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
        cloud.set(data, forKey: key)
        cloud.synchronize()
    }

    private func decodeFrom<T: Decodable>(_ data: Data?, as type: T.Type) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func mergeEntries(_ inputs: [PathQuest]?...) -> [PathQuest] {
        var map: [UUID: PathQuest] = [:]
        for source in inputs {
            for q in (source ?? []) { map[q.id] = q }
        }
        return map.values.sorted { $0.createdAt > $1.createdAt }
    }

    private func mergeById<T: Identifiable & Hashable>(_ inputs: [T]?...) -> [T] where T.ID == UUID {
        var map: [UUID: T] = [:]
        for source in inputs {
            for item in (source ?? []) { map[item.id] = item }
        }
        return Array(map.values)
    }
}

// MARK: - Path Quest Section UI

struct PathQuestSection: View {
    @ObservedObject var questStore: PathQuestStore
    @State private var showPathPicker = false
    let correlations: [EmotionCorrelation]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Path Quests")
                    .font(.headline)
                Spacer()
                if questStore.activeQuest != nil {
                    Button {
                        questStore.generateQuestEncouragement()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let quest = questStore.activeQuest {
                activeQuestCard(quest)
            } else {
                choosePathPrompt
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .sheet(isPresented: $showPathPicker) {
            PathPickerSheet(correlations: correlations) { choice, areas in
                questStore.commitToPath(choice, focusAreas: areas, correlations: correlations)
            }
        }
    }

    private var choosePathPrompt: some View {
        VStack(spacing: 12) {
            Text("Choose your next move")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(PathChoice.allCases) { choice in
                    Button {
                        showPathPicker = true
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: choice.icon)
                                .font(.title3)
                                .foregroundStyle(choice.accentColor)
                            Text(choice.rawValue)
                                .font(.subheadline.weight(.semibold))
                            Text(choice.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(choice.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(choice.accentColor.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func activeQuestCard(_ quest: PathQuest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: quest.choice.icon)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(quest.choice.accentColor)
                    .frame(width: 44, height: 44)
                    .background(quest.choice.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(quest.title)
                        .font(.subheadline.weight(.bold))
                    Text("\(Int(quest.overallProgress * 100))% complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                CircularProgressView(progress: quest.overallProgress, color: quest.choice.accentColor)
                    .frame(width: 36, height: 36)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1)).frame(height: 6)
                    Capsule().fill(quest.choice.accentColor).frame(width: geo.size.width * quest.overallProgress, height: 6)
                }
            }
            .frame(height: 6)

            ForEach(quest.subQuests) { sub in
                HStack(spacing: 8) {
                    Image(systemName: sub.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(sub.isCompleted ? .green : .secondary)
                    Text(sub.title)
                        .font(.caption)
                        .foregroundStyle(sub.isCompleted ? .secondary : .primary)
                        .strikethrough(sub.isCompleted)
                    Spacer()
                    if sub.trackedByNutrivance {
                        Image(systemName: "waveform.path.ecg")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Text("\(Int(sub.progress * 100))%")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            if !quest.aiEncouragement.isEmpty {
                Text(quest.aiEncouragement)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
                    .padding(.top, 4)
            }

            HStack {
                Button { showPathPicker = true } label: {
                    Text("Change Path")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Focus: \(quest.associations.prefix(3).map(\.displayName).joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(quest.choice.accentColor.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(quest.choice.accentColor.opacity(0.15), lineWidth: 1))
    }
}

struct CircularProgressView: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: 3)
            Circle().trim(from: 0, to: progress).stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))")
                .font(.system(size: 9, weight: .bold, design: .rounded))
        }
    }
}

// MARK: - Path Picker Sheet

struct PathPickerSheet: View {
    let correlations: [EmotionCorrelation]
    let onCommit: (PathChoice, [NutrivanceAssociation]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedChoice: PathChoice = .recover
    @State private var selectedAreas: Set<NutrivanceAssociation> = []

    private var suggestedAreas: [NutrivanceAssociation] {
        let grouped = Dictionary(grouping: correlations, by: \.association)
        let sorted = grouped.sorted { a, b in
            let aAvg = a.value.map(\.estimatedValence).reduce(0, +) / Double(a.value.count)
            let bAvg = b.value.map(\.estimatedValence).reduce(0, +) / Double(b.value.count)
            return selectedChoice == .push ? aAvg > bAvg : aAvg < bAvg
        }
        return sorted.prefix(6).map(\.key)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Choose your next move")
                        .font(.title3.weight(.bold))

                    ForEach(PathChoice.allCases) { choice in
                        Button {
                            withAnimation { selectedChoice = choice; selectedAreas = [] }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: choice.icon)
                                    .font(.title3)
                                    .foregroundStyle(choice.accentColor)
                                    .frame(width: 36, height: 36)
                                    .background(choice.accentColor.opacity(0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(choice.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                    Text(choice.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedChoice == choice {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(choice.accentColor)
                                }
                            }
                            .padding(12)
                            .background(selectedChoice == choice ? choice.accentColor.opacity(0.08) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Focus areas")
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 8)

                    Text("Select up to 3 areas to focus on. Suggestions based on your patterns:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let areas = suggestedAreas.isEmpty ? Array(NutrivanceAssociation.allCases.prefix(8)) : suggestedAreas
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(areas) { assoc in
                            let isSelected = selectedAreas.contains(assoc)
                            Button {
                                if isSelected { selectedAreas.remove(assoc) }
                                else if selectedAreas.count < 3 { selectedAreas.insert(assoc) }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: assoc.icon).font(.caption)
                                    Text(assoc.displayName).font(.caption).lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(isSelected ? selectedChoice.accentColor.opacity(0.15) : Color.white.opacity(0.06), in: Capsule())
                                .overlay(Capsule().stroke(isSelected ? selectedChoice.accentColor.opacity(0.4) : Color.clear, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("New Path")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Commit") {
                        onCommit(selectedChoice, Array(selectedAreas))
                        dismiss()
                    }
                    .disabled(selectedAreas.isEmpty)
                }
            }
        }
    }
}

// MARK: - AI Analysis Section

struct AIAnalysisSection: View {
    @ObservedObject var questStore: PathQuestStore
    let correlations: [EmotionCorrelation]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("AI Insights")
                    .font(.headline)
                Spacer()
                Button {
                    questStore.generateAIAdvice(correlations: correlations)
                } label: {
                    HStack(spacing: 4) {
                        if questStore.isGeneratingAdvice {
                            ProgressView().controlSize(.mini)
                        }
                        Text(questStore.aiAdvice.isEmpty ? "Analyze" : "Refresh")
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.purple.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(questStore.isGeneratingAdvice || correlations.count < 3)
            }

            if questStore.isGeneratingAdvice {
                HStack {
                    ProgressView()
                    Text("Analyzing your patterns...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if !questStore.aiAdvice.isEmpty {
                Text(questStore.aiAdvice)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .background(Color.purple.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if correlations.count < 3 {
                Text("Keep journaling to unlock AI insights. At least 3 correlations needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Tap Analyze to get personalized insights from your emotional patterns.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Harmony Ring + Gems Section

struct HarmonyGemSection: View {
    let gems: [PathfinderGem]
    @State private var pulsePhase: Double = 0

    private var allCharged: Bool { !gems.isEmpty && gems.allSatisfy(\.isCharged) }

    var body: some View {
        VStack(spacing: 14) {
            Text("Harmony")
                .font(.headline)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 6)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: averageCharge)
                    .stroke(
                        AngularGradient(colors: gemColors, center: .center),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))

                if allCharged {
                    Circle()
                        .fill(
                            RadialGradient(colors: [Color.orange.opacity(0.3), Color.clear], center: .center, startRadius: 20, endRadius: 70)
                        )
                        .frame(width: 140, height: 140)
                        .scaleEffect(1 + pulsePhase * 0.08)
                        .opacity(0.6 + pulsePhase * 0.4)
                }

                VStack(spacing: 2) {
                    if allCharged {
                        Image(systemName: "sparkle")
                            .font(.title3)
                            .foregroundStyle(.orange)
                    }
                    Text("\(Int(averageCharge * 100))%")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                }
            }
            .onAppear {
                if allCharged {
                    withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { pulsePhase = 1 }
                }
            }

            HStack(spacing: 20) {
                ForEach(gems) { gem in
                    GemView(gem: gem)
                }
            }

            if gems.isEmpty {
                Text("Commit to a path to activate gems.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var averageCharge: Double {
        guard !gems.isEmpty else { return 0 }
        return gems.map(\.charge).reduce(0, +) / Double(gems.count)
    }

    private var gemColors: [Color] {
        gems.isEmpty ? [.gray] : gems.map { gem in
            gem.isCharged ? .orange : gem.association.mode.accentColor
        }
    }
}

private extension PathfinderMode {
    var accentColor: Color {
        switch self {
        case .reflect: return .purple
        case .optimize: return .orange
        case .express: return .cyan
        case .analyze: return .green
        }
    }
}

struct GemView: View {
    let gem: PathfinderGem
    @State private var glow: Double = 0

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Image(systemName: "diamond.fill")
                    .font(.title2)
                    .foregroundStyle(
                        gem.isCharged
                        ? AnyShapeStyle(LinearGradient(colors: [.orange, .yellow], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(Color.gray.opacity(0.3 + gem.charge * 0.5))
                    )
                    .shadow(color: gem.isCharged ? .orange.opacity(0.6) : .clear, radius: 8 + glow * 4)

                if gem.isCharged {
                    Image(systemName: "sparkle")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .offset(x: 8, y: -8)
                        .opacity(glow)
                }
            }
            .onAppear {
                if gem.isCharged {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { glow = 1 }
                }
            }

            Text(gem.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1)).frame(height: 3)
                    Capsule().fill(gem.isCharged ? Color.orange : Color.white.opacity(0.3))
                        .frame(width: geo.size.width * gem.charge, height: 3)
                }
            }
            .frame(width: 50, height: 3)
        }
    }
}

// MARK: - Stat Page Section

struct StatPageSection: View {
    @ObservedObject var questStore: PathQuestStore
    @State private var animationPhase: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Stats")
                    .font(.headline)
                Spacer()
                Text("Commit to grow")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if questStore.stats.isEmpty {
                Button {
                    questStore.ensureDefaultStats()
                } label: {
                    Text("Initialize Stats")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(questStore.stats) { stat in
                        StatCardView(stat: stat) {
                            questStore.toggleStatFocus(stat.id)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            }
        )
    }
}

struct StatCardView: View {
    let stat: PathfinderStat
    var onToggleFocus: () -> Void
    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: stat.association.icon)
                    .font(.caption)
                    .foregroundStyle(stat.isFocused ? .orange : .secondary)
                Spacer()
                if stat.isFocused {
                    Image(systemName: "arrow.up")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Text(stat.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            HStack(spacing: 4) {
                Text("Lv.\(stat.level)")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(stat.isFocused ? .orange : .primary)

                Spacer()

                if stat.isFocused {
                    Text("FOCUSED")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                }
            }
        }
        .padding(10)
        .background(stat.isFocused ? Color.orange.opacity(0.06) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(stat.isFocused ? Color.orange.opacity(0.25) : Color.clear, lineWidth: 1))
        .scaleEffect(isPressed ? 0.96 : 1)
        .onTapGesture {
            withAnimation(.spring(response: 0.3)) {
                isPressed = true
                onToggleFocus()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3)) { isPressed = false }
            }
        }
    }
}

// MARK: - Journal Nudge

struct JournalNudgeView: View {
    let quest: PathQuest?

    var body: some View {
        if let quest, !quest.associations.isEmpty {
            let incompleteAreas = quest.associations.filter { assoc in
                !quest.subQuests.contains(where: { $0.isCompleted && quest.associations.contains(assoc) })
            }
            if let area = incompleteAreas.first {
                HStack(spacing: 8) {
                    Image(systemName: "pencil.line")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("Consider writing about \(area.displayName.lowercased()) in your journal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.orange.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

// MARK: - Updated PathfinderView with Phase 2+3

extension PathfinderView {

    var phase2QuestSection: some View {
        PathQuestSection(questStore: PathQuestStore.shared, correlations: statsCorrelations)
    }

    var phase2AISection: some View {
        AIAnalysisSection(questStore: PathQuestStore.shared, correlations: statsCorrelations)
    }

    var phase3GemSection: some View {
        HarmonyGemSection(gems: PathQuestStore.shared.gems)
    }

    var phase3StatSection: some View {
        StatPageSection(questStore: PathQuestStore.shared)
    }

    var journalNudge: some View {
        JournalNudgeView(quest: PathQuestStore.shared.activeQuest)
    }
}

// MARK: - Preview

#Preview {
    PathfinderView()
}
