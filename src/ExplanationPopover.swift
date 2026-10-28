import Cocoa
import WebKit

public protocol ExplanationPopoverDelegate: AnyObject {
    func didRequestRegenerate(simpler: Bool)
    func didRequestOpenSettings()
    func didSubmitDoubt(doubtText: String)
}

// Custom Draggable Header View using Apple's native performDrag
class DraggableHeaderView: NSView {
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1 {
            window?.performDrag(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }
}

public class ExplanationPopoverWindow: NSPanel, WKNavigationDelegate, WKScriptMessageHandler {
    public weak var actionDelegate: ExplanationPopoverDelegate?
    private var headerView: DraggableHeaderView!
    private var titleLabel: NSTextField!
    private var pageBadge: NSTextField!
    private var pinButton: NSButton!
    private var closeButton: NSButton!

    private var webView: WKWebView!
    private var currentTextToCopy: String = ""
    private var currentPageContext: String = ""
    private var hasBeenPositionedOnce: Bool = false

    public var isPinned: Bool = true {
        didSet {
            updatePinState()
        }
    }

    private func updatePinState() {
        updatePinButtonAppearance()
        if isPinned {
            self.isFloatingPanel = true
            self.hidesOnDeactivate = false
            self.level = .floating
        } else {
            self.isFloatingPanel = false
            self.hidesOnDeactivate = true
            self.level = .floating
        }
    }

    public init() {
        let contentRect = NSRect(x: 0, y: 0, width: 490, height: 320)
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isOpaque = true
        self.backgroundColor = NSColor.windowBackgroundColor
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hasShadow = true
        self.minSize = NSSize(width: 380, height: 240)

        // Hide unwanted macOS traffic light buttons
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true

        self.isMovable = true
        self.isMovableByWindowBackground = true

        setupViews()
        updatePinState()
    }

    private func setupViews() {
        guard let container = self.contentView else { return }

        // 1. Native Draggable Top Header (Height 36px)
        headerView = DraggableHeaderView(frame: NSRect(x: 0, y: container.bounds.height - 36, width: container.bounds.width, height: 36))
        headerView.autoresizingMask = [.width, .minYMargin]
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Document Title
        titleLabel = NSTextField(frame: NSRect(x: 14, y: 8, width: 250, height: 20))
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.stringValue = "📄 Document"
        headerView.addSubview(titleLabel)

        // Page Badge
        pageBadge = NSTextField(frame: NSRect(x: 268, y: 8, width: 90, height: 20))
        pageBadge.isEditable = false
        pageBadge.isBordered = false
        pageBadge.backgroundColor = .clear
        pageBadge.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        pageBadge.textColor = NSColor.secondaryLabelColor
        pageBadge.stringValue = ""
        headerView.addSubview(pageBadge)

        // Pin Button (Top right)
        pinButton = NSButton(frame: NSRect(x: container.bounds.width - 118, y: 6, width: 80, height: 24))
        pinButton.autoresizingMask = [.minXMargin]
        pinButton.title = "📌 Pin"
        pinButton.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        pinButton.bezelStyle = .rounded
        pinButton.target = self
        pinButton.action = #selector(togglePin)
        pinButton.focusRingType = .none
        headerView.addSubview(pinButton)

        // Close Button (Top right corner)
        closeButton = NSButton(frame: NSRect(x: container.bounds.width - 32, y: 6, width: 24, height: 24))
        closeButton.autoresizingMask = [.minXMargin]
        closeButton.title = "✕"
        closeButton.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.focusRingType = .none
        headerView.addSubview(closeButton)

        container.addSubview(headerView)

        // 2. WebKit View for clean, formatted content (Below header)
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "popoverAction")
        config.userContentController = controller

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: container.bounds.width, height: container.bounds.height - 36), configuration: config)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")

        container.addSubview(webView)
    }

    @objc private func togglePin() {
        isPinned.toggle()
    }

    private func updatePinButtonAppearance() {
        if isPinned {
            pinButton.title = "📍 Pinned"
            pinButton.contentTintColor = NSColor.systemBlue
        } else {
            pinButton.title = "📌 Pin"
            pinButton.contentTintColor = NSColor.secondaryLabelColor
        }
    }

    @objc private func closeClicked() {
        self.orderOut(nil)
    }

    public override var canBecomeKey: Bool {
        return true
    }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC key
            self.orderOut(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    public override func resignKey() {
        super.resignKey()
        if !isPinned {
            self.orderOut(nil)
        }
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let action = message.body as? String else { return }
        if action == "copy" {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(currentTextToCopy, forType: .string)
        } else if action == "copyContext" {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(currentPageContext, forType: .string)
        } else if action == "simpler" {
            actionDelegate?.didRequestRegenerate(simpler: true)
        } else if action == "settings" {
            actionDelegate?.didRequestOpenSettings()
        } else if action == "close" {
            self.orderOut(nil)
        } else if action.hasPrefix("doubt:") {
            let doubtText = String(action.dropFirst(6))
            actionDelegate?.didSubmitDoubt(doubtText: doubtText)
        }
    }

    // Step 1: Immediate display (0ms). If pinned, stays strictly in place!
    public func showLoading(
        selection: String,
        docName: String?,
        pageDisplay: String?,
        modelName: String,
        near screenRect: CGRect,
        initialStatus: String = "🔍 Reading page context..."
    ) {
        updateHeaderInfo(docName: docName, pageDisplay: pageDisplay)

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        \(cleanCss)
        </style>
        </head>
        <body>
        <div class="content-container">
            <div class="quote-box">“\(escapeHtml(selection))”</div>

            <div class="loading-box">
                <div class="spinner"></div>
                <div id="statusLabel" class="status-text">\(escapeHtml(initialStatus))</div>
            </div>
        </div>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: nil)

        // Only position near cursor on first show or when explicitly UNPINNED. When pinned, stays anchored in place!
        if !isPinned || !hasBeenPositionedOnce {
            positionWindow(near: screenRect)
            hasBeenPositionedOnce = true
        }

        self.makeKeyAndOrderFront(nil)
        self.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    // Dynamic progress updates while working
    public func updateProgress(status: String, docName: String? = nil, pageDisplay: String? = nil) {
        if docName != nil || pageDisplay != nil {
            updateHeaderInfo(docName: docName, pageDisplay: pageDisplay)
        }
        let js = "var el = document.getElementById('statusLabel'); if (el) { el.innerText = '\(escapeJs(status))'; }"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func updateHeaderInfo(docName: String?, pageDisplay: String?) {
        var clean = docName?.replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "_", with: " ") ?? "Document"
        if clean.count > 26 {
            clean = String(clean.prefix(24)) + "…"
        }
        let lower = clean.lowercased()
        if lower.contains("chrome") || lower.contains("safari") || lower.contains("firefox") || lower.contains("arc") || lower.contains("edge") || lower.contains("browser") {
            titleLabel.stringValue = "🌐 \(clean)"
        } else {
            titleLabel.stringValue = "📄 \(clean)"
        }
        titleLabel.sizeToFit()
        let availableWidth = (contentView?.bounds.width ?? 490) - 130 - 14 - 90
        let finalTitleWidth = min(titleLabel.frame.width, max(availableWidth, 120))
        titleLabel.frame = NSRect(x: 14, y: 8, width: finalTitleWidth, height: 20)

        if let page = pageDisplay {
            pageBadge.stringValue = "• \(page)"
            pageBadge.sizeToFit()
            pageBadge.frame = NSRect(x: 14 + finalTitleWidth + 6, y: 8, width: max(pageBadge.frame.width + 12, 110), height: 20)
        } else {
            pageBadge.stringValue = ""
        }
    }

    // Step 2: Render explanation with Doubt bar, Clickable Quote Page Context Inspector & Model Attribution
    public func showExplanation(
        selection: String,
        docName: String?,
        pageDisplay: String?,
        modelName: String,
        pageContext: String?,
        explanationMarkdown: String
    ) {
        self.currentTextToCopy = explanationMarkdown
        self.currentPageContext = pageContext ?? ""
        updateHeaderInfo(docName: docName, pageDisplay: pageDisplay)

        let cleanContext = pageContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let wordCount = cleanContext.isEmpty ? 0 : cleanContext.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count

        let renderedHTML = renderSimpleMarkdown(explanationMarkdown)

        let isFallback = modelName.contains("[Fallback]")
        let cleanModelName = modelName.replacingOccurrences(of: " [Fallback]", with: "")
        let pageSource = pageDisplay ?? "page"

        let drawerText: String
        let drawerTitle: String
        if cleanContext.isEmpty {
            drawerTitle = "Privacy: Highlighted text only"
            drawerText = "Only your highlighted text was processed. Background window contents or browser tabs are never accessed."
        } else {
            drawerTitle = "(\(wordCount) words context fetched from \(escapeHtml(pageSource)))"
            drawerText = cleanContext
        }

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        \(cleanCss)
        </style>
        </head>
        <body>
        <div class="content-container">
            <!-- Clickable Quote Box: Clicking toggles the page context drawer -->
            <div class="quote-box" onclick="toggleContextDrawer()" title="Click quote to view details">
                “\(escapeHtml(selection))”
            </div>

            <!-- Collapsible Context Drawer: Revealed only when quote is clicked -->
            <div id="contextDrawer" class="context-drawer" style="display: none;">
                <div class="context-drawer-header">
                    <span class="context-drawer-title">
                        <span class="context-dot \(cleanContext.isEmpty ? "gray" : "green")"></span>
                        <strong>\(drawerTitle)</strong>
                    </span>
                    <button class="context-copy-btn" onclick="copyContext(event)">Copy Text</button>
                </div>
                <div class="context-drawer-body">\(escapeHtml(drawerText))</div>
            </div>

            <div class="explanation-scroll" id="scrollContainer">
                <div id="mainExplanation">
                    \(renderedHTML)
                </div>

                <!-- Model Attribution Badge Below Output -->
                <div class="model-footer-badge">
                    <span class="model-badge-icon">\(isFallback ? "⚡" : "✨")</span>
                    <span class="model-badge-text">Generated by <strong>\(escapeHtml(cleanModelName))</strong></span>
                    \(isFallback ? "<span class='fallback-tag'>Auto-Fallback</span>" : "")
                </div>

                <div id="doubtThread"></div>
            </div>

            <!-- Inline Doubt Ask Bar (Expandable) -->
            <div id="doubtBar" class="doubt-bar" style="display: none;">
                <input id="doubtInput" type="text" class="doubt-input" placeholder="Ask a doubt about this text or page..." onkeydown="handleDoubtKey(event)" />
                <button class="action-btn" onclick="submitDoubt()">Ask</button>
            </div>

            <div class="bottom-bar">
                <div class="btn-group">
                    <button class="action-btn" onclick="copyExplanation()">📋 Copy</button>
                    <button class="action-btn" onclick="window.webkit.messageHandlers.popoverAction.postMessage('simpler')">💡 Simpler</button>
                    <button class="action-btn doubt-trigger-btn" onclick="toggleDoubtBar()">❓ Doubt</button>
                </div>
                <div class="hint-text">Drag header • Esc to close</div>
            </div>
        </div>

        <script>
        function toggleContextDrawer() {
            const drawer = document.getElementById('contextDrawer');
            if (!drawer) return;
            if (drawer.style.display === 'none' || drawer.style.display === '') {
                drawer.style.display = 'block';
            } else {
                drawer.style.display = 'none';
            }
        }

        function copyContext(e) {
            if (e) e.stopPropagation();
            window.webkit.messageHandlers.popoverAction.postMessage('copyContext');
            const btn = e.target;
            const orig = btn.innerText;
            btn.innerText = "✓ Copied";
            setTimeout(() => {
                btn.innerText = orig;
            }, 1200);
        }

        function copyExplanation() {
            window.webkit.messageHandlers.popoverAction.postMessage('copy');
            const btn = event.target;
            const orig = btn.innerText;
            btn.innerText = "✓ Copied";
            btn.style.color = "#34C759";
            setTimeout(() => {
                btn.innerText = orig;
                btn.style.color = "";
            }, 1400);
        }

        function toggleDoubtBar() {
            const bar = document.getElementById('doubtBar');
            if (bar.style.display === 'none') {
                bar.style.display = 'flex';
                document.getElementById('doubtInput').focus();
            } else {
                bar.style.display = 'none';
            }
        }

        function handleDoubtKey(e) {
            if (e.key === 'Enter') {
                submitDoubt();
            }
        }

        function submitDoubt() {
            const input = document.getElementById('doubtInput');
            const text = input.value.trim();
            if (!text) return;
            input.value = '';

            // Append user doubt with spinner in thread
            const thread = document.getElementById('doubtThread');
            const item = document.createElement('div');
            item.className = 'doubt-item';
            item.innerHTML = `
                <div class="doubt-query-bubble">❓ “${escapeHtml(text)}”</div>
                <div id="doubtPending" class="doubt-reply-box"><span class="spinner-inline"></span> 🌐 Researching internet & reasoning...</div>
            `;
            thread.appendChild(item);

            // Auto-scroll to bottom
            const scroller = document.getElementById('scrollContainer');
            scroller.scrollTop = scroller.scrollHeight;

            window.webkit.messageHandlers.popoverAction.postMessage('doubt:' + text);
        }

        function appendDoubtReply(renderedHtml) {
            const pending = document.getElementById('doubtPending');
            if (pending) {
                pending.removeAttribute('id');
                pending.innerHTML = renderedHtml;
            }
            const scroller = document.getElementById('scrollContainer');
            scroller.scrollTop = scroller.scrollHeight;
        }

        function escapeHtml(str) {
            return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
        }
        </script>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: nil)
        self.orderFrontRegardless()
    }

    public func appendDoubtAnswer(replyMarkdown: String) {
        let rendered = renderSimpleMarkdown(replyMarkdown)
        let escaped = escapeJs(rendered)
        let js = "appendDoubtReply('\(escaped)');"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    public func showError(selection: String, errorMessage: String) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        \(cleanCss)
        </style>
        </head>
        <body>
        <div class="content-container">
            <div class="quote-box">“\(escapeHtml(selection))”</div>

            <div class="explanation-scroll" style="color: #D32F2F;">
                \(escapeHtml(errorMessage))
            </div>

            <div class="bottom-bar">
                <button class="action-btn" onclick="window.webkit.messageHandlers.popoverAction.postMessage('settings')">⚙️ Preferences</button>
                <div class="hint-text">Esc to close</div>
            </div>
        </div>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func positionWindow(near screenRect: CGRect) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let mainHeight = NSScreen.screens.first?.frame.height ?? 900

        let cocoaX = screenRect.midX - (frame.width / 2)
        var cocoaY = mainHeight - screenRect.maxY - frame.height - 10

        if cocoaY < screen.minY + 20 {
            cocoaY = mainHeight - screenRect.minY + 10
        }

        let clampedX = max(screen.minX + 20, min(cocoaX, screen.maxX - frame.width - 20))
        let clampedY = max(screen.minY + 20, min(cocoaY, screen.maxY - frame.height - 20))

        self.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
    }

    private func escapeHtml(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func escapeJs(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: "")
    }

    private func renderSimpleMarkdown(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var html = ""
        var inList = false

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if inList {
                    html += "</ul>\n"
                    inList = false
                }
                html += "<div class='spacer'></div>\n"
                continue
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !inList {
                    html += "<ul>\n"
                    inList = true
                }
                let content = String(line.dropFirst(2))
                html += "<li>\(formatInline(content))</li>\n"
            } else if line.hasPrefix("> ") {
                if inList { html += "</ul>\n"; inList = false }
                let content = String(line.dropFirst(2))
                html += "<blockquote>\(formatInline(content))</blockquote>\n"
            } else if line.hasPrefix("### ") || line.hasPrefix("## ") || line.hasPrefix("# ") {
                if inList { html += "</ul>\n"; inList = false }
                let trimmed = line.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
                html += "<div class='section-title'>\(formatInline(trimmed))</div>\n"
            } else {
                if inList { html += "</ul>\n"; inList = false }
                html += "<p>\(formatInline(line))</p>\n"
            }
        }
        if inList { html += "</ul>\n" }
        return html
    }

    private func formatInline(_ text: String) -> String {
        var res = escapeHtml(text)
        res = res.replacingOccurrences(of: "\\*\\*(.*?)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
        res = res.replacingOccurrences(of: "\\*(.*?)\\*", with: "<em>$1</em>", options: .regularExpression)
        res = res.replacingOccurrences(of: "`(.*?)`", with: "<code>$1</code>", options: .regularExpression)
        return res
    }

    private var cleanCss: String {
        return """
        :root {
            --bg-color: #FFFFFF;
            --border-color: #E2E2E7;
            --text-primary: #1C1C1E;
            --text-secondary: #8E8E93;
            --quote-bg: #F4F4F7;
            --btn-bg: #EAEAEF;
            --btn-hover: #DCDCE2;
            --doubt-bg: rgba(10, 132, 255, 0.08);
            --doubt-border: rgba(10, 132, 255, 0.25);
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg-color: #202022;
                --border-color: #38383A;
                --text-primary: #F5F5F7;
                --text-secondary: #98989D;
                --quote-bg: #2A2A2D;
                --btn-bg: #323236;
                --btn-hover: #3E3E42;
                --doubt-bg: rgba(10, 132, 255, 0.12);
                --doubt-border: rgba(10, 132, 255, 0.35);
            }
        }
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
            user-select: text;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
            background: var(--bg-color);
            color: var(--text-primary);
            overflow: hidden;
            height: 100vh;
        }
        .content-container {
            display: flex;
            flex-direction: column;
            height: 100%;
            padding: 14px 16px 12px 16px;
        }
        .quote-box {
            font-size: 12px;
            font-style: italic;
            color: var(--text-secondary);
            background: var(--quote-bg);
            border-left: 3px solid #0A84FF;
            padding: 8px 12px;
            border-radius: 4px;
            margin-top: 2px;
            margin-bottom: 12px;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
            line-height: 1.35;
            cursor: pointer;
            transition: background 0.15s, border-left-color 0.15s;
        }
        .quote-box:hover {
            background: var(--btn-hover);
            border-left-color: #34C759;
        }
        .context-dot {
            width: 6px;
            height: 6px;
            border-radius: 50%;
            display: inline-block;
            margin-right: 4px;
            vertical-align: middle;
        }
        .context-dot.green {
            background: #34C759;
            box-shadow: 0 0 4px rgba(52, 199, 89, 0.4);
        }
        .context-dot.gray {
            background: #8E8E93;
        }
        .context-drawer {
            margin-bottom: 12px;
            background: var(--quote-bg);
            border: 1px solid var(--border-color);
            border-radius: 6px;
            padding: 8px 10px;
        }
        .context-drawer-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 6px;
        }
        .context-drawer-title {
            font-size: 11px;
            font-weight: 600;
            color: var(--text-secondary);
            display: flex;
            align-items: center;
        }
        .context-copy-btn {
            background: var(--btn-bg);
            border: 1px solid var(--border-color);
            border-radius: 4px;
            font-size: 10px;
            padding: 2px 6px;
            cursor: pointer;
            color: var(--text-primary);
        }
        .context-copy-btn:hover {
            background: var(--btn-hover);
        }
        .context-drawer-body {
            max-height: 120px;
            overflow-y: auto;
            font-size: 11px;
            line-height: 1.45;
            color: var(--text-primary);
            white-space: pre-wrap;
            word-break: break-word;
            padding: 6px 8px;
            background: rgba(0, 0, 0, 0.03);
            border-radius: 4px;
            border: 1px solid rgba(0, 0, 0, 0.05);
        }
        .model-footer-badge {
            display: flex;
            align-items: center;
            gap: 6px;
            margin-top: 12px;
            padding-top: 8px;
            border-top: 1px dashed var(--border-color);
            font-size: 11px;
            color: var(--text-secondary);
        }
        .model-badge-icon {
            font-size: 11px;
        }
        .model-badge-text {
            font-size: 11px;
        }
        .model-badge-text strong {
            color: var(--text-primary);
        }
        .fallback-tag {
            background: rgba(255, 149, 0, 0.15);
            color: #FF9500;
            font-weight: 600;
            font-size: 10px;
            padding: 1px 6px;
            border-radius: 4px;
            margin-left: 4px;
        }
        .explanation-scroll {
            flex: 1;
            overflow-y: auto;
            font-size: 13.5px;
            line-height: 1.55;
            padding-right: 4px;
        }
        .explanation-scroll p {
            margin-bottom: 8px;
        }
        .explanation-scroll ul {
            margin-left: 18px;
            margin-bottom: 8px;
        }
        .explanation-scroll li {
            margin-bottom: 4px;
        }
        .section-title {
            font-size: 11px;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 0.6px;
            color: var(--text-secondary);
            margin-top: 8px;
            margin-bottom: 3px;
        }
        .spacer {
            height: 6px;
        }
        code {
            font-family: Menlo, monospace;
            font-size: 11.5px;
            background: var(--quote-bg);
            padding: 1px 4px;
            border-radius: 3px;
        }
        .doubt-bar {
            display: flex;
            gap: 8px;
            margin-top: 8px;
            padding-top: 8px;
            border-top: 1px solid var(--border-color);
        }
        .doubt-input {
            flex: 1;
            background: var(--quote-bg);
            border: 1px solid var(--border-color);
            color: var(--text-primary);
            font-size: 12.5px;
            padding: 5px 10px;
            border-radius: 6px;
            outline: none;
        }
        .doubt-input:focus {
            border-color: #0A84FF;
        }
        .doubt-item {
            margin-top: 14px;
            padding-top: 10px;
            border-top: 1px dashed var(--border-color);
        }
        .doubt-query-bubble {
            background: var(--doubt-bg);
            border-left: 3px solid #0A84FF;
            padding: 6px 10px;
            border-radius: 4px;
            font-size: 12.5px;
            font-weight: 500;
            margin-bottom: 8px;
        }
        .doubt-reply-box {
            font-size: 13.5px;
            line-height: 1.5;
            padding-left: 4px;
        }
        .doubt-source-tag {
            display: inline-block;
            font-size: 10.5px;
            font-weight: 500;
            color: #0A84FF;
            background: var(--doubt-bg);
            border: 1px solid var(--doubt-border);
            padding: 3px 8px;
            border-radius: 4px;
            margin-top: 8px;
        }
        blockquote {
            border-left: 3px solid #0A84FF;
            padding-left: 10px;
            margin: 8px 0;
            color: var(--text-secondary);
            font-style: italic;
        }
        .bottom-bar {
            margin-top: 8px;
            padding-top: 8px;
            border-top: 1px solid var(--border-color);
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .btn-group {
            display: flex;
            gap: 6px;
        }
        .action-btn {
            background: var(--btn-bg);
            border: 1px solid var(--border-color);
            color: var(--text-primary);
            font-size: 11.5px;
            font-weight: 500;
            padding: 4px 10px;
            border-radius: 6px;
            cursor: pointer;
            transition: background 0.1s;
        }
        .action-btn:hover {
            background: var(--btn-hover);
        }
        .hint-text {
            font-size: 11px;
            color: var(--text-secondary);
        }
        .loading-box {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            flex: 1;
            gap: 12px;
        }
        .spinner {
            width: 22px;
            height: 22px;
            border: 2px solid var(--border-color);
            border-top: 2px solid var(--text-primary);
            border-radius: 50%;
            animation: spin 0.7s linear infinite;
        }
        .spinner-inline {
            display: inline-block;
            width: 12px;
            height: 12px;
            border: 2px solid var(--border-color);
            border-top: 2px solid #0A84FF;
            border-radius: 50%;
            animation: spin 0.7s linear infinite;
            vertical-align: middle;
            margin-right: 4px;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        .status-text {
            font-size: 12.5px;
            color: var(--text-secondary);
            font-weight: 500;
        }
        </style>
        """
    }
}
