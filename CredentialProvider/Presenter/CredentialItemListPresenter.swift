/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import RxSwift
import RxCocoa
import RxOptional
import CoreGraphics
import MozillaAppServices

class ItemListPresenter: BaseItemListPresenter {
    weak var view: ItemListViewProtocol? {
        return self.baseView as? ItemListViewProtocol
    }

    override var learnMoreObserver: AnyObserver<Void>? { return nil }

    override var learnMoreNewEntriesObserver: AnyObserver<Void>? { return nil }

    override var itemSelectedObserver: AnyObserver<String?> {
        return Binder(self) { target, itemId in
            guard let id = itemId else {
                return
            }

            target.view?.dismissKeyboard()

            target.dataStore.get(id)
                .map { login -> CredentialStatusAction in
                    if let login = login {
                        return CredentialStatusAction.loginSelected(login: login)
                    } else {
                        return CredentialStatusAction.cancelled(error: .userCanceled)
                    }
                }
                .subscribe(onNext: { target.dispatcher.dispatch(action: $0) })
                .disposed(by: target.disposeBag)
        }.asObserver()
    }

    override var helpTextItems: [LoginListCellConfiguration] { return [LoginListCellConfiguration.SelectAPasswordHelpText] }

    lazy var cancelButtonObserver: AnyObserver<Void> = {
        return Binder(self) { target, _ in
            target.dispatcher.dispatch(action: CredentialStatusAction.cancelled(error: .userCanceled))
        }.asObserver()
    }()
}
