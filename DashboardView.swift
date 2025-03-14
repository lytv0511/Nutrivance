VStack {
    ringStack
    Text(ring.name)
        .font(.headline)
        .foregroundColor(.primary)
    metricsStack
}
.frame(width: UIDevice.current.userInterfaceIdiom == .phone ? 300 : 350, 
       height: UIDevice.current.userInterfaceIdiom == .phone ? 300 : 350)
.padding(20)
.background(.ultraThinMaterial)
.cornerRadius(15)
