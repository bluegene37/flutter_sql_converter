import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Set initial window size to 1280x800 (fits 13" laptop screens)
    let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let windowWidth: CGFloat = min(1280, screenFrame.width)
    let windowHeight: CGFloat = min(800, screenFrame.height)
    let originX = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
    let originY = screenFrame.origin.y + (screenFrame.height - windowHeight) / 2
    self.setFrame(NSRect(x: originX, y: originY, width: windowWidth, height: windowHeight), display: true)

    // Set minimum window size
    self.minSize = NSSize(width: 1024, height: 680)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
