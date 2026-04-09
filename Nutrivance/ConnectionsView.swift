//
//  ConnectionsView.swift
//  Nutrivance
//
//  Created by Vincent Leong on 2/23/25.
//

import Foundation
import SwiftUI

struct ConnectionsView: View {
    let connections: [Connection]
    
    var body: some View {
        Canvas { context, size in
            for connection in connections {
                let path = Path { p in
                    p.move(to: connection.sourcePoint)
                    p.addLine(to: connection.targetPoint)
                }
                context.stroke(path, with: .color(.blue), lineWidth: 2)
            }
        }
    }
}
