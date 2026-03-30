import SwiftUI
import AVFoundation

struct ASRPlaygroundView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedModelID = ""
    @State private var selectedLanguage = ""
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var transcriptionResult = ""
    @State private var elapsedTime: Double?
    @State private var errorMessage: String?
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?

    private var availableModels: [ModelRegistryEntry] {
        appState.asrModels.filter { appState.downloadState(for: $0.id) == .running }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: Controls
            VStack(spacing: 16) {
                // Model settings card
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Model")
                                .frame(width: 70, alignment: .trailing)
                            Picker("Model", selection: $selectedModelID) {
                                if availableModels.isEmpty {
                                    Text("No ASR models").tag("")
                                }
                                ForEach(availableModels) { m in
                                    Text(m.displayName.localized).tag(m.id)
                                }
                            }
                            .labelsHidden()
                            Spacer()
                        }

                        if let model = availableModels.first(where: { $0.id == selectedModelID }) {
                            HStack {
                                Text("Language")
                                    .frame(width: 70, alignment: .trailing)
                                Picker("Language", selection: $selectedLanguage) {
                                    Text("Auto").tag("")
                                    ForEach(model.languages, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden()
                                Spacer()
                            }
                        }
                    }
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.medium))
                }

                Spacer()

                // Recording button
                VStack(spacing: 10) {
                    Button(action: toggleRecording) {
                        ZStack {
                            Circle()
                                .fill(isRecording ? .red : Color.accentColor)
                                .frame(width: 72, height: 72)
                            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)

                    Text(isRecording ? "Tap to stop" : "Tap to record")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(20)
            .frame(minWidth: 220, maxWidth: 260)

            Divider()

            // Right: Result
            VStack(alignment: .leading, spacing: 12) {
                Label("Result", systemImage: "text.quote")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                GroupBox {
                    if isTranscribing {
                        HStack {
                            Spacer()
                            ProgressView("Transcribing...")
                            Spacer()
                        }
                        .frame(maxHeight: .infinity)
                    } else if !transcriptionResult.isEmpty {
                        ScrollView {
                            Text(transcriptionResult)
                                .font(.title3)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "waveform")
                                .font(.largeTitle)
                                .foregroundStyle(.quaternary)
                            Text("Record audio to see transcription")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)

                // Footer
                HStack {
                    if let elapsed = elapsedTime {
                        Label(String(format: "%.2fs", elapsed), systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .onAppear { autoSelectModel() }
        .onChange(of: appState.loadedModels) { autoSelectModel() }
    }

    private func autoSelectModel() {
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
        } catch { errorMessage = "Recording failed: \(error.localizedDescription)" }
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
                if !selectedLanguage.isEmpty {
                    body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\n\(selectedLanguage)\r\n".data(using: .utf8)!)
                }
                body.append("--\(boundary)--\r\n".data(using: .utf8)!)
                request.httpBody = body

                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw NSError(domain: "", code: 0, userInfo: [
                        NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "Failed"
                    ])
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let text = json["text"] as? String {
                    transcriptionResult = text
                } else {
                    transcriptionResult = String(data: data, encoding: .utf8) ?? ""
                }
                elapsedTime = Date().timeIntervalSince(start)
            } catch { errorMessage = error.localizedDescription }
            isTranscribing = false
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
