//
//  NotificationsOverlay.swift
//  Spectra
//
//  Toast overlay rendering AppEnvironment.notifications as floating glass cards
//  in the top-trailing corner.
//

import SwiftUI

struct NotificationsOverlay: View {
    @Environment(\.appEnv) private var env

    var body: some View {
        VStack(alignment: .trailing, spacing: Tokens.Spacing.sm) {
            ForEach(env.notifications.items) { item in
                NotificationToast(item: item) {
                    env.notifications.dismiss(item.id)
                }
            }
        }
        .padding(Tokens.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(!env.notifications.items.isEmpty)
        .animation(.snappy, value: env.notifications.items.count)
    }
}

private struct NotificationToast: View {
    let item: NotificationCenterModel.Item
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.sm) {
            Image(systemName: item.level.systemImage)
                .foregroundStyle(item.level.status.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.callout.weight(.medium))
                if let message = item.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark").font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(Tokens.Spacing.md)
        .frame(maxWidth: 320, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: Tokens.Radius.md))
    }
}
