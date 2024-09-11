import Foundation
import os
import Combine

struct ClonedVoice: Identifiable, Codable {
    let id: String
    let name: String
}

public class ElevenLabsService: ObservableObject {
    private let apiKey: String
    private let baseURL = "https://api.elevenlabs.io/v1"
    private let logger = Logger(subsystem: "com.yourcompany.NarrateIt", category: "ElevenLabsService")
    private let userDefaults = UserDefaults.standard
    private var isSynthesizing = false
    private var synthesisTask: URLSessionDataTask?
    
    @Published private(set) var clonedVoices: [ClonedVoice] = []
    @Published private(set) var defaultVoiceID: String = "IKne3meq5aSn9XLyUdCD"
    
    public init(apiKey: String) {
        self.apiKey = apiKey
        loadClonedVoices()
        loadDefaultVoice()
        logger.info("ElevenLabsService initialized with API key: \(apiKey.prefix(5))...")
    }
    
    private func loadClonedVoices() {
        if let data = userDefaults.data(forKey: "clonedVoices"),
           let voices = try? JSONDecoder().decode([ClonedVoice].self, from: data) {
            DispatchQueue.main.async {
                self.clonedVoices = voices
            }
        }
    }
    
    private func saveClonedVoices() {
        if let data = try? JSONEncoder().encode(clonedVoices) {
            userDefaults.set(data, forKey: "clonedVoices")
        }
    }
    
    private func loadDefaultVoice() {
        let voiceID = userDefaults.string(forKey: "defaultVoiceID") ?? "IKne3meq5aSn9XLyUdCD"
        DispatchQueue.main.async {
            self.defaultVoiceID = voiceID
        }
    }
    
    public func setDefaultVoice(id: String) {
        DispatchQueue.main.async {
            self.defaultVoiceID = id
        }
        userDefaults.set(id, forKey: "defaultVoiceID")
    }
    
    public func cloneVoice(name: String, description: String, audioData: Data, completion: @escaping (Result<String, Error>) -> Void) {
        let endpoint = "\(baseURL)/voices/add"
        guard let url = URL(string: endpoint) else {
            logger.error("Invalid URL: \(endpoint)")
            completion(.failure(NSError(domain: "ElevenLabsService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "xi-api-key")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add name
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"name\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(name)\r\n".data(using: .utf8)!)
        
        // Add description
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"description\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(description)\r\n".data(using: .utf8)!)
        
        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"files\"; filename=\"voice_sample.mp3\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mpeg\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("Network error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response: not an HTTP response")
                completion(.failure(NSError(domain: "ElevenLabsService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                self.logger.error("HTTP error: status code \(httpResponse.statusCode)")
                if let data = data, let responseBody = String(data: data, encoding: .utf8) {
                    self.logger.error("Response body: \(responseBody)")
                }
                completion(.failure(NSError(domain: "ElevenLabsService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP status code: \(httpResponse.statusCode)"])))
                return
            }
            
            guard let data = data else {
                self.logger.error("No data received in response")
                completion(.failure(NSError(domain: "ElevenLabsService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let voiceID = json["voice_id"] as? String {
                    self.logger.info("Successfully cloned voice. Voice ID: \(voiceID)")
                    let newVoice = ClonedVoice(id: voiceID, name: name)
                    DispatchQueue.main.async {
                        self.clonedVoices.append(newVoice)
                        self.saveClonedVoices()
                    }
                    completion(.success(voiceID))
                } else {
                    self.logger.error("Failed to parse JSON response")
                    completion(.failure(NSError(domain: "ElevenLabsService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON response"])))
                }
            } catch {
                self.logger.error("Failed to parse response: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
        
        task.resume()
    }
    
    public func deleteClonedVoice(id: String) {
        DispatchQueue.main.async {
            self.clonedVoices.removeAll { $0.id == id }
            self.saveClonedVoices()
            if self.defaultVoiceID == id {
                self.setDefaultVoice(id: "IKne3meq5aSn9XLyUdCD") // Default to the original voice
            }
        }
    }
    
    public func synthesizeSpeech(text: String, voiceID: String, completion: @escaping (Result<Data, Error>) -> Void) {
        guard !isSynthesizing else {
            logger.info("Speech synthesis already in progress. Ignoring new request.")
            completion(.failure(NSError(domain: "ElevenLabsService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Speech synthesis already in progress"])))
            return
        }
        
        isSynthesizing = true
        
        let endpoint = "\(baseURL)/text-to-speech/\(voiceID)"
        guard let url = URL(string: endpoint) else {
            logger.error("Invalid URL: \(endpoint)")
            isSynthesizing = false
            completion(.failure(NSError(domain: "ElevenLabsService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "xi-api-key")
        
        // Increase timeout interval to 60 seconds
        request.timeoutInterval = 60
        
        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_monolingual_v1",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.5
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            logger.error("Failed to serialize request body: \(error.localizedDescription)")
            isSynthesizing = false
            completion(.failure(error))
            return
        }
        
        logger.info("Sending request to Eleven Labs: \(endpoint)")
        
        synthesisTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer { self?.isSynthesizing = false }
            
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("Network error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response: not an HTTP response")
                completion(.failure(NSError(domain: "ElevenLabsService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            
            self.logger.info("Received response from Eleven Labs. Status code: \(httpResponse.statusCode)")
            
            guard (200...299).contains(httpResponse.statusCode) else {
                self.logger.error("HTTP error: status code \(httpResponse.statusCode)")
                if let data = data, let responseBody = String(data: data, encoding: .utf8) {
                    self.logger.error("Response body: \(responseBody)")
                }
                completion(.failure(NSError(domain: "ElevenLabsService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP status code: \(httpResponse.statusCode)"])))
                return
            }
            
            guard let data = data else {
                self.logger.error("No data received in response")
                completion(.failure(NSError(domain: "ElevenLabsService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            self.logger.info("Successfully received audio data. Size: \(data.count) bytes")
            completion(.success(data))
        }
        
        synthesisTask?.resume()
        logger.info("Request sent to Eleven Labs")
    }
    
    // Add this new public method
    public func cancelOngoingSynthesis() {
        synthesisTask?.cancel()
        synthesisTask = nil
        isSynthesizing = false
    }
    
    public func deleteVoiceFromElevenLabs(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let endpoint = "\(baseURL)/voices/\(id)"
        guard let url = URL(string: endpoint) else {
            logger.error("Invalid URL: \(endpoint)")
            completion(.failure(NSError(domain: "ElevenLabsService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue(apiKey, forHTTPHeaderField: "xi-api-key")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("Network error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response: not an HTTP response")
                completion(.failure(NSError(domain: "ElevenLabsService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            
            if (200...299).contains(httpResponse.statusCode) {
                self.logger.info("Successfully deleted voice from ElevenLabs")
                completion(.success(()))
            } else {
                self.logger.error("HTTP error: status code \(httpResponse.statusCode)")
                completion(.failure(NSError(domain: "ElevenLabsService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP status code: \(httpResponse.statusCode)"])))
            }
        }
        
        task.resume()
    }
}
