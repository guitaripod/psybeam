import MidgarUI
import UIKit

/// A short list Settings pushes for a row with a few fixed answers, such as a language or the appearance, with the
/// current answer ticked. Choosing one reports it and returns to Settings.
final class OptionPickerViewController: UITableViewController {
    struct Option {
        let id: String
        let title: String
    }

    private let options: [Option]
    private let selectedID: String
    private let onSelect: (String) -> Void

    init(title: String, options: [Option], selectedID: String, onSelect: @escaping (String) -> Void) {
        self.options = options
        self.selectedID = selectedID
        self.onSelect = onSelect
        super.init(style: .insetGrouped)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let theme = MidgarTheme.psybeam
        view.backgroundColor = theme.uiBackground
        tableView.backgroundColor = theme.uiBackground
        tableView.separatorColor = theme.uiSeparator
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.identifier)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        options.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.identifier, for: indexPath)
        let option = options[indexPath.row]
        let theme = MidgarTheme.psybeam
        var content = cell.defaultContentConfiguration()
        content.text = option.title
        content.textProperties.color = theme.uiLabel
        cell.contentConfiguration = content
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = theme.uiSurface
        cell.backgroundConfiguration = background
        cell.accessoryType = option.id == selectedID ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onSelect(options[indexPath.row].id)
        navigationController?.popViewController(animated: true)
    }

    private static let identifier = "option"
}
