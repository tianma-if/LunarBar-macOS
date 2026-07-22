import SwiftUI

struct MainPopupView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @ObservedObject var weatherViewModel: WeatherViewModel
    @Environment(\.openWindow) private var openWindow

    init(viewModel: CalendarViewModel, weatherViewModel: WeatherViewModel) {
        self.viewModel = viewModel
        self.weatherViewModel = weatherViewModel
    }

    var body: some View {
        VStack(spacing: 16) {
            WeatherHeaderView(viewModel: weatherViewModel) {
                openWindow(id: "settings")
            }

            CalendarGridView(viewModel: viewModel)
        }
        .padding(18)
    }
}

struct MainPopupView_Previews: PreviewProvider {
    static var previews: some View {
        MainPopupView(viewModel: CalendarViewModel(), weatherViewModel: WeatherViewModel())
            .frame(width: 360, height: 520)
    }
}
