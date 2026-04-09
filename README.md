# Nutrivance v0.2

A nutrition and wellness advancement platform designed to help users achieve their health goals through personalized guidance and tracking.

## Development log
- SleepView is in development, showing sleep stages when paired with an Apple Watch compatible with sleep tracking. The app shows major and minor sleep stages and provides analysis based on the duration occurance of said sleep stage while taking into account the average respiratory rate and average heart rate. A condensed views provides quick metrics at a glance while a detailed view showcases all sleep stages. A comprehensive textual summary is provided below. Sleep hours are still under development and might not provide the most accurate metrics at this stage. Weekly, monthly, and yearly filters are still under development.

## Features

- Personalized nutrition tracking
- Wellness goal setting
- Progress monitoring
- Dietary recommendations
- Health metrics dashboard
- (NEW) Sleep metrics (beta)

## Getting Started

### Prerequisites

- Xcode 26+
- iOS or iPadOS 26+ device or simulator
- macOS 26 Tahoe or later for development
- Apple Developer Account (for deployment)

### Installation

1. Clone the repository
```bash
git clone https://github.com/lytv0511/nutrivance.git
```
2. Install dependencies
```bash
cd nutrivance && npm install
```
3. Build and run the application on your iOS device or simulator

## Usage

1. Launch the app on your iOS or iPadOS device
2. Select a nutrient category from the interactive grid
3. Use the wheel picker for precise nutrient selection
4. Long press the scanner button to analyze nutrition labels
5. View detailed nutrient information

## Tech Stack

- Frontend: SwiftUI, UIKit
- Backend: Swift, Objective-C, Objective-C++, Metal
- Frameworks: HealthKit
- Camera: VisionKit
- Platform: iOS 26+ or iPadOS 26+

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contact

Project Lead - [@lytv0511](https://twitter.com/lytv0511)
Project Link: [https://github.com/lytv0511/nutrivance](https://github.com/lytv0511/nutrivance)

## Acknowledgments

- Thanks to all contributors
- Inspired by modern wellness practices
- Built with love for the health-conscious community

## Version History

- 0.1
  - Initial Release
  - Interactive nutrient selection interface
  - Nutrition label scanning capability
- 0.2
    - SleepView enhancements and DashboardView bug fixes
