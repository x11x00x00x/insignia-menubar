//
//  LoginWindowController.swift
//  Insignia Menubar
//
//  Simple login window for Insignia Stats (email + password).
//

import AppKit

protocol LoginWindowControllerDelegate: AnyObject {
    func loginDidSucceed(username: String)
    func loginDidCancel()
}

final class LoginWindowController: NSWindowController {
    weak var delegate: LoginWindowControllerDelegate?

    private let emailField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let loginButton = NSButton(title: "Login", target: nil, action: nil)

    override var windowNibName: NSNib.Name? { nil }

    override func loadWindow() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Login to Insignia (xb.live)"
        window.isReleasedWhenClosed = false
        window.becomesKeyOnlyIfNeeded = false
        window.hidesOnDeactivate = false
        window.level = .floating
        window.delegate = self
        window.center()
        self.window = window

        let contentView = window.contentView!
        let stack = NSStackView(views: [])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        let emailLabel = NSTextField(labelWithString: "Email")
        emailLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        emailField.placeholderString = "your@email.com"
        emailField.font = .systemFont(ofSize: NSFont.systemFontSize)
        emailField.translatesAutoresizingMaskIntoConstraints = false
        emailField.widthAnchor.constraint(equalToConstant: 260).isActive = true

        let passwordLabel = NSTextField(labelWithString: "Password")
        passwordLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        passwordField.placeholderString = "••••••••"
        passwordField.font = .systemFont(ofSize: NSFont.systemFontSize)
        passwordField.translatesAutoresizingMaskIntoConstraints = false
        passwordField.widthAnchor.constraint(equalToConstant: 260).isActive = true

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .systemRed
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping

        loginButton.bezelStyle = .rounded
        loginButton.target = self
        loginButton.action = #selector(loginTapped)

        let emailStack = NSStackView(views: [emailLabel, emailField])
        emailStack.orientation = .vertical
        emailStack.alignment = .leading
        let passStack = NSStackView(views: [passwordLabel, passwordField])
        passStack.orientation = .vertical
        passStack.alignment = .leading

        stack.addArrangedSubview(emailStack)
        stack.addArrangedSubview(passStack)
        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(loginButton)

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20)
        ])
    }

    @objc private func loginTapped() {
        let email = emailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.stringValue
        guard !email.isEmpty, !password.isEmpty else {
            statusLabel.stringValue = "Please enter email and password."
            statusLabel.textColor = .systemRed
            return
        }
        statusLabel.stringValue = "Signing in, this can take up to 1 minute to complete."
        statusLabel.textColor = .labelColor
        loginButton.isEnabled = false

        InsigniaAuthService.login(email: email, password: password) { [weak self] result in
            DispatchQueue.main.async {
                self?.loginButton.isEnabled = true
                switch result {
                case .success(let (sessionKey, username)):
                    KeychainHelper.saveSession(sessionKey: sessionKey, username: username)
                    self?.delegate?.loginDidSucceed(username: username)
                    self?.window?.close()
                case .failure(let error):
                    self?.statusLabel.stringValue = error.localizedDescription
                    self?.statusLabel.textColor = .systemRed
                }
            }
        }
    }

    override func showWindow(_ sender: Any?) {
        loadWindow()
        super.showWindow(sender)
        guard let window = window else { return }
        window.center()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
        emailField.stringValue = ""
        passwordField.stringValue = ""
        statusLabel.stringValue = ""
        statusLabel.textColor = .labelColor
    }
}

extension LoginWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if KeychainHelper.getSessionKey() == nil {
            delegate?.loginDidCancel()
        }
        NotificationCenter.default.post(name: AppDelegate.windowDidCloseNotification, object: nil)
    }
}
