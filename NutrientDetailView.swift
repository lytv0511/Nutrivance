ScrollView {
                            VStack {
                                GeometryReader { geometry in
                                    if geometry.size.width >= 1200 {
                                        cardWidth = UIScreen.main.bounds.width / 3.5
                                    } else if geometry.size.width >= 900 {
                                        cardWidth = UIScreen.main.bounds.width / 2.5
                                    } else if geometry.size.width >= 700 {
                                        cardWidth = UIScreen.main.bounds.width * 0.8
                                    } else {
                                        cardWidth = UIScreen.main.bounds.width * 0.6
                                    }
                                    
                                    let columns = if geometry.size.width >= 1200 {
                                        3
                                    } else if geometry.size.width >= 900 {
                                        2
                                    } else {
                                        1
                                    }
                                    
                                    LazyVGrid(
                                        columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: 16), count: columns),
                                        spacing: 16
                                    ) {
                                        ForEach([CardType.today, .weekly, .monthly, .recommended, .foods, .benefits], id: \.self) { cardType in
                                            NutrientCard(
                                                type: cardType,
                                                nutrientName: nutrientName,
                                                selectedDate: $selectedDate,
                                                isSelected: selectedCard == cardType,
                                                healthStore: healthStore,
                                                titleColor: getNutrientColor(),
                                                symbolName: getSymbolName(for: cardType),
                                                cardWidth: $cardWidth
                                            )
                                            .onTapGesture {
                                                withAnimation(.spring()) {
                                                    selectedCard = cardType
                                                }
                                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                                generator.impactOccurred()
                                            }
                                        }
