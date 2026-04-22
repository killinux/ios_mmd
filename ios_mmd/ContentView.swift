import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var modelPath: String? = nil
    @State private var showFilePicker = false

    var body: some View {
        ZStack {
            ModelViewerView(modelPath: modelPath)
                .ignoresSafeArea()

            VStack {
                HStack {
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
                    .padding()
                }
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
                    modelPath = url.path
                }
            case .failure(let error):
                print("File picker error: \(error)")
            }
        }
    }

    func loadBundledModel() {
        if let pmxURL = Bundle.main.url(forResource: "Reika Shimohira 2 18 V1", withExtension: "pmx", subdirectory: "Reika Shimohira 2 18") {
            modelPath = pmxURL.path
        }
    }
}
