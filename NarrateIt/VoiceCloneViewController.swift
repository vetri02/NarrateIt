import Cocoa
import AVFoundation
import os

class VoiceCloneViewController: NSViewController {
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private let elevenlabsService: ElevenLabsService
    
    private let instructionLabel = NSTextField(labelWithString: "")
    private let recordButton = NSButton(title: "Start Recording", target: nil, action: #selector(recordButtonTapped))
    private let statusLabel = NSTextField(labelWithString: "")
    
    private let logger = Logger(subsystem: "com.yourcompany.NarrateIt", category: "VoiceCloneViewController")
    
    var statusUpdateHandler: ((String) -> Void)?
    var errorHandler: ((String) -> Void)?
    
    init(elevenlabsService: ElevenLabsService) {
        self.elevenlabsService = elevenlabsService
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupAudioRecorder()
    }
    
    private func setupUI() {
        instructionLabel.stringValue = "Record your voice for cloning"
        instructionLabel.isEditable = false
        
        recordButton.target = self
        recordButton.action = #selector(recordButtonTapped)
        
        statusLabel.isEditable = false
        
        let stackView = NSStackView(views: [instructionLabel, recordButton, statusLabel])
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 20
        
        view.addSubview(stackView)
        
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8)
        ])
    }
    
    private func setupAudioRecorder() {
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
            audioRecorder?.prepareToRecord()
            logger.info("Audio recorder setup completed")
        } catch {
            logger.error("Error setting up audio recorder: \(error.localizedDescription)")
        }
    }
    
    @objc private func recordButtonTapped() {
        if audioRecorder?.isRecording == true {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        audioRecorder?.record()
        recordButton.title = "Stop Recording"
        updateStatus("Recording...")
        logger.info("Started recording audio")
    }
    
    private func stopRecording() {
        audioRecorder?.stop()
        recordButton.title = "Start Recording"
        logger.info("Stopped recording audio")
        updateStatus("Recording finished. Preparing to clone voice...")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.checkRecordingFile()
        }
    }
    
    private func checkRecordingFile() {
        guard let audioURL = audioRecorder?.url else {
            logger.error("No recorded audio URL")
            handleError("No recorded audio URL")
            return
        }
        
        if FileManager.default.fileExists(atPath: audioURL.path) {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
                if let fileSize = attributes[.size] as? Int64, fileSize > 0 {
                    logger.info("Audio file created successfully. Size: \(fileSize) bytes")
                    self.cloneVoiceAndReadDocument()
                } else {
                    logger.error("Audio file is empty")
                    handleError("Audio file is empty")
                }
            } catch {
                logger.error("Error checking audio file: \(error.localizedDescription)")
                handleError("Error checking audio file: \(error.localizedDescription)")
            }
        } else {
            logger.error("Audio file not found at path: \(audioURL.path)")
            handleError("Audio file not found")
        }
    }
    
    private func cloneVoiceAndReadDocument() {
        guard let audioURL = audioRecorder?.url else {
            logger.error("No recorded audio found")
            handleError("No recorded audio found")
            return
        }
        
        logger.info("Starting voice cloning process")
        updateStatus("Cloning voice...")
        
        do {
            let audioData = try Data(contentsOf: audioURL)
            logger.info("Audio data loaded successfully. Size: \(audioData.count) bytes")
            let documentText = "This is a sample document text that will be read using your cloned voice."
            
            logger.info("Sending request to ElevenLabs for voice cloning and document reading")
            elevenlabsService.cloneVoice(name: "My Cloned Voice", description: "A cloned version of my voice", audioData: audioData) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let voiceID):
                        self.logger.info("Voice cloned successfully. Voice ID: \(voiceID)")
                        self.updateStatus("Voice cloned successfully. Voice ID: \(voiceID)")
                        self.synthesizeSpeech(text: documentText, voiceID: voiceID)
                    case .failure(let error):
                        self.logger.error("Error from ElevenLabs: \(error.localizedDescription)")
                        self.handleError("Error from ElevenLabs: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            logger.error("Failed to read audio file: \(error.localizedDescription)")
            handleError("Failed to read audio file: \(error.localizedDescription)")
        }
    }
    
    private func synthesizeSpeech(text: String, voiceID: String) {
        updateStatus("Synthesizing speech...")
        
        elevenlabsService.synthesizeSpeech(text: text, voiceID: voiceID) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let audioData):
                    self.logger.info("Speech synthesized successfully")
                    self.updateStatus("Speech synthesized successfully")
                    self.playAudio(data: audioData)
                case .failure(let error):
                    self.logger.error("Error synthesizing speech: \(error.localizedDescription)")
                    self.updateStatus("Error synthesizing speech: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func playAudio(data: Data) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.play()
            logger.info("Playing audio")
        } catch {
            logger.error("Failed to play audio: \(error.localizedDescription)")
            updateStatus("Failed to play audio: \(error.localizedDescription)")
        }
    }
    
    private func updateStatus(_ status: String) {
        statusLabel.stringValue = status
        statusUpdateHandler?(status)
    }
    
    private func handleError(_ error: String) {
        updateStatus("Error: \(error)")
        errorHandler?(error)
    }
}