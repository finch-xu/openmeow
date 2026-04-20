import SwiftUI
import AVFoundation

struct ASRPlaygroundView: View {
    @Environment(\.omTheme) private var theme
    @Environment(AppState.self) private var appState

    @State private var selectedModelID = ""
    @State private var selectedLanguage = "auto"
    @State private var responseFormat = "json"
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var transcriptionResult = ""
    @State private var elapsedTime: Double?
    @State private var errorMessage: String?
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?

    private var availableModels: [ModelRegistryEntry] { appState.runningASRModels }
    private var selectedModel: ModelRegistryEntry? {
        availableModels.first { $0.id == selectedModelID }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            leftPanel
            settingsPanel
        }
        .padding(20)
        .onAppear { autoSelect() }
        .onChange(of: appState.loadedModels) { _, _ in autoSelect() }
    }

    private var leftPanel: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                Button(action: toggleRecording) {
                    ZStack {
                        Circle()
                            .fill(isRecording ? theme.err : theme.accent)
                            .frame(width: 84, height: 84)
                            .shadow(color: (isRecording ? theme.err : theme.accent).opacity(0.35),
                                    radius: 10, y: 6)
                        Image(systemName: isRecording ? OMSymbol.stop : OMSymbol.mic)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isTranscribing || availableModels.isEmpty)

                OMWaveform(active: isRecording)

                Text(statusLine)
                    .font(.omBody)
                    .foregroundStyle(theme.ink3)

                if availableModels.isEmpty {
                    Text("No ASR model is running. Download one from Models.")
                        .font(.omCaption)
                        .foregroundStyle(theme.warn)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity)
            .overlay(
                Rectangle().fill(theme.divider2).frame(height: 1),
                alignment: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("TRANSCRIPT")
                        .font(.omMeta).tracking(0.5)
                        .foregroundStyle(theme.ink4)
                    Spacer()
                    if let e = elapsedTime {
                        Text(String(format: "%.2fs", e))
                            .font(.omMono)
                            .foregroundStyle(theme.ink4)
                    }
                }

                if isTranscribing {
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Text("Transcribing…")
                            .font(.omCaption)
                            .foregroundStyle(theme.ink3)
                        Spacer()
                    }
                    .padding(.vertical, 20)
                } else if !transcriptionResult.isEmpty {
                    ScrollView {
                        Text(transcriptionResult)
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .foregroundStyle(theme.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("Your transcription will appear here.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.ink4)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.omCaption)
                        .foregroundStyle(theme.err)
                        .padding(.top, 6)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(
            RoundedRectangle(cornerRadius: OMRadius.lg).fill(theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OMRadius.lg).strokeBorder(theme.divider, lineWidth: 1)
        )
    }

    private var statusLine: String {
        if isRecording { return "Recording… tap to stop" }
        if isTranscribing { return "Transcribing audio…" }
        return "Tap to record"
    }

    private var settingsPanel: some View {
        PlaygroundSettingsPanel(endpointPath: "/v1/audio/transcriptions") {
            OMFieldGroup("Model") {
                OMMenuPicker(selectedModel?.displayName.localized ?? "No models") {
                    ForEach(availableModels) { m in
                        Button(m.displayName.localized) { selectedModelID = m.id }
                    }
                    if availableModels.isEmpty {
                        Text("No running ASR models")
                    }
                }
            }

            OMFieldGroup("Language") {
                OMMenuPicker(selectedLanguage == "auto" ? "Auto detect" : selectedLanguage) {
                    Button("Auto detect") { selectedLanguage = "auto" }
                    if let m = selectedModel {
                        ForEach(m.languages, id: \.self) { lang in
                            Button(lang) { selectedLanguage = lang }
                        }
                    }
                }
            }

            OMFieldGroup("Response format") {
                OMSegmented(options: ["json","text","srt","vtt"], selection: $responseFormat)
            }
        }
    }

    private func autoSelect() {
        if selectedModelID.isEmpty, let first = availableModels.first {
            selectedModelID = first.id
        }
    }

    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginRecording()
        case .notDetermined:
            NSApplication.shared.activate()
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    if granted { self.beginRecording() }
                    else { self.errorMessage = "Microphone access denied." }
                }
            }
        case .denied, .restricted:
            errorMessage = "Microphone denied. Open System Settings → Privacy → Microphone."
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        @unknown default:
            beginRecording()
        }
    }

    private func beginRecording() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        recordingURL = url
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.record()
            audioRecorder = recorder
            isRecording = true
        } catch {
            errorMessage = "Recording failed: \(error.localizedDescription)"
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        if selectedModelID.isEmpty, let first = availableModels.first {
            selectedModelID = first.id
        }
        guard !selectedModelID.isEmpty else {
            errorMessage = "No ASR model available. Download one from Models."
            return
        }
        guard let url = recordingURL else { return }
        transcribe(fileURL: url)
    }

    private func transcribe(fileURL: URL) {
        isTranscribing = true
        errorMessage = nil
        elapsedTime = nil
        transcriptionResult = ""
        let modelToUse = selectedModelID

        Task {
            let start = Date()
            do {
                let port = appState.serverPort
                let apiURL = URL(string: "http://localhost:\(port)/v1/audio/transcriptions")!
                let boundary = UUID().uuidString
                var request = URLRequest(url: apiURL)
                request.httpMethod = "POST"
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

                var body = Data()
                let audioData = try Data(contentsOf: fileURL)
                body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"rec.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
                body.append(audioData)
                body.append("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n\(modelToUse)\r\n".data(using: .utf8)!)
                if selectedLanguage != "auto" && !selectedLanguage.isEmpty {
                    body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\n\(selectedLanguage)\r\n".data(using: .utf8)!)
                }
                body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"response_format\"\r\n\r\n\(responseFormat)\r\n".data(using: .utf8)!)
                body.append("--\(boundary)--\r\n".data(using: .utf8)!)
                request.httpBody = body

                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw NSError(domain: "", code: 0, userInfo: [
                        NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "Failed"
                    ])
                }
                if responseFormat == "json",
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let text = json["text"] as? String {
                    transcriptionResult = text
                } else {
                    transcriptionResult = String(data: data, encoding: .utf8) ?? ""
                }
                elapsedTime = Date().timeIntervalSince(start)
            } catch {
                errorMessage = error.localizedDescription
            }
            isTranscribing = false
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
