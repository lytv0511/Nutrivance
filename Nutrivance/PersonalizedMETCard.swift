import SwiftUI

struct PersonalizedMETCard: View {
    let dailySnapshot: DailyPersonalizedMETSnapshot
    let profile: PersonalizedMETProfile
    let last7DaySnapshots: [DailyPersonalizedMETSnapshot]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Personalized METs")
                        .font(.headline)
                    Text("Effort intensity based on your capacity")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "bolt.badge.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            
            // Main Metrics Row
            HStack(spacing: 16) {
                // Total METs
                VStack(alignment: .center, spacing: 6) {
                    Text(String(format: "%.1f", dailySnapshot.totalMETs))
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
                
                // Beneficial METs
                VStack(alignment: .center, spacing: 6) {
                    Text(String(format: "%.1f", dailySnapshot.beneficialMETs))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("Beneficial")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
                
                // Effort %
                VStack(alignment: .center, spacing: 6) {
                    Text(String(format: "%.0f%%", dailySnapshot.averageEffortProportion * 100))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    Text("Avg Effort")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            
            Divider().padding(.vertical, 8)
            
            // Zone Distribution
            if !dailySnapshot.zoneDistribution.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Zone Distribution")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    ZoneDistributionChart(distribution: dailySnapshot.zoneDistribution)
                    
                    HStack(spacing: 12) {
                        ForEach(PersonalizedMETZone.allCases, id: \.self) { zone in
                            if let minutes = dailySnapshot.zoneDistribution[zone], minutes > 0 {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color(zone.color))
                                        .frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(zone.rawValue)
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                        Text(String(format: "%.0f min", minutes))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            
            Divider().padding(.vertical, 8)
            
            // 7-Day Trend
            if !last7DaySnapshots.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("7-Day Beneficial METs Trend")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    BeneficialMETsTrendChart(snapshots: last7DaySnapshots)
                        .frame(height: 80)
                }
            }
            
            // Status Badge
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: beneficialMETStatusIcon)
                        .foregroundColor(beneficialMETStatusColor)
                    Text(beneficialMETStatusText)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("Workouts: \(dailySnapshot.workoutCount)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Color(beneficialMETStatusColor).opacity(0.1))
            .cornerRadius(6)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }
    
    // MARK: - Computed Properties
    
    private var beneficialMETStatusIcon: String {
        if dailySnapshot.beneficialMETs > (profile.maxMETs * 1.5) {
            return "exclamationmark.circle.fill"
        } else if dailySnapshot.beneficialMETs > (profile.maxMETs * 0.8) {
            return "checkmark.circle.fill"
        } else {
            return "info.circle.fill"
        }
    }
    
    private var beneficialMETStatusColor: Color {
        if dailySnapshot.beneficialMETs > (profile.maxMETs * 1.5) {
            return .red
        } else if dailySnapshot.beneficialMETs > (profile.maxMETs * 0.8) {
            return .green
        } else {
            return .orange
        }
    }
    
    private var beneficialMETStatusText: String {
        if dailySnapshot.beneficialMETs > (profile.maxMETs * 1.5) {
            return "High Load — Recovery Priority"
        } else if dailySnapshot.beneficialMETs > (profile.maxMETs * 0.8) {
            return "Optimal Training Load"
        } else {
            return "Light Load — Recovery Day"
        }
    }
}

// MARK: - Zone Distribution Chart

struct ZoneDistributionChart: View {
    let distribution: [PersonalizedMETZone: Double]
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            let total = distribution.values.reduce(0, +)
            
            ForEach(PersonalizedMETZone.allCases, id: \.self) { zone in
                let minutes = distribution[zone] ?? 0
                let proportion = total > 0 ? minutes / total : 0
                
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(zone.color))
                        .frame(height: max(4, proportion * 60))
                    
                    Text(zone.rawValue.prefix(3))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 70)
    }
}

// MARK: - 7-Day Trend Chart

struct BeneficialMETsTrendChart: View {
    let snapshots: [DailyPersonalizedMETSnapshot]
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            let maxBeneficial = snapshots.map { $0.beneficialMETs }.max() ?? 1
            
            ForEach(snapshots, id: \.id) { snapshot in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(snapshot.beneficialMETs > 0 ? Color.blue : Color(.systemGray4))
                        .frame(height: max(4, (snapshot.beneficialMETs / max(1, maxBeneficial)) * 60))
                    
                    Text(snapshot.date.formatted(.dateTime.day()))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

#Preview {
    PersonalizedMETCard(
        dailySnapshot: DailyPersonalizedMETSnapshot(
            date: Date(),
            totalMETs: 65.5,
            beneficialMETs: 35.2,
            thresholdMETs: 7.5,
            averageEffortProportion: 0.58,
            peakEffortProportion: 0.75,
            workoutCount: 2,
            zoneDistribution: [
                .light: 15,
                .moderate: 30,
                .vigorous: 45,
                .hard: 20
            ]
        ),
        profile: PersonalizedMETProfile(
            maxMETs: 15.0,
            beneficialMETThresholdPercentage: 0.50
        ),
        last7DaySnapshots: [
            DailyPersonalizedMETSnapshot(date: Date().addingTimeInterval(-6*86400), beneficialMETs: 28),
            DailyPersonalizedMETSnapshot(date: Date().addingTimeInterval(-5*86400), beneficialMETs: 42),
            DailyPersonalizedMETSnapshot(date: Date().addingTimeInterval(-4*86400), beneficialMETs: 35),
            DailyPersonalizedMETSnapshot(date: Date().addingTimeInterval(-3*86400), beneficialMETs: 0),
            DailyPersonalizedMETSnapshot(date: Date().addingTimeInterval(-2*86400), beneficialMETs: 38),
            DailyPersonalizedMETSnapshot(date: Date().addingTimeInterval(-1*86400), beneficialMETs: 45),
            DailyPersonalizedMETSnapshot(date: Date(), beneficialMETs: 35)
        ]
    )
}
