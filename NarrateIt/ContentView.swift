//
//  ContentView.swift
//  NarrateIt
//
//  Created by Vetrichelvan Jeyapalpandy on 07/09/24.
//

import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import Vision
import AVFoundation
import os
import AppKit

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
}

enum ActiveSheet: Identifiable {
    case settings
    case voiceClone
    
    var id: Int {
        hashValue
    }
}

struct ContentView: View {
    @State private var selectedDocument: URL?
    @State private var extractedText: String = ""
    @State private var isPlaying: Bool = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var currentWordIndex: Int = 0
    @State private var wordTimings: [WordTiming] = []
    @State private var highlightedRange: Range<String.Index>?
    @State private var showSettings = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var playbackTimer: Timer?
    @State private var isDragging = false
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("fontSize") private var fontSize: Double = 16
    @AppStorage("lineSpacing") private var lineSpacing: Double = 4
    @State private var activeSheet: ActiveSheet?
    @State private var isSynthesizing = false

    @StateObject private var elevenlabsService: ElevenLabsService
    
    private let logger = Logger(subsystem: "com.yourcompany.NarrateIt", category: "ContentView")

    init() {
        let apiKey = Environment.elevenLabsAPIKey
        _elevenlabsService = StateObject(wrappedValue: ElevenLabsService(apiKey: apiKey))
    }

    private var attributedText: AttributedString {
        var attributed = AttributedString(extractedText)
        if let range = highlightedRange,
           let startIndex = AttributedString.Index(range.lowerBound, within: attributed),
           let endIndex = AttributedString.Index(range.upperBound, within: attributed) {
            attributed[startIndex..<endIndex].backgroundColor = .yellow
        }
        return attributed
    }

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                HStack {
                    Text("NarrateIt")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Button(action: { activeSheet = .settings }) {
                        Image(systemName: "gear")
                            .font(.title2)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal)
                
                if let document = selectedDocument {
                    Text(document.lastPathComponent)
                        .font(.headline)
                        .foregroundColor(.secondary)
                }

                ZStack {
                    if extractedText.isEmpty {
                        dropOverlay
                    } else {
                        TextDisplayView(attributedText: attributedText)
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers -> Bool in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url = url {
                            DispatchQueue.main.async {
                                self.selectedDocument = url
                                self.extractTextFromDocument()
                            }
                        }
                    }
                    return true
                }
                .onTapGesture {
                    if extractedText.isEmpty {
                        selectDocument()
                    }
                }

                if !extractedText.isEmpty {
                    WordCountView(count: extractedText.split(separator: " ").count)
                    AudioProgressView(currentTime: $currentTime, duration: $duration)
                }

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                }

                if let errorMessage = errorMessage {
                    ErrorMessageView(message: errorMessage)
                }

                Spacer()

                PlaybackControlView(isPlaying: $isPlaying, togglePlayback: togglePlayback, isDisabled: extractedText.isEmpty || isLoading)
            }
            .padding()
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        .sheet(item: $activeSheet) { item in
            switch item {
            case .settings:
                SettingsView(appTheme: $appTheme, fontSize: $fontSize, lineSpacing: $lineSpacing, elevenlabsService: elevenlabsService, showVoiceCloneView: { activeSheet = .voiceClone })
            case .voiceClone:
                VoiceCloneView(elevenlabsService: elevenlabsService, isPresented: Binding(get: { activeSheet == .voiceClone }, set: { if !$0 { activeSheet = nil } }))
            }
        }
    }

    var dropOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.blue, lineWidth: isDragging ? 4 : 2)
                        .animation(.easeInOut, value: isDragging)
                )

            VStack {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 40))
                Text("Drop PDF or Image here")
                    .font(.headline)
                Text("or click to open")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.blue)
        }
        .frame(height: 300)
    }

    func selectDocument() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType.pdf, UTType.image]
        
        if panel.runModal() == .OK {
            selectedDocument = panel.url
            extractTextFromDocument()
        }
    }
    
    func extractTextFromDocument() {
        guard let document = selectedDocument else { return }
        
        if document.pathExtension.lowercased() == "pdf" {
            extractTextFromPDF(url: document)
        } else {
            extractTextFromImage(url: document)
        }
    }
    
    func extractTextFromPDF(url: URL) {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            guard let pdf = PDFDocument(url: url) else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load PDF"
                    self.isLoading = false
                }
                return
            }
            var text = ""
            for i in 0..<pdf.pageCount {
                guard let page = pdf.page(at: i) else { continue }
                if let pageText = page.string {
                    text += pageText + "\n"
                }
            }
            DispatchQueue.main.async {
                self.extractedText = text
                self.isLoading = false
            }
        }
    }
    
    func extractTextFromImage(url: URL) {
        isLoading = true
        guard let cgImage = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            errorMessage = "Failed to load image"
            isLoading = false
            return
        }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest { request, error in
            defer { DispatchQueue.main.async { self.isLoading = false } }
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "OCR failed: \(error.localizedDescription)"
                }
                return
            }
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            let recognizedStrings = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            DispatchQueue.main.async {
                self.extractedText = recognizedStrings.joined(separator: "\n")
            }
        }
        
        do {
            try requestHandler.perform([request])
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to perform OCR: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    func togglePlayback() {
        if isPlaying {
            audioPlayer?.pause()
            isPlaying = false
            playbackTimer?.invalidate()
        } else {
            if let player = audioPlayer {
                player.play()
                isPlaying = true
                startPlaybackTimer()
            } else {
                synthesizeSpeech()
            }
        }
    }
    
    func startPlaybackTimer() {
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            updatePlaybackProgress()
        }
    }
    
    func synthesizeSpeech() {
        guard !isSynthesizing else {
            logger.info("Speech synthesis already in progress. Ignoring new request.")
            return
        }
        
        isSynthesizing = true
        isLoading = true
        errorMessage = nil
        logger.info("Starting speech synthesis")
        
        // Cancel any ongoing synthesis
        elevenlabsService.cancelOngoingSynthesis()
        
        elevenlabsService.synthesizeSpeech(text: extractedText, voiceID: elevenlabsService.defaultVoiceID) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                self.isSynthesizing = false
                
                switch result {
                case .success(let audioData):
                    do {
                        self.audioPlayer = try AVAudioPlayer(data: audioData)
                        self.audioPlayer?.prepareToPlay()
                        self.audioPlayer?.play()
                        self.isPlaying = true
                        self.startPlaybackTimer()
                        self.logger.info("Speech synthesis successful, playing audio")
                    } catch {
                        self.logger.error("Failed to create audio player: \(error.localizedDescription)")
                        self.errorMessage = "Failed to play synthesized speech: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    self.logger.error("Speech synthesis failed: \(error.localizedDescription)")
                    self.errorMessage = "Failed to synthesize speech: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func clearText() {
        withAnimation {
            extractedText = ""
            selectedDocument = nil
            audioPlayer?.stop()
            audioPlayer = nil
            isPlaying = false
            currentTime = 0
            duration = 0
            playbackTimer?.invalidate()
        }
    }
    
    func updatePlaybackProgress() {
        guard let player = audioPlayer else { return }
        currentTime = player.currentTime
        if duration == 0 {
            duration = player.duration
        }
    }
}

struct TextDisplayView: View {
    let attributedText: AttributedString

    var body: some View {
        ScrollView {
            Text(attributedText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
        }
        .frame(height: 300)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .shadow(radius: 2)
    }
}

struct WordCountView: View {
    let count: Int
    
    var body: some View {
        Text("Word count: \(count)")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}

struct AudioProgressView: View {
    @Binding var currentTime: TimeInterval
    @Binding var duration: TimeInterval

    var body: some View {
        VStack(spacing: 4) {
            ProgressView(value: currentTime, total: max(duration, 1))
                .progressViewStyle(LinearProgressViewStyle())
            HStack {
                Text(timeString(from: currentTime))
                Spacer()
                Text(timeString(from: duration))
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval / 60)
        let seconds = Int(timeInterval.truncatingRemainder(dividingBy: 60))
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct ErrorMessageView: View {
    let message: String

    var body: some View {
        Text(message)
            .foregroundColor(.red)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
    }
}

struct SettingsView: View {
    @Binding var appTheme: AppTheme
    @Binding var fontSize: Double
    @Binding var lineSpacing: Double
    @State private var selectedVoiceID: String
    @ObservedObject var elevenlabsService: ElevenLabsService
    var showVoiceCloneView: () -> Void
    
    init(appTheme: Binding<AppTheme>, fontSize: Binding<Double>, lineSpacing: Binding<Double>, elevenlabsService: ElevenLabsService, showVoiceCloneView: @escaping () -> Void) {
        self._appTheme = appTheme
        self._fontSize = fontSize
        self._lineSpacing = lineSpacing
        self.elevenlabsService = elevenlabsService
        self._selectedVoiceID = State(initialValue: elevenlabsService.defaultVoiceID)
        self.showVoiceCloneView = showVoiceCloneView
    }
    
    var body: some View {
        Form {
            Section(header: Text("Appearance")) {
                Picker("Theme", selection: $appTheme) {
                    Text("System").tag(AppTheme.system)
                    Text("Light").tag(AppTheme.light)
                    Text("Dark").tag(AppTheme.dark)
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Slider(value: $fontSize, in: 12...24, step: 1) {
                    Text("Font Size: \(Int(fontSize))")
                }
                
                Slider(value: $lineSpacing, in: 1...10, step: 1) {
                    Text("Line Spacing: \(Int(lineSpacing))")
                }
            }
            
            Section(header: Text("Voice Settings")) {
                Picker("Default Voice", selection: $selectedVoiceID) {
                    Text("Default Voice").tag("IKne3meq5aSn9XLyUdCD")
                    ForEach(elevenlabsService.clonedVoices, id: \.id) { voice in
                        Text(voice.name).tag(voice.id)
                    }
                }
                .onChange(of: selectedVoiceID) { _, newValue in
                    elevenlabsService.setDefaultVoice(id: newValue)
                }
                
                Button("Clone New Voice") {
                    showVoiceCloneView()
                }
                
                ForEach(elevenlabsService.clonedVoices, id: \.id) { voice in
                    HStack {
                        Text(voice.name)
                        Spacer()
                        Button("Delete") {
                            elevenlabsService.deleteClonedVoice(id: voice.id)
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
        .padding()
        .frame(width: 300, height: 400)
    }
}

struct PlaybackControlView: View {
    @Binding var isPlaying: Bool
    let togglePlayback: () -> Void
    let isDisabled: Bool
    
    var body: some View {
        Button(action: togglePlayback) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 60, height: 60)
                    .shadow(color: .gray.opacity(0.3), radius: 3, x: 0, y: 2)
                
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
        .animation(.easeInOut, value: isPlaying)
        .help(isPlaying ? "Pause" : "Play")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.light)
        ContentView()
            .preferredColorScheme(.dark)
    }
}
