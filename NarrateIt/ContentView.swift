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

class ThemeManager: ObservableObject {
    @AppStorage("appTheme") var appTheme: AppTheme = .system {
        didSet {
            objectWillChange.send()
        }
    }
}

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
    @StateObject private var themeManager = ThemeManager()
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
            themeBackgroundColor.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                HStack {
                    Text("NarrateIt")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: { activeSheet = .settings }) {
                        Image(systemName: "gear")
                            .font(.title2)
                            .foregroundColor(.blue)
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
                }

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                } else if !extractedText.isEmpty {
                    PlaybackControlView(isPlaying: $isPlaying, 
                                        togglePlayback: togglePlayback, 
                                        isDisabled: extractedText.isEmpty || isLoading,
                                        currentTime: $currentTime,
                                        duration: $duration)
                }

                if let errorMessage = errorMessage {
                    ErrorMessageView(message: errorMessage)
                }

                Spacer()
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
                SettingsView(themeManager: themeManager, 
                             elevenlabsService: elevenlabsService, 
                             showVoiceCloneView: { activeSheet = .voiceClone }, 
                             isPresented: Binding(get: { activeSheet == .settings }, set: { if !$0 { activeSheet = nil } }))
            case .voiceClone:
                VoiceCloneView(elevenlabsService: elevenlabsService, 
                               isPresented: Binding(get: { activeSheet == .voiceClone }, set: { if !$0 { activeSheet = nil } }))
            }
        }
        .preferredColorScheme(colorScheme)
    }

    private var themeBackgroundColor: Color {
        switch themeManager.appTheme {
        case .system:
            return Color(.windowBackgroundColor)
        case .light:
            return Color.white
        case .dark:
            return Color.black
        }
    }

    private var colorScheme: ColorScheme? {
        switch themeManager.appTheme {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var dropOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.blue, lineWidth: isDragging ? 2 : 1)
                        .animation(.easeInOut, value: isDragging)
                )

            VStack {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                Text("Drop PDF or Image here")
                    .font(.headline)
                Text("or click to open")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
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
                .font(.system(size: 16))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
        }
        .frame(maxHeight: .infinity)
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
    @ObservedObject var themeManager: ThemeManager
    @State private var localAppTheme: AppTheme
    @ObservedObject var elevenlabsService: ElevenLabsService
    var showVoiceCloneView: () -> Void
    @Binding var isPresented: Bool
    
    @State private var selectedVoiceID: String
    
    init(themeManager: ThemeManager, elevenlabsService: ElevenLabsService, showVoiceCloneView: @escaping () -> Void, isPresented: Binding<Bool>) {
        self.themeManager = themeManager
        self.elevenlabsService = elevenlabsService
        self._selectedVoiceID = State(initialValue: elevenlabsService.defaultVoiceID)
        self.showVoiceCloneView = showVoiceCloneView
        self._isPresented = isPresented
        self._localAppTheme = State(initialValue: themeManager.appTheme)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.title)
                .fontWeight(.bold)
            
            GroupBox(label: Text("Appearance").font(.headline)) {
                Picker("Theme", selection: $localAppTheme) {
                    Text("System").tag(AppTheme.system)
                    Text("Light").tag(AppTheme.light)
                    Text("Dark").tag(AppTheme.dark)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.vertical, 8)
            }
            
            GroupBox(label: Text("Voice Settings").font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Default Voice", selection: $selectedVoiceID) {
                        Text("Default Voice").tag("IKne3meq5aSn9XLyUdCD")
                        ForEach(elevenlabsService.clonedVoices, id: \.id) { voice in
                            Text(voice.name).tag(voice.id)
                        }
                    }
                    .pickerStyle(DefaultPickerStyle())
                    .id(elevenlabsService.clonedVoices.count) // Force refresh when voices change
                }
                .padding(.vertical, 8)
            }
            
            Button(action: {
                isPresented = false
                showVoiceCloneView()
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Clone New Voice")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
            
            GroupBox(label: Text("Available Voices").font(.headline)) {
                if elevenlabsService.clonedVoices.isEmpty {
                    Text("No cloned voices available")
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    List {
                        ForEach(elevenlabsService.clonedVoices, id: \.id) { voice in
                            HStack {
                                Text(voice.name)
                                Spacer()
                                if voice.id == selectedVoiceID {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .onDelete(perform: deleteVoice)
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
                
                Button("Save") {
                    applySettings()
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top)
        }
        .padding()
        .frame(width: 400, height: 550)
        .onAppear {
            // Ensure selectedVoiceID is valid
            if !elevenlabsService.clonedVoices.contains(where: { $0.id == selectedVoiceID }) {
                selectedVoiceID = "IKne3meq5aSn9XLyUdCD" // Default to original voice if selected voice is not found
            }
        }
    }
    
    private func applySettings() {
        themeManager.appTheme = localAppTheme
        elevenlabsService.setDefaultVoice(id: selectedVoiceID)
    }
    
    private func deleteVoice(at offsets: IndexSet) {
        for index in offsets {
            let voice = elevenlabsService.clonedVoices[index]
            elevenlabsService.deleteClonedVoice(id: voice.id)
        }
    }
}

struct PlaybackControlView: View {
    @Binding var isPlaying: Bool
    let togglePlayback: () -> Void
    let isDisabled: Bool
    @Binding var currentTime: TimeInterval
    @Binding var duration: TimeInterval
    
    var body: some View {
        VStack(spacing: 10) {
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
            
            if isPlaying || currentTime > 0 {
                AudioProgressView(currentTime: $currentTime, duration: $duration)
            }
        }
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.light)
        ContentView()
            .preferredColorScheme(.dark)
    }
}
