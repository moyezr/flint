import Foundation

struct CorrectionProposal: Equatable, Sendable {
    let heardForm: String
    let preferredForm: String
}

struct CorrectionDiffExtractor: Sendable {
    var maximumCharacters = 80
    var maximumWords = 5
    var longRewriteRatio = 0.6

    func extract(original: String, corrected: String) -> CorrectionProposal? {
        guard original != corrected else { return nil }

        let originalCharacters = Array(original)
        let correctedCharacters = Array(corrected)
        var prefixCount = 0
        let sharedLimit = min(originalCharacters.count, correctedCharacters.count)
        while prefixCount < sharedLimit,
              originalCharacters[prefixCount] == correctedCharacters[prefixCount] {
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount < originalCharacters.count - prefixCount,
              suffixCount < correctedCharacters.count - prefixCount,
              originalCharacters[originalCharacters.count - suffixCount - 1]
                == correctedCharacters[correctedCharacters.count - suffixCount - 1] {
            suffixCount += 1
        }

        var originalStart = prefixCount
        var correctedStart = prefixCount
        var originalEnd = originalCharacters.count - suffixCount
        var correctedEnd = correctedCharacters.count - suffixCount
        guard originalStart < originalEnd, correctedStart < correctedEnd else { return nil }

        let touchesWord = isWordCharacter(originalCharacters[originalStart])
            || isWordCharacter(originalCharacters[originalEnd - 1])
            || isWordCharacter(correctedCharacters[correctedStart])
            || isWordCharacter(correctedCharacters[correctedEnd - 1])
        if touchesWord {
            while originalStart > 0, isWordCharacter(originalCharacters[originalStart - 1]) {
                originalStart -= 1
            }
            while correctedStart > 0, isWordCharacter(correctedCharacters[correctedStart - 1]) {
                correctedStart -= 1
            }
            while originalEnd < originalCharacters.count,
                  isWordCharacter(originalCharacters[originalEnd]) {
                originalEnd += 1
            }
            while correctedEnd < correctedCharacters.count,
                  isWordCharacter(correctedCharacters[correctedEnd]) {
                correctedEnd += 1
            }
        }

        let heardForm = String(originalCharacters[originalStart..<originalEnd])
        let preferredForm = String(correctedCharacters[correctedStart..<correctedEnd])
        guard !isPunctuationOnly(heardForm), !isPunctuationOnly(preferredForm) else {
            return nil
        }
        guard heardForm.count <= maximumCharacters,
              preferredForm.count <= maximumCharacters,
              wordCount(heardForm) <= maximumWords,
              wordCount(preferredForm) <= maximumWords else { return nil }

        // The changed spans are already bounded to five words, keeping this LCS check constant-size.
        guard tokenEditRegionCount(original: heardForm, corrected: preferredForm) <= 1 else {
            return nil
        }

        let fullLength = max(originalCharacters.count, correctedCharacters.count)
        let changedLength = max(heardForm.count, preferredForm.count)
        let fullWordCount = max(wordCount(original), wordCount(corrected))
        let isLongText = fullLength > maximumCharacters || fullWordCount > maximumWords
        if isLongText,
           fullLength > 0,
           Double(changedLength) / Double(fullLength) >= longRewriteRatio {
            return nil
        }

        return CorrectionProposal(heardForm: heardForm, preferredForm: preferredForm)
    }

    private func wordCount(_ value: String) -> Int {
        value.split(whereSeparator: \Character.isWhitespace).count
    }

    private func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains)
    }

    private func isPunctuationOnly(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
    }

    private func tokenEditRegionCount(original: String, corrected: String) -> Int {
        let lhs = original.split(whereSeparator: \Character.isWhitespace).map(String.init)
        let rhs = corrected.split(whereSeparator: \Character.isWhitespace).map(String.init)
        guard !lhs.isEmpty || !rhs.isEmpty else { return 0 }

        var lengths = Array(
            repeating: Array(repeating: 0, count: rhs.count + 1),
            count: lhs.count + 1
        )
        if !lhs.isEmpty, !rhs.isEmpty {
            for leftIndex in stride(from: lhs.count - 1, through: 0, by: -1) {
                for rightIndex in stride(from: rhs.count - 1, through: 0, by: -1) {
                    if lhs[leftIndex] == rhs[rightIndex] {
                        lengths[leftIndex][rightIndex] = lengths[leftIndex + 1][rightIndex + 1] + 1
                    } else {
                        lengths[leftIndex][rightIndex] = max(
                            lengths[leftIndex + 1][rightIndex],
                            lengths[leftIndex][rightIndex + 1]
                        )
                    }
                }
            }
        }

        var leftIndex = 0
        var rightIndex = 0
        var regions = 0
        var isInsideChange = false
        while leftIndex < lhs.count || rightIndex < rhs.count {
            if leftIndex < lhs.count,
               rightIndex < rhs.count,
               lhs[leftIndex] == rhs[rightIndex] {
                isInsideChange = false
                leftIndex += 1
                rightIndex += 1
            } else {
                if !isInsideChange {
                    regions += 1
                    isInsideChange = true
                }
                if rightIndex == rhs.count || (
                    leftIndex < lhs.count
                        && lengths[leftIndex + 1][rightIndex] >= lengths[leftIndex][rightIndex + 1]
                ) {
                    leftIndex += 1
                } else {
                    rightIndex += 1
                }
            }
        }
        return regions
    }
}
