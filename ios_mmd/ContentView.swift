import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var modelPath: String?
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
                    // Note: keep security scope alive while model is loaded
                }
            case .failure(let error):
                print("File picker error: \(error)")
            }
        }
    }
}
