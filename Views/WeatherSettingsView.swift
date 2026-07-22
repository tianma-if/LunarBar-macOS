import SwiftUI
import AppKit

struct WeatherSettingsView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage(WeatherDefaults.cityCodeKey) private var cityCode = "101010100"
    @AppStorage(WeatherDefaults.cityNameKey) private var cityName = "北京"
    @State private var updateState: UpdateState = .idle

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

                Text("启动时自动获取当前位置，用于查询当地天气。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("重新获取当前位置") {
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

            VStack(alignment: .leading, spacing: 8) {
                Text("应用更新")
                    .font(.headline)

                LabeledContent("当前版本") {
                    Text(UpdateChecker.currentVersion)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("检查更新") {
                        checkForUpdates()
                    }
                    .disabled(updateState == .checking)

                    updateStatusView
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
        switch updateState {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .latest:
            Text("已是最新版本")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .available(let result):
            Button("下载 v\(result.latestVersion)") {
                openURL(result.releaseURL)
            }
            .buttonStyle(.link)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func checkForUpdates() {
        updateState = .checking

        Task {
            do {
                let result = try await UpdateChecker().checkForUpdates()
                if UpdateChecker.isNewer(result.latestVersion, than: UpdateChecker.currentVersion) {
                    updateState = .available(result)
                } else {
                    updateState = .latest
                }
            } catch {
                updateState = .failed((error as? LocalizedError)?.errorDescription ?? "检查更新失败")
            }
        }
    }
}

private enum UpdateState: Equatable {
    case idle
    case checking
    case latest
    case available(UpdateCheckResult)
    case failed(String)
}

struct WeatherSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        WeatherSettingsView(viewModel: WeatherViewModel())
    }
}
