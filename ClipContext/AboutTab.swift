import StoreKit
import SwiftUI

private let authorName   = "Lukáš Nagy"
private let contactEmail = "nagy.lukas50@icloud.com"
private let contactURL: URL? = nil

private struct ChangelogEntry {
    let version: String
    let date: String
    let changes: [String]
}

private let changelog: [ChangelogEntry] = [
    ChangelogEntry(version: "1.6", date: "June 2026", changes: [
        "Bug fixes",
        "Added localization",
        "Added right-click popup",
        "Fixed menubar icon right-click on macOS 27.0",
    ]),
    ChangelogEntry(version: "1.5", date: "May 2026", changes: [
        "Improved light mode appearance with better contrast and visible borders",
    ]),
    ChangelogEntry(version: "1.4", date: "May 2026", changes: [
        "Added Launch at Login toggle",
        "Open App shortcut now closes the popover if already open",
    ]),
    ChangelogEntry(version: "1.3", date: "May 2026", changes: [
        "Added translation via Apple's system Translate",
        "Added per-item Remove to the ⋮ menu",
        "Added history limit setting (default 200, up to 2000)",
        "Added global & action keyboard shortcuts",
    ]),
    ChangelogEntry(version: "1.2", date: "May 2026", changes: [
        "Added word & character count per item",
        "Added ⋮ menu with five additional text-editing functions",
        "Added Options menu",
    ]),
    ChangelogEntry(version: "1.1", date: "April 2026", changes: [
        "Clipboard history persistent across launches",
        "Source app and timestamp shown per item",
    ]),
    ChangelogEntry(version: "1.0", date: "March 2026", changes: [
        "Initial release",
    ]),
]

struct AboutTab: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                DonateSection()

                VStack(spacing: 0) {
                // App identity
                VStack(spacing: 8) {
                    if let icon = NSImage(named: NSImage.applicationIconName) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    Text("ClipContext")
                        .font(.title2.bold())
                    Text("Version \(appVersion)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)

                Divider().padding(.horizontal, 16)

                // Changelog
                VStack(alignment: .leading, spacing: 16) {
                    Text("What's New")
                        .font(.headline)
                        .padding(.top, 16)

                    ForEach(changelog, id: \.version) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text("v\(entry.version)")
                                    .font(.subheadline.bold())
                                Text("— \(entry.date)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(entry.changes, id: \.self) { change in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .foregroundStyle(.secondary)
                                    Text(change)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.callout)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().padding(.horizontal, 16).padding(.top, 16)

                // Made by / contact
                VStack(spacing: 8) {
                    Text("Made by \(authorName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Image(systemName: "envelope")
                            .imageScale(.small)
                        if let mailto = URL(string: "mailto:\(contactEmail)") {
                            Link(contactEmail, destination: mailto)
                                .font(.subheadline)
                        }
                    }
                    .foregroundStyle(.secondary)

                    if let url = contactURL {
                        Link("Visit website", destination: url)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 20)
            }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.controlBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                )
            }
            .padding(16)
        }
    }
}

// MARK: - Donate

struct DonateSection: View {
    @StateObject private var store = TipStore.shared
    @State private var showThankYou = false
    @State private var showError = false

    var body: some View {
        VStack(spacing: 10) {
            if store.hasDonated {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                    Text("Thank you for your support!")
                        .font(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.pink.opacity(0.10))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.pink.opacity(0.25), lineWidth: 1))
                )
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "heart")
                    .foregroundStyle(.pink)
                    .frame(width: 20)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Support ClipContext")
                        .font(.subheadline.weight(.semibold))
                    Text("ClipContext is a one-person project. A tip helps keep development going.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if TipStore.isAppStore {
                if store.products.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                } else {
                    HStack(spacing: 8) {
                        ForEach(store.products, id: \.id) { product in
                            Button {
                                Task {
                                    do {
                                        if try await store.purchase(product) {
                                            showThankYou = true
                                        }
                                    } catch {
                                        showError = true
                                    }
                                }
                            } label: {
                                VStack(spacing: 2) {
                                    Text(product.displayPrice)
                                        .font(.subheadline.bold())
                                    Text(product.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                            .disabled(store.isPurchasing)
                        }
                    }
                }
            } else {
                Button {
                    NSWorkspace.shared.open(TipStore.kofiURL)
                    store.markDonatedExternally()
                } label: {
                    Label("Support on Ko-fi", systemImage: "heart")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.pink.opacity(0.20), lineWidth: 1))
        )
        .alert(String(localized: "Thank You!"), isPresented: $showThankYou) {
            Button(String(localized: "You're welcome!")) { }
        } message: {
            Text("Your support means a lot and helps keep ClipContext going.")
        }
        .alert(String(localized: "Purchase Failed"), isPresented: $showError) {
            Button(String(localized: "OK")) { }
        } message: {
            Text("Something went wrong. Please try again.")
        }
    }
}
