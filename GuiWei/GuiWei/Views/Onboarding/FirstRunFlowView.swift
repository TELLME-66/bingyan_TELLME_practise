import SwiftUI

/// 首次启动的完整流程：**先问外观，再看新手指南**。
///
/// 两件事放在同一个 fullScreenCover 里，中间用状态切换而不是"关掉一个再开一个"——
/// 后者在 SwiftUI 里容易出现第二个弹不出来的时序问题。
struct FirstRunFlowView: View {
    /// 直接从新手指南开始（设置页里"重新查看使用教程"走这条）
    let skipAppearance: Bool

    @State private var showGuide: Bool

    init(skipAppearance: Bool = false) {
        self.skipAppearance = skipAppearance
        _showGuide = State(initialValue: skipAppearance)
    }

    var body: some View {
        Group {
            if showGuide {
                OnboardingView()
            } else {
                AppearanceSetupView {
                    withAnimation(.snappy(duration: 0.3)) { showGuide = true }
                }
            }
        }
    }
}
