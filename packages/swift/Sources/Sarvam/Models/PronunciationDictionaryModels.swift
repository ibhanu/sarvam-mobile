import Foundation

public struct PronunciationDictionaryListResponse: Codable, Sendable, Equatable {
    public let dictionaryCount: Int
    public let dictionaries: [String]

    public init(dictionaryCount: Int, dictionaries: [String]) {
        self.dictionaryCount = dictionaryCount
        self.dictionaries = dictionaries
    }

    enum CodingKeys: String, CodingKey {
        case dictionaryCount = "dictionary_count"
        case dictionaries
    }
}

public struct PronunciationDictionaryCreateResponse: Codable, Sendable, Equatable {
    public let dictionaryId: String

    public init(dictionaryId: String) {
        self.dictionaryId = dictionaryId
    }

    enum CodingKeys: String, CodingKey {
        case dictionaryId = "dictionary_id"
    }
}

public struct PronunciationDictionaryUpdateResponse: Codable, Sendable, Equatable {
    public let dictionaryId: String
    public let updatedPronunciations: [String: [String: String]]

    public init(dictionaryId: String, updatedPronunciations: [String: [String: String]]) {
        self.dictionaryId = dictionaryId
        self.updatedPronunciations = updatedPronunciations
    }

    enum CodingKeys: String, CodingKey {
        case dictionaryId = "dictionary_id"
        case updatedPronunciations = "updated_pronunciations"
    }
}

public struct PronunciationDictionaryData: Codable, Sendable, Equatable {
    public let pronunciations: [String: [String: String]]

    public init(pronunciations: [String: [String: String]]) {
        self.pronunciations = pronunciations
    }
}

public struct PronunciationDictionaryDeleteResponse: Codable, Sendable, Equatable {
    public let success: Bool
    public let message: String

    public init(success: Bool, message: String) {
        self.success = success
        self.message = message
    }
}
