import SwiftUI

// MARK: - Pairing

struct PairingSheet: View {
    @Environment(AppModel.self) private var model
    @State private var code = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 22) {
            Capsule().fill(.white.opacity(0.15)).frame(width: 40, height: 5).padding(.top, 10)
            switch model.state {
            case .pairing(.enterCode(let length, let error)):
                enterCode(length: length, error: error)
            case .pairing(.verifying):
                waiting(title: "Checking the code…", message: " ")
            case .pairing(.acceptOnTV):
                waiting(title: "Check your TV",
                        message: "Use your regular remote to choose Allow on the TV screen.")
            default:
                waiting(title: "Talking to your TV…", message: " ")
            }
            Spacer(minLength: 0)
            Button("Cancel") { model.cancelPairing() }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .interactiveDismissDisabled()
        #if os(macOS)
        .frame(width: 400, height: 380)
        #endif
    }

    private func enterCode(length: Int, error: String?) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "tv.badge.wifi").font(.system(size: 34, weight: .semibold)).foregroundStyle(Theme.accent)
            Text("Enter the code on your TV").font(.system(size: 22, weight: .bold, design: .rounded))
            ZStack {
                TextField("", text: $code)
                    .focused($fieldFocused)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    .keyboardType(.asciiCapable)
                    #endif
                    .opacity(0.02)
                    .onChange(of: code) { _, new in
                        let cleaned = String(new.uppercased().filter(\.isHexDigit).prefix(length))
                        if cleaned != new { code = cleaned }
                        if cleaned.count == length { model.submitPairingCode(cleaned) }
                    }
                HStack(spacing: 8) {
                    ForEach(0..<length, id: \.self) { i in
                        let chars = Array(code)
                        Text(i < chars.count ? String(chars[i]) : "")
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .frame(width: 44, height: 56)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.well))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(i == chars.count ? Theme.accent : .white.opacity(0.08), lineWidth: i == chars.count ? 2 : 1))
                    }
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { fieldFocused = true }
            if let error {
                Text(error).font(.footnote).foregroundStyle(Theme.power).multilineTextAlignment(.center)
            } else {
                Text("Codes use the numbers 0–9 and the letters A–F.").font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
        .onAppear {
            code = ""
            fieldFocused = true
        }
        .onChange(of: error) { _, _ in code = "" }
    }

    private func waiting(title: String, message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large).padding(.bottom, 6)
            Text(title).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(message).font(.subheadline).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }
}

// MARK: - Keyboard

struct KeyboardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Type on your TV").font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.plain).foregroundStyle(Theme.accent).fontWeight(.semibold)
            }
            HStack(spacing: 10) {
                TextField("Search or type…", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.well))
                KeyCap(repeats: true, enabled: model.supports(.backspace), accessibilityLabel: "Delete on TV") {
                    model.press(.backspace)
                } label: {
                    Image(systemName: "delete.left").font(.system(size: 17, weight: .semibold))
                }
                .frame(width: 52, height: 48)
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(Theme.accent))
                }
                .buttonStyle(PressScaleStyle())
                .disabled(text.isEmpty)
                .accessibilityLabel("Send text")
            }
            Text("Select a search box on your TV first, then type here.")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Theme.background.ignoresSafeArea())
        .onAppear { focused = true }
        #if os(iOS)
        .presentationDetents([.height(210)])
        #else
        .frame(width: 400, height: 180)
        #endif
    }

    /// Sends the whole text at once, then gets out of the way so the TV's search can be navigated.
    private func send() {
        guard !text.isEmpty else { return }
        model.sendText(text)
        dismiss()
    }
}

// MARK: - Apps

struct AppsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    ForEach(model.allApps, id: \.app.id) { entry in
                        AppTile(app: entry.app, style: entry.style) {
                            model.launch(entry.app)
                            dismiss()
                        }
                        .frame(height: 72)
                    }
                }
                .padding(20)
                if model.installedApps == nil {
                    Text("Your TV doesn't share its app list, so these are popular apps. Ones that aren't installed won't open.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 20)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Apps")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await model.refreshApps() }
        }
        #if os(macOS)
        .frame(minWidth: 360, idealWidth: 380, maxWidth: 400, minHeight: 480)
        #endif
    }
}
