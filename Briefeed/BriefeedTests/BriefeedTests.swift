//
//  BriefeedTests.swift
//  BriefeedTests
//
//  Created by Eric M on 6/21/25.
//

import Foundation
import Testing
@testable import Briefeed

struct BriefeedTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func firecrawlV2ScrapeResponseDecodesWithoutContentField() throws {
        let json = """
        {
          "success": true,
          "data": {
            "markdown": "# Example Domain",
            "html": "<h1>Example Domain</h1>",
            "metadata": {
              "title": "Example Domain"
            }
          }
        }
        """

        let response = try JSONDecoder().decode(FirecrawlResponse.self, from: Data(json.utf8))

        #expect(response.success)
        #expect(response.data?.content == "")
        #expect(response.data?.bestContent == "# Example Domain")
        #expect(response.data?.metadata?.title == "Example Domain")
    }

}
