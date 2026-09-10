import Foundation

enum QuizGrading {
    static func normalizeCloze(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func gradeMC(choiceId: String?, correctId: String) -> Bool {
        guard let choiceId else { return false }
        return choiceId == correctId
    }

    static func gradeCloze(answer: String, accepted: [String]) -> Bool {
        let normalized = normalizeCloze(answer)
        return accepted.contains { normalizeCloze($0) == normalized }
    }
}
