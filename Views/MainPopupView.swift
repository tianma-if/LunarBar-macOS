import SwiftUI

struct MainPopupView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @StateObject private var weatherViewModel = WeatherViewModel()
    @State private var showingWeatherSettings = false

    var body: some View {
        VStack(spacing: 16) {
            WeatherHeaderView(viewModel: weatherViewModel) {
                showingWeatherSettings = true
            }

            CalendarGridView(viewModel: viewModel)
        }
        .padding(18)
        .sheet(isPresented: $showingWeatherSettings) {
            WeatherSettingsView(viewModel: weatherViewModel)
        }
    }
}

struct MainPopupView_Previews: PreviewProvider {
    static var previews: some View {
        MainPopupView(viewModel: CalendarViewModel())
            .frame(width: 360, height: 520)
    }
}
