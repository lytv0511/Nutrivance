//
//  WaterWidgetLiveActivity.swift
//  WaterWidget
//
//  Created by Vincent Leong on 11/7/24.
//

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)  // Ensure it only compiles for iOS with ActivityKit support
import ActivityKit
import WidgetKit
import SwiftUI

struct WaterWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct WaterWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WaterWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("mL")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension WaterWidgetAttributes {
    fileprivate static var preview: WaterWidgetAttributes {
        WaterWidgetAttributes(name: "World")
    }
}

extension WaterWidgetAttributes.ContentState {
    fileprivate static var smiley: WaterWidgetAttributes.ContentState {
        WaterWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: WaterWidgetAttributes.ContentState {
         WaterWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: WaterWidgetAttributes.preview) {
   WaterWidgetLiveActivity()
} contentStates: {
    WaterWidgetAttributes.ContentState.smiley
    WaterWidgetAttributes.ContentState.starEyes
}

#endif
