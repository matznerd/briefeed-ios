//
//  String+Extensions.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import Foundation
import UIKit

extension String {
    var stripHTML: String {
        guard let data = self.data(using: .utf8) else { return self }
        
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        
        guard let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return self
        }
        
        return attributedString.string
    }
    
    var trimmed: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var isValidURL: Bool {
        guard let url = URL(string: self) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
    
    func truncated(to length: Int, trailing: String = "...") -> String {
        if self.count > length {
            return String(self.prefix(length)) + trailing
        }
        return self
    }
    
    var redditURL: URL? {
        if self.hasPrefix("/r/") || self.hasPrefix("r/") {
            let path = self.hasPrefix("/") ? self : "/\(self)"
            return URL(string: "\(Constants.API.redditBaseURL)\(path).json")
        }
        return nil
    }
}