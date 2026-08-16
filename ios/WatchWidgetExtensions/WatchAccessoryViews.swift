//
//  WatchAccessoryViews.swift
//  WatchWidgetExtensions
//
//  表盘复杂功能共用布局：按 Circular / Rectangular / Inline / Corner 分别适配
//

import SwiftUI
import WidgetKit

/// 固定内容的入口型复杂功能。校园卡余额使用下方的专用视图。
enum WatchAccessoryKind {
    case flow
    case ecard

    var title: String {
        switch self {
        case .flow: return "日程"
        case .ecard: return "付款码"
        }
    }

    /// 矩形族副标题（固定文案，非业务数据）
    var subtitle: String {
        switch self {
        case .flow: return "今日课表"
        case .ecard: return "校园卡"
        }
    }

    var systemImage: String {
        switch self {
        case .flow: return "calendar"
        case .ecard: return "qrcode"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .flow: return "打开日程"
        case .ecard: return "打开付款码"
        }
    }

    var deepLink: URL {
        switch self {
        case .flow: return WatchDeepLink.flow
        case .ecard: return WatchDeepLink.ecard
        }
    }
}

/// 按 `widgetFamily` 切换布局，覆盖全部 accessory 族
struct WatchAccessoryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let kind: WatchAccessoryKind

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularBody
            case .accessoryRectangular:
                rectangularBody
            case .accessoryInline:
                inlineBody
            case .accessoryCorner:
                cornerBody
            default:
                // 未知 / 未来 family：退回圆形风格
                circularBody
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.accessibilityLabel)
    }

    // MARK: - Circular
    // 圆形：表盘两侧圆形槽位。用背景 + 居中图标，留白充足。

    private var circularBody: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: kind.systemImage)
                .font(.system(size: 20, weight: .semibold))
                .widgetAccentable()
                .minimumScaleFactor(0.7)
        }
        // 圆形内容需居中填满可用区域，避免被裁切
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Rectangular
    // 矩形：信息密度最高。图标 + 标题 + 一行副标题，左对齐填满。

    private var rectangularBody: some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack {
                // 轻量圆形底板，在 fullColor / accented 下都更易辨认
                Circle()
                    .fill(.tertiary.opacity(renderingMode == .fullColor ? 0.35 : 0.2))
                Image(systemName: kind.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .widgetAccentable()
            }
            .frame(width: 28, height: 28)
            .layoutPriority(1)

            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(kind.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.vertical, 1)
    }

    // MARK: - Inline
    // 行内：仅一行，极短文案 + SF Symbol。

    private var inlineBody: some View {
        Label {
            Text(kind.title)
                .lineLimit(1)
        } icon: {
            Image(systemName: kind.systemImage)
        }
    }

    // MARK: - Corner
    // 角位：主图标在角上，文案沿表圈弯曲。

    private var cornerBody: some View {
        Image(systemName: kind.systemImage)
            .font(.system(size: 22, weight: .semibold))
            .widgetAccentable()
            .widgetLabel {
                Text(kind.title)
                    .widgetAccentable()
            }
            // watchOS 10+：让内容贴合角位弧线
            .modifier(CornerCurvesIfAvailable())
    }
}

/// 校园卡复杂功能：按不同表盘槽位显示真实缓存余额，并保留付款码入口语义。
struct WatchECardAccessoryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    let balance: Int

    private var fullBalance: String {
        ECardBalanceFormatter.string(from: balance)
    }

    private var compactBalance: String {
        ECardBalanceFormatter.compact(from: balance)
    }

    private var accessibilityText: String {
        if balance < 0 {
            return "校园卡余额待刷新，打开付款码"
        }
        return "校园卡余额\(fullBalance)，打开付款码"
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularBody
            case .accessoryRectangular:
                rectangularBody
            case .accessoryInline:
                inlineBody
            case .accessoryCorner:
                cornerBody
            default:
                circularBody
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var circularBody: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "qrcode")
                    .font(.system(size: 12, weight: .semibold))
                    .widgetAccentable()
                Text(compactBalance)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            .padding(.horizontal, 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rectangularBody: some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack {
                Circle()
                    .fill(.tertiary.opacity(renderingMode == .fullColor ? 0.35 : 0.2))
                Image(systemName: "qrcode")
                    .font(.system(size: 16, weight: .semibold))
                    .widgetAccentable()
            }
            .frame(width: 28, height: 28)
            .layoutPriority(1)

            VStack(alignment: .leading, spacing: 0) {
                Text("校园卡余额")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(fullBalance)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.vertical, 1)
    }

    private var inlineBody: some View {
        Label {
            Text(balance < 0 ? "校园卡余额待刷新" : "校园卡 \(fullBalance)")
                .monospacedDigit()
                .lineLimit(1)
        } icon: {
            Image(systemName: "qrcode")
        }
    }

    private var cornerBody: some View {
        Text(compactBalance)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .widgetAccentable()
            .widgetLabel {
                Label {
                    Text("付款码")
                } icon: {
                    Image(systemName: "qrcode")
                }
                    .widgetAccentable()
            }
            .modifier(CornerCurvesIfAvailable())
    }
}

/// `widgetCurvesContent` 仅在较新系统上稳定；用 ViewModifier 兼容编译。
private struct CornerCurvesIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(watchOS 10.0, *) {
            content.widgetCurvesContent()
        } else {
            content
        }
    }
}
