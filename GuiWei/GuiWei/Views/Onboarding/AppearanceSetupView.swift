import SwiftUI

/// 首次启动的第一步：问一下外观偏好。
///
/// 样式和后面的新手指南保持一致——大图标、标题、说明、一组选项、底部主按钮，
/// 让整个首次启动像一件事，而不是两个互相无关的弹窗。
struct AppearanceSetupView: View {
    /// 选完之后由上层决定去哪（通常是接着播新手指南）
    let onContinue: () -> Void

    @AppStorage(AppAppearance.storageKey) private var storedAppearance = AppAppearance.system.rawValue
    @State private var selection: AppAppearance = .system

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: Theme.gapXL) {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "2E5FA3"), Color(hex: "1C7A8C")],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .frame(width: 108, height: 108)
                    .overlay {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 46, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: Color(hex: "2E5FA3").opacity(0.28), radius: 16, y: 8)

                VStack(spacing: Theme.gapM) {
                    Text("选择外观")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("默认跟随系统。之后也可以随时在「设置」里更改。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.gapXL)
                }
            }

            VStack(spacing: Theme.gapM) {
                ForEach(AppAppearance.allCases) { option in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { selection = option }
                    } label: {
                        optionRow(option)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.gapXL)
            .padding(.top, Theme.gapXL)

            Spacer(minLength: 0)

            Button {
                storedAppearance = selection.rawValue
                AppAppearance.hasChosen = true
                onContinue()
            } label: {
                Text("继续")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .appButtonShape()
            .controlSize(.large)
            .padding(.horizontal, Theme.gapXL)
            .padding(.bottom, Theme.gapXL)
        }
        .background(Color(.systemBackground))
    }

    private func optionRow(_ option: AppAppearance) -> some View {
        let selected = selection == option
        return HStack(spacing: Theme.gapM) {
            Image(systemName: option.symbol)
                .font(.title3)
                .frame(width: 30)
                .foregroundStyle(selected ? Color(hex: "2E5FA3") : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                    .font(.body)
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(.primary)
                Text(option.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color(hex: "2E5FA3"))
            } else {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(Theme.gapL)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .strokeBorder(selected ? Color(hex: "2E5FA3") : Color.clear, lineWidth: 2)
        }
    }
}
