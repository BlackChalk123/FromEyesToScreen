import SwiftUI

struct BilibiliLinkSheet: View {
    @ObservedObject var model: AppModel
    @FocusState private var inputFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "play.rectangle.on.rectangle").font(.system(size: 25, weight: .light)).foregroundStyle(Theme.mint)
                VStack(alignment: .leading, spacing: 5) {
                    Text("打开哔哩哔哩视频").font(.system(size: 20, weight: .medium))
                    Text("粘贴链接，继续随视观看。").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                TextField("视频链接 / BV 号 / 分享短链接", text: $model.bilibiliInput)
                    .textFieldStyle(.roundedBorder).font(.system(size: 12)).controlSize(.large)
                    .focused($inputFocused).disabled(model.resolvingBilibili)
                    .onSubmit { if !model.resolvingBilibili { model.openBilibili() } }
                    .accessibilityIdentifier("bilibiliLinkInput")
                Text("支持 bilibili.com/video/…、b23.tv 分享链接，以及分 P 视频。")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
            if let error = model.bilibiliError {
                Label(error, systemImage: "exclamationmark.circle").font(.system(size: 11))
                    .foregroundStyle(Color.orange.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "info.circle")
                Text("使用 B 站官方网页播放器。清晰度、登录和可观看内容由 B 站决定；播放、音量和弹幕在画面内操作。")
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(4)
            }.font(.system(size: 11)).foregroundStyle(Theme.secondary)
                .padding(13).background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
            HStack {
                if model.resolvingBilibili {
                    ProgressView().controlSize(.small)
                    Text("正在解析分享链接…").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button("取消") {
                    model.cancelBilibiliResolution()
                    model.showingBilibiliSheet = false
                }.keyboardShortcut(.cancelAction)
                Button("打开视频", action: model.openBilibili)
                    .buttonStyle(.borderedProminent).foregroundStyle(Theme.background)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.bilibiliInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.resolvingBilibili)
                    .accessibilityIdentifier("openBilibiliVideo")
            }
        }.padding(28).frame(width: 520).background(Theme.sidebar)
            .preferredColorScheme(.dark).tint(Theme.mint)
            .onAppear { inputFocused = true; model.bilibiliError = nil }
            .onDisappear { model.cancelBilibiliResolution() }
    }
}
