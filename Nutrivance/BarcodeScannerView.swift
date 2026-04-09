//import SwiftUI
//import AVFoundation
//import Vision
//
//struct BarcodeScannerView: View {
//    @StateObject private var scannerModel = BarcodeScannerModel()
//    @State private var showNutritionSheet = false
//    
//    var body: some View {
//        Group {
//            if scannerModel.cameraPermissionGranted {
//                ZStack {
//                    CameraPreview(session: scannerModel.session)
//                        .ignoresSafeArea()
//                    
//                    VStack {
//                        Text(scannerModel.lastScannedCode)
//                            .font(.headline)
//                            .foregroundColor(.white)
//                            .padding()
//                            .background(.ultraThinMaterial)
//                            .cornerRadius(10)
//                        
//                        Spacer()
//                        
//                        RoundedRectangle(cornerRadius: 2)
//                            .stroke(.green, lineWidth: 2)
//                            .frame(width: 250, height: 150)
//                            .padding()
//                    }
//                }
//            } else {
//                VStack {
//                    Image(systemName: "camera.slash")
//                        .font(.largeTitle)
//                    Text("Camera access needed to scan barcodes")
//                        .padding()
//                    Button("Open Settings") {
//                        if let url = URL(string: UIApplication.openSettingsURLString) {
//                            UIApplication.shared.open(url)
//                        }
//                    }
//                }
//            }
//        }
//        .sheet(isPresented: $showNutritionSheet) {
//            if let product = scannerModel.scannedProduct {
//                BarcodeNutritionView(product: product)
//            }
//        }
//        .onAppear {
//            if scannerModel.cameraPermissionGranted {
//                scannerModel.startScanning { success in
//                    if success {
//                        showNutritionSheet = true
//                    }
//                }
//            }
//        }
//    }
//}
//
//class BarcodeScannerModel: NSObject, ObservableObject {
//    @Published var lastScannedCode = ""
//    @Published var scannedProduct: Product?
//    
//    let session = AVCaptureSession()
//    @Published var cameraPermissionGranted = false
//
//    private let apiBaseURL = "https://world.openfoodfacts.org/api/v0/product/"
//
//    override init() {
//        super.init()
//        checkCameraPermission()
//    }
//
//    private func checkCameraPermission() {
//        switch AVCaptureDevice.authorizationStatus(for: .video) {
//        case .authorized:
//            self.cameraPermissionGranted = true
//        case .notDetermined:
//            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
//                DispatchQueue.main.async {
//                    self?.cameraPermissionGranted = granted
//                }
//            }
//        default:
//            self.cameraPermissionGranted = false
//        }
//    }
//    
//    struct Product: Codable {
//        let name: String
//        let nutriments: Nutriments
//        
//        struct Nutriments: Codable {
//            let energy: Double?
//            let proteins: Double?
//            let carbohydrates: Double?
//            let fat: Double?
//            let fiber: Double?
//            let sodium: Double?
//            
//            enum CodingKeys: String, CodingKey {
//                case energy = "energy-kcal_100g"
//                case proteins = "proteins_100g"
//                case carbohydrates = "carbohydrates_100g"
//                case fat = "fat_100g"
//                case fiber = "fiber_100g"
//                case sodium = "sodium_100g"
//            }
//        }
//    }
//    
//    func startScanning(completion: @escaping (Bool) -> Void) {
//        guard let device = AVCaptureDevice.default(for: .video) else { return }
//        
//        do {
//            let input = try AVCaptureDeviceInput(device: device)
//            session.addInput(input)
//            
//            let output = AVCaptureVideoDataOutput()
//            output.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: .userInitiated))
//            session.addOutput(output)
//            
//            DispatchQueue.global(qos: .userInitiated).async {
//                self.session.startRunning()
//            }
//        } catch {
//            print("Camera setup failed: \(error)")
//        }
//    }
//    
//    func fetchProductInfo(barcode: String) {
//        let url = URL(string: "\(apiBaseURL)\(barcode).json")!
//        
//        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
//            guard let data = data else { return }
//            
//            do {
//                let product = try JSONDecoder().decode(Product.self, from: data)
//                DispatchQueue.main.async {
//                    self?.scannedProduct = product
//                }
//            } catch {
//                print("Decoding failed: \(error)")
//            }
//        }.resume()
//    }
//}
//
//extension BarcodeScannerModel: AVCaptureVideoDataOutputSampleBufferDelegate {
//    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
//        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
//        
//        let request = VNDetectBarcodesRequest { [weak self] request, error in
//            guard let results = request.results as? [VNBarcodeObservation],
//                  let barcode = results.first?.payloadStringValue else { return }
//            
//            DispatchQueue.main.async {
//                self?.lastScannedCode = barcode
//                self?.fetchProductInfo(barcode: barcode)
//            }
//        }
//        
//        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
//    }
//}
//
//struct CameraPreview: UIViewRepresentable {
//    let session: AVCaptureSession
//    
//    func makeUIView(context: Context) -> UIView {
//        let view = UIView(frame: .zero)
//        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
//        previewLayer.frame = view.frame
//        previewLayer.videoGravity = .resizeAspectFill
//        view.layer.addSublayer(previewLayer)
//        return view
//    }
//    
//    func updateUIView(_ uiView: UIView, context: Context) {
//        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
//            previewLayer.frame = uiView.frame
//        }
//    }
//}
//
//struct BarcodeNutritionView: View {
//    let product: BarcodeScannerModel.Product
//    
//    var body: some View {
//        ScrollView {
//            VStack(alignment: .leading, spacing: 20) {
//                Text(product.name)
//                    .font(.title)
//                    .bold()
//                
//                Group {
//                    NutrientRow(nutrient: "Energy: \(product.nutriments.energy ?? 0) kcal")
//                    NutrientRow(nutrient: "Protein: \(product.nutriments.proteins ?? 0) g")
//                    NutrientRow(nutrient: "Carbohydrates: \(product.nutriments.carbohydrates ?? 0) g")
//                    NutrientRow(nutrient: "Fat: \(product.nutriments.fat ?? 0) g")
//                    NutrientRow(nutrient: "Fiber: \(product.nutriments.fiber ?? 0) g")
//                    NutrientRow(nutrient: "Sodium: \(product.nutriments.sodium ?? 0) g")
//                }
//                .padding(.horizontal)
//            }
//            .padding()
//        }
//        .background(.ultraThinMaterial)
//    }
//}
