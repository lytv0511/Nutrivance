import Foundation
import SwiftUI
import AVFoundation

struct UnifiedLogView: View {
    @StateObject private var viewModel = UnifiedLoggingViewModel()
    @State private var description = ""
    @State private var showingCamera = false
    @State private var capturedImage: UIImage?
    @State private var orientation = UIDevice.current.orientation
    @State private var animationPhase: Double = 0
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    CameraPreview(session: viewModel.session)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(4/3, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(alignment: .trailing) {
                            VStack(spacing: 12) {
                                if viewModel.hasVisibleText {
                                    Image(systemName: "doc.text.viewfinder")
                                        .foregroundStyle(.blue)
                                }
                                if viewModel.hasVisibleBarcode {
                                    Image(systemName: "barcode.viewfinder")
                                        .foregroundStyle(.green)
                                }
                                if viewModel.hasVisibleFood {
                                    Image(systemName: "camera.metering.center")
                                        .foregroundStyle(.orange)
                                }
                            }
                            .font(.title2)
                            .padding()
                        }
                        .padding()
                        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                            if let connection = viewModel.session.connections.first,
                               let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                               let previewLayer = (connection.videoPreviewLayer) {
                                if #available(iOS 17.0, *) {
                                    let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
                                    connection.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelCapture
                                }
                            }
                        }
                    
                    VStack(spacing: 16) {
                        TextField("Describe what you're logging...", text: $description)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)
                        
                        HStack(spacing: 20) {
                            Button(action: viewModel.capturePhoto) {
                                Image(systemName: "camera.circle.fill")
                                    .font(.system(size: 64))
                            }
                            .disabled(!viewModel.canTakePhoto)
                            
                            Button("Analyze") {
                                Task {
                                    await viewModel.analyzeInput(description: description, image: capturedImage)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!viewModel.canAnalyze)
                        }
                        .padding()
                    }
                }
                .sheet(isPresented: $viewModel.showingResults) {
                    NutrientResultsView(results: viewModel.analysisResults)
                }
                .onAppear {
                    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                }
                .onDisappear {
                    UIDevice.current.endGeneratingDeviceOrientationNotifications()
                }
            }
            .background(
                GradientBackgrounds().natureGradient(animationPhase: $animationPhase)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                            animationPhase = 20
                        }
                    }
            )
            .navigationTitle("Log Nutrients")
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }
        
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
    
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.frame = uiView.bounds
        if let connection = uiView.videoPreviewLayer.connection,
           let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            if #available(iOS 17.0, *) {
                let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: uiView.videoPreviewLayer)
                connection.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelCapture
            }
        }
    }
}

struct NutrientResultsView: View {
    let results: NutrientAnalysis?
    
    var body: some View {
        List {
            if let nutrients = results?.nutrients {
                ForEach(nutrients.keys.sorted(), id: \.self) { nutrient in
                    HStack {
                        Text(nutrient)
                        Spacer()
                        Text("\(nutrients[nutrient] ?? 0, specifier: "%.1f")")
                    }
                }
            }
        }
    }
}

struct NutrientAnalysis {
    var nutrients: [String: Double]
    var confidence: Double
    var source: AnalysisSource
    
    enum AnalysisSource {
        case text
        case image
        case combined
    }
}

class UnifiedLoggingViewModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var hasVisibleText = false
    @Published var hasVisibleBarcode = false
    @Published var hasVisibleFood = false
    @Published var showingResults = false
    @Published var analysisResults: NutrientAnalysis?
    @Published var capturedImage: UIImage?
    
    let session = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    
    var canTakePhoto: Bool {
        session.isRunning
    }
    
    var canAnalyze: Bool {
        hasVisibleText || hasVisibleBarcode || hasVisibleFood
    }
    
    override init() {
        super.init()
        checkCameraAuthorization()
    }
    
    private func checkCameraAuthorization() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            DispatchQueue.global(qos: .userInitiated).async {
                self.setupCamera()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.global(qos: .userInitiated).async {
                        self.setupCamera()
                    }
                }
            }
        default:
            break
        }
    }
    
    private func setupCamera() {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                return
            }
            
            self.session.beginConfiguration()
            self.session.addInput(input)
            self.session.addOutput(self.photoOutput)
            
            if let connection = self.photoOutput.connection(with: .video) {
                if #available(iOS 17.0, *) {
                    if let previewLayer = connection.videoPreviewLayer {
                        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
                        connection.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelCapture
                    }
                }
            }
            
            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }
    
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else { return }
        
        DispatchQueue.main.async {
            self.capturedImage = image
        }
    }
    
    @MainActor
    func analyzeInput(description: String, image: UIImage?) async {
        let textResults = await processText(description)
        let imageResults = await processImage(image)
        analysisResults = combineResults(textResults, imageResults)
        showingResults = true
    }
    
    private func processText(_ text: String) async -> NutrientAnalysis {
        return NutrientAnalysis(nutrients: [:], confidence: 0.0, source: .text)
    }
    
    private func processImage(_ image: UIImage?) async -> NutrientAnalysis {
        return NutrientAnalysis(nutrients: [:], confidence: 0.0, source: .image)
    }
    
    private func combineResults(_ textResults: NutrientAnalysis, _ imageResults: NutrientAnalysis) -> NutrientAnalysis {
        return NutrientAnalysis(nutrients: [:], confidence: 0.0, source: .combined)
    }
}
