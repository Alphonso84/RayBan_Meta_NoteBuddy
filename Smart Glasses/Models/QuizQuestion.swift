//
//  QuizQuestion.swift
//  Smart Glasses
//
//  In-memory quiz data structures (no persistence)
//

import Foundation

/// A single multiple-choice quiz question generated from card content
struct QuizQuestion: Identifiable {
    let id: UUID
    let question: String
    let options: [String]       // 4 options
    let correctAnswerIndex: Int // 0-3
    let sourceCardTitle: String // which card it came from

    init(id: UUID = UUID(), question: String, options: [String], correctAnswerIndex: Int, sourceCardTitle: String) {
        self.id = id
        self.question = question
        self.options = options
        self.correctAnswerIndex = correctAnswerIndex
        self.sourceCardTitle = sourceCardTitle
    }
}

/// Results from a completed quiz session
struct QuizResult {
    let questions: [QuizQuestion]
    let answers: [Int?]         // user's selected index per question (nil = skipped)
    let startedAt: Date
    let completedAt: Date

    var score: Int {
        zip(questions, answers).filter { question, answer in
            answer == question.correctAnswerIndex
        }.count
    }

    var total: Int { questions.count }

    var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(score) / Double(total) * 100
    }
}
