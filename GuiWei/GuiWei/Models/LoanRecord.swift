import Foundation
import SwiftData

/// 借出记录。物品借给谁、什么时候还。
/// 这是「归位」这个 App 的第二个记忆点：东西不只在一个地方，
/// 还会临时在别人手里，所以位置之外还要记录「在谁那里」。
@Model
final class LoanRecord {
    var borrower: String = ""
    var lentAt: Date = Date.now
    var dueAt: Date?
    var returnedAt: Date?
    var note: String?

    var item: Item?

    init(borrower: String, lentAt: Date = .now, dueAt: Date? = nil, note: String? = nil, item: Item? = nil) {
        self.borrower = borrower
        self.lentAt = lentAt
        self.dueAt = dueAt
        self.note = note
        self.item = item
    }
}

extension LoanRecord {
    var isActive: Bool { returnedAt == nil }

    var dueState: LoanDueState {
        guard let dueAt else { return .noDue }
        let cal = Calendar.current
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: .now),
                                      to: cal.startOfDay(for: dueAt)).day ?? 0
        if days < 0 { return .overdue }
        if days <= 2 { return .dueSoon }
        return .onTrack
    }

    var statusText: String {
        if let returnedAt {
            return "已于 \(returnedAt.formatted(date: .abbreviated, time: .omitted)) 归还"
        }
        switch dueState {
        case .noDue: return "借出中"
        case .onTrack: return "借出中"
        case .dueSoon: return "即将到期"
        case .overdue: return "已逾期"
        }
    }
}

enum LoanDueState {
    case noDue, onTrack, dueSoon, overdue
}
