import SwiftUI
import AppKit

struct WeatherSettingsView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @EnvironmentObject private var updateManager: AutoUpdateManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage(WeatherDefaults.cityCodeKey) private var cityCode = "101010100"
    @AppStorage(WeatherDefaults.cityNameKey) private var cityName = "北京"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("设置")
                    .font(.system(size: 18, weight: .semibold))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }

            Text("天气")
                .font(.headline)

            LabeledContent("天气服务") {
                Text("LunarBar Weather")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("位置")
                    .font(.subheadline.weight(.medium))

                Text(viewModel.locationMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(viewModel.locationMessage.contains("关闭") ? "打开定位设置" : "重新获取当前位置") {
                    viewModel.requestCurrentLocation()
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("无法获取位置时使用以下城市")
                    .font(.subheadline.weight(.medium))

                LabeledContent("城市编码") {
                    TextField("101010100", text: $cityCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 210)
                }

                LabeledContent("城市名称") {
                    TextField("北京", text: $cityName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 210)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("应用更新")
                    .font(.headline)

                Toggle("自动检查并下载新版本", isOn: $updateManager.automaticallyCheckForUpdates)
                    .font(.subheadline)

                LabeledContent("当前版本") {
                    Text(UpdateChecker.currentVersion)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button("检查更新") {
                        updateManager.checkForUpdates(manual: true)
                    }
                    .disabled(updateManager.status == .checking || updateManager.status == .installing)

                    updateStatusView
                }

                if let version = updateManager.readyVersion {
                    HStack {
                        Text("新版本 v\(version) 已就绪")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("立即重启更新") {
                            updateManager.applyUpdateAndRestart()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }

            Divider()

            HStack {
                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出 LunarBar", systemImage: "power")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("退出 LunarBar")

                Spacer()

                Button("保存") {
                    viewModel.reloadSettings()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateManager.status {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("正在检查…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .latest:
            Text("已是最新版本")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .downloading(let progress, let version):
            HStack(spacing: 6) {
                ProgressView(value: progress > 0 ? progress : nil)
                    .controlSize(.small)
                    .frame(width: 40)
                Text("正在下载 v\(version)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .readyToRestart:
            EmptyView()
        case .installing:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("正在重启更新…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}

struct WeatherSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        WeatherSettingsView(viewModel: WeatherViewModel())
    }
}
