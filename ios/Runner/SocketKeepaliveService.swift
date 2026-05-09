import Foundation
import BackgroundTasks
import UIKit

class SocketKeepaliveService {

    static let shared = SocketKeepaliveService()
    static let backgroundTaskIdentifier = "com.xamepage.xamepage.socketkeepalive"

    private var keepaliveTimer: Timer?

    func start(channel: AnyObject?) {
        registerBackgroundTask()
        startTimer()
        setupLifecycleObservers()
    }

    private func startTimer() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = Timer.scheduledTimer(
            timeInterval: 25.0,
            target: self,
            selector: #selector(pingFlutter),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(keepaliveTimer!, forMode: .common)
    }

    @objc private func pingFlutter() {
        NotificationCenter.default.post(name: Notification.Name("SocketHeartbeat"), object: nil)
    }

    private func registerBackgroundTask() {
        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: SocketKeepaliveService.backgroundTaskIdentifier,
                using: nil
            ) { task in
                self.handleBackgroundTask(task: task as! BGAppRefreshTask)
            }
        }
    }

    func scheduleBackgroundRefresh() {
        if #available(iOS 13.0, *) {
            let request = BGAppRefreshTaskRequest(
                identifier: SocketKeepaliveService.backgroundTaskIdentifier
            )
            request.earliestBeginDate = Date(timeIntervalSinceNow: 25)
            try? BGTaskScheduler.shared.submit(request)
        }
    }

    @available(iOS 13.0, *)
    private func handleBackgroundTask(task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()
        pingFlutter()
        task.setTaskCompleted(success: true)
    }

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc private func appDidEnterBackground() { scheduleBackgroundRefresh() }
    @objc private func appWillEnterForeground() { startTimer(); pingFlutter() }
    func stop() { keepaliveTimer?.invalidate(); keepaliveTimer = nil }
}
