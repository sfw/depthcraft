import Foundation
import UIKit
import UserNotifications

/// Manages background execution and notifications for course generation
/// 
/// iOS Background Strategy (Honest Assessment):
/// 
/// What iOS Allows:
/// 1. beginBackgroundTask: ~30s-3min best-effort continuation when backgrounded
/// 2. Checkpoint/Resume: Persist state to survive process death
/// 
/// What We Guarantee:
/// - Frequent checkpointing survives process death (every lesson completion)
/// - Resume from checkpoint on app foreground/restart (zero lesson redo)
/// - Notifications on complete/fail
/// - Best-effort continuation while backgrounded (iOS decides how long)
/// 
/// What We Don't Guarantee:
/// - Multi-day background runs without foreground return (iOS terminates suspended apps)
/// - Continuation after beginBackgroundTask expires (~30s-3min)
/// - Generation during Low Power Mode (iOS suspends background work)
/// 
/// Tradeoffs:
/// - Exhaustive depth may require periodic foreground returns for very long runs
/// - Best results: keep device charging, don't force-quit app, return to foreground periodically
/// - Checkpoint ensures zero lesson redo even if process dies
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
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if !granted {
                print("⚠️ Notification permission denied")
            } else {
                print("✓ Notification permission granted")
            }
        } catch {
            print("⚠️ Notification permission error: \(error)")
        }
    }
    
    /// Begin background task when generation starts
    func beginBackgroundTask(name: String) {
        // If already running, don't start another
        guard backgroundTaskID == .invalid else { return }
        
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // Expiration handler - iOS is about to terminate background execution
            // Checkpoint is already being saved incrementally, so partial work survives
            print("⚠️ Background task expiring - will resume from checkpoint when foregrounded")
            self?.handleBackgroundTaskExpiration()
        }
        
        print("✓ Background task started: \(name)")
    }
    
    /// Handle background task expiration (iOS killing background time)
    private func handleBackgroundTaskExpiration() {
        // Checkpoint is already being saved incrementally by orchestrator
        // Just end the background task gracefully
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
    
    /// End background task (call when generation completes/fails)
    func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
        print("✓ Background task ended")
    }
    
    /// Post local notification for generation completion
    func postCompletionNotification(topic: String, totalLessons: Int, durationMs: Int?) {
        let content = UNMutableNotificationContent()
        content.title = "✅ Course Generated"
        content.body = "\(topic) is ready with \(totalLessons) lesson\(totalLessons == 1 ? "" : "s")"
        if let duration = durationMs {
            let minutes = duration / 60_000
            if minutes > 0 {
                content.body += " (\(minutes)m)"
            }
        }
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "GENERATION_COMPLETE"
        
        let request = UNNotificationRequest(
            identifier: "generation-complete-\(UUID().uuidString)",
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("⚠️ Failed to post completion notification: \(error)")
            } else {
                print("✓ Posted completion notification")
            }
        }
    }
    
    /// Post local notification for generation failure
    func postFailureNotification(topic: String, error: String) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Generation Failed"
        content.body = "\(topic) encountered an error"
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "GENERATION_FAILED"
        
        let request = UNNotificationRequest(
            identifier: "generation-failed-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("⚠️ Failed to post failure notification: \(error)")
            } else {
                print("✓ Posted failure notification")
            }
        }
    }
    
    /// Clear notification badges
    func clearNotificationBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }
}
