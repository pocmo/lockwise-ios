/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import AuthenticationServices

class CredentialProviderView: ASCredentialProviderViewController {
    private var presenter: CredentialProviderPresenter?

    private var currentViewController: UIViewController? {
        didSet {
            if let currentViewController = self.currentViewController {
                self.addChild(currentViewController)
                currentViewController.view.frame = self.view.bounds
                self.view.addSubview(currentViewController.view)
                currentViewController.didMove(toParent: self)
            }

            guard let oldViewController = oldValue else {
                return
            }
            oldViewController.willMove(toParent: nil)
            oldViewController.view.removeFromSuperview()
            oldViewController.removeFromParent()
        }
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return self.currentViewController?.preferredStatusBarStyle ?? .lightContent
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        AppearanceHelper.shared.setupAppearance()
        self.presenter = CredentialProviderPresenter(view: self)
    }

    override func prepareInterfaceForExtensionConfiguration() {
        self.presenter?.extensionConfigurationRequested()
    }

    /*
     Prepare your UI to list available credentials for the user to choose from. The items in
     'serviceIdentifiers' describe the service the user is logging in to, so your extension can
     prioritize the most relevant credentials in the list.
    */
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        self.presenter?.credentialList(for: serviceIdentifiers)
    }

    override func prepareInterfaceToProvideCredential(for credentialIdentity: ASPasswordCredentialIdentity) {
        self.presenter?.prepareAuthentication(for: credentialIdentity)
    }

    override func provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity) {
        self.presenter?.credentialProvisionRequested(for: credentialIdentity)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        self.presenter?.changeDisplay(traitCollection: traitCollection)
    }
}

extension CredentialProviderView: CredentialProviderViewProtocol {
    func displayWelcome() {
        let welcomeView = UIStoryboard(name: "CredentialWelcome", bundle: nil)
            .instantiateViewController(withIdentifier: "welcome")
        self.currentViewController = welcomeView
    }

    func displayItemList() {
        let viewController = UIStoryboard(name: "ItemList", bundle: nil)
            .instantiateViewController(withIdentifier: "itemlist")

        self.currentViewController = UINavigationController(rootViewController: viewController)
    }
}
