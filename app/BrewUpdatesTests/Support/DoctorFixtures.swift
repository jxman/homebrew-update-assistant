import Foundation

// Doctor output trimmed from real `brew doctor --verbose` logs (Homebrew 7.0.11).
enum DoctorFixtures {
    static let warnings = """
    ==> Cask Environment Variables:
    LC_ALL="en_US.UTF-8"
    ==> Homebrew Version
    7.0.11
    ==> macOS
    27.0.1
    ==> SIP
    Enabled
    Please note that these warnings are just used to help the Homebrew maintainers
    with debugging if you file an issue. If everything you use Homebrew for is
    working fine: please don't worry or file an issue; just ignore this. Thanks!

    Warning: Some installed kegs have no formulae!
    This means they were either deleted or installed manually.


    You should find replacements for the following formulae:

      azure-cli
      tflint

    Warning: The following taps are not trusted:
      anchore/grype
      hashicorp/tap

    Homebrew is currently ignoring formulae, casks and commands
    from these taps because tap trust is required.
    Trust installed formulae from these taps with:
      brew trust --formula hashicorp/tap/terraform
    Trust other specific commands with:
      brew trust --command <user>/<tap>/<command>
    Untap them with:
      brew untap anchore/grype hashicorp/tap
    For more information, see:
      https://docs.brew.sh/Tap-Trust
    """

    static let healthy = """
    ==> Homebrew Version
    7.0.11
    ==> macOS
    27.0.1
    Your system is ready to brew.
    """

    /// Wrapped headline, inline command, an error, an unknown check and the support tier trailer
    static let mixed = """
    Warning: Homebrew's "sbin" was not found in your PATH but you have installed
    formulae that put executables in /opt/homebrew/sbin.
    Consider setting your PATH for example like so:
      echo 'export PATH="/opt/homebrew/sbin:$PATH"' >> ~/.zshrc

    Warning: Broken symlinks were found. Remove them with `brew cleanup`:
      /opt/homebrew/bin/oldtool

    Error: Something entirely new went wrong.
    This is a Tier 2 configuration:
      https://docs.brew.sh/Support-Tiers#tier-2
    You can report issues with Tier 2 configurations to Homebrew/* repositories!
    """
}
