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
    @State private var showModelPicker = false
    @State private var bundledModels: [(name: String, path: String)] = []

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

                    Button {
                        showModelPicker = true
                    } label: {
                        Image(systemName: "cube")
                            .font(.title2)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    Button {
                        showFilePicker = true
                    } label: {
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
            findBundledModels()
            if let first = bundledModels.first {
                loadModel(name: first.name, path: first.path)
            }
        }
        .confirmationDialog("选择模型", isPresented: $showModelPicker) {
            ForEach(bundledModels, id: \.path) { model in
                Button(model.name) {
                    loadModel(name: model.name, path: model.path)
                }
            }
            Button("取消", role: .cancel) {}
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
                    state.statusText = url.lastPathComponent
                }
            case .failure(let error):
                state.statusText = "错误: \(error.localizedDescription)"
            }
        }
    }

    func findBundledModels() {
        let paths = Bundle.main.paths(forResourcesOfType: "pmx", inDirectory: nil)
        bundledModels = paths.map { path in
            let name = (path as NSString).lastPathComponent
            return (name: name, path: path)
        }.sorted { $0.name < $1.name }
    }

    func loadModel(name: String, path: String) {
        state.statusText = "加载中..."
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            state.modelPath = path
            state.statusText = name
        }
    }
}
