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

            VStack(alignment: .leading, spacing: 10) {
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
