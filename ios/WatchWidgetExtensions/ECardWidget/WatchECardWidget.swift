//
//  WatchECardWidget.swift
//  WatchWidgetExtensions
//
//  表盘复杂功能「付款码」：展示本地余额并作为付款码入口
//

import SwiftUI
import WidgetKit

struct WatchECardEntry: TimelineEntry {
    let date: Date
    /// 单位为分；负值表示尚未取得真实余额。
    let balance: Int
}

struct WatchECardProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchECardEntry {
        WatchECardEntry(date: Date(), balance: -1)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchECardEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchECardEntry>) -> Void) {
        completion(
            Timeline(
                entries: [currentEntry()],
                // Watch App 写入新余额时也会主动 reload；定时刷新用于兜底。
                policy: .after(Date(timeIntervalSinceNow: 1_800))
            )
        )
    }

    private func currentEntry(now: Date = Date()) -> WatchECardEntry {
        guard
            let defaults = WidgetAppGroup.defaults,
            defaults.object(forKey: WidgetAppGroup.ecardBalanceKey) != nil
        else {
            return WatchECardEntry(date: now, balance: -1)
        }
        return WatchECardEntry(
            date: now,
            balance: defaults.integer(forKey: WidgetAppGroup.ecardBalanceKey)
        )
    }
}

struct WatchECardWidget: Widget {
    let kind: String = "ECardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchECardProvider()) { entry in
            WatchECardWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
                .widgetURL(WatchAccessoryKind.ecard.deepLink)
        }
        .configurationDisplayName("付款码")
        .description("显示校园卡余额并打开付款码")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner,
        ])
    }
}

struct WatchECardWidgetView: View {
    let entry: WatchECardEntry

    var body: some View {
        WatchECardAccessoryView(balance: entry.balance)
    }
}

// MARK: - Previews（四种复杂功能族）

#Preview("付款码 · 圆形", as: .accessoryCircular) {
    WatchECardWidget()
} timeline: {
    WatchECardEntry(date: Date(), balance: 5_235)
}

#Preview("付款码 · 矩形", as: .accessoryRectangular) {
    WatchECardWidget()
} timeline: {
    WatchECardEntry(date: Date(), balance: 5_235)
}

#Preview("付款码 · 行内", as: .accessoryInline) {
    WatchECardWidget()
} timeline: {
    WatchECardEntry(date: Date(), balance: 5_235)
}

#Preview("付款码 · 角位", as: .accessoryCorner) {
    WatchECardWidget()
} timeline: {
    WatchECardEntry(date: Date(), balance: 5_235)
}
