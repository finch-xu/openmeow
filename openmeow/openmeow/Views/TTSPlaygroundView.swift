import SwiftUI
import AVFoundation

struct TTSPlaygroundView: View {
    @Environment(\.omTheme) private var theme
    @Environment(AppState.self) private var appState
    @AppStorage(AppConstants.defaultTTSFormatKey) private var format: String = "wav"

    private static let locallyPlayableFormats: Set<String> = ["wav", "mp3", "aac", "flac"]

    @State private var inputText = "Welcome to OpenMeow — a local voice gateway for the OpenAI API. Try switching voices or tweaking speed on the right."
    @State private var selectedModelID = ""
    @State private var selectedVoiceID = ""
    @State private var speed: Double = 1.0
    @State private var isGenerating = false
    @State private var isPlaying = false
    @State private var elapsedTime: Double?
    @State private var errorMessage: String?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var completionTask: Task<Void, Never>?

    private var availableModels: [ModelRegistryEntry] { appState.runningTTSModels }
    private var selectedModel: ModelRegistryEntry? {
        availableModels.first { $0.id == selectedModelID }
    }
    private var voices: [VoiceInfo] { selectedModel?.voiceList ?? [] }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            leftPanel
            settingsPanel
        }
        .padding(20)
        .onAppear { autoSelect() }
        .onDisappear { completionTask?.cancel() }
        .onChange(of: appState.loadedModels) { _, _ in autoSelect() }
        .onChange(of: selectedModelID) { _, _ in
            if let v = selectedModel?.voiceList?.first { selectedVoiceID = v.id }
        }
    }

    private var leftPanel: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("INPUT TEXT")
                    .font(.omMeta).tracking(0.5)
                    .foregroundStyle(theme.ink4)

                TextEditor(text: $inputText)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)

                HStack {
                    Text("\(inputText.count) chars")
                    Spacer()
                    Text("~\(max(1, Int(Double(inputText.count) / 15.0)))s output")
                }
                .font(.omMono)
                .foregroundStyle(theme.ink4)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                Rectangle().fill(theme.divider2).frame(height: 1),
                alignment: .bottom
            )

            VStack(spacing: 20) {
                Spacer(minLength: 0)

                Button(action: generate) {
                    ZStack {
                        Circle()
                            .fill(theme.accent)
                            .frame(width: 84, height: 84)
                            .shadow(color: theme.accent.opacity(0.35), radius: 10, y: 6)
                        Image(systemName: isGenerating ? "hourglass" : (isPlaying ? OMSymbol.pause : OMSymbol.play))
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(theme.accentInk)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isGenerating || inputText.isEmpty || selectedModelID.isEmpty)

                OMWaveform(active: isGenerating || isPlaying)

                HStack(spacing: 12) {
                    Text(statusLine)
                    if let e = elapsedTime {
                        Text("·").foregroundStyle(theme.ink4)
                        Text(String(format: "%.2fs total", e))
                    }
                }
                .font(.omMono)
                .foregroundStyle(theme.ink3)

                if let error = errorMessage {
                    Text(error)
                        .font(.omCaption)
                        .foregroundStyle(theme.err)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                if availableModels.isEmpty {
                    Text("No TTS model is running. Download one from Models.")
                        .font(.omCaption)
                        .foregroundStyle(theme.warn)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 260)
            .padding(32)
        }
        .background(
            RoundedRectangle(cornerRadius: OMRadius.lg).fill(theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OMRadius.lg).strokeBorder(theme.divider, lineWidth: 1)
        )
    }

    private var statusLine: String {
        if isGenerating { return "generating…" }
        if isPlaying    { return "playing…" }
        if audioPlayer != nil { return "ready — replay available" }
        return "ready"
    }

    private var settingsPanel: some View {
        PlaygroundSettingsPanel(endpointPath: "/v1/audio/speech") {
            OMFieldGroup("Model") {
                OMMenuPicker(verbatim: selectedModel?.displayName.localized ?? String(localized: "No models")) {
                    ForEach(availableModels) { m in
                        Button(m.displayName.localized) { selectedModelID = m.id }
                    }
                    if availableModels.isEmpty {
                        Text("No running TTS models")
                    }
                }
            }

            if !voices.isEmpty {
                OMFieldGroup("Voice") { voiceList }
            }

            OMFieldGroup("Speed · \(String(format: "%.1f", speed))×") {
                VStack(spacing: 2) {
                    Slider(value: $speed, in: 0.5...2.0, step: 0.1)
                        .tint(theme.accent)
                    HStack {
                        Text("0.5×"); Spacer(); Text("1.0×"); Spacer(); Text("2.0×")
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.ink4)
                }
            }

            OMFieldGroup("Format") {
                OMSegmented(options: ["opus","mp3","wav","flac","aac","pcm"], selection: $format)
            }
        }
    }

    private var voiceList: some View {
        ScrollView {
            VStack(spacing: 3) {
                ForEach(voices, id: \.id) { v in
                    Button {
                        selectedVoiceID = v.id
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(v.gender?.uppercased() == "F" ? theme.errSoft : theme.accentSoft)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Text(v.gender?.prefix(1).uppercased() ?? "·")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(v.gender?.uppercased() == "F" ? theme.err : theme.accent)
                                )
                            Text(v.name).font(.system(size: 12.5))
                                .foregroundStyle(theme.ink)
                            Spacer()
                            Text(v.language.uppercased())
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(theme.ink4)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: OMRadius.xs)
                                .fill(selectedVoiceID == v.id ? theme.surface : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: OMRadius.xs)
                                .strokeBorder(selectedVoiceID == v.id ? theme.divider : .clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .frame(maxHeight: 190)
        .background(
            RoundedRectangle(cornerRadius: OMRadius.sm).fill(theme.surface2)
        )
    }

    private func autoSelect() {
        if selectedModelID.isEmpty, let first = availableModels.first {
            selectedModelID = first.id
        }
    }

    private func generate() {
        if !Self.locallyPlayableFormats.contains(format) {
            errorMessage = "\"\(format)\" can't be previewed locally. Use wav / mp3 / aac / flac for in-app playback, or test \(format) via curl."
            return
        }

        isGenerating = true
        errorMessage = nil
        elapsedTime = nil
        completionTask?.cancel()

        Task {
            let start = Date()
            do {
                let port = appState.serverPort
                let url = URL(string: "http://127.0.0.1:\(port)/v1/audio/speech")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let body: [String: Any] = [
                    "model": selectedModelID,
                    "input": inputText,
                    "voice": selectedVoiceID.isEmpty ? "0" : selectedVoiceID,
                    "speed": speed,
                    "response_format": format
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let bodyText = String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
                    throw NSError(domain: "TTS", code: status, userInfo: [
                        NSLocalizedDescriptionKey: "HTTP \(status): \(bodyText)"
                    ])
                }

                let player: AVAudioPlayer
                do {
                    player = try AVAudioPlayer(data: data)
                } catch {
                    throw NSError(domain: "TTS", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Decode failed for \(format) (\(data.count) bytes). \(error.localizedDescription)"
                    ])
                }
                audioPlayer = player
                guard player.play() else {
                    throw NSError(domain: "TTS", code: -2, userInfo: [
                        NSLocalizedDescriptionKey: "AVAudioPlayer refused to play \(format) data."
                    ])
                }
                isPlaying = true
                elapsedTime = Date().timeIntervalSince(start)

                let duration = player.duration
                completionTask = Task { [weak player] in
                    try? await Task.sleep(for: .seconds(duration + 0.2))
                    guard !Task.isCancelled, player != nil else { return }
                    isPlaying = false
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }
}
