////
////  DragAndDrop_Mac.swift
////  Nutrivance
////
////  Created by Vincent Leong on 11/22/24.
////
//
//import Foundation
//import SwiftUI
//import UniformTypeIdentifiers
//
//struct NutrientDragAndDrop: View {
//    let nutrient: String
//    let value: Double
//    
//    var body: some View {
//        HStack {
//            Image(systemName: getNutrientIcon(for: nutrient))
//            Text(nutrient)
//            Spacer()
//            Text("\(value, specifier: "%.1f") \(getUnit(for: nutrient))")
//        }
//        .padding()
//        .draggable(NutrientItem(name: nutrient, value: value))
//        .dropDestination(for: NutrientItem.self) { items, location in
//            // Handle dropped nutrients
//            return true
//        }
//    }
//}
//
//struct NutrientItem: Transferable {
//    let name: String
//    let value: Double
//    
//    static var transferRepresentation: some TransferRepresentation {
//        CodableRepresentation(contentType: .nutrientData)
//    }
//}
