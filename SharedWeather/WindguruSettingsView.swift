import SwiftUI

struct WindguruSettingsView: View {
    @ObservedObject private var store = WindguruCredentialsStore.shared
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var savedAt: Date?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Windguru PRO credentials")
                .font(.headline)
            Text("Required to fetch the AROME-HU forecast for the custom spot \"Palóznaki Öböl\". The standard \"Zagykazetta\" spot works without an account.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Username")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("windguru username", text: $username)
                    #if os(iOS) || os(tvOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    #endif
                    #if !os(tvOS)
                    .textFieldStyle(.roundedBorder)
                    #endif

                Text("Password")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("password", text: $password)
                    #if !os(tvOS)
                    .textFieldStyle(.roundedBorder)
                    #endif
            }

            HStack {
                Button("Save") {
                    store.save(username: username, password: password)
                    savedAt = Date()
                    #if os(tvOS) || os(iOS)
                    dismiss()
                    #endif
                }
                #if !os(tvOS)
                .keyboardShortcut(.defaultAction)
                #endif
                .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("Clear") {
                    store.clear()
                    username = ""
                    password = ""
                    savedAt = nil
                }
                .disabled(store.username.isEmpty && !store.hasPassword)

                Spacer()

                if let savedAt {
                    Text("Saved \(savedAt, style: .time)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if store.hasPassword {
                    Label("Stored", systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Not set", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 380)
        .onAppear {
            username = store.username
            password = ""
        }
    }
}
