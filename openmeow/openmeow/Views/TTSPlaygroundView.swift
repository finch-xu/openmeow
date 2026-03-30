import SwiftUI
import AVFoundation

struct TTSPlaygroundView: View {
    @Environment(AppState.self) private var appState

    @State private var inputText = "Hello, welcome to OpenMeow!"
    @State private var selectedModelID = ""
    @State private var selectedVoiceID = ""
    @State private var speed: Double = 1.0
    @State private var isGenerating = false
    @State private var elapsedTime: Double?
    @State private var errorMessage: String?
    @State private var audioPlayer: AVAudioPlayer?

    private var availableModels: [ModelRegistryEntry] {
        appState.ttsModels.filter { appState.downloadState(for: $0.id) == .running }
    }

    private var selectedModel: ModelRegistryEntry? {
        availableModels.first { $0.id == selectedModelID }
    }

    private var voices: [VoiceInfo] {
        selectedModel?.voiceList ?? []
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: Controls
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Text input
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Text", systemImage: "text.alignleft")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $inputText)
                            .font(.body)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(.background)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.quaternary, lineWidth: 1)
                            )
                    }

                    // Model & Voice
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Model")
                                    .frame(width: 70, alignment: .trailing)
                                Picker("Model", selection: $selectedModelID) {
                                    if availableModels.isEmpty {
                                        Text("No models").tag("")
                                    }
                                    ForEach(availableModels) { m in
                                        Text(m.displayName.localized).tag(m.id)
                                    }
                                }
                                .labelsHidden()
                                Spacer()
                            }

                            if !voices.isEmpty {
                                HStack {
                                    Text("Voice")
                                        .frame(width: 70, alignment: .trailing)
                                    Picker("Voice", selection: $selectedVoiceID) {
                                        ForEach(voices, id: \.id) { v in
                                            Text("\(v.name) (\(v.gender ?? ""))")
                                                .tag(v.id)
                                        }
                                    }
                                    .labelsHidden()
                                    Spacer()
                                }
                            }

                            HStack {
                                Text("Speed")
                                    .frame(width: 70, alignment: .trailing)
                                Slider(value: $speed, in: 0.5...2.0, step: 0.1)
                                Text("\(speed, specifier: "%.1f")x")
                                    .font(.caption.monospaced())
                                    .frame(width: 32)
                            }
                        }
                    } label: {
                        Label("Settings", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.medium))
                    }
                }
                .padding(20)
            }
            .frame(minWidth: 260, maxWidth: 320)

            Divider()

            // Right: Playback
            VStack(spacing: 20) {
                Spacer()

                // Play button
                Button(action: generateAndPlay) {
                    ZStack {
                        Circle()
                            .fill(isGenerating ? Color.secondary.opacity(0.2) : Color.accentColor)
                            .frame(width: 72, height: 72)
                        Image(systemName: isGenerating ? "hourglass" : "play.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isGenerating || inputText.isEmpty || selectedModelID.isEmpty)

                Text(isGenerating ? "Generating..." : "Generate & Play")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Status row
                HStack(spacing: 12) {
                    if let elapsed = elapsedTime {
                        Label(String(format: "%.2fs", elapsed), systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if audioPlayer != nil {
                        Button { audioPlayer?.play() } label: {
                            Label("Replay", systemImage: "arrow.counterclockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .onAppear { autoSelectModel() }
        .onChange(of: appState.loadedModels) { autoSelectModel() }
        .onChange(of: selectedModelID) {
            if let model = selectedModel, let first = model.voiceList?.first {
                selectedVoiceID = first.id
            }
        }
    }

    private func autoSelectModel() {
        if selectedModelID.isEmpty, let first = availableModels.first {
            selectedModelID = first.id
        }
    }

    private func generateAndPlay() {
        isGenerating = true
        errorMessage = nil
        elapsedTime = nil

        Task {
            let start = Date()
            do {
                let port = appState.serverPort
                let url = URL(string: "http://localhost:\(port)/v1/audio/speech")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let body: [String: Any] = [
                    "model": selectedModelID,
                    "input": inputText,
                    "voice": selectedVoiceID.isEmpty ? "0" : selectedVoiceID,
                    "speed": speed,
                    "response_format": UserDefaults.standard.string(forKey: AppConstants.defaultTTSFormatKey) ?? "opus"
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw NSError(domain: "", code: 0, userInfo: [
                        NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "Failed"
                    ])
                }

                let player = try AVAudioPlayer(data: data)
                self.audioPlayer = player
                player.play()
                elapsedTime = Date().timeIntervalSince(start)
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }
}
