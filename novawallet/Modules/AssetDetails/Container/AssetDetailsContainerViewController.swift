import UIKit
import SoraFoundation

final class AssetDetailsContainerViewController: ContainerViewController {
    override var presentationNavigationItem: UINavigationItem? {
        navigationController != nil ? navigationItem : nil
    }

    override var navigationItem: UINavigationItem {
        (content as? UIViewController)?.navigationItem ?? .init()
    }
}

extension AssetDetailsContainerViewController: AssetDetailsContainerViewProtocol {}
