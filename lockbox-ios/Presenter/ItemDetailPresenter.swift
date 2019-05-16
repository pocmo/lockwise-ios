/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import RxSwift
import RxCocoa
import RxDataSources
import MozillaAppServices

protocol ItemDetailViewProtocol: class, StatusAlertView {
    func enableSwipeNavigation(enabled: Bool)
    func enableLargeTitle(enabled: Bool)
    var cellTapped: Observable<String?> { get }
    var deleteTapped: Observable<Void> { get }
    var rightBarButtonTapped: Observable<Void> { get }
    var leftBarButtonTapped: Observable<Void> { get }
    var itemDetailObserver: ItemDetailSectionModelObserver { get }
    var titleText: Binder<String?> { get }
    var rightButtonText: Binder<String?> { get }
    var leftButtonText: Binder<String?> { get }
    var deleteHidden: Binder<Bool> { get }
}

let copyableFields = [Constant.string.username, Constant.string.password]

class ItemDetailPresenter {
    weak var view: ItemDetailViewProtocol?
    private var dispatcher: Dispatcher
    private var dataStore: DataStore
    private var itemDetailStore: ItemDetailStore
    private var copyDisplayStore: CopyDisplayStore
    private var sizeClassStore: SizeClassStore
    private var disposeBag = DisposeBag()

    lazy private var onPasswordToggle: AnyObserver<Bool> = {
        return Binder(self) { target, revealed in
            target.dispatcher.dispatch(action: ItemDetailDisplayAction.togglePassword(displayed: revealed))
        }.asObserver()
    }()

    lazy private(set) var onRightSwipe: AnyObserver<Void> = {
        return Binder(self) { target, _ in
            target.dispatcher.dispatch(action: MainRouteAction.list)
        }.asObserver()
    }()

    init(view: ItemDetailViewProtocol,
         dispatcher: Dispatcher = .shared,
         dataStore: DataStore = DataStore.shared,
         itemDetailStore: ItemDetailStore = ItemDetailStore.shared,
         copyDisplayStore: CopyDisplayStore = CopyDisplayStore.shared,
         sizeClassStore: SizeClassStore = SizeClassStore.shared) {
        self.view = view
        self.dispatcher = dispatcher
        self.dataStore = dataStore
        self.itemDetailStore = itemDetailStore
        self.copyDisplayStore = copyDisplayStore
        self.sizeClassStore = sizeClassStore
    }

    func onViewReady() {
        let itemObservable = self.dataStore.locked
                .filter { !$0 }
                .take(1)
                .flatMap { _ in self.itemDetailStore.itemDetailId }
                .flatMap { self.dataStore.get($0) }

        let itemDriver = itemObservable.asDriver(onErrorJustReturn: nil)

        Driver.combineLatest(itemDriver.filterNil(), self.itemDetailStore.passwordRevealed)
                .map { e -> [ItemDetailSectionModel] in
                    return self.configurationForLogin(e.0, passwordDisplayed: e.1)
                }
                .drive(self.view!.itemDetailObserver)
                .disposed(by: self.disposeBag)

        itemObservable
                .filterNil()
                .map { item -> String in
                    let title = item.hostname.titleFromHostname()
                    return title.isEmpty ? Constant.string.unnamedEntry : title
                }
                .asDriver(onErrorJustReturn: Constant.string.unnamedEntry)
                .drive(self.view!.titleText)
                .disposed(by: self.disposeBag)

        self.setupEdit()
        self.setupCopy(itemObservable: itemObservable)
        self.setupNavigation()
    }

    private func setupEdit() {
        self.itemDetailStore.isEditing
                .map { !$0 }
                .subscribe(self.view!.deleteHidden)
                .disposed(by: self.disposeBag)

        self.itemDetailStore.isEditing
                .subscribe(onNext: { editing in self.view?.enableLargeTitle(enabled: !editing) })
                .disposed(by: self.disposeBag)
    }

    private func setupCopy(itemObservable: Observable<LoginRecord?>) {
        self.view?.cellTapped
                .filterNil()
                .withLatestFrom(itemObservable) { (cellTitle: String, item: LoginRecord?) -> [Action] in
                    var actions: [Action] = []
                    if copyableFields.contains(cellTitle) {
                        if let item = item {
                            actions.append(DataStoreAction.touch(id: item.id))
                            actions.append(ItemDetailPresenter.getCopyActionFor(item, value: cellTitle, actionType: .tap))
                        }
                    } else if cellTitle == Constant.string.webAddress {
                        if let origin = item?.hostname {
                            actions.append(ExternalLinkAction(baseURLString: origin))
                        }
                    }
                    return actions

                }
                .observeOn(MainScheduler.instance)
                .subscribe(onNext: { actions in
                    for action in actions {
                        self.dispatcher.dispatch(action: action)
                    }
                })
                .disposed(by: self.disposeBag)

        self.copyDisplayStore.copyDisplay
                .drive(onNext: { field in
                    let fieldName: String
                    switch field {
                    case .password: fieldName = Constant.string.password
                    case .username: fieldName = Constant.string.username
                    }

                    let message = String(format: Constant.string.fieldNameCopied, fieldName)
                    self.view?.displayTemporaryAlert(message, timeout: Constant.number.displayStatusAlertLength)
                })
        .disposed(by: self.disposeBag)
    }

    private func setupNavigation() {
        self.view?.leftBarButtonTapped
                .flatMap { _ in self.itemDetailStore.isEditing.take(1) }
                .map { editing -> Action in
                    return editing ? ItemDetailDisplayAction.viewMode : MainRouteAction.list
                }
                .subscribe(onNext: { self.dispatcher.dispatch(action: $0) })
                .disposed(by: self.disposeBag)

        self.view?.rightBarButtonTapped
                .flatMap { _ in self.itemDetailStore.isEditing.take(1) }
                .map { editing -> Action in
                    return editing ? ItemDetailDisplayAction.viewMode : ItemDetailDisplayAction.editMode
                }
                .subscribe(onNext: { self.dispatcher.dispatch(action: $0) })
                .disposed(by: self.disposeBag)

        self.itemDetailStore.isEditing
                .withLatestFrom(self.sizeClassStore.shouldDisplaySidebar) { (editing: Bool, sidebar: Bool) -> String? in
                    if editing {
                        return Constant.string.cancel
                    } else if !sidebar {
                        return Constant.string.back
                    } else {
                        return nil
                    }
                }
                .subscribe(self.view!.leftButtonText)
                .disposed(by: self.disposeBag)

        self.sizeClassStore.shouldDisplaySidebar
                .subscribe(onNext: { (enableSidebar) in
                    self.view?.enableSwipeNavigation(enabled: !enableSidebar)
                })
                .disposed(by: self.disposeBag)
    }

    func dndStarted(value: String?) {
        self.itemDetailStore.itemDetailId
            .take(1)
            .flatMap { self.dataStore.get($0) }
            .flatMap { item -> Observable<[Action]> in
                var actions: [Action] = []
                if let item = item {
                    actions.append(DataStoreAction.touch(id: item.id))
                    actions.append(ItemDetailPresenter.getCopyActionFor(item, value: value, actionType: .dnd))
                }

                return Observable.just(actions)
            }.subscribe(onNext: { actions in
                for action in actions {
                    self.dispatcher.dispatch(action: action)
                }
            }).disposed(by: self.disposeBag)
    }
}

// helpers
extension ItemDetailPresenter {
    private func configurationForLogin(_ login: LoginRecord?, passwordDisplayed: Bool) -> [ItemDetailSectionModel] {
        var passwordText: String
        let itemPassword: String = login?.password ?? ""

        if passwordDisplayed {
            passwordText = itemPassword
        } else {
            passwordText = String(repeating: "•", count: itemPassword.count)
        }

        let editing = self.itemDetailStore.isEditing
                .asDriver(onErrorJustReturn: true)

        let hostname = login?.hostname ?? ""
        let username = login?.username ?? ""
        let sectionModels = [
            ItemDetailSectionModel(model: 0, items: [
                ItemDetailCellConfiguration(
                        title: Constant.string.webAddress,
                        value: hostname,
                        accessibilityLabel: String(format: Constant.string.websiteCellAccessibilityLabel, hostname),
                        valueFontColor: Constant.color.lockBoxViolet,
                        accessibilityId: "webAddressItemDetail",
                        textFieldEnabled: editing,
                        openButtonHidden: editing,
                        dragValue: hostname)
            ]),
            ItemDetailSectionModel(model: 1, items: [
                ItemDetailCellConfiguration(
                        title: Constant.string.username,
                        value: username,
                        accessibilityLabel: String(format: Constant.string.usernameCellAccessibilityLabel, username),
                        accessibilityId: "userNameItemDetail",
                        textFieldEnabled: editing,
                        copyButtonHidden: editing,
                        dragValue: username),
                ItemDetailCellConfiguration(
                        title: Constant.string.password,
                        value: passwordText,
                        accessibilityLabel: String(
                            format: Constant.string.passwordCellAccessibilityLabel,
                            passwordText),
                        accessibilityId: "passwordItemDetail",
                        textFieldEnabled: editing,
                        copyButtonHidden: editing,
                        revealPasswordObserver: self.onPasswordToggle,
                        dragValue: login?.password)
            ])
        ]

        return sectionModels
    }

    private static func getCopyActionFor(_ item: LoginRecord?, value: String?, actionType: CopyActionType) -> CopyAction {
        var field = CopyField.username
        var text = ""
        if value == Constant.string.username {
            text = item?.username ?? ""
            field = CopyField.username
        } else if value == Constant.string.password {
            text = item?.password ?? ""
            field = CopyField.password
        }

        return CopyAction(text: text, field: field, itemID: item?.id ?? "", actionType: actionType)
    }
}
