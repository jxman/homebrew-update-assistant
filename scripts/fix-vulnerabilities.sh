#!/bin/bash
# Vulnerability Fix Script
# Automatically updates packages with known security vulnerabilities

set -e

echo "🔒 Homebrew Security Vulnerability Fix Script"
echo "=============================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check if package is installed
package_installed() {
    brew list --formula 2>/dev/null | grep -q "^${1}$"
}

# Function to upgrade package
upgrade_package() {
    local package="$1"
    local description="$2"

    if package_installed "$package"; then
        echo -e "${BLUE}📦 Updating $package${NC} $description"
        if brew upgrade "$package" 2>/dev/null; then
            echo -e "${GREEN}✓ $package updated${NC}"
        else
            echo -e "${YELLOW}⚠️  $package is already up to date${NC}"
        fi
    else
        echo -e "${YELLOW}⏭️  $package not installed, skipping${NC}"
    fi
    echo ""
}

echo "Step 1: Updating Homebrew..."
brew update

echo ""
echo "Step 2: Fixing High Priority Vulnerabilities"
echo "=============================================="

# Ruby gem vulnerabilities (tzinfo, json, rexml, cocoapods-downloader)
upgrade_package "cocoapods" "(fixes Ruby gem vulnerabilities: tzinfo, json, rexml)"
upgrade_package "ruby" "(fixes system Ruby gems)"

# Go stdlib vulnerabilities
upgrade_package "go" "(fixes Go stdlib CVEs)"
upgrade_package "helm" "(may include Go stdlib updates)"
upgrade_package "terraform" "(may include Go stdlib updates)"
upgrade_package "aws-sam-cli" "(may include Go stdlib updates)"
upgrade_package "awscli" "(AWS CLI tool)"
upgrade_package "azure-cli" "(Azure CLI tool)"

# Python vulnerabilities (urllib3, pip)
echo -e "${BLUE}🐍 Updating Python installations...${NC}"
for py_version in python@3.12 python@3.13 python@3.14; do
    if package_installed "$py_version"; then
        echo -e "${BLUE}📦 Updating $py_version${NC}"
        brew upgrade "$py_version" 2>/dev/null || echo -e "${YELLOW}⚠️  $py_version already up to date${NC}"

        # Update pip and urllib3 within each Python version
        py_bin="/opt/homebrew/opt/${py_version}/bin/pip${py_version#python@}"
        if [ -f "$py_bin" ]; then
            echo -e "${BLUE}  Updating pip and urllib3...${NC}"
            "$py_bin" install --upgrade pip urllib3 2>/dev/null || echo -e "${YELLOW}  Already up to date${NC}"
        fi
    fi
done

# Node.js and NPM vulnerabilities
upgrade_package "node" "(fixes NPM package vulnerabilities)"

echo ""
echo "Step 3: Running Security Scan"
echo "=============================================="

if command -v grype &> /dev/null; then
    echo -e "${BLUE}🔍 Scanning for remaining vulnerabilities...${NC}"
    echo ""

    vuln_count=$(grype dir:/opt/homebrew/Cellar --only-fixed -q 2>/dev/null | grep -c "High\|Critical" || echo "0")

    if [ "$vuln_count" -eq 0 ]; then
        echo -e "${GREEN}✅ No high/critical vulnerabilities found!${NC}"
    else
        echo -e "${YELLOW}⚠️  Found $vuln_count high/critical vulnerabilities remaining${NC}"
        echo ""
        echo "Top remaining vulnerabilities:"
        grype dir:/opt/homebrew/Cellar --only-fixed -q 2>/dev/null | grep -E "High|Critical" | head -10
        echo ""
        echo -e "${BLUE}💡 Some vulnerabilities may require package maintainer updates${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Grype not installed. Install with: brew install --cask grype${NC}"
fi

echo ""
echo "=============================================="
echo -e "${GREEN}🎉 Vulnerability fix process complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Review any remaining vulnerabilities above"
echo "  2. Run: grype dir:/opt/homebrew/Cellar --only-fixed"
echo "  3. Research persistent CVEs to determine impact"
echo ""
