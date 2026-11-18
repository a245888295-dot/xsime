import UIKit
#if KEYBOARD_LAYOUT_TESTS
@testable import RIMES
#endif

/// 剪贴板面板的两个页签：本地文字历史、常用语。
enum TextClipboardTab { case clipboard, phrases }

/// 键盘里的剪贴板：上排两个页签，下面是卡片。
/// 点卡片把整段加入 Buffer；右侧“…”里可以拆词、存为常用语或删除。
final class TextClipboardPanel: UIView, UITableViewDataSource, UITableViewDelegate {
    let collect = BufferPasteButton()
    var onSelect: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onClear: (() -> Void)?
    var onSplit: ((UUID) -> Void)?
    var onAddPhrase: ((UUID) -> Void)?
    var onPhraseSelect: ((String) -> Void)?
    var onPhraseDelete: ((String) -> Void)?
    var onPhraseClear: (() -> Void)?

    private let tabs = UISegmentedControl(items: [L("剪贴板", "Clipboard"), L("常用语", "Phrases")])
    private let caption = UILabel(), clear = UIButton(type: .system)
    private let table = UITableView(frame: .zero, style: .plain)
    private var entries: [TextClipboardStore.Entry] = []
    private var phrases: [String] = []
    private var enabled = false
    private var tab: TextClipboardTab = .clipboard
    private var phraseMode: Bool { tab == .phrases }

    override init(frame: CGRect) {
        super.init(frame: frame)
        collect.accessibilityIdentifier = "keyboard.clipboard.collect"
        collect.setPurpose(label: L("收录当前剪贴板文字", "Collect current clipboard text"), hint: L("只保存于本机，不上屏", "Save on this device without inserting"))
        tabs.selectedSegmentIndex = 0
        tabs.accessibilityIdentifier = "keyboard.clipboard.tabs"
        tabs.addAction(UIAction { [weak self] _ in self?.switchTab() }, for: .valueChanged)
        caption.font = .systemFont(ofSize: 12)
        caption.textColor = .secondaryLabel
        caption.numberOfLines = 2
        clear.titleLabel?.font = .systemFont(ofSize: 12)
        clear.accessibilityIdentifier = "keyboard.clipboard.clear"
        clear.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if self.phraseMode { self.onPhraseClear?() } else { self.onClear?() }
        }, for: .touchUpInside)
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 54
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.keyboardDismissMode = .none
        table.register(ClipboardRowCell.self, forCellReuseIdentifier: "row")
        table.accessibilityIdentifier = "keyboard.clipboard.entries"
        for item in [tabs, collect, caption, clear, table] { addSubview(item) }
    }
    required init?(coder: NSCoder) { fatalError() }

    /// 打开面板时直接落在哪一页。
    func select(tab next: TextClipboardTab) {
        tab = next
        tabs.selectedSegmentIndex = next == .phrases ? 1 : 0
        relayout()
    }

    func update(_ entries: [TextClipboardStore.Entry], phrases: [String], fullAccess: Bool, enabled: Bool) {
        self.entries = entries
        self.phrases = phrases
        self.enabled = enabled
        collect.fullAccess = fullAccess
        relayout()
    }

    func redact() {
        entries = []
        phrases = []
        enabled = false
        collect.isEnabled = false
        table.reloadData()
    }

    private func switchTab() {
        tab = tabs.selectedSegmentIndex == 1 ? .phrases : .clipboard
        relayout()
    }

    private func relayout() {
        collect.isHidden = phraseMode
        collect.isEnabled = enabled && !phraseMode
        clear.isEnabled = enabled && !(phraseMode ? phrases.isEmpty : entries.isEmpty)
        clear.setTitle(phraseMode ? L("清空", "Clear") : L("清空历史", "Clear history"), for: .normal)
        caption.text = phraseMode
            ? L("点一下插入；条目右侧“…”可删除", "Tap to insert. Use … to delete.")
            : L("最多 40 条，只存在本机", "Up to 40 entries, stored on this device")
        table.reloadData()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let rowY: CGFloat = 34
        tabs.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 30)
        collect.frame = CGRect(x: 0, y: rowY, width: 44, height: 26)
        clear.frame = CGRect(x: max(44, bounds.width - 82), y: rowY, width: min(82, bounds.width), height: 26)
        let captionX: CGFloat = phraseMode ? 0 : 48
        caption.frame = CGRect(x: captionX, y: rowY, width: max(0, clear.frame.minX - captionX - 4), height: 26)
        table.frame = CGRect(x: 0, y: rowY + 30, width: bounds.width, height: max(0, bounds.height - rowY - 30))
    }

    // MARK: - Rows
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        phraseMode ? phrases.count : entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath) as! ClipboardRowCell
        if phraseMode {
            guard phrases.indices.contains(indexPath.row) else { return cell }
            let text = phrases[indexPath.row]
            cell.label.text = text
            cell.more.isEnabled = enabled
            cell.more.menu = UIMenu(children: [
                UIAction(title: L("删除", "Delete"), image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                    self?.onPhraseDelete?(text)
                }
            ])
            cell.accessibilityIdentifier = "keyboard.clipboard.phrase"
            cell.accessibilityHint = L("点按插入这句常用语", "Tap to insert this phrase")
            cell.isAccessibilityElement = false
            cell.contentView.accessibilityLabel = text
            return cell
        }
        guard entries.indices.contains(indexPath.row) else { return cell }
        let entry = entries[indexPath.row]
        cell.label.text = entry.text
        cell.more.isEnabled = enabled
        var actions: [UIAction] = []
        if entry.text.count > 8 {
            actions.append(UIAction(title: L("拆词", "Split text"), image: UIImage(systemName: "scissors")) { [weak self] _ in
                self?.onSplit?(entry.id)
            })
        }
        actions.append(UIAction(title: L("存为常用语", "Save as phrase"), image: UIImage(systemName: "text.quote")) { [weak self] _ in
            self?.onAddPhrase?(entry.id)
        })
        actions.append(UIAction(title: L("删除", "Delete"), image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            self?.onDelete?(entry.id)
        })
        cell.more.menu = UIMenu(children: actions)
        cell.accessibilityIdentifier = "keyboard.clipboard.entry.\(entry.id)"
        cell.accessibilityHint = L("点按加入 Buffer", "Tap to add to Buffer")
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard enabled else { return }
        if phraseMode {
            guard phrases.indices.contains(indexPath.row) else { return }
            onPhraseSelect?(phrases[indexPath.row])
        } else {
            guard entries.indices.contains(indexPath.row) else { return }
            onSelect?(entries[indexPath.row].id)
        }
    }
}

/// 一张卡片：左边三行文字，右边“…”菜单。
private final class ClipboardRowCell: UITableViewCell {
    let label = UILabel()
    let more = UIButton(type: .system)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 10
        card.layer.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .label
        label.numberOfLines = 3
        label.translatesAutoresizingMaskIntoConstraints = false
        more.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        more.tintColor = .secondaryLabel
        more.showsMenuAsPrimaryAction = true
        more.accessibilityLabel = L("更多操作", "More actions")
        more.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(label)
        card.addSubview(more)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            label.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            label.trailingAnchor.constraint(equalTo: more.leadingAnchor, constant: -4),
            more.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6),
            more.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            more.widthAnchor.constraint(equalToConstant: 28),
            more.heightAnchor.constraint(equalToConstant: 30)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}
