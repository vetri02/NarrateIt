import SwiftUI
import AVFoundation

struct VoiceCloneView: View {
    @ObservedObject var elevenlabsService: ElevenLabsService
    @State private var voiceName = ""
    @State private var isRecording = false
    @State private var recordedAudioURL: URL?
    @State private var audioRecorder: AVAudioRecorder?
    @Binding var isPresented: Bool
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var recordingTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var showDeleteConfirmation = false
    @State private var voiceToDelete: ClonedVoice?
    @State private var isDeleting = false

    private let maxRecordingTime: TimeInterval = 30
    private let recordingText = """
    The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs.
    How vexingly quick daft zebras jump! The five boxing wizards jump quickly.
    Sphinx of black quartz, judge my vow. Two driven jocks help fax my big quiz.
    Five quacking zephyrs jolt my wax bed. The jay, pig, fox, zebra, and my wolves quack!
    Blowzy red vixens fight for a quick jump. Joaquin Phoenix was gazed by MTV for luck.
    A wizard's job is to vex chumps quickly in fog. Watch "Jeopardy!", Alex Trebek's fun TV quiz game.
    """

    var body: some View {
        VStack(spacing: 20) {
            Text("Clone Your Voice")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Voice Name")
                    .font(.headline)
                TextField("Enter a name for your cloned voice", text: $voiceName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue, lineWidth: 1)
                    )
                Text(voiceNameValidationMessage)
                    .font(.caption)
                    .foregroundColor(isVoiceNameValid ? .secondary : .red)
            }
            .padding(.horizontal)

            ScrollView {
                Text(recordingText)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            .frame(height: 150)

            Text("Please read the text above clearly")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(action: {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }) {
                HStack {
                    Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    Text(isRecording ? "Stop Recording" : "Start Recording")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isRecording ? Color.red : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(!isVoiceNameValid)

            if isRecording {
                Text(String(format: "Recording: %.1f / %.1f seconds", recordingTime, maxRecordingTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let audioURL = recordedAudioURL {
                Button("Clone Voice") {
                    cloneVoice(audioURL: audioURL)
                }
                .buttonStyle(BorderedButtonStyle())
                .controlSize(.large)
            }

            if !elevenlabsService.clonedVoices.isEmpty {
                GroupBox(label: Text("Cloned Voices").font(.headline)) {
                    List {
                        ForEach(elevenlabsService.clonedVoices, id: \.id) { voice in
                            HStack {
                                Text(voice.name)
                                Spacer()
                                Button(action: {
                                    voiceToDelete = voice
                                    showDeleteConfirmation = true
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    .frame(height: 100)
                }
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(recordedAudioURL == nil)
            }
            .padding(.top)
        }
        .padding()
        .frame(width: 400, height: 700)
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Voice Cloning"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
        .alert(isPresented: $showDeleteConfirmation) {
            Alert(
                title: Text("Delete Voice"),
                message: Text("Are you sure you want to delete this voice? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    if let voice = voiceToDelete {
                        deleteVoice(voice: voice)
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .overlay(
            Group {
                if isDeleting {
                    ProgressView("Deleting voice...")
                        .padding()
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(10)
                        .shadow(radius: 10)
                }
            }
        )
    }

    private var isVoiceNameValid: Bool {
        !voiceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && voiceName.count <= 30
    }

    private var voiceNameValidationMessage: String {
        if voiceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Voice name cannot be empty"
        } else if voiceName.count > 30 {
            return "Voice name must be 30 characters or less"
        } else {
            return "Choose a unique and memorable name for your voice"
        }
    }

    private func startRecording() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("voice_sample.m4a")
        
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.record()
            isRecording = true
            recordingTime = 0
            
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                if self.recordingTime < self.maxRecordingTime {
                    self.recordingTime += 0.1
                } else {
                    self.stopRecording()
                }
            }
        } catch {
            showAlert(message: "Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    private func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        recordedAudioURL = audioRecorder?.url
        timer?.invalidate()
        timer = nil
    }
    
    private func cloneVoice(audioURL: URL) {
        guard let audioData = try? Data(contentsOf: audioURL) else {
            showAlert(message: "Failed to read audio data")
            return
        }
        
        elevenlabsService.cloneVoice(name: voiceName, description: "Cloned voice", audioData: audioData) { result in
            switch result {
            case .success(let voiceID):
                showAlert(message: "Voice cloned successfully with ID: \(voiceID)")
                voiceName = ""
                recordedAudioURL = nil
            case .failure(let error):
                showAlert(message: "Failed to clone voice: \(error.localizedDescription)")
            }
        }
    }
    
    private func deleteVoice(voice: ClonedVoice) {
        isDeleting = true
        elevenlabsService.deleteVoiceFromElevenLabs(id: voice.id) { result in
            DispatchQueue.main.async {
                self.isDeleting = false
                switch result {
                case .success:
                    self.elevenlabsService.deleteClonedVoice(id: voice.id)
                    self.showAlert(message: "Voice deleted successfully")
                case .failure(let error):
                    self.showAlert(message: "Failed to delete voice: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func showAlert(message: String) {
        alertMessage = message
        showAlert = true
    }
}
