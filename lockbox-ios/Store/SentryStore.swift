/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Sentry
import RxSwift

class SentryStore {
    private let SentryDSNKey = "SentryDSN"
    private var disposeBag = DisposeBag()

    public static let shared = SentryStore()

    init(dispatcher: Dispatcher = .shared) {
        dispatcher.register
                .filterByType(class: SentryAction.self)
                .subscribe(onNext: { (action) in
                    Client.shared?.reportUserException(
                        action.title,
                        reason: action.error.localizedDescription,
                        language: NSLocale.preferredLanguages.first ?? "",
                        lineOfCode: action.line,
                        stackTrace: Thread.callStackSymbols,
                        logAllThreads: false,
                        terminateProgram: false)
                })
                .disposed(by: self.disposeBag)
        
    }

    func setup(sendUsageData: Bool) {
        if isSimulator() || !sendUsageData {
            return
        }

        guard let dsn = Bundle.main.object(forInfoDictionaryKey: SentryDSNKey) as? String, !dsn.isEmpty else {
            return
        }

        do {
            Client.shared = try Client(dsn: dsn)
            try Client.shared?.startCrashHandler()

            // https://docs.sentry.io/clients/cocoa/advanced/#breadcrumbs
            Client.shared?.enableAutomaticBreadcrumbTracking()
        } catch let error {
            print("\(error)")
        }
    }

    private func isSimulator() -> Bool {
        return ProcessInfo.processInfo.environment["SIMULATOR_ROOT"] != nil
    }
}
