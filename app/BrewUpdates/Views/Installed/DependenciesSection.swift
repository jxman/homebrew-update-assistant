import SwiftUI

/// The inspector's Dependencies section for a formula: what installed it, what it needs and
/// what needs it. Names are links that select that package.
struct DependenciesSection: View {
    let package: InstalledPackage
    let dependencies: PackageDependencies
    let select: (InstalledPackage) -> Void

    var body: some View {
        Section("Dependencies") {
            if !package.installedOnRequest {
                installedFor
            }
            PackageLinks(title: "Needed by", packages: dependencies.neededBy, select: select)
            PackageLinks(title: "Needs", packages: dependencies.needs, select: select)
            if dependencies.indirectCount > 0 {
                Text("Plus \(dependencies.indirectCount) more through those")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var installedFor: some View {
        if dependencies.isLeftover {
            Label {
                Text("Nothing installed needs this any more. It's probably left over from something you "
                    + "uninstalled; `brew autoremove` removes leftovers like this.")
            } icon: {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
            }
            .foregroundStyle(.secondary)
        } else if !dependencies.installedFor.isEmpty {
            PackageLinks(title: "Installed for", packages: dependencies.installedFor, select: select)
                .help("The packages you installed that need this one, directly or through other dependencies")
        } else {
            // e.g. an older library version that packages built against it still list
            PackageLinks(title: "Still used by", packages: dependencies.indirectlyNeededBy, select: select)
                .help("These were built with it as a dependency of a dependency, so brew keeps it until they're "
                    + "upgraded or reinstalled")
        }
    }
}

/// A titled, wrapping list of package names. Packages you installed yourself are bold.
private struct PackageLinks: View {
    let title: String
    let packages: [InstalledPackage]
    let select: (InstalledPackage) -> Void

    /// Long lists (python is needed by dozens of formulae) start collapsed
    @State private var showsAll = false
    private static let collapsedCount = 8

    private var shown: [InstalledPackage] {
        showsAll ? packages : Array(packages.prefix(Self.collapsedCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(packages.isEmpty ? "\(title): nothing" : "\(title) (\(packages.count))")
                .font(.callout.weight(.medium))
                .foregroundStyle(packages.isEmpty ? .secondary : .primary)
            if !packages.isEmpty {
                // `.adaptive(minimum:)` fits as many columns as the inspector's width allows,
                // so the names wrap like text
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 4) {
                    ForEach(shown) { package in
                        Button(package.name) { select(package) }
                            .buttonStyle(.link)
                            .fontWeight(package.installedOnRequest ? .semibold : .regular)
                            .lineLimit(1)
                            .help(package.summary ?? package.name)
                    }
                }
                if packages.count > Self.collapsedCount {
                    Button(showsAll ? "Show fewer" : "Show all \(packages.count)") { showsAll.toggle() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
