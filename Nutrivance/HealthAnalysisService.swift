//
//  HealthAnalysisService.swift
//  Nutrivance
//
//  Created by Vincent Leong on 11/27/24.
//

import Foundation

class HealthAnalysisService: ObservableObject {
    @Published var isAnalyzing = false
    @Published var insights: String = ""
    
    private let apiKey = "YOUR_API_KEY"
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    
    func analyzeNutrientData(_ data: [String: Double]) {
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
