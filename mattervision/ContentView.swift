import SwiftUI
import AVFoundation
import SceneKit
import Combine

// MARK: - App State

enum AppScreen {
    case camera, loading, mesh
}

// MARK: - Root

struct ContentView: View {
    @State private var screen: AppScreen = .camera

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch screen {
            case .camera:
                CameraScreen { screen = .loading }
            case .loading:
                LoadingScreen { screen = .mesh }
            case .mesh:
                MeshScreen { screen = .camera }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: screen)
    }
}

// MARK: - Screen 1: Camera

class CameraSessionManager: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let objectWillChange = ObservableObjectPublisher()
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    var onCapture: (() -> Void)?

    override init() {
        super.init()
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { session.commitConfiguration(); return }
        session.addInput(input)
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        session.commitConfiguration()
    }

    func start() { DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() } }
    func stop()  { session.stopRunning() }

    func capture() {
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        DispatchQueue.main.async { self.onCapture?() }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {}
}

class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraScreen: View {
    var onCapture: () -> Void
    @StateObject private var camera = CameraSessionManager()
    @State private var flash = false

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session).ignoresSafeArea()

            Color.white
                .opacity(flash ? 1 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.15), value: flash)

            VStack {
                Spacer()
                Button {
                    flash = true
                    camera.capture()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { flash = false }
                } label: {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 72, height: 72)
                        Circle().fill(.white).frame(width: 58, height: 58)
                    }
                }
                .padding(.bottom, 52)
            }
        }
        .onAppear { camera.onCapture = onCapture; camera.start() }
        .onDisappear { camera.stop() }
    }
}

// MARK: - Screen 2: Loading

struct LoadingScreen: View {
    var onComplete: () -> Void

    private let messages = [
        "taking a break and eating a sandwich",
        "consulting the mesh wizard",
        "counting triangles manually",
        "teaching pixels to behave",
        "asking the GPU nicely",
        "untangling vertex soup",
        "converting sadness to polygons",
        "negotiating with the renderer",
        "herding stray normals",
        "bribing the depth buffer",
    ]

    @State private var progress: Double = 0
    @State private var messageIndex = 0
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()

                Text("processing mesh")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white)
                            .frame(width: geo.size.width * progress, height: 3)
                            .animation(.linear(duration: 0.05), value: progress)
                    }
                }
                .frame(width: 240, height: 3)

                Text(messages[messageIndex])
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .italic()
                    .multilineTextAlignment(.center)
                    .frame(width: 280)
                    .id(messageIndex)
                    .transition(.opacity)

                Spacer()
            }
        }
        .onAppear { startLoading() }
        .onDisappear { timer?.invalidate() }
    }

    private func startLoading() {
        let total = 3.5
        let interval = 0.05
        let steps = total / interval

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { t in
            progress = min(progress + 1.0 / steps, 1.0)
            let next = min(Int(progress * Double(messages.count - 1)), messages.count - 1)
            if next != messageIndex {
                withAnimation(.easeInOut(duration: 0.3)) { messageIndex = next }
            }
            if progress >= 1.0 {
                t.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onComplete() }
            }
        }
    }
}

// MARK: - Screen 3: Mesh Viewer

struct MeshSceneView: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = buildScene()
        view.backgroundColor = .black
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    private func buildScene() -> SCNScene {
        let scene = SCNScene()

        let sphere = SCNSphere(radius: 1.0)
        sphere.segmentCount = 14

        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.1, green: 0.85, blue: 0.6, alpha: 1)
        mat.fillMode = .lines
        mat.isDoubleSided = true
        sphere.materials = [mat]

        let node = SCNNode(geometry: sphere)
        node.runAction(.repeatForever(.rotateBy(x: 0.3, y: 2 * .pi, z: 0, duration: 9)))
        scene.rootNode.addChildNode(node)

        let camNode = SCNNode()
        camNode.camera = SCNCamera()
        camNode.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(camNode)

        return scene
    }
}

struct MeshScreen: View {
    var onExit: () -> Void

    private let capturedAt = Date()
    private let metadata: [(String, String)] = [
        ("vertices", "5,184"),
        ("faces",    "2,592"),
        ("dims",     "12.4 × 9.1 × 8.3 cm"),
        ("format",   "OBJ"),
    ]

    var body: some View {
        ZStack(alignment: .top) {
            MeshSceneView().ignoresSafeArea()

            HStack(alignment: .top) {
                // Metadata — top left
                VStack(alignment: .leading, spacing: 4) {
                    Text(formattedDate(capturedAt))
                    ForEach(metadata, id: \.0) { key, value in
                        Text("\(key): \(value)")
                    }
                }
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))

                Spacer()

                // Exit — top right
                Button("exit") { onExit() }
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return "captured: \(f.string(from: date))"
    }
}

#Preview {
    ContentView()
}
