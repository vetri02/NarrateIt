import Foundation

public struct WordTiming {
    public let word: String
    public let start: Double
    public let end: Double
    public let startIndex: Int
    public let endIndex: Int
    
    public init(word: String, start: Double, end: Double, startIndex: Int, endIndex: Int) {
        self.word = word
        self.start = start
        self.end = end
        self.startIndex = startIndex
        self.endIndex = endIndex
    }
}