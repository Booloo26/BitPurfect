import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var switchingEngine: SwitchingEngine?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !terminateIfAlreadyRunning() else { return }

        let audio = AudioDeviceController()
        let engine = SwitchingEngine(audio: audio)
        switchingEngine = engine
        menuBarController = MenuBarController(audio: audio, engine: engine)
        engine.start()
        installTerminationSignalHandlers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // We spawn two helper processes (the MediaRemote perl bridge and `log stream`), and
        // neither notices we're gone promptly on its own. This covers the normal Quit path.
        switchingEngine?.stop()
    }

    /// A second copy is actively harmful, not just untidy: two engines write sample rates to
    /// the same device, two menu bar items appear, and each one's stray-stream reaper kills the
    /// other's `log stream` on launch. Checked before anything else starts for that last
    /// reason. Two bundles in different folders (say `/Applications` and a build directory)
    /// share a bundle identifier, so this catches the realistic case as well as `open -n`.
    private func terminateIfAlreadyRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard !others.isEmpty else { return false }

        // Hand the user back the copy that's already there, so clicking the app again reads as
        // "show me BitPurfect" rather than doing nothing at all.
        others.first?.activate()
        NSApp.terminate(nil)
        return true
    }

    /// AppKit does not run `applicationWillTerminate` for a bare SIGTERM, so a `kill`, a
    /// logout, or a `pkill` during development would leave those helpers behind. A dispatch
    /// signal source is safe here (it runs as a normal block, not in signal context) — and
    /// SIGKILL still can't be caught, which is why the stream also reaps strays at launch.
    private func installTerminationSignalHandlers() {
        for signalNumber in [SIGTERM, SIGINT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                self?.switchingEngine?.stop()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
