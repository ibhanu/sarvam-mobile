import Foundation

// MARK: - Translation

public struct TranslateRequest: Codable, Sendable, Equatable {
    public var input: String
    public var sourceLanguageCode: LanguageCode
    public var targetLanguageCode: LanguageCode
    public var speakerGender: String?
    public var mode: String?
    public var model: String?
    public var enablePreprocessing: Bool?

    public init(
        input: String,
        sourceLanguageCode: LanguageCode,
        targetLanguageCode: LanguageCode,
        speakerGender: String? = nil,
        mode: String? = nil,
        model: String? = nil,
        enablePreprocessing: Bool? = nil
    ) {
        self.input = input
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCode = targetLanguageCode
        self.speakerGender = speakerGender
        self.mode = mode
        self.model = model
        self.enablePreprocessing = enablePreprocessing
    }

    enum CodingKeys: String, CodingKey {
        case input
        case sourceLanguageCode = "source_language_code"
        case targetLanguageCode = "target_language_code"
        case speakerGender = "speaker_gender"
        case mode
        case model
        case enablePreprocessing = "enable_preprocessing"
    }
}

public struct TranslateResponse: Codable, Sendable, Equatable {
    public let translatedText: String

    public init(translatedText: String) {
        self.translatedText = translatedText
    }

    enum CodingKeys: String, CodingKey {
        case translatedText = "translated_text"
    }
}

// MARK: - Transliteration

public struct TransliterateRequest: Codable, Sendable, Equatable {
    public var input: String
    public var sourceLanguageCode: LanguageCode
    public var targetLanguageCode: LanguageCode

    public init(
        input: String,
        sourceLanguageCode: LanguageCode,
        targetLanguageCode: LanguageCode
    ) {
        self.input = input
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCode = targetLanguageCode
    }

    enum CodingKeys: String, CodingKey {
        case input
        case sourceLanguageCode = "source_language_code"
        case targetLanguageCode = "target_language_code"
    }
}

public struct TransliterateResponse: Codable, Sendable, Equatable {
    public let transliteratedText: String

    public init(transliteratedText: String) {
        self.transliteratedText = transliteratedText
    }

    enum CodingKeys: String, CodingKey {
        case transliteratedText = "transliterated_text"
    }
}

// MARK: - Language Identification (LID)

public struct TextLidRequest: Codable, Sendable, Equatable {
    public var input: String

    public init(input: String) {
        self.input = input
    }

    enum CodingKeys: String, CodingKey {
        case input
    }
}

public struct TextLidResponse: Codable, Sendable, Equatable {
    public let detectedLanguage: String
    public let confidence: Double

    public init(detectedLanguage: String, confidence: Double) {
        self.detectedLanguage = detectedLanguage
        self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey {
        case detectedLanguage = "detected_language"
        case confidence
    }
}
