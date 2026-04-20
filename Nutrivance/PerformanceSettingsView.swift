import SwiftUI

struct PerformanceSettingsView: View {
    @ObservedObject private var profile = PerformanceProfileSettings.shared
    @State private var showResetConfirmation = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackgrounds().forestGradient(animationPhase: .constant(0))
                    .ignoresSafeArea()
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        // MARK: - Master Toggle
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "bolt.fill")
                                    .font(.title3)
                                    .foregroundColor(.orange)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Pro-Athlete Mode")
                                        .font(.headline)
                                    Text("Advanced performance metrics for elite training")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: $profile.isProAthleteMode)
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                            
                            if profile.isProAthleteMode {
                                Text("All optimization features are now active. Configure thresholds below to match your training profile.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.horizontal)
                        
                        if profile.isProAthleteMode {
                            // MARK: - Dynamic Metrics Section
                            settingSection(
                                title: "Dynamic Metrics",
                                description: "Adjust HRV and sleep weighting based on training load",
                                content: {
                                    VStack(spacing: 16) {
                                        // Strain-Sensitive HRV Toggle
                                        settingRow(
                                            title: "Strain-Sensitive HRV",
                                            description: "Boost HRV weight to 50% when training load is high",
                                            isOn: $profile.enableStrainSensitiveHRV,
                                            icon: "heart.fill",
                                            iconColor: .red
                                        )
                                        
                                        Divider().padding(.vertical, 4)
                                        
                                        // Chronic Load Percentile Slider
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text("High Load Threshold")
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                                Spacer()
                                                Text(String(format: "%.0f%%", profile.chronicLoadPercentile * 100))
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            Slider(
                                                value: $profile.chronicLoadPercentile,
                                                in: 0.5...0.95,
                                                step: 0.05
                                            )
                                            .tint(.orange)
                                            Text("Triggers at top \(String(format: "%.0f%%", (1 - profile.chronicLoadPercentile) * 100)) of athlete's chronic load range")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.vertical, 8)
                                        
                                        Divider().padding(.vertical, 4)
                                        
                                        // HRV Bell-Curve Toggle
                                        settingRow(
                                            title: "HRV Bell-Curve Cap",
                                            description: "Flag extremely high HRV as parasympathetic overactivity",
                                            isOn: $profile.enableHRVBellCurveCap,
                                            icon: "waveform.circle.fill",
                                            iconColor: .red
                                        )
                                        
                                        Divider().padding(.vertical, 4)
                                        
                                        // HRV Z-Score Cap Slider
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text("HRV Z-Score Cap")
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                                Spacer()
                                                Text(String(format: "%.1f σ", profile.hrvZScoreCap))
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            Slider(
                                                value: $profile.hrvZScoreCap,
                                                in: 1.5...3.5,
                                                step: 0.1
                                            )
                                            .tint(.red)
                                            Text("HRV above \(String(format: "%.1f", profile.hrvZScoreCap)) standard deviations signals potential deep fatigue, not peak recovery")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.vertical, 8)
                                        
                                        Divider().padding(.vertical, 4)
                                        
                                        // Sleep Quality Toggle
                                        settingRow(
                                            title: "Sleep Quality Penalty",
                                            description: "Penalize fragmented sleep despite adequate duration",
                                            isOn: $profile.enableSleepQualityPenalty,
                                            icon: "moon.zzz.fill",
                                            iconColor: .indigo
                                        )
                                    }
                                    .padding()
                                }
                            )
                            
                            // MARK: - Training Load Section
                            settingSection(
                                title: "Training Load Analysis",
                                description: "Monitor acute-to-chronic load ratio (ACWR) for injury prevention",
                                content: {
                                    VStack(spacing: 16) {
                                        // ACWR Toggle
                                        settingRow(
                                            title: "ACWR Logic",
                                            description: "Reward optimal loading (0.8–1.3) and penalize dangerous zones",
                                            isOn: $profile.enableACWRLogic,
                                            icon: "chart.line.uptrend.xyaxis",
                                            iconColor: .green
                                        )
                                        
                                        Divider().padding(.vertical, 4)
                                        
                                        // ACWR Optimal Range Sliders
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text("Optimal ACWR Range")
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                                Spacer()
                                                Text("\(String(format: "%.2f", profile.acwrOptimalMin))–\(String(format: "%.2f", profile.acwrOptimalMax))")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            HStack(spacing: 8) {
                                                Slider(
                                                    value: $profile.acwrOptimalMin,
                                                    in: 0.5...0.95,
                                                    step: 0.05
                                                )
                                                .tint(.green)
                                                Text("Min")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            HStack(spacing: 8) {
                                                Slider(
                                                    value: $profile.acwrOptimalMax,
                                                    in: 1.05...1.6,
                                                    step: 0.05
                                                )
                                                .tint(.green)
                                                Text("Max")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            Text("Sweet spot for injury prevention and adaptation. Values outside this range reduce readiness.")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.vertical, 8)
                                        
                                        Divider().padding(.vertical, 4)
                                        
                                        // ACWR Danger Threshold Slider
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text("ACWR Danger Threshold")
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                                Spacer()
                                                Text(String(format: "%.2f", profile.acwrDangerThreshold))
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            Slider(
                                                value: $profile.acwrDangerThreshold,
                                                in: 1.3...1.8,
                                                step: 0.05
                                            )
                                            .tint(.red)
                                            Text("ACWR above this ratio triggers significant readiness penalty (up to −40 points)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.vertical, 8)
                                    }
                                    .padding()
                                }
                            )
                            
                            // MARK: - Strain Modeling Section
                            settingSection(
                                title: "Strain Modeling",
                                description: "Advanced load interpretation for precision performance",
                                content: {
                                    VStack(spacing: 16) {
                                        // Asymmetric Strain Toggle
                                        settingRow(
                                            title: "Asymmetric Strain Penalty",
                                            description: "Apply multiplicative penalty at high strain levels",
                                            isOn: $profile.enableAsymmetricStrainPenalty,
                                            icon: "chart.bar.xaxis",
                                            iconColor: .orange
                                        )
                                        
                                        Divider().padding(.vertical, 4)
                                        
                                        // Taper Detection Toggle
                                        settingRow(
                                            title: "Taper Detection",
                                            description: "Cap readiness at 88 to prevent over-enthusiasm during planned rest",
                                            isOn: $profile.enableTaperDetection,
                                            icon: "pause.fill",
                                            iconColor: .yellow
                                        )
                                        
                                        Divider().padding(.vertical, 4)
                                        
                                        // Exponential Zone Weighting Toggle
                                        settingRow(
                                            title: "Exponential Zone Weighting",
                                            description: "Zone 5 contributes 9x more load than base; Zone 1 contributes 1x",
                                            isOn: $profile.enableExponentialZoneWeighting,
                                            icon: "bolt.circle.fill",
                                            iconColor: .purple
                                        )
                                    }
                                    .padding()
                                }
                            )
                            
                            // MARK: - Subjective Data Section
                            settingSection(
                                title: "Subjective Data Collection",
                                description: "Optional daily ratings to refine recovery estimates",
                                content: {
                                    VStack(spacing: 16) {
                                        settingRow(
                                            title: "Daily Ratings",
                                            description: "Collect soreness, stress, and sleep quality (1–10 scale)",
                                            isOn: $profile.enableSubjectiveDataCollection,
                                            icon: "checkmark.circle.fill",
                                            iconColor: .green
                                        )
                                        
                                        if profile.enableSubjectiveDataCollection {
                                            Divider().padding(.vertical, 4)
                                            
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text("Impact Range")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.secondary)
                                                HStack(spacing: 16) {
                                                    VStack(alignment: .center, spacing: 4) {
                                                        Text("−5 pts")
                                                            .font(.caption2)
                                                            .fontWeight(.bold)
                                                            .foregroundColor(.red)
                                                        Text("High stress\nHigh soreness")
                                                            .font(.caption2)
                                                            .foregroundColor(.secondary)
                                                            .multilineTextAlignment(.center)
                                                    }
                                                    Divider()
                                                    VStack(alignment: .center, spacing: 4) {
                                                        Text("+5 pts")
                                                            .font(.caption2)
                                                            .fontWeight(.bold)
                                                            .foregroundColor(.green)
                                                        Text("Low stress\nLow soreness")
                                                            .font(.caption2)
                                                            .foregroundColor(.secondary)
                                                            .multilineTextAlignment(.center)
                                                    }
                                                }
                                            }
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 12)
                                            .background(Color(.systemGray6))
                                            .cornerRadius(8)
                                        }
                                    }
                                    .padding()
                                }
                            )
                            
                            // MARK: - Personalized MET Section
                            settingSection(
                                title: "Personalized MET Tracking",
                                description: "Measure effort intensity personalized to your fitness level",
                                content: {
                                    VStack(spacing: 16) {
                                        // Master MET Toggle
                                        settingRow(
                                            title: "Personalized MET Mode",
                                            description: "Track effort as % of your personal max METs",
                                            isOn: $profile.enablePersonalizedMET,
                                            icon: "bolt.badge.fill",
                                            iconColor: .blue
                                        )
                                        
                                        if profile.enablePersonalizedMET {
                                            Divider().padding(.vertical, 4)
                                            
                                            // Max METs Input
                                            VStack(alignment: .leading, spacing: 8) {
                                                HStack {
                                                    Text("Your Max METs")
                                                        .font(.subheadline)
                                                        .fontWeight(.semibold)
                                                    Spacer()
                                                    Text(String(format: "%.1f", profile.personalizedMETProfile.maxMETs))
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                Slider(
                                                    value: $profile.personalizedMETProfile.maxMETs,
                                                    in: 8...30,
                                                    step: 0.5
                                                )
                                                .tint(.blue)
                                                HStack(spacing: 12) {
                                                    Button(action: {
                                                        if let derivedMax = sharedDeriveMaxMETsFromHistory(engine: HealthStateEngine.shared) {
                                                            profile.personalizedMETProfile.maxMETs = derivedMax
                                                            profile.personalizedMETProfile.estimationMethod = .historicalMax
                                                            profile.personalizedMETProfile.calibrationDate = Date()
                                                        }
                                                    }) {
                                                        Text("Calculate from History")
                                                            .font(.caption2)
                                                            .foregroundColor(.blue)
                                                    }
                                                    Text("•")
                                                        .foregroundColor(.secondary)
                                                    Text("Current: \(profile.personalizedMETProfile.estimationMethod.description)")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                                .padding(.top, 4)
                                            }
                                            .padding(.vertical, 8)
                                            
                                            Divider().padding(.vertical, 4)
                                            
                                            // Beneficial MET Threshold
                                            VStack(alignment: .leading, spacing: 8) {
                                                HStack {
                                                    Text("Beneficial MET Threshold")
                                                        .font(.subheadline)
                                                        .fontWeight(.semibold)
                                                    Spacer()
                                                    Text(String(format: "%.0f%%", profile.personalizedMETProfile.beneficialMETThresholdPercentage * 100))
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                Slider(
                                                    value: $profile.personalizedMETProfile.beneficialMETThresholdPercentage,
                                                    in: 0.3...0.8,
                                                    step: 0.05
                                                )
                                                .tint(.blue)
                                                Text("Only METs above this % of your max contribute to cardiovascular gains")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            .padding(.vertical, 8)
                                            
                                            Divider().padding(.vertical, 4)
                                            
                                            // Adaptive Threshold Toggle
                                            settingRow(
                                                title: "Daily Adaptive Threshold",
                                                description: "Adjust threshold based on recovery score",
                                                isOn: $profile.useDailyAdaptiveThreshold,
                                                icon: "waveform.path",
                                                iconColor: .green
                                            )
                                        }
                                    }
                                    .padding()
                                }
                            )
                            
                            // MARK: - Reset Button
                            VStack(spacing: 12) {
                                Button(action: { showResetConfirmation = true }) {
                                    HStack {
                                        Image(systemName: "arrow.counterclockwise.circle.fill")
                                        Text("Reset to Defaults")
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(.systemBackground))
                                    .cornerRadius(12)
                                }
                                
                                Text("All settings will return to factory defaults. This action cannot be undone.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                            }
                            .padding(.horizontal)
                        }
                        
                        Spacer(minLength: 20)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Performance Mode")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Reset to Defaults?",
                isPresented: $showResetConfirmation,
                actions: {
                    Button("Reset", role: .destructive) {
                        profile.resetToDefaults()
                    }
                    Button("Cancel", role: .cancel) { }
                },
                message: {
                    Text("All Pro-Athlete settings will return to defaults. This cannot be undone.")
                }
            )
        }
    }
    
    // MARK: - Helper Views
    
    @ViewBuilder
    private func settingSection<Content: View>(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            content()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private func settingRow(
        title: String,
        description: String,
        isOn: Binding<Bool>,
        icon: String,
        iconColor: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: isOn)
        }
    }
}

#Preview {
    PerformanceSettingsView()
}
