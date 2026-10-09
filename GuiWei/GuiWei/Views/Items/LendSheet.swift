import SwiftUI
import SwiftData

/// 借出登记。东西离开家就进入了"在别人手里"的状态，
/// 这一步把借给谁、什么时候还记下来，并可以发到期提醒。
struct LendSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let item: Item

    @State private var borrower = ""
    @State private var hasDueDate = true
    @State private var dueDate = Date.now.addingTimeInterval(86400 * 7)
    @State private var note = ""
    @State private var reminderRequested = true

    var body: some View {
        NavigationStack {
            Form {
                Section("借给谁") {
                    TextField("对方的名字", text: $borrower)
                }

                Section {
                    Toggle("约定归还日期", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker("应还日期", selection: $dueDate, displayedComponents: .date)
                    }
                    Toggle("到期前提醒我", isOn: $reminderRequested)
                } header: {
                    Text("归还")
                } footer: {
                    Text("开启提醒后，会在应还日当天上午提醒你去要回来。")
                }

                Section("备注") {
                    TextField("借去做什么（可选）", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("借出「\(item.name)」")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") { save() }
                        .disabled(borrower.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let loan = LoanRecord(borrower: borrower.trimmingCharacters(in: .whitespaces),
                              lentAt: .now,
                              dueAt: hasDueDate ? dueDate : nil,
                              note: note.isEmpty ? nil : note,
                              item: item)
        context.insert(loan)
        item.touch()
        try? context.save()

        if reminderRequested, hasDueDate {
            Task { await NotificationService.shared.scheduleLoanDue(for: loan) }
        }

        // 借出期间在灵动岛 / 锁定屏上显示"借给谁、还剩几天"
        LiveActivityCenter.shared.start(itemName: item.name,
                                     borrower: loan.borrower,
                                     locationPath: item.locationPath,
                                     dueDate: loan.dueAt)

        let all = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        WidgetBridge.publish(items: all)
        dismiss()
    }
}
