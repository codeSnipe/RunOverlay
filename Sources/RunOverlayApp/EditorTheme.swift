import SwiftUI

enum EditorTheme {
    static let canvas = Color(red: 0.065, green: 0.075, blue: 0.091)
    static let sidebar = Color(red: 0.090, green: 0.105, blue: 0.126)
    static let inspector = Color(red: 0.100, green: 0.115, blue: 0.138)
    static let surface = Color(red: 0.139, green: 0.157, blue: 0.185)
    static let raised = Color(red: 0.174, green: 0.193, blue: 0.224)
    static let separator = Color(red: 0.235, green: 0.261, blue: 0.296)
    static let accent = Color(red: 0.43, green: 0.89, blue: 0.83)
    static let highlight = Color(red: 1.0, green: 0.86, blue: 0.27)
    static let muted = Color(red: 0.63, green: 0.68, blue: 0.72)
    static let text = Color(red: 0.95, green: 0.97, blue: 0.98)
}

/// 全局操作按钮：主操作实心胶囊、次操作描边胶囊，密集区域使用同体系的紧凑版。
struct EditorActionButtonStyle: ButtonStyle {
    enum Tone {
        case primary
        case outline
        case selected
        case quiet
        case destructive
    }

    enum Size {
        case regular
        case compact
        case icon
        case smallIcon

        var height: CGFloat {
            switch self {
            case .regular: 48
            case .compact, .icon: 34
            case .smallIcon: 28
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .regular: 18
            case .compact: 10
            case .icon, .smallIcon: 0
            }
        }
    }

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    let tone: Tone
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule()
        let emphasized = tone == .primary || tone == .selected
        let activeForeground: Color = switch tone {
        case .primary, .selected: EditorTheme.canvas
        case .outline: EditorTheme.accent
        case .quiet: EditorTheme.text
        case .destructive: isHovered ? .red : EditorTheme.muted
        }
        let background: Color = switch tone {
        case .primary, .selected:
            isHovered ? EditorTheme.accent.opacity(0.88) : EditorTheme.accent
        case .outline:
            isHovered ? EditorTheme.accent.opacity(0.12) : EditorTheme.sidebar
        case .quiet:
            isHovered ? EditorTheme.raised : EditorTheme.surface.opacity(0.64)
        case .destructive:
            isHovered ? .red.opacity(0.15) : EditorTheme.surface.opacity(0.55)
        }
        configuration.label
            .font(.system(
                size: size == .regular ? 14 : 11,
                weight: emphasized ? .semibold : .medium
            ))
            .foregroundStyle(isEnabled ? activeForeground : EditorTheme.muted.opacity(0.6))
            .frame(
                width: size == .icon || size == .smallIcon ? size.height : nil,
                height: size.height
            )
            .padding(.horizontal, size.horizontalPadding)
            .background(
                isEnabled ? background : EditorTheme.surface.opacity(0.55),
                in: shape
            )
            .overlay {
                shape.strokeBorder(
                    isEnabled && (tone == .outline || tone == .destructive)
                        ? (tone == .destructive
                            ? EditorTheme.muted.opacity(0.38)
                            : EditorTheme.accent)
                        : .clear,
                    lineWidth: tone == .outline ? 1.4 : 1
                )
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 工作台顶部的成组 Tab，保留每个选项的辅助提示与键盘可访问性。
struct EditorInlineTabs<Option: Hashable>: View {
    let options: [Option]
    let selection: Option
    let title: (Option) -> String
    let onSelect: (Option) -> Void
    var helpText: (Option) -> String = { _ in "" }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection == option
                Button {
                    if !isSelected { onSelect(option) }
                } label: {
                    Text(title(option))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 11)
                        .frame(height: 38)
                        .foregroundStyle(
                            isSelected ? EditorTheme.text : EditorTheme.muted
                        )
                }
                .buttonStyle(EditorChoiceTabButtonStyle(isSelected: isSelected))
                .help(helpText(option))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(3)
        .background(EditorTheme.surface, in: RoundedRectangle(cornerRadius: 11))
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct EditorChoiceTabs<Option: Hashable>: View {
    let options: [Option]
    let selection: Option
    let columns: Int
    let title: (Option) -> String
    let onSelect: (Option) -> Void

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 0),
                count: max(1, columns)
            ),
            spacing: 0
        ) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection == option
                Button {
                    if !isSelected {
                        onSelect(option)
                    }
                } label: {
                    Text(title(option))
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isSelected ? EditorTheme.text : EditorTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .padding(.horizontal, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(EditorChoiceTabButtonStyle(isSelected: isSelected))
                .help(title(option))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(EditorTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity)
    }
}

struct EditorChoiceTabButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let isSelected: Bool
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                isSelected ? EditorTheme.raised
                    : (isHovered ? EditorTheme.raised.opacity(0.5) : .clear),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(isSelected ? EditorTheme.accent : .clear)
                    .frame(height: 2)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 2)
            }
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
