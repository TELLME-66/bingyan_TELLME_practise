import WidgetKit
import SwiftUI

/// 扩展的入口：同时提供「桌面小组件」和「借出实时活动（含灵动岛）」。
@main
struct GuiWeiWidgetBundle: WidgetBundle {
    var body: some Widget {
        GuiWeiLiveActivity()
        GuiWeiWidget()
    }
}
