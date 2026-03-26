//
//  HealthAnalysisService.swift
//  Nutrivance
//
//  Created by Vincent Leong on 11/27/24.
//

import Foundation

@MainActor
class HealthAnalysisService: ObservableObject {
    @Published var isAnalyzing = false
    @Published var insights: String = ""
    
    private let apiKey = "YOUR_API_KEY"
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    
    func analyzeNutrientData(_ data: [String: Double]) {
        if AppResourceCoordinator.shared.isStrainRecoveryForegroundCritical() {
            return
        }

        isAnalyzing = true
        let prompt = createAnalysisPrompt(from: data)
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "gpt-4",
            "messages": [
                ["role": "system", "content": "You are a nutrition expert analyzing health data."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isAnalyzing = false
                if let data = data,
                   let response = try? JSONDecoder().decode(GPTResponse.self, from: data) {
                    self?.insights = response.choices.first?.message.content ?? ""
                }
            }
        }.resume()
    }
    
    private func createAnalysisPrompt(from data: [String: Double]) -> String {
        """
        Analyze the following daily nutrient intake:
        Calories: \(data["calories"] ?? 0) kcal
        Protein: \(data["protein"] ?? 0) g
        Carbs: \(data["carbs"] ?? 0) g
        Fats: \(data["fats"] ?? 0) g
        Water: \(data["water"] ?? 0) L
        
        Please provide:
        1. Analysis of current intake vs recommended values
        2. Specific nutritional recommendations
        3. Suggested meal adjustments
        4. Health optimization tips
        """
    }
}

struct GPTResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: Message
    }
    
    struct Message: Codable {
        let content: String
    }
}

enum AthleticCoachFocusMode: String, Codable {
    case general
    case toughestWorkout
    case latestWorkout
    case recoveryVitalsSleep
    case trendBalance
    case sportDeepDive

    static func detect(from text: String) -> AthleticCoachFocusMode {
        let normalized = text.lowercased()
        if normalized.contains("toughest workout") || normalized.contains("hardest workout") {
            return .toughestWorkout
        }
        if normalized.contains("latest workout") {
            return .latestWorkout
        }
        if normalized.contains("recovery") || normalized.contains("vitals") || normalized.contains("sleep") {
            return .recoveryVitalsSleep
        }
        if normalized.contains("trend") || normalized.contains("balance") || normalized.contains("strain") {
            return .trendBalance
        }
        if normalized.contains("deep dive") || normalized.contains("cycling") || normalized.contains("running") {
            return .sportDeepDive
        }
        return .general
    }

    var promptRules: String {
        switch self {
        case .general:
            return "Use broad context, but still pick one or two most meaningful themes instead of listing everything."
        case .toughestWorkout:
            return "Focus almost entirely on the toughest workout. Support it with workout-specific evidence such as sport, date, load, zones, power, cadence, peak HR, HRR, VO2 or splits when available. Mention sleep or recovery only if it clearly explains the response to that workout. Do not drift into general weekly counts."
        case .latestWorkout:
            return "Focus on the latest workout only. Compare it to recent baseline and explain what changed. Keep non-workout context brief."
        case .recoveryVitalsSleep:
            return "Focus sharply on sleep and recovery vitals. Mention training only as context, not as a list of counts or zone totals. Avoid unnecessary raw numbers for vitals. Prefer baseline-aware wording like stable, elevated, suppressed, or improving."
        case .trendBalance:
            return "Focus on trends across the selected day, week, or month. Explain patterns such as repeated high-strain days, repeated recovery-led days, or balanced periods. Prefer pattern language over isolated data points."
        case .sportDeepDive:
            return "Focus on the chosen sport and synthesize its load, zones, VO2, personal records, cadence, power, HRR, HRV, and consistency into one coherent sport-specific report. Exclude zeros and irrelevant modalities."
        }
    }
}

struct WorkoutReportMetric: Identifiable, Codable, Hashable {
    let id: UUID
    let icon: String
    let title: String
    let value: String

    init(icon: String, title: String, value: String) {
        self.id = UUID()
        self.icon = icon
        self.title = title
        self.value = value
    }
}

enum WorkoutReportNLPParser {
    static func parseMetrics(from summary: String) -> [WorkoutReportMetric] {
        let patterns: [(String, String, String)] = [
            (#"zone 4[^0-9]*(\d+)\s*min"#, "waveform.path.ecg", "Zone 4"),
            (#"zone 5[^0-9]*(\d+)\s*min"#, "flame", "Zone 5"),
            (#"(\d+)\s*w\b"#, "bolt", "Power"),
            (#"(\d+)\s*rpm"#, "gauge.with.dots.needle.bottom.50percent", "Cadence"),
            (#"(\d+)\s*bpm"#, "heart.fill", "Heart Rate"),
            (#"(\d+(?:\.\d+)?)\s*h(?:ours?)?"#, "bed.double.fill", "Sleep"),
            (#"vo2[^0-9]*(\d+(?:\.\d+)?)"#, "lungs.fill", "VO2 Max"),
            (#"hrr[^0-9]*(\d+)"#, "heart.text.square.fill", "HRR")
        ]

        var metrics: [WorkoutReportMetric] = []
        let lowercased = summary.lowercased()

        for (pattern, icon, title) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(lowercased.startIndex..<lowercased.endIndex, in: lowercased)
            guard let match = regex.firstMatch(in: lowercased, range: range),
                  match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: lowercased) else {
                continue
            }

            let value = String(lowercased[captureRange])
            metrics.append(WorkoutReportMetric(icon: icon, title: title, value: value))
        }

        var seen = Set<String>()
        return metrics.filter { metric in
            seen.insert("\(metric.title)|\(metric.value)").inserted
        }
    }
}

struct SavedWorkoutReportPayload {
    let title: String
    let content: String
    let date: Date
}

extension Notification.Name {
    static let saveWorkoutReportToJournal = Notification.Name("saveWorkoutReportToJournal")
}
