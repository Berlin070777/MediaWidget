import SwiftUI

struct PlaybackSourcePicker: View {
    @ObservedObject var monitor: MediaMonitor
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(.primary.opacity(0.07), in: .circle)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回媒体控制")
                Text("选择播放源")
                    .font(.headline)
            }

            PlaybackSourceRow(icon: "sparkle", title: "自动选择", subtitle: "优先跟随正在播放的来源",
                              selected: monitor.preferredSource.isEmpty) { select("") }

            if monitor.allSources.isEmpty {
                Text("暂无可用播放源。打开播放器或 B 站视频后，来源会出现在这里。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                Divider()
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(monitor.allSources) { source in
                            PlaybackSourceRow(icon: source.sourceSymbol, title: source.title,
                                              subtitle: "\(source.sourceName) · \(source.stateLabel)",
                                              selected: monitor.preferredSource == source.sourceID) {
                                select(source.sourceID)
                            }
                        }
                    }
                }
                .frame(maxHeight: 210)
            }
        }
        .onExitCommand { isPresented = false }
    }

    private func select(_ id: String) {
        if monitor.chooseSource(id) { isPresented = false }
    }
}

private struct PlaybackSourceRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(.secondary)
                    .background(.primary.opacity(0.06), in: .rect(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.medium)).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(7)
            .background(.primary.opacity(hovered || selected ? 0.08 : 0), in: .rect(cornerRadius: 9))
            .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("\(title)，\(subtitle)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
