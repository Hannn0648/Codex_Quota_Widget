import AppKit
import Darwin

// Keep the advisory lock for the process lifetime; never unlink the lock file.
final class SingleInstance {
    private var descriptor: Int32 = -1
    func acquire() throws -> Bool {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CodexQuota")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        descriptor = Darwin.open(folder.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return true }
        let code = errno
        Darwin.close(descriptor); descriptor = -1
        if code == EWOULDBLOCK { return false }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }
    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }
}


struct Window: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Double?
    var remaining: Double { max(0, min(100, 100 - usedPercent)) }
    var label: String { windowDurationMins == 300 ? "5 小时额度" : windowDurationMins == 10080 ? "周额度" : "\(windowDurationMins ?? 0) 分钟额度" }
    var resetText: String {
        guard let t = resetsAt else { return "重置时间暂不可用" }
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日 HH:mm:ss"
        return "重置：\(f.string(from: Date(timeIntervalSince1970: t)))"
    }
}
struct Bucket: Decodable { let primary: Window?; let secondary: Window?; let planType: String? }
struct Usage: Decodable {
    let rateLimits: Bucket?
    let rateLimitsByLimitId: [String: Bucket]?
    let ordinaryUsageAllowed: Bool?
    var bucket: Bucket { rateLimitsByLimitId?["codex"] ?? rateLimits ?? Bucket(primary: nil, secondary: nil, planType: nil) }
    var windows: [Window] { [bucket.primary, bucket.secondary].compactMap { $0 } }
    var selected: Window? { windows.first { $0.windowDurationMins == 300 } ?? windows.first { $0.windowDurationMins == 10080 } ?? windows.first }
    var weekly: Bool { selected?.windowDurationMins == 10080 }
}

// Read-only JSON-RPC connection; credentials remain owned by Codex.
final class UsageClient {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var completion: ((Result<Usage, Error>) -> Void)?
    private var timeout: Timer?
    private var generation = 0
    // Resolve on every read: an app update may replace or relocate the CLI.
    static func bundledExecutable(in app: URL) -> String? {
        let resources = app.appendingPathComponent("Contents/Resources")
        let paths = ["codex-cli/bin/codex", "codex-cli/CodexCLI.app/Contents/MacOS/codex", "codex"]
        for path in paths {
            let candidate = resources.appendingPathComponent(path).path
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        // Bounded fallback for future bundle layouts; avoid dependency trees.
        guard let files = FileManager.default.enumerator(at: resources, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return nil }
        var visited = 0
        for case let url as URL in files {
            visited += 1
            if visited > 2000 { break }
            if ["node_modules", "cua_node", "assets"].contains(url.lastPathComponent) || files.level > 7 {
                files.skipDescendants(); continue
            }
            if url.lastPathComponent == "codex", !((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? true), FileManager.default.isExecutableFile(atPath: url.path) { return url.path }
        }
        return nil
    }
    static var executable: String? {
        let fm = FileManager.default
        if let override = ProcessInfo.processInfo.environment["CODEX_BINARY"], fm.isExecutableFile(atPath: override) { return override }
        var apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "com.openai.codex" && !$0.isTerminated }.compactMap { $0.bundleURL }
        if let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") { apps.append(registered) }
        apps += ["/Applications/ChatGPT.app", "/Applications/Codex.app", NSHomeDirectory() + "/Applications/ChatGPT.app", NSHomeDirectory() + "/Applications/Codex.app"].map { URL(fileURLWithPath: $0) }
        var seen = Set<String>()
        for app in apps where seen.insert(app.path).inserted {
            if let path = bundledExecutable(in: app) { return path }
        }
        let candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/codex" }
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }
    static var executableFingerprint: String {
        guard let path = executable else { return "missing" }
        let attrs = (try? FileManager.default.attributesOfItem(atPath: URL(fileURLWithPath: path).resolvingSymlinksInPath().path)) ?? [:]
        return "\(path)|\(attrs[.modificationDate] ?? "")|\(attrs[.size] ?? "")|\(attrs[.systemFileNumber] ?? "")"
    }
    func fetch(_ done: @escaping (Result<Usage, Error>) -> Void) {
        guard completion == nil else { return }
        completion = done
        generation += 1
        let requestGeneration = generation
        guard let executable = Self.executable else { finish(.failure(error("找不到 Codex CLI：应用可能正在更新，将自动重新查找"))); return }
        let p = Process(), i = Pipe(), o = Pipe()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = ["app-server", "--listen", "stdio://"]
        p.standardInput = i; p.standardOutput = o; p.standardError = FileHandle.nullDevice
        input = i.fileHandleForWriting; output = o.fileHandleForReading; process = p; buffer = Data()
        o.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            DispatchQueue.main.async {
                guard let self = self, self.generation == requestGeneration else { return }
                self.receive(data)
            }
        }
        do {
            try p.run()
            send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "codex_quota_ring", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"]]])
            timeout = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in guard let self = self else { return }; self.finish(.failure(self.error("额度读取超时，请检查网络和 Codex 登录状态"))) }
        } catch { finish(.failure(error)) }
    }
    static func rpcError(_ value: [String: Any]) -> String {
        let message = value["message"] as? String ?? "额度读取失败"
        let lower = message.lowercased()
        if value["code"] as? Int == -32601 { return "Codex 额度接口不兼容，请更新 Codex Quota" }
        if ["unauthorized", "not logged", "authentication", "unauthenticated", "401", "sign in"].contains(where: { lower.contains($0) }) { return "Codex 登录状态失效，请在 Codex 中重新登录" }
        return message
    }
    private func error(_ message: String) -> NSError { NSError(domain: "CodexQuota", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    private func send(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
        do { try input?.write(contentsOf: data + Data([10])) } catch { finish(.failure(error)) }
    }
    private func receive(_ data: Data) {
        guard completion != nil else { return }
        if data.isEmpty { finish(.failure(error("Codex CLI 连接已结束：可能正在更新，将自动重连"))); return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.subdata(in: 0..<newline); buffer.removeSubrange(0...newline)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let id = obj["id"] as? Int else { continue }
            if let e = obj["error"] as? [String: Any] { finish(.failure(error(Self.rpcError(e)))); return }
            if id == 1 {
                send(["method": "initialized"])
                send(["id": 2, "method": "account/rateLimits/read", "params": NSNull()])
            } else if id == 2 {
                do {
                    let raw = try JSONSerialization.data(withJSONObject: obj["result"] ?? [:])
                    finish(.success(try JSONDecoder().decode(Usage.self, from: raw)))
                } catch { finish(.failure(self.error("额度数据格式不兼容，请更新 Codex Quota"))) }
                return
            }
        }
    }
    private func finish(_ result: Result<Usage, Error>) {
        guard let done = completion else { return }
        generation += 1
        completion = nil; timeout?.invalidate(); timeout = nil
        output?.readabilityHandler = nil
        try? input?.close(); input = nil
        let p = process; process = nil
        if p?.isRunning == true { p?.terminate() }
        output = nil
        done(result)
    }
    func stop() { finish(.failure(error("已停止"))) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    let client = UsageClient()
    var usage: Usage?
    var lastUpdate: Date?
    var failure: String?
    var timer: Timer?
    var fetching = false
    private var monitor: Timer?
    private var retry: Timer?
    private var failures = 0
    private var cliFingerprint = ""
    var barStyle = UserDefaults.standard.string(forKey: "displayStyle") == "bar"
    @objc func chooseStyle(_ sender: NSMenuItem) {
        barStyle = sender.tag == 1
        UserDefaults.standard.set(barStyle ? "bar" : "ring", forKey: "displayStyle")
        render()
    }
    private let hostBundleID = "com.openai.codex"
    private var followingHost = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(hostChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(hostChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        hostChanged()
        monitor = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(checkInstallation), userInfo: nil, repeats: true)
        RunLoop.main.add(monitor!, forMode: .common)
    }
    @objc func woke() { hostChanged(); refresh() }
    @objc func checkInstallation() {
        hostChanged()
        guard followingHost else { return }
        let fingerprint = UsageClient.executableFingerprint
        guard fingerprint != cliFingerprint else { return }
        cliFingerprint = fingerprint
        retry?.invalidate(); retry = nil; failures = 0
        client.stop()
        retry?.invalidate(); retry = nil
        refresh()
    }
    @objc func hostChanged() {
        let hostRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == hostBundleID && !$0.isTerminated }
        guard hostRunning != followingHost else { return }
        followingHost = hostRunning
        if hostRunning {
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self; item.button?.action = #selector(showDetails)
            cliFingerprint = UsageClient.executableFingerprint
            render(); refresh()
            timer = Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
            RunLoop.main.add(timer!, forMode: .common)
        } else {
            timer?.invalidate(); timer = nil
            retry?.invalidate(); retry = nil; failures = 0
            if let existing = item { NSStatusBar.system.removeStatusItem(existing); item = nil }
            client.stop()
        }
    }
    func applicationWillTerminate(_ notification: Notification) { monitor?.invalidate(); retry?.invalidate(); client.stop() }
    @objc func refresh() {
        guard followingHost, !fetching else { return }
        retry?.invalidate(); retry = nil; fetching = true
        client.fetch { [weak self] result in
            guard let self = self else { return }; self.fetching = false
            switch result {
            case .success(let value): self.usage = value; self.lastUpdate = Date(); self.failure = nil; self.failures = 0
            case .failure(let error):
                self.failure = error.localizedDescription
                if self.followingHost {
                    self.failures += 1
                    let delay = [5.0, 10, 20, 60][min(self.failures - 1, 3)]
                    self.retry = Timer.scheduledTimer(timeInterval: delay, target: self, selector: #selector(self.refresh), userInfo: nil, repeats: false)
                    RunLoop.main.add(self.retry!, forMode: .common)
                }
            }
            self.render()
        }
    }
    func render() {
        guard let button = item?.button else { return }
        let selected = usage?.selected
        let isBar = barStyle
        let alpha: CGFloat = failure == nil ? 1 : 0.4
        let image = NSImage(size: NSSize(width: isBar ? 82 : 28, height: 22), flipped: false) { rect in
            if isBar {
                let label = selected.map { "\(Int($0.remaining.rounded()))" } ?? "—"
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold), .foregroundColor: NSColor.black]
                let size = (label as NSString).size(withAttributes: attrs)
                (label as NSString).draw(at: NSPoint(x: 27 - size.width, y: (22 - size.height) / 2), withAttributes: attrs)
                let frame = NSRect(x: 34, y: 8, width: 44, height: 6)
                let track = NSBezierPath(roundedRect: frame, xRadius: 3, yRadius: 3)
                NSColor.black.withAlphaComponent(0.18).setFill(); track.fill()
                if let value = selected?.remaining, value > 0 {
                    NSGraphicsContext.saveGraphicsState()
                    track.addClip()
                    NSColor.black.withAlphaComponent(alpha).setFill()
                    NSBezierPath(rect: NSRect(x: frame.minX, y: frame.minY, width: frame.width * CGFloat(value / 100), height: frame.height)).fill()
                    NSGraphicsContext.restoreGraphicsState()
                }
                return true
            }
            let center = NSPoint(x: 14, y: 11), radius: CGFloat = 9.5
            let track = NSBezierPath(ovalIn: NSRect(x: 4.5, y: 1.5, width: 19, height: 19))
            track.lineWidth = 1.7; NSColor.black.withAlphaComponent(0.18).setStroke(); track.stroke()
            if let value = selected?.remaining, value > 0 {
                let arc = NSBezierPath(); arc.lineWidth = 1.7; arc.lineCapStyle = .round
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - CGFloat(value) * 3.6, clockwise: true)
                NSColor.black.withAlphaComponent(alpha).setStroke(); arc.stroke()
            }
            let label = selected.map { "\(Int($0.remaining.rounded()))" } ?? "—"
            let font = NSFont.monospacedDigitSystemFont(ofSize: label.count > 2 ? 8.5 : 10, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let size = (label as NSString).size(withAttributes: attrs)
            (label as NSString).draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attrs)
            return true
        }
        image.isTemplate = true; button.image = image
        button.imagePosition = .imageLeading
        button.title = ""
        button.font = NSFont.systemFont(ofSize: 10)
        let prefix = failure == nil ? "" : (usage == nil ? "" : "刷新失败：\(failure!)\n以下为上次数据\n")
        button.toolTip = prefix + (selected.map { "\($0.label)剩余 \(Int($0.remaining.rounded()))%\n\($0.resetText)" } ?? (failure ?? "正在读取额度…")) + (usage?.weekly == true ? "\n当前仅返回周额度，未返回 5 小时额度" : "")
        button.setAccessibilityLabel(button.toolTip)
    }
    @objc func showDetails() {
        let menu = NSMenu()
        func row(_ text: String) { let i = NSMenuItem(title: text, action: nil, keyEquivalent: ""); i.isEnabled = false; menu.addItem(i) }
        row("Codex 额度详情")
        if let usage = usage {
            if let plan = usage.bucket.planType { row("套餐：\(plan)") }
            for w in usage.windows { row("\(w.label) · 剩余 \(Int(w.remaining.rounded()))%"); row(w.resetText) }
            if usage.windows.isEmpty { row("暂无额度窗口数据") }
            if usage.weekly { row("当前仅返回周额度"); row("未返回 5 小时额度；不据此判断无限制") }
            if usage.ordinaryUsageAllowed == false { row("当前常规额度使用受限") }
        }
        if let failure = failure { row("刷新失败：\(failure)") }
        if let date = lastUpdate { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; row("更新于 \(f.string(from: date)) · 每 60 秒刷新") }
        menu.addItem(.separator())
        for (title, tag) in [("圆环样式", 0), ("横条样式", 1)] {
            let option = NSMenuItem(title: title, action: #selector(chooseStyle(_:)), keyEquivalent: "")
            option.target = self; option.tag = tag
            option.state = (barStyle == (tag == 1)) ? .on : .off
            menu.addItem(option)
        }
        menu.addItem(.separator())
        let refresh = NSMenuItem(title: fetching ? "正在刷新…" : "立即刷新", action: #selector(refresh), keyEquivalent: "r"); refresh.target = self; refresh.isEnabled = !fetching; menu.addItem(refresh)
        let quit = NSMenuItem(title: "退出 Codex 额度", action: #selector(quit), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
        item.menu = menu; item.button?.performClick(nil); item.menu = nil
    }
    @objc func quit() { NSApp.terminate(nil) }
}

if CommandLine.arguments.contains("--self-test") {
    func check(_ json: String, _ percent: Double?, _ weekly: Bool) {
        let usage = try! JSONDecoder().decode(Usage.self, from: Data(json.utf8))
        if usage.selected?.remaining != percent || usage.weekly != weekly { fputs("FAIL: \(json)\n", stderr); exit(1) }
    }
    check(#"{"rateLimits":{"primary":{"usedPercent":15,"windowDurationMins":10080}}}"#, 85, true)
    check(#"{"rateLimits":{"primary":{"usedPercent":15,"windowDurationMins":10080},"secondary":{"usedPercent":28,"windowDurationMins":300}}}"#, 72, false)
    check(#"{"rateLimits":{}}"#, nil, false)
    check(#"{"rateLimits":{"primary":{"usedPercent":120,"windowDurationMins":300}}}"#, 0, false)
    check(#"{"rateLimits":{"primary":{"usedPercent":-5,"windowDurationMins":300}}}"#, 100, false)
    check(#"{"rateLimits":{"primary":{"usedPercent":15,"windowDurationMins":10080}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":40,"windowDurationMins":300}}}}"#, 60, false)
    check(#"{"rateLimits":null,"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":25,"windowDurationMins":300}}},"futureField":true}"#, 75, false)
    check(#"{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":10,"windowDurationMins":15}}}}"#, 90, false)
    check(#"{}"#, nil, false)
    precondition(UsageClient.rpcError(["code": -32601]).contains("接口不兼容"))
    precondition(UsageClient.rpcError(["message": "401 Unauthorized"]).contains("重新登录"))
    // Simulate a bundle update moving the executable, including an unknown layout.
    let fm = FileManager.default
    let fixture = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("quota-resolver-" + UUID().uuidString)
    try! fm.createDirectory(at: fixture, withIntermediateDirectories: true)
    do {
        defer { try? fm.removeItem(at: fixture) }
        func createCLI(_ relative: String) -> URL {
            let url = fixture.appendingPathComponent("Contents/Resources/" + relative)
            try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try! Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
            try! fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return url
        }
        let old = createCLI("codex")
        precondition(UsageClient.bundledExecutable(in: fixture) == old.path)
        try! fm.removeItem(at: old)
        precondition(UsageClient.bundledExecutable(in: fixture) == nil)
        let updated = createCLI("codex-cli/bin/codex")
        precondition(UsageClient.bundledExecutable(in: fixture) == updated.path)
        try! fm.removeItem(at: updated)
        let future = createCLI("tools/next/bin/codex")
        let discovered = UsageClient.bundledExecutable(in: fixture)
        precondition(discovered != nil)
        // Directory enumeration may canonicalize /var to /private/var.
        let expectedID = try! fm.attributesOfItem(atPath: future.path)[.systemFileNumber] as! NSNumber
        let discoveredID = try! fm.attributesOfItem(atPath: discovered!)[.systemFileNumber] as! NSNumber
        precondition(expectedID == discoveredID)
    }
    print("PASS: quota decoding, future windows, error classification, CLI relocation and rediscovery")
} else if CommandLine.arguments.contains("--probe") {
    let client = UsageClient()
    client.fetch { result in
        switch result {
        case .success(let usage):
            print("读取成功：" + usage.windows.map { "\($0.label)剩余 \(Int($0.remaining))%，\($0.resetText)" }.joined(separator: "；"))
            exit(0)
        case .failure(let error): fputs(error.localizedDescription + "\n", stderr); exit(1)
        }
    }
    RunLoop.main.run()
} else {
    let instance = SingleInstance()
    do { guard try instance.acquire() else { exit(0) } }
    catch { fputs("无法取得单实例锁：\(error.localizedDescription)\n", stderr); exit(1) }
    let app = NSApplication.shared
    let delegate = AppDelegate(); app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(instance) { app.run() }
}
