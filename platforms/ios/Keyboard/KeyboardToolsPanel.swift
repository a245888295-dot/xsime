import UIKit
#if KEYBOARD_LAYOUT_TESTS
@testable import RIMES
#endif
import RimesCore

/// 常用语：只存在键盘自己的沙盒里，和本地剪贴板一样不联网、不上屏。
enum KeyboardPhrases {
    static let maximumCount = 40
    static let maximumBytes = 2000
    private static let key = "keyboard.phrases.v1"

    static func load() -> [String] {
        (UserDefaults.standard.array(forKey: key) as? [String] ?? []).filter { valid($0) }
    }
    static func add(_ text: String) {
        guard valid(text) else { return }
        var items = load()
        items.removeAll { $0 == text }
        items.insert(text, at: 0)
        while items.count > maximumCount { items.removeLast() }
        UserDefaults.standard.set(items, forKey: key)
    }
    static func remove(_ text: String) {
        UserDefaults.standard.set(load().filter { $0 != text }, forKey: key)
    }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
    private static func valid(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= maximumBytes
    }
}

/// 工具面板里的一格。
struct ToolTile {
    let id: String
    let title: String
    let symbol: String
    var detail: String? = nil
    var selected = false
}

/// 一格工具：白色圆角方块里放图标，下面一行名字，选中时整块染色。
final class ToolTileButton: UIControl {
    private let card = UIView()
    private let icon = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    var tile: ToolTile { didSet { apply() } }

    init(_ tile: ToolTile) {
        self.tile = tile
        super.init(frame: .zero)
        card.isUserInteractionEnabled = false
        card.layer.cornerRadius = 15
        card.layer.cornerCurve = .continuous
        icon.contentMode = .scaleAspectFit
        icon.isUserInteractionEnabled = false
        titleLabel.textAlignment = .center
        titleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        titleLabel.textColor = .label
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75
        detailLabel.textAlignment = .center
        detailLabel.font = .systemFont(ofSize: 10, weight: .medium)
        detailLabel.textColor = .secondaryLabel
        addSubview(card)
        card.addSubview(icon)
        addSubview(titleLabel)
        addSubview(detailLabel)
        isAccessibilityElement = true
        accessibilityTraits = .button
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (button: ToolTileButton, _: UITraitCollection) in
                button.apply()
            }
        }
        apply()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.55 : 1 } }
    override func tintColorDidChange() { super.tintColorDidChange(); apply() }

    private func apply() {
        let accent = tintColor ?? .label
        titleLabel.text = tile.title
        detailLabel.text = tile.detail
        detailLabel.isHidden = tile.detail == nil
        icon.image = UIImage(systemName: tile.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .regular))
        icon.tintColor = tile.selected ? accent : .label
        card.backgroundColor = tile.selected ? accent.withAlphaComponent(0.16) : .secondarySystemGroupedBackground
        card.layer.borderWidth = tile.selected ? 1 : 0
        card.layer.borderColor = accent.withAlphaComponent(0.45).resolvedColor(with: traitCollection).cgColor
        accessibilityLabel = tile.title + (tile.detail.map { "，" + $0 } ?? "")
        accessibilityTraits = tile.selected ? [.button, .selected] : .button
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(bounds.width, 54)
        card.frame = CGRect(x: (bounds.width - side) / 2, y: 3, width: side, height: side)
        icon.frame = card.bounds.insetBy(dx: 15, dy: 15)
        titleLabel.frame = CGRect(x: 0, y: card.frame.maxY + 6, width: bounds.width, height: 14)
        detailLabel.frame = CGRect(x: 0, y: card.frame.maxY + 20, width: bounds.width, height: 12)
    }
}

/// 工具面板：盖住键盘区的一页格子，做的事和豆包输入法上排那几格一样。
final class KeyboardToolsPanel: UIView {
    var onSelect: ((String) -> Void)?
    var onClose: (() -> Void)?
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .custom)
    private let scroll = UIScrollView()
    private var buttons: [ToolTileButton] = []
    private var signature = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemGroupedBackground
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .label
        addSubview(titleLabel)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.backgroundColor = .tertiarySystemFill
        closeButton.layer.cornerRadius = 14
        closeButton.accessibilityLabel = L("关闭工具", "Close tools")
        closeButton.accessibilityIdentifier = "keyboard.tools.close"
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        addSubview(closeButton)
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = true
        scroll.hideEdgeEffects()
        addSubview(scroll)
        accessibilityIdentifier = "keyboard.tools"
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(title: String, tiles: [ToolTile]) {
        let next = title + "|" + tiles.map { "\($0.id):\($0.title):\($0.symbol):\($0.detail ?? ""):\($0.selected)" }.joined(separator: ",")
        guard next != signature else { return }
        signature = next
        titleLabel.text = title
        buttons.forEach { $0.removeFromSuperview() }
        buttons = tiles.map { tile in
            let button = ToolTileButton(tile)
            button.accessibilityIdentifier = "keyboard.tools.\(tile.id)"
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(tile.id) }, for: .touchUpInside)
            scroll.addSubview(button)
            return button
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset: CGFloat = 12
        titleLabel.frame = CGRect(x: inset, y: 6, width: max(0, bounds.width - 2 * inset - 34), height: 28)
        closeButton.frame = CGRect(x: bounds.width - inset - 28, y: 6, width: 28, height: 28)
        scroll.frame = CGRect(x: 0, y: 38, width: bounds.width, height: max(0, bounds.height - 38))
        let columns = 4, gap: CGFloat = 8, tileHeight: CGFloat = 92
        let width = max(1, (scroll.bounds.width - 2 * inset - CGFloat(columns - 1) * gap) / CGFloat(columns))
        var row = 0, column = 0
        for button in buttons {
            button.frame = CGRect(x: inset + CGFloat(column) * (width + gap), y: 4 + CGFloat(row) * (tileHeight + 2), width: width, height: tileHeight)
            column += 1
            if column == columns { column = 0; row += 1 }
        }
        let rows = buttons.isEmpty ? 0 : (buttons.count + columns - 1) / columns
        scroll.contentSize = CGSize(width: scroll.bounds.width, height: 8 + CGFloat(rows) * (tileHeight + 2))
    }
}
