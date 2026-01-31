import SwiftUI

struct SearchView_iPhone: View {
    @State private var selectedView: AppView = .all
    @EnvironmentObject var navigationState: NavigationState
    
    enum AppView {
        case all
        case nutrition
        case fitness
        case mentalHealth
        
        var icon: String {
            switch self {
            case .all:
                return "square.grid.2x2"
            case .nutrition:
                return "leaf.fill"
            case .fitness:
                return "figure.run"
            case .mentalHealth:
                return "brain.head.profile"
            }
        }
        
        var title: String {
            switch self {
            case .all:
                return "All"
            case .nutrition:
                return "Nutrition"
            case .fitness:
                return "Fitness"
            case .mentalHealth:
                return "Mental Health"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                switch selectedView {
                case .all:
                    SearchView()
                case .nutrition:
                    NutrivanceView()
                case .fitness:
                    MovanceView()
                case .mentalHealth:
                    SpirivanceView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("View", selection: $selectedView) {
                            ForEach([AppView.all, .nutrition, .fitness, .mentalHealth], id: \.self) { view in
                                Label(view.title, systemImage: view.icon)
                                    .tag(view)
                            }
                        }
                    } label: {
                        Image(systemName: selectedView.icon)
                    }
                }
            }
        }
    }
}

#Preview {
    SearchView_iPhone()
        .environmentObject(NavigationState())
        .environmentObject(SearchState())
}
