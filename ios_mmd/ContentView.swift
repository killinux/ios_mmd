import SwiftUI
import Combine
import UniformTypeIdentifiers

class AppState: ObservableObject {
    @Published var modelPath: String? = nil
    @Published var statusText = "启动中..."
    @Published var modelLoaded = false
    @Published var vmdPath: String? = nil
}

struct ContentView: View {
    @StateObject private var state = AppState()
    @State private var showFilePicker = false
    @State private var showModelPicker = false
    @State private var showVMDPicker = false
    @State private var bundledModels: [(name: String, path: String)] = []
    @State private var bundledVMDs: [(name: String, path: String)] = []
    @State private var isPlaying = false

    var body: some View {
        ZStack {
            ModelViewerView(state: state)
                .ignoresSafeArea()

            VStack {
                HStack(spacing: 8) {
                    Text(state.statusText)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.6))
                        .clipShape(Capsule())
                    Spacer()

                    Button { showModelPicker = true } label: {
                        Image(systemName: "cube")
                            .font(.title3)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    Button { showVMDPicker = true } label: {
                        Image(systemName: "figure.dance")
                            .font(.title3)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    Button { showFilePicker = true } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.title3)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer()
            }
        }
        .onAppear {
            findBundledFiles()
            if let first = bundledModels.first {
                loadModel(name: first.name, path: first.path)
            }
        }
        .confirmationDialog("选择模型", isPresented: $showModelPicker) {
            ForEach(bundledModels, id: \.path) { m in
                Button(m.name) { loadModel(name: m.name, path: m.path) }
            }
        }
        .confirmationDialog("选择动作", isPresented: $showVMDPicker) {
            ForEach(bundledVMDs, id: \.path) { v in
                Button(v.name) {
                    state.vmdPath = v.path
                    state.statusText = "\(state.statusText.components(separatedBy: " | ").first ?? "") | \(v.name)"
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType(filenameExtension: "pmx") ?? .data, UTType(filenameExtension: "vmd") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                if url.startAccessingSecurityScopedResource() {
                    if url.pathExtension.lowercased() == "vmd" {
                        state.vmdPath = url.path
                    } else {
                        state.modelPath = url.path
                        state.statusText = url.lastPathComponent
                    }
                }
            }
        }
    }

    func findBundledFiles() {
        bundledModels = Bundle.main.paths(forResourcesOfType: "pmx", inDirectory: nil)
            .map { (name: ($0 as NSString).lastPathComponent, path: $0) }
            .sorted { $0.name < $1.name }
        bundledVMDs = Bundle.main.paths(forResourcesOfType: "vmd", inDirectory: nil)
            .map { (name: ($0 as NSString).lastPathComponent, path: $0) }
            .sorted { $0.name < $1.name }
    }

    func loadModel(name: String, path: String) {
        state.statusText = "加载中..."
        state.vmdPath = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            state.modelPath = path
            state.statusText = name
        }
    }
}
