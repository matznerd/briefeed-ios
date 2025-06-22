//
//  ArticleReaderView.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import SwiftUI
import WebKit

struct ArticleReaderView: UIViewRepresentable {
    let content: String?
    let url: String?
    let fontSize: CGFloat
    let isReaderMode: Bool
    
    init(content: String, fontSize: CGFloat, isReaderMode: Bool) {
        self.content = content
        self.url = nil
        self.fontSize = fontSize
        self.isReaderMode = isReaderMode
    }
    
    init(url: String, fontSize: CGFloat, isReaderMode: Bool) {
        self.content = nil
        self.url = url
        self.fontSize = fontSize
        self.isReaderMode = isReaderMode
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptEnabled = true
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.showsVerticalScrollIndicator = true
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        if let content = content {
            loadHTMLContent(webView, content: content)
        } else if let urlString = url, let webURL = URL(string: urlString) {
            if isReaderMode {
                // Attempt to load in reader mode
                loadReaderMode(webView, url: webURL)
            } else {
                let request = URLRequest(url: webURL)
                webView.load(request)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func loadHTMLContent(_ webView: WKWebView, content: String) {
        // Check if content is already HTML or needs to be converted from markdown
        let isHTML = content.contains("<") && content.contains(">")
        let processedContent: String
        
        if isHTML {
            processedContent = content
        } else {
            // Convert markdown to HTML (basic conversion)
            processedContent = convertMarkdownToHTML(content)
        }
        
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes">
            <style>
                :root {
                    color-scheme: light dark;
                }
                
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                    font-size: \(fontSize)px;
                    line-height: 1.6;
                    color: \(colorScheme == .dark ? "#FFFFFF" : "#000000");
                    background-color: \(colorScheme == .dark ? "#000000" : "#FFFFFF");
                    padding: 16px;
                    margin: 0;
                    word-wrap: break-word;
                    -webkit-text-size-adjust: 100%;
                }
                
                p {
                    margin: 1em 0;
                }
                
                img {
                    max-width: 100%;
                    height: auto;
                    display: block;
                    margin: 1em auto;
                    border-radius: 8px;
                }
                
                a {
                    color: \(colorScheme == .dark ? "#FF6B6B" : "#FF0000");
                    text-decoration: none;
                }
                
                a:hover {
                    text-decoration: underline;
                }
                
                pre {
                    background-color: \(colorScheme == .dark ? "#1C1C1E" : "#F2F2F7");
                    padding: 12px;
                    border-radius: 8px;
                    overflow-x: auto;
                    white-space: pre-wrap;
                }
                
                code {
                    background-color: \(colorScheme == .dark ? "#1C1C1E" : "#F2F2F7");
                    padding: 2px 4px;
                    border-radius: 4px;
                    font-family: 'SF Mono', Consolas, 'Liberation Mono', Menlo, monospace;
                    font-size: 0.9em;
                }
                
                blockquote {
                    border-left: 4px solid \(colorScheme == .dark ? "#FF6B6B" : "#FF0000");
                    padding-left: 16px;
                    margin-left: 0;
                    color: \(colorScheme == .dark ? "#C7C7CC" : "#3C3C43");
                }
                
                h1, h2, h3, h4, h5, h6 {
                    margin-top: 1.5em;
                    margin-bottom: 0.5em;
                    font-weight: 600;
                }
                
                hr {
                    border: none;
                    border-top: 1px solid \(colorScheme == .dark ? "#38383A" : "#C6C6C8");
                    margin: 2em 0;
                }
                
                ul, ol {
                    padding-left: 20px;
                }
                
                li {
                    margin: 0.5em 0;
                }
                
                /* Table styles */
                table {
                    border-collapse: collapse;
                    width: 100%;
                    margin: 1em 0;
                }
                
                th, td {
                    border: 1px solid \(colorScheme == .dark ? "#38383A" : "#C6C6C8");
                    padding: 8px;
                    text-align: left;
                }
                
                th {
                    background-color: \(colorScheme == .dark ? "#1C1C1E" : "#F2F2F7");
                    font-weight: 600;
                }
                
                /* Reader mode specific styles */
                \(isReaderMode ? """
                body {
                    max-width: 700px;
                    margin: 0 auto;
                    padding: 20px;
                }
                """ : "")
            </style>
        </head>
        <body>
            \(processedContent)
        </body>
        </html>
        """
        
        webView.loadHTMLString(html, baseURL: nil)
    }
    
    private func convertMarkdownToHTML(_ markdown: String) -> String {
        var html = markdown
        
        // Convert headers
        html = html.replacingOccurrences(of: #"(?m)^# (.+)$"#, with: "<h1>$1</h1>", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?m)^## (.+)$"#, with: "<h2>$1</h2>", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?m)^### (.+)$"#, with: "<h3>$1</h3>", options: .regularExpression)
        
        // Convert bold and italic
        html = html.replacingOccurrences(of: #"\*\*\*(.+?)\*\*\*"#, with: "<strong><em>$1</em></strong>", options: .regularExpression)
        html = html.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        html = html.replacingOccurrences(of: #"\*(.+?)\*"#, with: "<em>$1</em>", options: .regularExpression)
        
        // Convert links
        html = html.replacingOccurrences(of: #"\[(.+?)\]\((.+?)\)"#, with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        
        // Convert line breaks to paragraphs
        let paragraphs = html.components(separatedBy: "\n\n")
        html = paragraphs.map { "<p>\($0)</p>" }.joined(separator: "\n")
        
        return html
    }
    
    private func loadReaderMode(_ webView: WKWebView, url: URL) {
        // For reader mode, we'll inject JavaScript to simplify the page
        let readerJS = """
        (function() {
            // Remove ads, sidebars, and other distracting elements
            const elementsToRemove = [
                'aside', 'nav', 'header', 'footer',
                '.sidebar', '.advertisement', '.ad',
                '.social-share', '.comments', '.related'
            ];
            
            elementsToRemove.forEach(selector => {
                document.querySelectorAll(selector).forEach(el => el.remove());
            });
            
            // Find the main content
            const article = document.querySelector('article, main, [role="main"], .content, #content');
            if (article) {
                document.body.innerHTML = '';
                document.body.appendChild(article);
            }
            
            // Apply reader styles
            document.body.style.maxWidth = '700px';
            document.body.style.margin = '0 auto';
            document.body.style.padding = '20px';
            document.body.style.fontFamily = '-apple-system, BlinkMacSystemFont, sans-serif';
            document.body.style.fontSize = '\(fontSize)px';
            document.body.style.lineHeight = '1.6';
        })();
        """
        
        let request = URLRequest(url: url)
        webView.load(request)
        
        // Inject the JavaScript after the page loads
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            webView.evaluateJavaScript(readerJS)
        }
    }
    
    @Environment(\.colorScheme) private var colorScheme
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: ArticleReaderView
        
        init(_ parent: ArticleReaderView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                // Allow initial load and about:blank
                if navigationAction.navigationType == .other || url.scheme == "about" {
                    decisionHandler(.allow)
                    return
                }
                
                // Open external links in Safari
                if navigationAction.navigationType == .linkActivated {
                    UIApplication.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
            }
            
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Apply font size adjustment
            let fontJS = """
            document.body.style.fontSize = '\(parent.fontSize)px';
            """
            webView.evaluateJavaScript(fontJS)
            
            // If reader mode is enabled and we're loading a URL, apply reader mode
            if parent.isReaderMode && parent.url != nil {
                let readerJS = """
                (function() {
                    // Remove ads, sidebars, and other distracting elements
                    const elementsToRemove = [
                        'aside', 'nav', 'header', 'footer',
                        '.sidebar', '.advertisement', '.ad',
                        '.social-share', '.comments', '.related'
                    ];
                    
                    elementsToRemove.forEach(selector => {
                        document.querySelectorAll(selector).forEach(el => el.remove());
                    });
                    
                    // Find the main content
                    const article = document.querySelector('article, main, [role="main"], .content, #content');
                    if (article) {
                        document.body.innerHTML = '';
                        document.body.appendChild(article);
                    }
                    
                    // Apply reader styles
                    document.body.style.maxWidth = '700px';
                    document.body.style.margin = '0 auto';
                    document.body.style.padding = '20px';
                    document.body.style.fontFamily = '-apple-system, BlinkMacSystemFont, sans-serif';
                    document.body.style.lineHeight = '1.6';
                })();
                """
                webView.evaluateJavaScript(readerJS)
            }
        }
    }
}

#Preview {
    ArticleReaderView(
        content: """
        <h1>SwiftUI Article Reader</h1>
        <p>This is a sample article content with <strong>bold text</strong> and <em>italic text</em>.</p>
        <p>Here's a code example:</p>
        <pre><code>struct ContentView: View {
            var body: some View {
                Text("Hello, World!")
            }
        }</code></pre>
        <blockquote>This is a quoted text that should be styled differently.</blockquote>
        <p>And here's a list:</p>
        <ul>
            <li>First item</li>
            <li>Second item</li>
            <li>Third item</li>
        </ul>
        """,
        fontSize: 16,
        isReaderMode: true
    )
}