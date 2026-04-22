import SwiftUI
import Combine
import UniformTypeIdentifiers

class AppState: ObservableObject {
    @Published var modelPath: String? = nil
    @Published var statusText = "启动中..."
    @Published var modelLoaded = false
}

struct ContentView: View {
    @StateObject private var state = AppState()
    @State private var showFilePicker = false

    var body: some View {
        ZStack {
            ModelViewerView(state: state)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Text(state.statusText)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.6))
                        .clipShape(Capsule())
                    Spacer()
                    Button(action: {
                        showFilePicker = true
                    }) {
                        Image(systemName: "folder.badge.plus")
                            .font(.title2)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding()
                Spacer()
            }
        }
        .onAppear {
            loadBundledModel()
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType(filenameExtension: "pmx") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if url.startAccessingSecurityScopedResource() {
                    state.modelPath = url.path
                    state.statusText = "已加载: \(url.lastPathComponent)"
                }
            case .failure(let error):
                state.statusText = "错误: \(error.localizedDescription)"
            }
        }
    }

    func loadBundledModel() {
        if let pmxURL = Bundle.main.url(forResource: "Reika Shimohira 2 18 V1", withExtension: "pmx") {
            state.statusText = "找到模型，加载中..."
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                state.modelPath = pmxURL.path
                state.statusText = "Reika Shimohira 2 18 V1.pmx"
            }
        } else {
            let allPmx = Bundle.main.paths(forResourcesOfType: "pmx", inDirectory: nil)
            state.statusText = "未找到内置模型 (pmx: \(allPmx.count))"
        }
    }
}
