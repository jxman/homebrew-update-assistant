# Contributing to Homebrew Update Assistant

Thank you for considering contributing to the Homebrew Update Assistant! 🍺

## 🌟 Ways to Contribute

- 🐛 **Bug Reports**: Help us identify and fix issues
- ✨ **Feature Requests**: Suggest new functionality
- 🔧 **Code Contributions**: Submit pull requests with improvements
- 📚 **Documentation**: Improve guides, examples, and explanations
- 🧪 **Testing**: Test the script on different systems and scenarios

## 🚀 Getting Started

### Prerequisites
- macOS or Linux system
- Homebrew installed
- Bash 4.0+ (pre-installed on most systems)
- Git for version control

### Development Setup
```bash
# 1. Fork the repository on GitHub
# 2. Clone your fork
git clone https://github.com/yourusername/homebrew-update-assistant.git
cd homebrew-update-assistant

# 3. Make the script executable
chmod +x brew-updates.command

# 4. Test the current version
./brew-updates.command --dry-run --verbose
```

## 🐛 Reporting Bugs

Before submitting a bug report, please:

1. **Check existing issues** to avoid duplicates
2. **Test with the latest version** of the script
3. **Run in verbose mode** to gather detailed logs

### Bug Report Template
```markdown
**Describe the bug**
A clear description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:
1. Run command '...'
2. See error

**Expected behavior**
What you expected to happen.

**Environment:**
- OS: [e.g., macOS 14.0, Ubuntu 22.04]
- Homebrew version: [output of `brew --version`]
- Script version: [if applicable]

**Logs**
Please attach relevant log files or command output.
```

## ✨ Suggesting Features

We welcome feature suggestions! Please:

1. **Check existing issues** for similar requests
2. **Explain the use case** - why would this be helpful?
3. **Describe the expected behavior** in detail
4. **Consider backward compatibility** implications

### Feature Request Template
```markdown
**Is your feature request related to a problem?**
A clear description of what the problem is.

**Describe the solution you'd like**
A clear description of what you want to happen.

**Describe alternatives you've considered**
Alternative solutions or features you've considered.

**Additional context**
Any other context, screenshots, or examples.
```

## 🔧 Code Contributions

### Development Guidelines

#### Code Style
- **Use consistent indentation**: 4 spaces (no tabs)
- **Follow existing patterns**: Match the style of surrounding code
- **Comment complex logic**: Explain the "why," not just the "what"
- **Use meaningful variable names**: `backup_file` not `bf`

#### Security Best Practices
- **Validate all inputs**: User inputs, environment variables, file paths
- **Avoid eval**: Use safe command execution methods
- **Sanitize file paths**: Prevent directory traversal attacks
- **Handle errors gracefully**: Don't expose sensitive information

#### Testing Requirements
- **Test on multiple systems**: macOS and Linux if possible
- **Test edge cases**: Empty inputs, network failures, disk space issues
- **Use dry-run mode**: Verify logic without making changes
- **Test automation mode**: Ensure non-interactive execution works

### Pull Request Process

1. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
   - Follow the coding guidelines above
   - Add/update tests if applicable
   - Update documentation if needed

3. **Test thoroughly**
   ```bash
   # Test basic functionality
   ./brew-updates.command --dry-run --verbose
   
   # Test specific scenarios
   ./brew-updates.command --help
   ./brew-updates.command --yes --skip-casks
   ```

4. **Commit with clear messages**
   ```bash
   git add .
   git commit -m "feat: add support for custom timeout configuration
   
   - Add BREW_UPDATE_TIMEOUT environment variable
   - Update documentation with usage examples
   - Add input validation for timeout values"
   ```

5. **Push and create PR**
   ```bash
   git push origin feature/your-feature-name
   ```

### Commit Message Guidelines

Use the [Conventional Commits](https://www.conventionalcommits.org/) format:

- `feat:` New features
- `fix:` Bug fixes
- `docs:` Documentation changes
- `style:` Code style changes (formatting, etc.)
- `refactor:` Code refactoring
- `test:` Adding or updating tests
- `chore:` Maintenance tasks

### Code Review Process

All submissions require review. We use GitHub pull requests for this purpose. Please:

- **Be responsive** to feedback and questions
- **Keep PRs focused** - one feature/fix per PR
- **Update your branch** if requested
- **Be patient** - reviews may take a few days

## 🧪 Testing

### Manual Testing Checklist
- [ ] Script runs without errors in interactive mode
- [ ] `--dry-run` mode works correctly
- [ ] `--verbose` mode provides detailed output
- [ ] `--yes` mode runs without prompts
- [ ] Error handling works for network failures
- [ ] Backup creation and rotation works
- [ ] Doctor output parsing works correctly
- [ ] Clickable links work in supported terminals

### Test Scenarios
```bash
# Basic functionality tests
./brew-updates.command --dry-run
./brew-updates.command --help
./brew-updates.command --yes --verbose --skip-cleanup

# Error condition tests (simulate these safely)
# - Network disconnection
# - Low disk space
# - Missing Homebrew
# - Invalid configuration file
```

## 📚 Documentation

When updating documentation:

- **Use clear, simple language**
- **Include practical examples**
- **Keep README.md up to date**
- **Update help text** if adding new options
- **Add inline comments** for complex code

## 🏷️ Release Process

For maintainers:

1. **Update CHANGELOG.md** with new features/fixes
2. **Update version number** in script header
3. **Test release candidate** thoroughly
4. **Create GitHub release** with detailed notes
5. **Update badges/links** if necessary

## ❓ Questions?

If you have questions about contributing:

- **Check existing issues** for similar questions
- **Open a discussion** for general questions
- **Contact maintainers** for specific guidance

## 🙏 Recognition

Contributors will be:
- **Listed in README.md** acknowledgments
- **Mentioned in release notes** for significant contributions
- **Given credit** in commit messages when appropriate

## 📜 Code of Conduct

This project follows a simple code of conduct:

- **Be respectful** and inclusive
- **Provide constructive feedback**
- **Focus on the code**, not the person
- **Help newcomers** learn and contribute
- **Keep discussions on-topic**

---

Thank you for contributing to the Homebrew Update Assistant! Your help makes this tool better for everyone. 🍺✨