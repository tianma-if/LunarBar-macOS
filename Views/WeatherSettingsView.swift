import SwiftUI

struct WeatherSettingsView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage(WeatherDefaults.cityCodeKey) private var cityCode = "101010100"
    @AppStorage(WeatherDefaults.cityNameKey) private var cityName = "北京"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("天气")
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

            HStack {
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
}

struct WeatherSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        WeatherSettingsView(viewModel: WeatherViewModel())
    }
}
