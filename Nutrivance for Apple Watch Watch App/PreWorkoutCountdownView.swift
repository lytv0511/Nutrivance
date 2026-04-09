import SwiftUI
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Pre-workout countdown view that shows a 3-second countdown
/// and waits for device/sensor connection before allowing workout to start
struct PreWorkoutCountdownView: View {
    @ObservedObject var workoutManager: WatchWorkoutManager
    @Binding var countdownSeconds: Int
    @Binding var countdownState: PreWorkoutCountdownState
    let onCountdownComplete: () -> Void
    let onCancel: () -> Void
    
    @State private var countdownTimer: Timer?
    
    var body: some View {
        VStack(spacing: 16) {
            switch countdownState {
            case .waitingForConnection:
                waitingForConnectionView
            case .connected:
                connectedView
            case .counting:
                countingView
            case .ready:
                readyView
            case .cancelled:
                cancelledView
            }
        }
        .padding()
        .onAppear {
            startCountdown()
        }
        .onDisappear {
            countdownTimer?.invalidate()
        }
    }
    
    @ViewBuilder
    private var waitingForConnectionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "applewatch")
                .font(.system(size: 44))
                .foregroundColor(.orange)
                .blinking()
            
            Text("Waiting for Watch")
                .font(.headline)
            
            Text("Make sure your watch is connected")
                .font(.caption)
                .foregroundColor(.secondary)
            
            ProgressView()
                .progressViewStyle(.circular)
                .padding(.top, 8)
            
            Button(action: onCancel) {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.top, 12)
        }
    }
    
    @ViewBuilder
    private var connectedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "applewatch.radiowaves")
                .font(.system(size: 44))
                .foregroundColor(.green)
            
            Text("Watch Connected")
                .font(.headline)
            
            Text("Sensors initialized")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Starting in 3...")
                .font(.title3)
                .padding(.top, 8)
        }
    }
    
    @ViewBuilder
    private var countingView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 4)
                    .frame(width: 100, height: 100)
                
                VStack(spacing: 0) {
                    Text("\(countdownSeconds)")
                        .font(.system(size: 48, weight: .bold, design: .default))
                        .monospacedDigit()
                    Text("seconds")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Text("Get ready...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private var readyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
                .scaleEffect(1.2)
            
            Text("Ready to Start")
                .font(.headline)
            
            Text("All systems go")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                onCountdownComplete()
            }
        }
    }
    
    @ViewBuilder
    private var cancelledView: some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.red)
            
            Text("Cancelled")
                .font(.headline)
        }
    }
    
    private func startCountdown() {
        // First, check if watch is connected
        Task {
            #if canImport(WatchConnectivity)
            let reachable = await checkWatchConnection()
            if reachable {
                DispatchQueue.main.async {
                    countdownState = .connected
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        startNumberCountdown()
                    }
                }
            }
            #endif
        }
    }
    
    private func checkWatchConnection() async -> Bool {
        #if canImport(WatchConnectivity)
        let session = WCSession.default
        if session.activationState == .activated && session.isReachable {
            return true
        }
        // Wait up to 3 seconds for connection
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            if session.isReachable {
                return true
            }
        }
        #endif
        return false
    }
    
    private func startNumberCountdown() {
        countdownState = .counting
        countdownSeconds = 3
        
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if countdownSeconds > 1 {
                countdownSeconds -= 1
                // Haptic feedback for each second (WatchKit WKInterfaceDevice.current().play(.success))
                // This will be triggered via the watch's haptic engine when properly configured
            } else {
                countdownTimer?.invalidate()
                countdownState = .ready
            }
        }
    }
}

extension View {
    func blinking() -> some View {
        modifier(BlinkingModifier())
    }
}

struct BlinkingModifier: ViewModifier {
    @State private var opacity: Double = 1.0
    
    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever()) {
                    opacity = 0.3
                }
            }
    }
}
