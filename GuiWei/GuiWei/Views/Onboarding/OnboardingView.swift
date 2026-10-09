import SwiftUI

/// 教程的一页内容
struct OnboardingPage {
    let symbol: String
    let title: String
    let message: String
    let bullets: [String]
    let colors: [Color]
}

/// 首次启动的使用教程。
/// 样式对齐苹果自家 App 的首次启动页：一枚大图标 + 标题 + 说明 + 要点，
/// 底部是进度点与主按钮，右上角可以跳过。
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var pageIndex = 0

    static let pages: [OnboardingPage] = [
        OnboardingPage(
            symbol: "shippingbox.fill",
            title: "欢迎使用归位",
            message: "把每一件东西放在哪记下来，下次不用翻箱倒柜。",
            bullets: ["按「位置」组织，而不是堆成一个清单", "数据只保存在你自己的手机上"],
            colors: [Color(hex: "2E5FA3"), Color(hex: "1C7A8C")]),
        OnboardingPage(
            symbol: "books.vertical.fill",
            title: "位置分三层",
            message: "房间 › 容器 › 格位。物品落到具体格位，才知道该翻哪个抽屉。",
            bullets: ["例如：卧室 › 衣柜 › 第二层抽屉", "每个容器的物品数量自动汇总"],
            colors: [Color(hex: "4B5BD2"), Color(hex: "2E5FA3")]),
        OnboardingPage(
            symbol: "magnifyingglass",
            title: "一句话找到它",
            message: "输入两个字，直接告诉你它在哪；借出去了，就告诉你在谁手里。",
            bullets: ["名称、标签、位置都能命中", "Spotlight 桌面搜索里也能搜到"],
            colors: [Color(hex: "1C7A8C"), Color(hex: "3FA36B")]),
        OnboardingPage(
            symbol: "person.2.fill",
            title: "借出与归还",
            message: "记下借给谁、什么时候还。到期当天提醒你去要回来。",
            bullets: ["逾期自动标红", "归还后留下完整记录"],
            colors: [Color(hex: "8A5BD2"), Color(hex: "4B5BD2")]),
        OnboardingPage(
            symbol: "bell.badge.fill",
            title: "到期提醒与系统集成",
            message: "临期自动提醒；物品也出现在 Spotlight、Siri 与快捷指令里。",
            bullets: ["到期前 7 天提醒一次", "对 Siri 说「归位我的护照放哪了」"],
            colors: [Color(hex: "E08A2E"), Color(hex: "D2564B")]),
    ]

    private var isLastPage: Bool { pageIndex == Self.pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            skipBar

            TabView(selection: $pageIndex) {
                ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, page in
                    pageView(page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            footer
        }
        .background(Color(.systemBackground))
        .onAppear {
            #if DEBUG
            // 调试入口：xcrun simctl launch booted com.bingyan.guiwei -showOnboarding 1 -onboardingPage 3
            let requested = UserDefaults.standard.integer(forKey: "onboardingPage")
            if requested >= 1, requested <= Self.pages.count { pageIndex = requested - 1 }
            #endif
        }
    }

    // MARK: - 分块

    private var skipBar: some View {
        HStack {
            Spacer()
            Button("跳过") { finish() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .opacity(isLastPage ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: isLastPage)
        }
        .padding(.horizontal, Theme.gapXL)
        .padding(.top, Theme.gapS)
        .frame(height: 44)
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: Theme.gapXL) {
            Spacer(minLength: 0)

            // 图标：圆角方块 + 渐变色，模仿系统 App 图标的观感
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: page.colors,
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
                .frame(width: 132, height: 132)
                .overlay {
                    Image(systemName: page.symbol)
                        .font(.system(size: 56, weight: .medium))
                        .foregroundStyle(.white)
                }
                .shadow(color: page.colors[0].opacity(0.28), radius: 18, y: 10)

            VStack(spacing: Theme.gapM) {
                Text(page.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(page.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.gapXL)
            }

            VStack(alignment: .leading, spacing: Theme.gapM) {
                ForEach(page.bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: Theme.gapM) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(page.colors[0])
                        Text(bullet)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, Theme.gapXL)

            Spacer(minLength: 0)
        }
        .padding(.bottom, Theme.gapL)
    }

    private var footer: some View {
        VStack(spacing: Theme.gapXL) {
            HStack(spacing: Theme.gapS) {
                ForEach(Self.pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == pageIndex ? Color.primary : Color.secondary.opacity(0.25))
                        .frame(width: index == pageIndex ? 22 : 8, height: 8)
                }
            }
            .animation(.snappy(duration: 0.25), value: pageIndex)

            Button {
                if isLastPage {
                    finish()
                } else {
                    withAnimation(.snappy(duration: 0.3)) { pageIndex += 1 }
                }
            } label: {
                Text(isLastPage ? "开始使用" : "继续")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .appButtonShape()
            .controlSize(.large)
            .padding(.horizontal, Theme.gapXL)
        }
        .padding(.bottom, Theme.gapXL)
    }

    private func finish() {
        hasCompletedOnboarding = true
        dismiss()
    }
}
