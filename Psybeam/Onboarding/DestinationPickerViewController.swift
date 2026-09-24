import UIKit

/// The first-run "where are you headed?" sheet. Most first launches happen at
/// home, before the trip, where GPS can only suggest the language you already
/// speak; one tap here gives the conversation a language to translate into.
///
/// Dismisses itself, then reports: `onPick` with the chosen language, or
/// `onSkip` for "Not now" and for a swipe down.
final class DestinationPickerViewController: UIViewController {
    var onPick: ((String) -> Void)?
    var onSkip: (() -> Void)?

    private let destinations: [String]
    private let brand = UIColor(red: 0.30, green: 0.62, blue: 1.0, alpha: 1)
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: Self.makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>?

    init(destinations: [String]) {
        self.destinations = destinations
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        traitCollection.userInterfaceStyle == .dark ? .lightContent : .darkContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        presentationController?.delegate = self
        build()
        configureDataSource()
    }

    private static func makeLayout() -> UICollectionViewLayout {
        var list = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        list.headerMode = .supplementary
        list.backgroundColor = .clear
        return UICollectionViewCompositionalLayout.list(using: list)
    }

    /// The list scrolls under a pinned "Not now", so every destination stays
    /// reachable on a short window: an iPad running the iPhone app, or the
    /// largest accessibility text sizes.
    private func build() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true

        let skip = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.attributedTitle = AttributedString(String(localized: "Not now"), attributes: AttributeContainer([
            .font: UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 16, weight: .medium)),
        ]))
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        skip.configuration = config
        skip.translatesAutoresizingMaskIntoConstraints = false
        skip.addAction(UIAction { [weak self] _ in self?.skip() }, for: .touchUpInside)

        view.addSubview(collectionView)
        view.addSubview(skip)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: skip.topAnchor, constant: -4),

            skip.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            skip.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            skip.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            skip.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
    }

    private func configureDataSource() {
        let brand = brand
        let header = UICollectionView.SupplementaryRegistration<DestinationHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { header, _, _ in
            header.configure(accent: brand)
        }
        let cell = UICollectionView.CellRegistration<UICollectionViewListCell, String> { cell, _, code in
            cell.accessories = [.disclosureIndicator()]
            cell.backgroundConfiguration = .listCell()
            cell.accessibilityAttributedLabel = Self.accessibilityTitle(code)
            cell.accessibilityTraits = .button
            cell.configurationUpdateHandler = { cell, state in
                var content = UIListContentConfiguration.cell()
                content.attributedText = Self.rowTitle(code, traits: state.traitCollection)
                cell.contentConfiguration = content
            }
        }
        let dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collectionView) { collectionView, indexPath, code in
            collectionView.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: code)
        }
        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(destinations)
        dataSource.apply(snapshot, animatingDifferences: false)
        self.dataSource = dataSource
    }

    /// "Japanese · 日本語": the name you read, then the name they read, which
    /// is dropped when the two are the same word.
    private static func rowTitle(_ code: String, traits: UITraitCollection) -> NSAttributedString {
        let body = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
        let name = LanguageNames.listTitle(code)
        let endonym = LanguageNames.endonym(code)
        let title = NSMutableAttributedString(string: name, attributes: [
            .font: UIFont.systemFont(ofSize: body.pointSize, weight: .semibold),
            .foregroundColor: UIColor.label,
        ])
        guard name.caseInsensitiveCompare(endonym) != .orderedSame else { return title }
        title.append(NSAttributedString(string: "\u{00A0}· " + endonym, attributes: [
            .font: body,
            .foregroundColor: UIColor.secondaryLabel,
        ]))
        return title
    }

    /// VoiceOver reads the endonym in its own voice rather than spelling
    /// foreign script out in the UI language's voice.
    private static func accessibilityTitle(_ code: String) -> NSAttributedString {
        let name = LanguageNames.listTitle(code)
        let endonym = LanguageNames.endonym(code)
        let label = NSMutableAttributedString(string: name)
        guard name.caseInsensitiveCompare(endonym) != .orderedSame else { return label }
        label.append(NSAttributedString(string: ", "))
        label.append(NSAttributedString(string: endonym, attributes: [.accessibilitySpeechLanguage: code]))
        return label
    }

    private func pick(_ code: String) {
        dismiss(animated: true) { self.onPick?(code) }
    }

    private func skip() {
        dismiss(animated: true) { self.onSkip?() }
    }
}

extension DestinationPickerViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let code = dataSource?.itemIdentifier(for: indexPath) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        pick(code)
    }
}

extension DestinationPickerViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onSkip?()
    }
}

private final class DestinationHeaderView: UICollectionReusableView {
    private let icon = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        icon.image = UIImage(systemName: "airplane.departure", withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .semibold))
        icon.contentMode = .center
        icon.isAccessibilityElement = false

        titleLabel.text = String(localized: "Where are you headed?")
        titleLabel.font = UIFontMetrics(forTextStyle: .title1).scaledFont(for: .systemFont(ofSize: 28, weight: .bold))
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header

        subtitleLabel.text = String(localized: "Psybeam will speak their language for you.")
        subtitleLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 16))
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [icon, titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 8
        stack.setCustomSpacing(18, after: icon)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 36),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(accent: UIColor) {
        icon.tintColor = accent
    }
}
