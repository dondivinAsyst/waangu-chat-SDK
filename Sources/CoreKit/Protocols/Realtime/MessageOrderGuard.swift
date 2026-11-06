import Foundation

public actor MessageOrderGuard {
    
    public static let shared = MessageOrderGuard()
    
    private var conversationSequences: [String: ConversationSequence] = [:]
    private let maxGapSize = 100
    private let sequenceTimeout: TimeInterval = 300
    
    private init() {}
    
    public func validateMessage(
        conversationId: String,
        messageId: String,
        sequenceNumber: Int64,
        timestamp: Date
    ) throws -> ValidationResult {
        
        var sequence = conversationSequences[conversationId] ?? ConversationSequence(conversationId: conversationId)
        
        if sequence.processedMessages.contains(messageId) {
            throw OrderError.duplicateMessage(messageId: messageId)
        }
        
        if let lastSeq = sequence.lastSequence {
            if sequenceNumber <= lastSeq {
                if sequenceNumber == lastSeq {
                    throw OrderError.duplicateSequence(sequence: sequenceNumber)
                }
                return .outOfOrder(expected: lastSeq + 1, received: sequenceNumber)
            }
            
            let gap = sequenceNumber - lastSeq
            if gap > 1 {
                let missingRange = (lastSeq + 1)..<sequenceNumber
                sequence.gaps.append(SequenceGap(range: missingRange, detectedAt: Date()))
                
                if gap > maxGapSize {
                    throw OrderError.gapTooLarge(gap: Int(gap))
                }
                
                conversationSequences[conversationId] = sequence
                return .gap(missing: Array(missingRange))
            }
        }
        
        sequence.lastSequence = sequenceNumber
        sequence.processedMessages.insert(messageId)
        sequence.lastMessageTime = timestamp
        
        if sequence.processedMessages.count > 10000 {
            sequence.processedMessages.removeFirst()
        }
        
        conversationSequences[conversationId] = sequence
        
        return .inOrder
    }
    
    public func fillGap(conversationId: String, sequenceNumber: Int64) {
        guard var sequence = conversationSequences[conversationId] else { return }
        
        sequence.gaps.removeAll { gap in
            gap.range.contains(sequenceNumber)
        }
        
        conversationSequences[conversationId] = sequence
    }
    
    public func getGaps(conversationId: String) -> [SequenceGap] {
        conversationSequences[conversationId]?.gaps ?? []
    }
    
    public func reset(conversationId: String) {
        conversationSequences.removeValue(forKey: conversationId)
    }
    
    public func cleanupStale() {
        let now = Date()
        conversationSequences = conversationSequences.filter { _, sequence in
            guard let lastTime = sequence.lastMessageTime else { return false }
            return now.timeIntervalSince(lastTime) < sequenceTimeout
        }
    }
}

private struct ConversationSequence {
    let conversationId: String
    var lastSequence: Int64?
    var processedMessages: Set<String> = []
    var gaps: [SequenceGap] = []
    var lastMessageTime: Date?
}

public struct SequenceGap: Sendable {
    public let range: Range<Int64>
    public let detectedAt: Date
}

public enum ValidationResult: Sendable {
    case inOrder
    case outOfOrder(expected: Int64, received: Int64)
    case gap(missing: [Int64])
}

public enum OrderError: Error {
    case duplicateMessage(messageId: String)
    case duplicateSequence(sequence: Int64)
    case gapTooLarge(gap: Int)
}
