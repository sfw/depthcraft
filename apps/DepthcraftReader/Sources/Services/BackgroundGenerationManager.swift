import Foundation
import UIKit
import UserNotifications

/// Manages background execution and notifications for course generation
/// 
/// iOS Background Reality Check:
/// - beginBackgroundTask gives ~30 seconds (occasionally up to 3 minutes) of background time
/// - This is **best-effort** for LLM generation that may take minutes/hours
/// - OS will terminate the app if it exceeds the granted time
/// - BGTaskScheduler cannot resume long-running generation (it's for discrete scheduled tasks)
/// - URLSession background is for downloads, not computation
///
/// What we guarantee:
/// - Progress persists across backgrounding via partial state
/// - User gets notified on completion/failure (if app survives background)
/// - Can leave Generate screen and return to live progress
/// - Honest about iOS limits: multi-hour Exhaustive may not survive days of suspension
@MainActor
class BackgroundGenerationManager: ObservableObject {
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var hasRequestedNotificationPermission = false
    
    /// Request notification permission (call once at generation start)
    func requestNotificationPermission() async {
        // Only request once per app session to avoid spam
        guard !hasRequestedNotificationPermission else { return }
        hasRequestedNotificationPermission = true
        
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            if !granted {
                print("Notification permission denied")
            }
        } catch {
            print("Notification permission error: \(error)")
        }
    }
    
    /// Begin background task when generation starts
    func beginBackgroundTask(name: String) {
        // If already running, don't start another
        guard backgroundTaskID == .invalid else { return }
        
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // Expiration handler - OS is about to terminate us
            self?.endBackgroundTask()
        }
        
        print("Background task started: \(name)")
    }
    
    /// End background task (call when generation completes/fails or app returns to foreground)
    func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
        print("Background task ended")
    }
    
    /// Post local notification for generation completion
    func postCompletionNotification(topic: String, totalLessons: Int, durationMs: Int64?) {
        let content = UNMutableNotificationContent()
        content.title = "Course Generated"
        content.body = ""\(topic)" is ready with \(totalLessons) lesson\(totalLessons == 1 ? "" : "s")"
        if let duration = durationMs {
            let minutes = Int(duration / 60_000)
            if minutes > 0 {
                content.body += " (took \(minutes)m)"
            }
        }
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "generation-complete",
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }
    }
    
    /// Post local notification for generation failure
    func postFailureNotification(topic: String, error: String) {
        let content = UNMutableNotificationContent()
        content.title = "Generation Failed"
        content.body = ""\(topic)" encountered an error"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "generation-failed",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }
    }
}
