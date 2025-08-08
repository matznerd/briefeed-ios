#!/bin/bash
#
# Complete Development Tools Setup for iOS Project
# This script sets up all recommended tools for code quality and performance

echo "🚀 Setting Up Complete Development Environment"
echo "=============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. SwiftLint (already done)
echo -e "\n${GREEN}✅ SwiftLint${NC} - Already configured"

# 2. SwiftFormat
echo -e "\n${YELLOW}📦 Installing SwiftFormat...${NC}"
if ! command -v swiftformat &> /dev/null; then
    brew install swiftformat
    echo -e "${GREEN}✅ SwiftFormat installed${NC}"
else
    echo "SwiftFormat already installed"
fi

# 3. Periphery (finds unused code)
echo -e "\n${YELLOW}📦 Installing Periphery...${NC}"
if ! command -v periphery &> /dev/null; then
    brew install periphery
    echo -e "${GREEN}✅ Periphery installed${NC}"
else
    echo "Periphery already installed"
fi

# 4. XCLogParser (analyzes build times)
echo -e "\n${YELLOW}📦 Installing XCLogParser...${NC}"
if ! command -v xclogparser &> /dev/null; then
    brew install xclogparser
    echo -e "${GREEN}✅ XCLogParser installed${NC}"
else
    echo "XCLogParser already installed"
fi

# 5. Sourcery (code generation)
echo -e "\n${YELLOW}📦 Installing Sourcery...${NC}"
if ! command -v sourcery &> /dev/null; then
    brew install sourcery
    echo -e "${GREEN}✅ Sourcery installed${NC}"
else
    echo "Sourcery already installed"
fi

# 6. SwiftGen (resource generation)
echo -e "\n${YELLOW}📦 Installing SwiftGen...${NC}"
if ! command -v swiftgen &> /dev/null; then
    brew install swiftgen
    echo -e "${GREEN}✅ SwiftGen installed${NC}"
else
    echo "SwiftGen already installed"
fi

# 7. Danger Swift
echo -e "\n${YELLOW}📦 Setting up Danger...${NC}"
if [ ! -f "Dangerfile.swift" ]; then
    echo "Creating Dangerfile.swift..."
    cat > Dangerfile.swift << 'EOF'
import Danger

let danger = Danger()

// Check for large PRs
if (danger.github?.pullRequest.additions ?? 0) > 500 {
    warn("This PR is quite large. Consider breaking it up into smaller PRs.")
}

// Check for SwiftLint
SwiftLint.lint(inline: true)

// Check for print statements
let modifiedFiles = danger.git.modifiedFiles + danger.git.createdFiles
let swiftFiles = modifiedFiles.filter { $0.hasSuffix(".swift") }

for file in swiftFiles {
    let content = danger.utils.readFile(file)
    if content.contains("print(") && !file.contains("Debug") {
        warn("Found print statement in \(file). Consider using proper logging.")
    }
}

// Check for force unwrapping
for file in swiftFiles {
    let content = danger.utils.readFile(file)
    let forceUnwraps = content.components(separatedBy: "!").count - 1
    if forceUnwraps > 2 {
        warn("\(file) has \(forceUnwraps) force unwraps. Consider safer alternatives.")
    }
}

// Encourage testing
let hasTests = !danger.git.modifiedFiles.filter { $0.contains("Test") }.isEmpty
if !hasTests && (danger.github?.pullRequest.additions ?? 0) > 100 {
    warn("No tests modified. Consider adding tests for your changes.")
}
EOF
    echo -e "${GREEN}✅ Dangerfile created${NC}"
else
    echo "Dangerfile already exists"
fi

echo -e "\n=============================================="
echo -e "${GREEN}✅ Development tools setup complete!${NC}"
echo -e "==============================================\n"

echo "Next steps:"
echo "1. Run './Scripts/create_swiftformat_config.sh' to set up SwiftFormat"
echo "2. Run './Scripts/setup_periphery.sh' to configure unused code detection"
echo "3. Run './Scripts/setup_performance_tests.sh' to add performance tests"
echo "4. Open Xcode and use the Briefeed-Debug scheme for enhanced debugging"