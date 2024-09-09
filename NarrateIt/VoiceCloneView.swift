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
            TextField("Voice Name", text: $voiceName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            ScrollView {
                Text(recordingText)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            .frame(height: 150)
            
            Button(action: {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }) {
                Text(isRecording ? "Stop Recording" : "Start Recording")
                    .foregroundColor(.white)
                    .padding()
                    .background(isRecording ? Color.red : Color.blue)
                    .cornerRadius(8)
            }
            
            if let audioURL = recordedAudioURL {
                Button("Clone Voice") {
                    cloneVoice(audioURL: audioURL)
                }
                .foregroundColor(.white)
                .padding()
                .background(Color.green)
                .cornerRadius(8)
            }
        }
        .padding()
        .frame(width: 400, height: 400)
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Voice Cloning"), message: Text(alertMessage), dismissButton: .default(Text("OK")) {
                if alertMessage.contains("successfully") {
                    isPresented = false
                }
            })
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
            
            // Automatically stop recording after 30 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                self.stopRecording()
            }
        } catch {
            print("Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    private func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        recordedAudioURL = audioRecorder?.url
    }
    
    private func cloneVoice(audioURL: URL) {
        guard let audioData = try? Data(contentsOf: audioURL) else {
            alertMessage = "Failed to read audio data"
            showAlert = true
            return
        }
        
        elevenlabsService.cloneVoice(name: voiceName, description: "Cloned voice", audioData: audioData) { result in
            switch result {
            case .success(let voiceID):
                alertMessage = "Voice cloned successfully with ID: \(voiceID)"
                showAlert = true
            case .failure(let error):
                alertMessage = "Failed to clone voice: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
}
