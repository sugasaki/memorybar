import AppKit
import Observation
import SwiftUI

/// 数値をネイティブのタイトルとして更新し、MenuBarExtra の画像再生成を避ける。
@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
  let statusItem: NSStatusItem
  let popover = NSPopover()
  private let monitor: MemoryMonitor
  private let floatingController: FloatingWindowController

  init(monitor: MemoryMonitor, floatingController: FloatingWindowController) {
    self.monitor = monitor
    self.floatingController = floatingController
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    super.init()

    if let button = statusItem.button {
      button.image = NSImage(systemSymbolName: "memorychip", accessibilityDescription: "MemoryBar")
      button.imagePosition = .imageLeading
      button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
      button.target = self
      button.action = #selector(togglePopover)
      button.setAccessibilityLabel("MemoryBar")
    }
    popover.behavior = .transient
    popover.delegate = self
    // 毎秒更新と詳細の開閉でサイズが動くため、伸縮アニメーションを入れない。
    popover.animates = false
    observeTitle()
  }

  private func observeTitle() {
    withObservationTracking {
      let text = monitor.menuBarText
      if statusItem.button?.title != text {
        statusItem.button?.title = text
      }
    } onChange: { [weak self] in
      // Observation は書き換え前に通知する。次のターンで最新値を読み、再登録する。
      Task { @MainActor [weak self] in self?.observeTitle() }
    }
  }

  func popoverDidClose(_ notification: Notification) {
    // 非表示のパネルを毎秒更新し続けず、次回は設定を読み直して生成する。
    popover.contentViewController = nil
  }

  @objc func togglePopover() {
    if popover.isShown {
      popover.performClose(nil)
      return
    }
    guard let button = statusItem.button else { return }
    if popover.contentViewController == nil {
      let content = MenuContentView(
        monitor: monitor, updateController: .shared,
        loginItemController: .shared, floatingController: floatingController,
        onHeightChange: { [weak popover] height in
          guard let popover, abs(popover.contentSize.height - height) > 0.5 else { return }
          popover.contentSize = NSSize(width: 280, height: height)
        })
      popover.contentViewController = NSHostingController(rootView: content)
      popover.contentSize = NSSize(width: 280, height: 300)
    }
    NSApp.activate(ignoringOtherApps: true)
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
  }
}
