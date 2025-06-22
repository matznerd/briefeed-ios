//
//  Array+Extensions.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/22/25.
//

import Foundation

extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}