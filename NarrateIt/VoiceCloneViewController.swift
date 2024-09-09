import Cocoa
import AVFoundation
import os

class VoiceCloneViewController: NSViewController {
    private var audioPlayer: AVAudioPlayer?
    private let elevenlabsService: ElevenLabsService
    private let voiceID: String
    
    private let instructionLabel = NSTextField(labelWithString: "")
    private let textField = NSTextField()
    private let synthesizeButton = NSButton(title: "Synthesize Speech", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    
    private let logger = Logger(subsystem: "com.yourcompany.NarrateIt", category: "VoiceCloneViewController")
    
    var statusUpdateHandler: ((String) -> Void)?
    var errorHandler: ((String) -> Void)?
    
    init(elevenlabsService: ElevenLabsService, voiceID: String) {
        self.elevenlabsService = elevenlabsService
        self.voiceID = voiceID
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
    }
    
    private func setupUI() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.cgColor
        
        instructionLabel.stringValue = "Enter text to synthesize:"
        instructionLabel.isEditable = false
        instructionLabel.isSelectable = false
        instructionLabel.alignment = .center
        
        textField.placeholderString = "Enter text here"
        
        synthesizeButton.target = self
        synthesizeButton.action = #selector(synthesizeButtonTapped)
        
        statusLabel.isEditable = false
        statusLabel.isSelectable = false
        statusLabel.alignment = .center
        
        let stackView = NSStackView(views: [instructionLabel, textField, synthesizeButton, statusLabel])
        stackView.orientation = .vertical
        stackView.spacing = 20
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8)
        ])
        
        logger.info("UI setup completed")
    }
    
    @objc private func synthesizeButtonTapped() {
        guard !textField.stringValue.isEmpty else {
            updateStatus("Please enter some text to synthesize")
            return
        }
        
        synthesizeSpeech(text: textField.stringValue)
    }
    
    private func synthesizeSpeech(text: String) {
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