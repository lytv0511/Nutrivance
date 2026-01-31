//
//  ResizableWidgetView.swift
//  Nutrivance
//
//  Created by Vincent Leong on 2/23/25.
//

import Foundation
import SwiftUI

struct ResizableWidgetView: View {
    @Binding var widget: ResizableWidget
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        widget.view
            .frame(width: widget.size.width, height: widget.size.height)
            .position(widget.position)
            .onTapGesture(perform: onSelect)
    }
}
