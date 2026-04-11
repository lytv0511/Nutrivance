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
    description: "One emotional correlation from journal text. emotion: standard word. valence: -1.0 to 1.0. associationKey: one raw key from health, fitness, selfCare, hobbies, identity, spirituality, community, family, friends, partner, dating, tasks, work, education, travel, weather, currentEvents, money, thoughtLoops, beliefsChallenged, mentalClarity, alignment, unexpressed, solitude, innerWorld, energyLevels, focusQuality, motivation, habitsSystems, experiments, recovery, ideas, curiosity, creativeSparks, suppressedReactions, problems, decisions, timePerception, constraints, inputsInfluences, learning, physicalOutput, bodyAwareness, goalsDirection, progressDrift. contextSummary: one brief sentence describing ONLY the journal author's experience (use \"You\" or neutral wording like \"Felt…\", \"Stressed when…\"). Never make another named person (e.g. a teacher or friend) the grammatical subject of the author's own feelings, goals, or actions—wrong: \"Mr. Hale was determined to improve grades\"; right: \"Determined to improve grades after a tough assignment\" or \"Felt stressed in Mr. Hale's class\"."
)
struct DetectedCorrelationItem {
    var emotion: String
    var valence: Double
    var associationKey: String
    var contextSummary: String
}

@available(iOS 26.0, *)
@Generable(description: "A named person or identifiable group (e.g. Endure therapists). mentionContext: 1–2 short phrases from the entry describing HOW they appear (role-in-story), not a generic relationship label—e.g. sports therapists you met about your app, not just therapist.")
struct DetectedPersonItem {
    var name: String
    var mentionContext: String
}

@available(iOS 26.0, *)
@Generable(description: "Follow-up to disambiguate people or life areas. Provide 5–8 choiceLabels when the situation needs nuance. Include options like: Collaborator on a project, Professional / expert contact (brief), Networking or one-time meeting, Advisor on a product or app, Acquaintance, Community contact—not only Friend, Family, Coworker, Teacher. choiceAssociationKeys must parallel choiceLabels (friends, family, partner, work, education, community, goalsDirection, inputsInfluences, habitsSystems, skip). linkedContextHint: paste an 8–48 character VERBATIM phrase from the journal that identifies THIS person/situation. linkedPersonName: person or team name if known.")
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

struct JournalSuggestedPerson: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var mentionContext: String

    init(id: UUID = UUID(), name: String, mentionContext: String) {
        self.id = id
        self.name = name
        self.mentionContext = mentionContext
    }
}

struct JournalCorrelationClarifier: Identifiable, Hashable, Codable {
    let id: UUID
    var question: String
    var choices: [String]
    /// Parallel to choices: NutrivanceAssociation rawValue, or skip / empty.
    var associationKeys: [String]
    var linkedPersonName: String?
    var linkedContextHint: String
    /// Correlations this clarifier is meant to refine (may be empty → infer by name/hint on apply).
    var targetCorrelationIDs: [UUID]
    /// Durable key for storing answer memory across wording tweaks.
    var stableKey: String

    init(
        id: UUID = UUID(),
        question: String,
        choices: [String],
        associationKeys: [String],
        linkedPersonName: String?,
        linkedContextHint: String,
        targetCorrelationIDs: [UUID] = [],
        stableKey: String = ""
    ) {
        self.id = id
        self.question = question
        self.choices = choices
        self.associationKeys = associationKeys
        self.linkedPersonName = linkedPersonName
        self.linkedContextHint = linkedContextHint
        self.targetCorrelationIDs = targetCorrelationIDs
        if stableKey.isEmpty {
            let personPart = linkedPersonName?.lowercased() ?? "none"
            let hintPart = linkedContextHint.lowercased().prefix(48)
            let assocPart = associationKeys.joined(separator: "|").lowercased()
            self.stableKey = "\(personPart)::\(hintPart)::\(assocPart)"
        } else {
            self.stableKey = stableKey
        }
    }
}

// MARK: - Paragraph & professional context (study vs collaboration; therapist ≠ self-care)

/// Corrects cross-paragraph bleed and “therapist” keyword → self-care when the story is professional/product collaboration.
private enum JournalCorrelationContextCorrector {
    /// Splits the journal into labeled sections so the model keeps separate emotions per paragraph.
    static func paragraphAnnotated(_ raw: String) -> String {
        let parts = raw.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard parts.count > 1 else { return raw }
        return parts.enumerated().map { idx, paragraph in
            "### Section \(idx + 1)\n\(paragraph)"
        }.joined(separator: "\n\n")
    }

    static func adjustAssociations(_ correlations: [EmotionCorrelation], fullText: String) -> [EmotionCorrelation] {
        let lower = fullText.lowercased()
        return correlations.map { adjustOne($0, fullLower: lower) }
    }

    private static func adjustOne(_ c: EmotionCorrelation, fullLower: String) -> EmotionCorrelation {
        var cc = c
        let ctx = c.contextNotes.lowercased()

        if JournalCorrelationHeuristics.hasBodySymptomCue(ctx), cc.association == .health || cc.association == .bodyAwareness {
            return cc
        }

        let studyCue = ["study", "studying", "studied", "unmotivated", "lecture", "exam", "homework", "assignment", "class", "course", "school", "session", "textbook", "essay"].contains { ctx.contains($0) }
        if studyCue, cc.association == .selfCare {
            cc.association = .education
        }

        let entryMentionsTherapist = ["therapist", "therapists", "physio", "physiotherapist", "chiropractor"].contains { fullLower.contains($0) }
        let entrySuggestsProfessionalCollaboration = [
            "collaborat", " my app", "health app", "passion project", "product", "startup", "build ", "building ",
            "network", "advisor", "advice", "meet ", " met ", "work with", "working with", "endure",
            "expressed interest", "help with", "briefly", "project"
        ].contains { fullLower.contains($0) }

        guard entryMentionsTherapist && entrySuggestsProfessionalCollaboration else { return cc }

        let summaryMatchesTherapistThread = [
            "therapist", "physio", "endure", "sports", "collaborat", "app", "passion", "wonderful", "great time",
            "enjoyed", "networking", "meet", "project"
        ].contains { ctx.contains($0) }

        guard summaryMatchesTherapistThread else { return cc }

        if cc.association == .selfCare || (cc.association == .health && !JournalCorrelationHeuristics.hasBodySymptomCue(ctx)) {
            if fullLower.contains("app") || fullLower.contains("product") || fullLower.contains("project") || fullLower.contains("passion") {
                cc.association = .goalsDirection
            } else {
                cc.association = .community
            }
        }
        return cc
    }
}

// MARK: - Journal correlation heuristics (food ↔ body, intensity / frequency gating)

/// Reduces false positives for food–symptom “correlations” and aligns intensity scales with symptom detection.
private enum JournalCorrelationHeuristics {
    private static let symptomLexicon: [String] = [
        "headache", "migraine", "nausea", "bloat", "bloating", "cramp", "cramps", "rash", "hives",
        "eczema", "acne", "stomach", "belly", "abdomen", "nauseous", "dizzy", "vertigo", "fatigue",
        "pain", "aching", "ache", "symptom", "flare", "breakout", "complexion", "itchy", "heartburn",
        "constipation", "diarrhea", "ibs", "reflux", "migraines"
    ]

    private static let nutrientDeltaCue: [String] = [
        "more ", "less ", "increased", "decreased", "cut out", "cut back", "stopped eating", "started eating",
        "eliminated", "introduced", "added ", "removed ", "fiber", "gluten", "dairy", "lactose", "sugar",
        "sodium", "salt", "whole grain", "processed", "fried", "alcohol", "caffeine", "supplement",
        "nutrient", "macros", "protein", "carb", "carbs", "omega"
    ]

    private static let foodCue: [String] = [
        "meal", "meals", "food", "ate", "eating", "snack", "dinner", "lunch", "breakfast", "restaurant",
        "drank", "coffee", "grain", "wheat", "oats", "oatmeal", "rice", "bread", "pasta"
    ]

    private static func containsAny(_ text: String, phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }

    /// “Bad” or “very bad” (and close synonyms) on an intensity scale — treat as symptom-level signal when tied to body/food/frequency context.
    static func hasDefiniteBadOrVeryBadIntensity(_ text: String) -> Bool {
        let t = text.lowercased()
        if t.contains("very bad") || t.contains("verybad") { return true }
        if t.range(of: #"\bbad\b"#, options: .regularExpression) != nil {
            if t.contains("not bad") || t.contains("wasn't bad") || t.contains("wasnt bad") { return false }
            let badAnchors = [
                "how intense", "intensity", "frequent", "frequency", "rating", "scale", "felt", "symptom",
                "pain", "rash", "skin", "headache", "stomach", "nausea", "bloat", "meal", "food", "ate",
                "snack", "breakfast", "lunch", "dinner", "logged"
            ]
            if badAnchors.contains(where: { t.contains($0) }) || symptomLexicon.contains(where: { t.contains($0) }) {
                return true
            }
        }
        if t.contains("terrible") || t.contains("awful") || t.contains("severe") || (t.contains("extreme") && t.contains("pain")) {
            return true
        }
        return false
    }

    /// Worse than “good” / “fine” for pairing with symptom language (includes moderate discomfort).
    static func intensityGreaterThanGood(_ text: String) -> Bool {
        let t = text.lowercased()
        if hasDefiniteBadOrVeryBadIntensity(t) { return true }
        let softBad = ["moderate", "uncomfortable", "pretty bad", "somewhat bad", "not great", "worse", "off"]
        if softBad.contains(where: { t.contains($0) }) { return true }
        if t.contains("okay") || t.contains("so-so") || t.contains("so so") {
            return symptomLexicon.contains { t.contains($0) }
        }
        return false
    }

    static func hasBodySymptomCue(_ text: String) -> Bool {
        containsAny(text.lowercased(), phrases: symptomLexicon)
    }

    static func hasNutrientStrongIndicator(_ text: String) -> Bool {
        containsAny(text.lowercased(), phrases: nutrientDeltaCue)
    }

    /// Stricter than “any food + any mood”: needs bad/very bad intensity, or nutrient change + body cue, or high frequency + enough intensity + body cue.
    static func passesStrictFoodBodyCorrelationGate(_ text: String) -> Bool {
        let t = text.lowercased()
        if hasDefiniteBadOrVeryBadIntensity(t) { return true }
        if hasNutrientStrongIndicator(t) && hasBodySymptomCue(t) { return true }
        let freqHigh = ["always", "often", "every time", "everytime", "daily", "constantly", "frequently", "keeps happening"].contains { t.contains($0) }
        let intenseEnough = hasDefiniteBadOrVeryBadIntensity(t)
            || t.contains("moderate")
            || t.contains("uncomfortable")
            || t.contains("pretty bad")
        return freqHigh && intenseEnough && hasBodySymptomCue(t)
    }

    static func refine(_ correlations: [EmotionCorrelation], fullText: String) -> [EmotionCorrelation] {
        let lower = fullText.lowercased()
        let mapped = correlations.compactMap { c -> EmotionCorrelation? in
            if shouldDropAsSpuriousSelfCareFood(c, fullLower: lower) { return nil }
            return adjustForSymptomIntensity(c, fullLower: lower)
        }
        return dedupeCorrelations(mapped)
    }

    private static func shouldDropAsSpuriousSelfCareFood(_ c: EmotionCorrelation, fullLower: String) -> Bool {
        guard c.association == .selfCare else { return false }
        let ctx = (c.contextNotes + " " + c.emotionLabel).lowercased()
        let foodMentioned = containsAny(fullLower, phrases: foodCue) || containsAny(ctx, phrases: foodCue)
        guard foodMentioned else { return false }
        if c.estimatedValence < -0.05 { return false }
        if passesStrictFoodBodyCorrelationGate(fullLower) { return false }
        if hasBodySymptomCue(fullLower) || hasNutrientStrongIndicator(fullLower) { return false }
        return true
    }

    private static func adjustForSymptomIntensity(_ c: EmotionCorrelation, fullLower: String) -> EmotionCorrelation {
        var out = c
        let notesLower = c.contextNotes.lowercased()
        let physical = hasBodySymptomCue(fullLower) || symptomLexicon.contains { notesLower.contains($0) }
        if physical && intensityGreaterThanGood(fullLower) {
            if out.association == .selfCare || out.association == .health {
                out.association = .bodyAwareness
            }
            let label = out.emotionLabel.lowercased()
            if hasDefiniteBadOrVeryBadIntensity(fullLower), label.contains("content") || label.contains("happy") {
                out.emotionLabel = "Symptom"
                out.estimatedValence = min(out.estimatedValence, -0.45)
            }
        }
        if hasDefiniteBadOrVeryBadIntensity(fullLower), physical {
            out.emotionLabel = out.emotionLabel.lowercased().contains("symptom") ? out.emotionLabel : "Symptom"
            out.estimatedValence = min(out.estimatedValence, -0.5)
        }
        return out
    }

    private static func dedupeCorrelations(_ items: [EmotionCorrelation]) -> [EmotionCorrelation] {
        var seen: Set<String> = []
        var out: [EmotionCorrelation] = []
        for c in items {
            let key = "\(c.emotionLabel.lowercased())|\(c.association.rawValue)|\(c.contextNotes.lowercased().prefix(80))"
            if seen.insert(key).inserted {
                out.append(c)
            }
        }
        return out
    }

    /// Regex path: extra symptom–nutrient bridges when the stricter gate passes.
    static func supplementRegexCorrelations(
        text: String,
        journalEntryID: UUID?,
        referenceDate: Date,
        existing: [EmotionCorrelation]
    ) -> [EmotionCorrelation] {
        let lower = text.lowercased()
        guard passesStrictFoodBodyCorrelationGate(lower) || (hasDefiniteBadOrVeryBadIntensity(lower) && hasBodySymptomCue(lower)) else {
            return existing
        }
        var results = existing
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for sentence in sentences {
            let sl = sentence.lowercased()
            guard hasBodySymptomCue(sl) else { continue }
            let foodHere = containsAny(sl, phrases: foodCue) || containsAny(sl, phrases: nutrientDeltaCue)
            guard foodHere || hasNutrientStrongIndicator(lower) else { continue }
            guard hasDefiniteBadOrVeryBadIntensity(sl) || hasNutrientStrongIndicator(sl) || intensityGreaterThanGood(sl) else { continue }
            let note = sentence.count > 90 ? String(sentence.prefix(87)) + "…" : sentence
            let candidate = EmotionCorrelation(
                journalEntryID: journalEntryID,
                date: referenceDate,
                emotionLabel: hasDefiniteBadOrVeryBadIntensity(sl) ? "Symptom" : "Physical discomfort",
                estimatedValence: hasDefiniteBadOrVeryBadIntensity(sl) ? -0.72 : -0.42,
                association: .bodyAwareness,
                contextNotes: note,
                source: .aiDetected
            )
            if !results.contains(where: { $0.contextNotes.lowercased() == note.lowercased() }) {
                results.append(candidate)
            }
            if results.count >= 5 { break }
        }
        return Array(results.prefix(5))
    }

    static func supplementClarifiers(
        _ existing: [JournalCorrelationClarifier],
        fullText: String,
        correlations: [EmotionCorrelation]
    ) -> [JournalCorrelationClarifier] {
        let t = fullText.lowercased()
        var out = existing
        var keys = Set(existing.map(\.stableKey))

        func appendGrain(_ block: () -> JournalCorrelationClarifier) {
            let c = block()
            if keys.insert(c.stableKey).inserted { out.append(c) }
        }

        let grainHit = ["whole grain", "wholegrain", "brown rice", "oatmeal", "oats ", " wheat", "bran", "quinoa"].contains { t.contains($0) }
        let skinHit = ["skin", "complexion", "rash", "acne", "eczema", "breakout", "hives", "itchy"].contains { t.contains($0) }
        let digestionHit = ["bloat", "digest", "stomach", "gut", "fiber", "gluten"].contains { t.contains($0) }

        if grainHit || digestionHit {
            appendGrain {
                JournalCorrelationClarifier(
                    question: "Did this involve a recent change in whole grains (amount or type)?",
                    choices: ["More whole grains", "Less / cut back", "Switched types", "About the same", "Not sure"],
                    associationKeys: ["inputsInfluences", "inputsInfluences", "experiments", "skip", "skip"],
                    linkedPersonName: nil,
                    linkedContextHint: "whole grains",
                    targetCorrelationIDs: correlations.map(\.id),
                    stableKey: "clarifier::whole_grains::v1"
                )
            }
        }

        if skinHit {
            appendGrain {
                JournalCorrelationClarifier(
                    question: "For skin appearance, what shifted most around the same time?",
                    choices: ["Diet change", "New product / topical", "Sleep / stress", "Hormonal cycle", "Not sure"],
                    associationKeys: ["inputsInfluences", "selfCare", "recovery", "health", "skip"],
                    linkedPersonName: nil,
                    linkedContextHint: "skin",
                    targetCorrelationIDs: correlations.map(\.id),
                    stableKey: "clarifier::skin_appearance::v1"
                )
            }
        }

        return out
    }
}

@MainActor
final class JournalCorrelationEngine: ObservableObject {
    @Published var detectedCorrelations: [EmotionCorrelation] = []
    @Published var suggestedPeople: [JournalSuggestedPerson] = []
    @Published var correlationClarifiers: [JournalCorrelationClarifier] = []
    private var analysisTask: Task<Void, Never>?
    /// Matches `JournalAssistantFingerprint` for the same reflection + inspiration; avoids wiping rehydrated cache when AI returns empty.
    private var assistantRestoredContentFingerprint: UInt64?
    /// Fired after a correlation pass finishes (including early exits) so the journal editor can persist assistant cache.
    var onAnalysisFinished: (() -> Void)?

    func restoreFromAssistantCache(
        correlations: [EmotionCorrelation],
        people: [JournalSuggestedPerson],
        clarifiers: [JournalCorrelationClarifier],
        contentFingerprint: UInt64
    ) {
        withAnimation(.easeOut(duration: 0.12)) {
            detectedCorrelations = correlations
            suggestedPeople = people
            correlationClarifiers = clarifiers
        }
        assistantRestoredContentFingerprint = contentFingerprint
    }

    func analyzeText(journalContent: String, journalInspiration: String, journalEntryID: UUID?, referenceDate: Date, statCardsContext: String = "") {
        analysisTask?.cancel()
        let combined = journalContent + " " + journalInspiration + " " + statCardsContext
        let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        let stableFP = JournalAssistantFingerprint.combine(content: journalContent, inspiration: journalInspiration, statCardsSignature: statCardsContext)
        if assistantRestoredContentFingerprint != nil, assistantRestoredContentFingerprint != stableFP {
            assistantRestoredContentFingerprint = nil
        }
        guard trimmed.count >= 15 else {
            assistantRestoredContentFingerprint = nil
            withAnimation {
                detectedCorrelations = []
                suggestedPeople = []
                correlationClarifiers = []
            }
            onAnalysisFinished?()
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

            results = JournalCorrelationContextCorrector.adjustAssociations(results, fullText: trimmed)
            let refinedFM = JournalCorrelationHeuristics.refine(results, fullText: trimmed)
            if refinedFM.isEmpty {
                let regexRaw = analyzeWithRegex(text: trimmed, journalEntryID: journalEntryID, referenceDate: referenceDate)
                results = JournalCorrelationContextCorrector.adjustAssociations(regexRaw, fullText: trimmed)
                results = JournalCorrelationHeuristics.refine(results, fullText: trimmed)
            } else {
                results = refinedFM
            }

            results = JournalCorrelationHeuristics.supplementRegexCorrelations(
                text: trimmed,
                journalEntryID: journalEntryID,
                referenceDate: referenceDate,
                existing: results
            )

            if people.isEmpty {
                people = extractPeopleHeuristic(from: trimmed)
            }
            clarifiers = Self.resolveClarifierTargets(clarifiers, correlations: results)
            clarifiers = JournalCorrelationHeuristics.supplementClarifiers(clarifiers, fullText: trimmed, correlations: results)

            guard !Task.isCancelled else { return }

            let fpNow = JournalAssistantFingerprint.combine(content: journalContent, inspiration: journalInspiration, statCardsSignature: statCardsContext)
            if results.isEmpty && people.isEmpty && clarifiers.isEmpty,
               assistantRestoredContentFingerprint == fpNow {
                onAnalysisFinished?()
                return
            }

            assistantRestoredContentFingerprint = nil
            withAnimation(.easeOut(duration: 0.2)) {
                detectedCorrelations = results
                suggestedPeople = people
                correlationClarifiers = clarifiers
            }
            onAnalysisFinished?()
        }
    }

    func clear() {
        analysisTask?.cancel()
        assistantRestoredContentFingerprint = nil
        withAnimation {
            detectedCorrelations = []
            suggestedPeople = []
            correlationClarifiers = []
        }
        onAnalysisFinished?()
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

                AUTHOR VS OTHER PEOPLE (critical):
                - The entry is written in the first person by a single author. That author is the ONLY person whose feelings, intentions, and actions you summarize in correlations.
                - Other people (teachers, friends, family, "Mr./Ms./Dr. Lastname", first names) may appear ONLY as context: where things happened, who was present, who assigned work, etc.
                - NEVER recast the author's experience as if someone else felt it or pursued it. If the writer says "I was determined…", "I felt inspired…", "I felt stressed…", the contextSummary must keep the writer as the experiencer—never "Mr. Hale was determined…" or "Frank felt inspired…" unless the entry clearly attributes that exact emotion to that other person (e.g. "Frank said he felt thrilled").
                - Good patterns: "Felt stressed in class with a demanding teacher", "Determined to improve grades after a rushed essay", "Inspired by a friend's passion for STEM", "Overwhelmed by a Wednesday essay deadline".
                - Bad patterns: using a mentioned person's name as the subject for the writer's emotion or goal (e.g. wrong: "Mr. Hale was determined to improve his grades" when the writer is the student).
                - Each correlation's contextSummary is one short sentence; prefer "You …" or verb-first ("Felt…", "Stressed when…") so the author stays centered. Do not drift into third-person biography of people the author merely mentioned.

                correlations: For each distinct emotion expressed or implied, output emotion, valence (-1…1), associationKey (exact raw key from the allowed set), and contextSummary per the rules above.
                School, class, teacher, professor, homework, lecture, exam, study session → associationKey education (not work). Job, boss, office, deadline without school context → work.
                Only extract emotions clearly present. At most 5 correlations.

                PARAGRAPHS AND SEPARATE CONTEXTS (critical):
                - The journal may use blank lines between paragraphs. Each ### Section in the prompt is a separate block. Do NOT merge or relabel emotions across sections.
                - If one section is about study/school and another is about different people or activities, output SEPARATE correlations with contextSummary text taken from THAT section only. Preserve the unmotivated/education correlation even if a later section mentions health professionals.
                - Do NOT let keywords from a later paragraph overwrite the association for an earlier paragraph’s correlation.

                THERAPISTS, COACHES, CLINICIANS, “SPORTS THERAPISTS” (do NOT default to selfCare):
                - Words like therapist, physio, or clinic do NOT mean selfCare unless the author is clearly receiving personal care, treatment for wellbeing, or therapy as a client/patient.
                - If therapists or experts appear in a collaboration, product, app, startup, networking, “met and discussed”, passion project, or professional-advice context, use work, community, goalsDirection, or inputsInfluences—not selfCare.
                - selfCare is for rest, routines, personal wellness activities, or self-kindness—not for meeting professionals about a project.

                FOOD, NUTRIENTS, SYMPTOMS, AND INTENSITY (tighten false positives):
                - Propose a diet/food-linked correlation only when there is a plausible physical symptom, skin/gut reaction, or a clear change in intake (more/less/cut/added/switched) tied to how the author felt.
                - If the author describes symptom intensity as bad or very bad (or clearly severe), treat that as a symptom signal: prefer associationKey bodyAwareness or health with negative valence—not a generic “selfCare” meal mood.
                - “How frequent?” and “How intense?” matter: do not infer a nutrient correlation from a one-off pleasant meal; prefer correlations when frequency is high and/or intensity is at least moderate—or when specific nutrients or foods changed.
                - Optional [Logged stat cards] lines may appear at the end: treat them as structured answers (titles/values/subtitles) alongside the prose.

                mentionedPeople: Proper names, orgs, or identifiable groups (e.g. Endure, sports therapists from Endure). Skip vague "someone". mentionContext MUST reflect the scene from the text (what you did together or why they appear)—≤120 chars—not a single-word role guess.

                followUpClarifiers: 2–8 quick checks as multiple choice. Include:
                - For each important person or group: ask how they fit the author’s life with 5–8 options when Friend/Family/Coworker/Teacher is too narrow—e.g. Collaborator on a project, Professional contact (brief meeting), Networking / one-time contact, Advisor on app or product, Community or sport org, Acquaintance, Friend, Family, Work colleague, Teacher, Not sure / skip.
                - Each question MUST reference the situation (e.g. “the people from Endure you mentioned”) so context is not lost.
                - When school vs work could be confused: disambiguate with enough options.
                - If whole grains, oats, wheat, fiber, or gluten appear with digestion or energy symptoms, include a clarifier about recent whole-grain changes (more/less/different kinds).
                - If skin, complexion, rash, acne, or breakouts appear, include a clarifier about what else shifted (diet, topical product, sleep/stress).
                choiceLabels: up to 8 short options (≤7 words each). choiceAssociationKeys must parallel choiceLabels: friends, family, partner, work, education, community, goalsDirection, inputsInfluences, habitsSystems, skip.
                linkedPersonName: the person's or team’s name if the question is about them, else empty string.
                linkedContextHint: REQUIRED when asking about someone—copy 8–48 consecutive characters from the journal (verbatim) that anchor that person or scene; empty only for non-person questions.
                """
            )

            let truncated = JournalCorrelationContextCorrector.paragraphAnnotated(String(text.prefix(4000)))
            let userTurn = """
            Journal entry (first-person author — keep them as the emotional subject in every contextSummary; other names are only context). Respect ### Section boundaries as separate scenes.

            \(truncated)
            """
            let response = try await session.respond(to: userTurn, generating: DetectedCorrelationOutput.self)
            let content = response.content

            let correlations: [EmotionCorrelation] = content.correlations.prefix(5).compactMap { item in
                let assoc = NutrivanceAssociation(rawValue: item.associationKey) ?? guessAssociation(from: item.contextSummary)
                let normalizedValence = normalizeValence(item.valence, context: item.contextSummary)
                return EmotionCorrelation(
                    journalEntryID: journalEntryID,
                    date: referenceDate,
                    emotionLabel: normalizeEmotionLabel(item.emotion),
                    estimatedValence: normalizedValence,
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
        guard labels.count >= 2, labels.count <= 8 else { return nil }

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
            choices: Array(labels.prefix(8)),
            associationKeys: Array(keys.prefix(labels.count)),
            linkedPersonName: person.isEmpty ? nil : person,
            linkedContextHint: hint,
            targetCorrelationIDs: [],
            stableKey: "\(person.lowercased())::\(hint.lowercased().prefix(48))::\(keys.joined(separator: "|"))"
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
            if ids.isEmpty, hint.count >= 8 {
                let prefix = String(hint.prefix(24))
                ids = correlations.filter { $0.contextNotes.localizedCaseInsensitiveContains(prefix) }.map(\.id)
            }
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

    /// Prefer education / project associations when “therapist” appears in a collaboration story (not spa self-care).
    private static func applyRegexAssociationOverrides(sentLower: String, assoc: NutrivanceAssociation) -> NutrivanceAssociation {
        var a = assoc
        if ["study", "studying", "unmotivated", "lecture", "homework", "exam", "class", "session", "school", "assignment", "essay"].contains(where: { sentLower.contains($0) }) {
            if a == .selfCare { a = .education }
        }
        let therapist = ["therapist", "therapists", "physio", "physiotherapist"].contains { sentLower.contains($0) }
        let collab = ["collaborat", "app", "product", "project", "passion", "network", "meet ", " met ", "work with", "working with", "endure", "advisor", "build ", "health app"].contains { sentLower.contains($0) }
        if therapist && collab && (a == .selfCare || a == .health) {
            a = .goalsDirection
        }
        return a
    }

    private func analyzeWithRegex(text: String, journalEntryID: UUID?, referenceDate: Date) -> [EmotionCorrelation] {
        let paragraphBlocks = text.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let segments = paragraphBlocks.count > 1 ? paragraphBlocks : [text]
        var results: [EmotionCorrelation] = []

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

        for segment in segments {
            var usedAssociations: Set<NutrivanceAssociation> = []
            let sentences = segment.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        for sentence in sentences {
            let sentLower = sentence.lowercased()
            let hasNegation = sentLower.contains(" not ")
                || sentLower.contains("n't")
                || sentLower.contains("never ")
                || sentLower.hasPrefix("not ")
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

            assoc = Self.applyRegexAssociationOverrides(sentLower: sentLower, assoc: assoc)

            guard !usedAssociations.contains(assoc) || assocScore > 1 else { continue }
            usedAssociations.insert(assoc)

            let contextNote = sentence.count > 80 ? String(sentence.prefix(77)) + "..." : sentence
            let normalizedEmotion = normalizeEmotionLabel(emotion.emotion)
            let signedValence = hasNegation ? -emotion.valence : emotion.valence
            results.append(EmotionCorrelation(
                journalEntryID: journalEntryID,
                date: referenceDate,
                emotionLabel: normalizedEmotion,
                estimatedValence: normalizeValence(signedValence, context: contextNote),
                association: assoc,
                contextNotes: contextNote,
                source: .aiDetected
            ))

            if results.count >= 5 { break }
        }

            if results.count >= 5 { break }
        }

        return Array(results.prefix(5))
    }

    private func guessAssociation(from text: String) -> NutrivanceAssociation {
        let lower = text.lowercased()
        let therapistWord = ["therapist", "therapists", "physio", "physiotherapist"].contains { lower.contains($0) }
        let professionalCollab = ["collaborat", " my app", "app ", "product", "startup", "passion project", "network", "advisor", "meet ", " met ", "work with", "endure", "build "].contains { lower.contains($0) }
        if therapistWord && professionalCollab {
            return lower.contains("app") || lower.contains("product") || lower.contains("passion") ? .goalsDirection : .community
        }
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
        if lower.contains("think") || lower.contains("loop") || lower.contains("mind") {
            return .thoughtLoops
        }
        return .learning
    }

    private func normalizeEmotionLabel(_ raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let map: [String: String] = [
            "anxious": "stressed",
            "anxiety": "stressed",
            "tense": "stressed",
            "stressed out": "stressed",
            "happy": "happy",
            "joyful": "happy",
            "excited": "excited",
            "sad": "sad",
            "angry": "angry",
            "frustrated": "frustrated",
            "overwhelmed": "overwhelmed",
            "calm": "peaceful",
            "relaxed": "peaceful",
        ]
        return map[key] ?? key
    }

    private func normalizeValence(_ value: Double, context: String) -> Double {
        var output = max(-1, min(1, value))
        let lower = context.lowercased()
        if lower.contains("very") || lower.contains("extremely") || lower.contains("really") {
            output *= 1.15
        }
        if lower.contains("a bit") || lower.contains("slightly") || lower.contains("kind of") {
            output *= 0.85
        }
        if lower.contains("but") || lower.contains("however") {
            output *= 0.9
        }
        return max(-1, min(1, output))
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

    let dateFormatter = ISO8601DateFormatter()
    dateFormatter.formatOptions = [.withFullDate, .withTime]

    for corr in local {
        results.append(SynthesizedCorrelation(correlation: corr))
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
            .onReceiveViewControl(.nutrivanceViewControlPathfinderLogEmotion) {
                showAddSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlPathfinderWorkoutCompleted)) { notification in
                if let associations = notification.object as? [NutrivanceAssociation] {
                    PathQuestStore.shared.processWorkoutProgress(associations: associations)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .nutrivanceViewControlPathfinderMindfulnessLogged)) { notification in
                if let minutes = notification.object as? Double {
                    PathQuestStore.shared.processMindfulnessProgress(minutes: minutes, relatedAssociation: nil)
                }
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
                    .catalystDesktopFocusable()
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
                    .catalystDesktopFocusable()

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
                    .catalystDesktopFocusable()
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
                        .catalystDesktopFocusable()
                        #if targetEnvironment(macCatalyst)
                        .keyboardShortcut(.escape, modifiers: [])
                        #endif
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
                    .catalystDesktopFocusable()
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
                    .catalystDesktopFocusable()
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
                    .catalystDesktopFocusable()
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
                        .catalystDesktopFocusable()
                        #if targetEnvironment(macCatalyst)
                        .keyboardShortcut(.escape, modifiers: [])
                        #endif
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(correlation)
                        dismiss()
                    }
                    .catalystDesktopFocusable()
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
    var associationKey: String?

    init(id: UUID = UUID(), title: String, progress: Double = 0, isCompleted: Bool = false, trackedByNutrivance: Bool = false, association: NutrivanceAssociation? = nil) {
        self.id = id
        self.title = title
        self.progress = progress
        self.isCompleted = isCompleted
        self.trackedByNutrivance = trackedByNutrivance
        self.associationKey = association?.rawValue
    }

    var trackedAssociation: NutrivanceAssociation? {
        guard let associationKey else { return nil }
        return NutrivanceAssociation(rawValue: associationKey)
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
                    sub.trackedAssociation == gemAssoc
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

    // MARK: - Quest Progress Tracking

    func processCorrelationProgress(_ correlations: [EmotionCorrelation]) {
        guard let quest = activeQuest, !quest.subQuests.isEmpty else { return }
        let questAssociations = Set(quest.associations)
        let relevantCorrelations = correlations.filter { questAssociations.contains($0.association) }
        
        guard !relevantCorrelations.isEmpty else { return }
        
        var newProgressMap: [UUID: Double] = [:]
        for sub in quest.subQuests {
            let subAssociations = Set(sub.trackedAssociation.map { [$0] } ?? quest.associations)
            let matchingCorrs = relevantCorrelations.filter { subAssociations.contains($0.association) }
            if matchingCorrs.isEmpty { continue }
            
            let currentProgress = sub.progress
            let increment = 0.15 / Double(quest.subQuests.count)
            var updatedProgress = currentProgress
            
            for corr in matchingCorrs {
                let valenceBonus: Double
                switch corr.valenceCategory {
                case .pleasant: valenceBonus = increment * 1.5
                case .neutral: valenceBonus = increment
                case .unpleasant: valenceBonus = increment * 0.3
                }
                updatedProgress += valenceBonus
            }
            
            newProgressMap[sub.id] = min(1.0, updatedProgress)
        }
        
        for (subQuestID, progress) in newProgressMap {
            if let sub = quest.subQuests.first(where: { $0.id == subQuestID }) {
                updateSubQuestProgress(quest.id, subQuestID: sub.id, progress: progress)
            }
        }
        
        if !newProgressMap.isEmpty {
            generateQuestEncouragement()
        }
    }

    func processWorkoutProgress(associations: [NutrivanceAssociation]) {
        guard let quest = activeQuest, !quest.subQuests.isEmpty else { return }
        let questAssociations = Set(quest.associations)
        
        let relevantAssociations = associations.filter { questAssociations.contains($0) }
        guard !relevantAssociations.isEmpty else { return }
        
        for sub in quest.subQuests {
            let subAssociations = Set(sub.trackedAssociation.map { [$0] } ?? quest.associations)
            if relevantAssociations.contains(where: { subAssociations.contains($0) }) {
                let increment = 0.2
                let newProgress = min(1.0, sub.progress + increment)
                updateSubQuestProgress(quest.id, subQuestID: sub.id, progress: newProgress)
            }
        }
        
        generateQuestEncouragement()
    }

    func processMindfulnessProgress(minutes: Double, relatedAssociation: NutrivanceAssociation?) {
        guard let quest = activeQuest, !quest.subQuests.isEmpty else { return }
        let questAssociations = Set(quest.associations)
        
        let targetAssociations: Set<NutrivanceAssociation>
        if let related = relatedAssociation, questAssociations.contains(related) {
            targetAssociations = [related]
        } else {
            targetAssociations = Set([.recovery, .mentalClarity, .energyLevels].filter { questAssociations.contains($0) })
        }
        
        guard !targetAssociations.isEmpty else { return }
        
        let progressIncrement = min(1.0, minutes / 30.0) * 0.15
        
        for sub in quest.subQuests {
            let subAssociations = Set(sub.trackedAssociation.map { [$0] } ?? quest.associations)
            if targetAssociations.contains(where: { subAssociations.contains($0) }) {
                let newProgress = min(1.0, sub.progress + progressIncrement)
                updateSubQuestProgress(quest.id, subQuestID: sub.id, progress: newProgress)
            }
        }
        
        generateQuestEncouragement()
    }

    func getSubQuestProgress(for association: NutrivanceAssociation) -> Double {
        guard let quest = activeQuest else { return 0 }
        let relevantSubQuests = quest.subQuests.filter { sub in
            if let tracked = sub.trackedAssociation {
                return tracked == association
            }
            return quest.associations.contains(association)
        }
        guard !relevantSubQuests.isEmpty else { return 0 }
        return relevantSubQuests.map(\.progress).reduce(0, +) / Double(relevantSubQuests.count)
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
                quests.append(PathSubQuest(title: "Improve \(area.displayName.lowercased()) awareness", trackedByNutrivance: tracked, association: area))
            case .push:
                quests.append(PathSubQuest(title: "Push boundaries in \(area.displayName.lowercased())", trackedByNutrivance: tracked, association: area))
            case .reset:
                quests.append(PathSubQuest(title: "Rebuild consistency in \(area.displayName.lowercased())", trackedByNutrivance: tracked, association: area))
            case .explore:
                quests.append(PathSubQuest(title: "Explore new approaches to \(area.displayName.lowercased())", trackedByNutrivance: tracked, association: area))
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
                VStack(alignment: .leading, spacing: 3) {
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
                    Text(chargingHint(for: sub))
                        .font(.caption2)
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

    private func chargingHint(for sub: PathSubQuest) -> String {
        guard let assoc = sub.trackedAssociation else {
            return "Charged by general progress events."
        }
        return "Charged by \(assoc.displayName.lowercased())-related logs, workouts, and mindful sessions."
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
                            .catalystDesktopFocusable()
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("New Path")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .catalystDesktopFocusable()
                        #if targetEnvironment(macCatalyst)
                        .keyboardShortcut(.escape, modifiers: [])
                        #endif
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Commit") {
                        onCommit(selectedChoice, Array(selectedAreas))
                        dismiss()
                    }
                    .disabled(selectedAreas.isEmpty)
                    .catalystDesktopFocusable()
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

    private let harmonyCircleSize: CGFloat = 120
    private let compactThreshold: CGFloat = 500
    private let fullWidthThreshold: CGFloat = 800

    var body: some View {
        VStack(spacing: 14) {
            Text("Harmony")
                .font(.headline)

            GeometryReader { geo in
                let width = geo.size.width

                if width < compactThreshold {
                    compactLayout
                } else {
                    expandedLayout(totalWidth: width)
                }
            }
            .frame(minHeight: harmonyCircleSize + 20)
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var compactLayout: some View {
        VStack(spacing: 14) {
            harmonyCircle

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
    }

    private func expandedLayout(totalWidth: CGFloat) -> some View {
        let showChargingHints = totalWidth >= fullWidthThreshold

        return HStack(alignment: .top, spacing: 0) {
            harmonyCircle
                .frame(width: harmonyCircleSize + 20)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(gems) { gem in
                    ExpandedGemRow(
                        gem: gem,
                        showChargingHint: showChargingHints,
                        maxBarWidth: showChargingHints ? 240 : 320
                    )
                }

                if gems.isEmpty {
                    Text("Commit to a path to activate gems.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            }
            .padding(.leading, 20)

            Spacer(minLength: 0)
        }
    }

    private var harmonyCircle: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 6)
                .frame(width: harmonyCircleSize, height: harmonyCircleSize)

            Circle()
                .trim(from: 0, to: averageCharge)
                .stroke(
                    AngularGradient(colors: gemColors, center: .center),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: harmonyCircleSize, height: harmonyCircleSize)
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

    private func gemChargingHint(for gem: PathfinderGem) -> String {
        let assoc = gem.association
        let area = assoc.displayName.lowercased()
        switch gem.association.mode {
        case .reflect:
            return "Journal and reflect on \(area)"
        case .optimize:
            return "Log habits and track \(area)"
        case .express:
            return "Capture ideas and sparks around \(area)"
        case .analyze:
            return "Review patterns and decisions in \(area)"
        }
    }
}

struct ExpandedGemRow: View {
    let gem: PathfinderGem
    let showChargingHint: Bool
    let maxBarWidth: CGFloat
    @State private var glow: Double = 0

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            gemIcon

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(gem.label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Spacer()

                    Text("\(Int(gem.charge * 100))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.1))
                        Capsule().fill(gem.isCharged ? Color.orange : Color.white.opacity(0.4))
                            .frame(width: max(0, geo.size.width * gem.charge), height: 6)
                    }
                }
                .frame(height: 6)
                .frame(maxWidth: maxBarWidth)
            }
            .frame(maxWidth: showChargingHint ? 300 : .infinity)

            if showChargingHint {
                Text(gemChargingHint(for: gem))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 200, alignment: .leading)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(gem.isCharged ? Color.orange.opacity(0.05) : Color.clear)
        .cornerRadius(8)
    }

    private var gemIcon: some View {
        ZStack {
            Image(systemName: "diamond.fill")
                .font(.title2)
                .foregroundStyle(
                    gem.isCharged
                    ? AnyShapeStyle(LinearGradient(colors: [.orange, .yellow], startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(gem.association.mode.accentColor.opacity(0.4 + gem.charge * 0.5))
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
        .frame(width: 32, height: 32)
        .onAppear {
            if gem.isCharged {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { glow = 1 }
            }
        }
    }

    private func gemChargingHint(for gem: PathfinderGem) -> String {
        let assoc = gem.association
        let area = assoc.displayName.lowercased()
        switch gem.association.mode {
        case .reflect:
            return "Journal and reflect on \(area)"
        case .optimize:
            return "Log habits and track \(area)"
        case .express:
            return "Capture ideas and sparks around \(area)"
        case .analyze:
            return "Review patterns and decisions in \(area)"
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
