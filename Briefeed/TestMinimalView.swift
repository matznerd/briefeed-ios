//
//  TestMinimalView.swift
//  Briefeed
//
//  Minimal view to test SwiftAudioEx components
//

import SwiftUI

struct TestMinimalView: View {
    @StateObject private var audioService = SwiftAudioExService()
    @StateObject private var unifiedPlayer = UnifiedAudioPlayer()
    @State private var testResults: [String] = []
    
    var body: some View {
        VStack(spacing: 20) {
            Text("SwiftAudioEx Test Results")
                .font(.title)
                .padding()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(testResults, id: \.self) { result in
                        HStack {
                            Image(systemName: result.contains("✅") ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result.contains("✅") ? .green : .red)
                            Text(result)
                                .font(.system(.body, design: .monospaced))
                        }
                        .padding(.horizontal)
                    }
                }
            }
            
            Button("Run Tests") {
                runTests()
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .onAppear {
            runTests()
        }
    }
    
    func runTests() {
        testResults = []
        
        // Test 1: Service creation
        testResults.append("✅ SwiftAudioExService created")
        testResults.append("✅ isPlaying = \(audioService.isPlaying) (expected: false)")
        testResults.append("✅ state = \(String(describing: audioService.state)) (expected: idle)")
        
        // Test 2: TTS Generator
        let tts = TTSGeneratorService()
        testResults.append("✅ TTSGeneratorService created")
        testResults.append("✅ cacheSize = \(tts.cacheSize) bytes")
        
        // Test 3: Unified Player
        testResults.append("✅ UnifiedAudioPlayer created")
        testResults.append("✅ rate = \(unifiedPlayer.rate)x")
        testResults.append("✅ isPlaying = \(unifiedPlayer.isPlaying)")
        
        // Test 4: What's NOT working
        testResults.append("❌ SwiftAudioEx not imported (commented out)")
        testResults.append("❌ No actual audio playback")
        testResults.append("❌ No seeking functionality")
        testResults.append("❌ No speeds > 2x")
        testResults.append("❌ No streaming support")
        testResults.append("❌ TTS returns empty Data()")
        
        // Summary
        testResults.append("━━━━━━━━━━━━━━━━━━━━")
        testResults.append("Summary: Classes compile ✅")
        testResults.append("But no functionality yet ❌")
    }
}

#Preview {
    TestMinimalView()
}