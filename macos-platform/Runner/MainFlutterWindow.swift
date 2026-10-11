import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // 短剧为竖屏内容，默认按较宽的窗口呈现，避免两侧留白。
    if self.frame.size.width < 900 {
      self.setContentSize(NSSize(width: 1180, height: 760))
    }
    self.minSize = NSSize(width: 900, height: 600)
    self.center()

    super.awakeFromNib()
  }
}
