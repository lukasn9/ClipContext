import SwiftUI

struct CustomizationTab: View {
    @EnvironmentObject var settings: SettingsStore

    private var pinnedActions: [ClipAction] {
        settings.pinnedActionIDs.compactMap { allActions.action(id: $0) }
    }
    private var moreActions: [ClipAction] {
        settings.moreActionIDs.compactMap { allActions.action(id: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionView(
                    title: "Pinned",
                    subtitle: "Shown as icon buttons on each item (max 4)",
                    ids: $settings.pinnedActionIDs,
                    actions: pinnedActions,
                    isPinned: true
                )
                sectionView(
                    title: "More Options",
                    subtitle: "Shown in the ⋮ menu",
                    ids: $settings.moreActionIDs,
                    actions: moreActions,
                    isPinned: false
                )
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func sectionView(
        title: String,
        subtitle: String,
        ids: Binding<[String]>,
        actions: [ClipAction],
        isPinned: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    if isPinned {
                        Text("\(pinnedActions.count)/4")
                            .font(.caption)
                            .foregroundStyle(pinnedActions.count >= 4 ? .red : .secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }

            // Styled card containing a List for onMove support
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.regularMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.2), lineWidth: 1))

                if actions.isEmpty {
                    Text("Drag items here")
                        .font(.callout).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    List {
                        ForEach(actions) { action in
                            ActionDragRow(
                                action: action,
                                isPinned: isPinned,
                                onMoveToOther: { moveToOther(actionID: action.id, fromPinned: isPinned) }
                            )
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                        }
                        .onMove { indices, newOffset in
                            ids.wrappedValue.move(fromOffsets: indices, toOffset: newOffset)
                        }
                    }
                    .listStyle(.plain)
                    .scrollDisabled(true)
                    .frame(height: CGFloat(actions.count) * 44)
                }
            }
            // Drop target for cross-section drags
            .dropDestination(for: String.self) { droppedIDs, _ in
                guard let id = droppedIDs.first else { return false }
                let fromPinned = settings.pinnedActionIDs.contains(id)
                guard fromPinned != isPinned else { return false } // same section — no-op
                moveToOther(actionID: id, fromPinned: fromPinned)
                return true
            } isTargeted: { _ in }
        }
    }

    private func moveToOther(actionID: String, fromPinned: Bool) {
        if fromPinned {
            settings.pinnedActionIDs.removeAll { $0 == actionID }
            settings.moreActionIDs.append(actionID)
        } else {
            guard settings.pinnedActionIDs.count < 4 else { return }
            settings.moreActionIDs.removeAll { $0 == actionID }
            settings.pinnedActionIDs.append(actionID)
        }
    }
}

struct ActionDragRow: View {
    let action: ClipAction
    let isPinned: Bool
    let onMoveToOther: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.systemImage)
                .frame(width: 20)
                .foregroundStyle(.secondary)

            Text(action.label)
                .foregroundStyle(.primary)

            Spacer()

            Button(action: onMoveToOther) {
                Text(isPinned ? "Move to More" : "Pin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(height: 44)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .draggable(action.id)
    }
}
