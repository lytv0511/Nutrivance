//
//  MindfulnessRealm.swift
//  Nutrivance
//
//  Created by Vincent Leong on 2/25/25.
//

import SwiftUI

enum HapticEngine {
    static func play(_ type: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: type)
        generator.impactOccurred()
    }
    
    static let soft = UIImpactFeedbackGenerator.FeedbackStyle.soft
    static let light = UIImpactFeedbackGenerator.FeedbackStyle.light
    static let medium = UIImpactFeedbackGenerator.FeedbackStyle.medium
    static let rigid = UIImpactFeedbackGenerator.FeedbackStyle.rigid
    static let heavy = UIImpactFeedbackGenerator.FeedbackStyle.heavy
}

struct MindfulnessRealmView: View {
    @State private var animationPhase: Double = 0
    @State private var selectedMood: String = "calm"
    @State private var breathingActive = false
    @State private var showingJournal = false
    private let gradients = GradientBackgrounds()
    
    var body: some View {
        NavigationStack {
                ScrollView {
                    VStack(spacing: 24) {
                        // Enhanced Mindfulness Score with animation
                        MindfulnessScoreCard()
                        
                        // Mood Tracker
                        MoodTrackerCompact(selectedMood: $selectedMood)
                        
                        // Interactive Quick Actions
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            QuickActionCard(title: "Breathe", icon: "lungs.fill") {
                                withAnimation {
                                    breathingActive.toggle()
                                }
                            }
                            
                            QuickActionCard(title: "Meditate", icon: "sparkles") {
                                // Meditation action
                            }
                            
                            QuickActionCard(title: "Journal", icon: "book.fill") {
                                showingJournal = true
                            }
                            
                            QuickActionCard(title: "Track Mood", icon: "face.smiling.fill") {
                                // Mood tracking action
                            }
                        }
                        
                        // Daily Stats Card
                        DailyStatsCard()
                        
                        // Mindful Moments Timeline
                        MindfulMomentsTimeline()
                    }
                    .padding()
                
                // Breathing exercise overlay
                if breathingActive {
                    BreathingExerciseView(isActive: $breathingActive)
                        .transition(.opacity)
                }
            }
            .background(
               GradientBackgrounds().realmGradientFull(animationPhase: $animationPhase)
                   .onAppear {
                       withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                           animationPhase = 20
                       }
                   }
           )
            .sheet(isPresented: $showingJournal) {
                JournalView()
            }
            .onAppear {
                startAnimations()
            }
            .navigationTitle("Mindfulness Realm")
        }
    }
    
    private func startAnimations() {
        withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
            animationPhase = 1.0
        }
    }
}

struct MindfulnessScoreCard: View {
    @State private var score: Double = 0
    
    var body: some View {
        HStack {
            Spacer()
            VStack {
                Text("Daily Mindfulness Score")
                    .font(.title2.weight(.bold))
                
                ZStack {
                    Circle()
                        .stroke(.ultraThinMaterial, lineWidth: 12)
                        .frame(width: 120, height: 120)
                    
                    Circle()
                        .trim(from: 0, to: score)
                        .stroke(
                            AngularGradient(
                                colors: [.blue, .purple, .pink],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                    
                    Text("\(Int(score * 100))")
                        .font(.system(.title, design: .rounded))
                        .bold()
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 2)) {
                        score = 0.7
                    }
                }
            }
            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct QuickActionCard: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        VStack {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .scaleEffect(isPressed ? 0.9 : 1.0)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.3), lineWidth: 1)
                        .scaleEffect(isPressed ? 1.2 : 1.0)
                        .opacity(isPressed ? 0 : 1)
                }
            
            Text(title)
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        isPressed = true
                    }
                    HapticEngine.play(.soft)
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        isPressed = false
                    }
                    action()
                }
        )
    }
}

struct ParticleSystem: View {
    let size: CGSize
    @State private var particles: [Particle] = []
    
    init(in size: CGSize) {
        self.size = size
        _particles = State(initialValue: Array(repeating: Particle(), count: 15))
    }
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                for particle in particles {
                    context.opacity = particle.opacity
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: particle.x * size.width,
                            y: particle.y * size.height,
                            width: particle.size,
                            height: particle.size
                        )),
                        with: .color(.white)
                    )
                }
            }
        }
    }
}

struct Particle {
    var x = Double.random(in: 0...1)
    var y = Double.random(in: 0...1)
    var size = Double.random(in: 2...6)
    var opacity = Double.random(in: 0.1...0.5)
}

struct DailyStatsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily Stats")
                .font(.title2.bold())
            
            HStack {
                StatItem(value: "15", label: "Minutes Meditated", icon: "timer")
                StatItem(value: "3", label: "Mindful Sessions", icon: "sparkles")
            }
            
            HStack {
                StatItem(value: "85%", label: "Focus Score", icon: "brain.head.profile")
                StatItem(value: "High", label: "HRV Status", icon: "heart.fill")
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct MindfulMomentsTimeline: View {
    var body: some View {
        HStack {
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Text("Today's Journey")
                    .font(.title2.bold())
                
                ForEach(["Morning Meditation", "Mindful Break", "Evening Reflection"], id: \.self) { moment in
                    TimelineItem(time: "10:30 AM", title: moment)
                }
            }
            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct BreathingExerciseView: View {
    @Binding var isActive: Bool
    @State private var scale = 1.0
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack {
                Text("Breathe")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                
                Circle()
                    .stroke(.white, lineWidth: 2)
                    .frame(width: 200, height: 200)
                    .scaleEffect(scale)
                    .animation(
                        Animation.easeInOut(duration: 4)
                            .repeatForever(autoreverses: true),
                        value: scale
                    )
            }
        }
        .onAppear {
            scale = 1.5
        }
        .onTapGesture {
            withAnimation {
                isActive = false
            }
        }
    }
}

struct StatItem: View {
    let value: String
    let label: String
    let icon: String
    
    var body: some View {
        VStack {
            Image(systemName: icon)
                .font(.title2)
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct TimelineItem: View {
    let time: String
    let title: String
    
    var body: some View {
        HStack {
            Text(time)
                .font(.caption)
                .foregroundStyle(.secondary)
            Circle()
                .fill(.white)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.body)
        }
    }
}

struct MoodTrackerCompact: View {
    @Binding var selectedMood: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Mood")
                .font(.headline)
            
            MoodButtonsRow(selectedMood: $selectedMood)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct MoodButtonsRow: View {
    @Binding var selectedMood: String
    private let quickMoods = [
        "calm": "face.smiling",
        "focused": "brain.head.profile",
        "tired": "zzz"
    ]
    
    var body: some View {
        HStack(spacing: 12) {
            Spacer()
            ForEach(Array(quickMoods.keys), id: \.self) { mood in
                MoodButton(
                    mood: mood,
                    icon: quickMoods[mood] ?? "",
                    isSelected: selectedMood == mood
                ) {
                    selectedMood = mood
                }
            }
            Spacer()
        }
    }
}

struct MoodButton: View {
    let mood: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Circle()
            .fill(isSelected ? Color.blue : Color.secondary.opacity(0.2))
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: icon)
                    .foregroundColor(isSelected ? .white : .secondary)
            )
            .onTapGesture {
                withAnimation(.spring()) {
                    action()
                    HapticEngine.play(.light)
                }
            }
    }
}
