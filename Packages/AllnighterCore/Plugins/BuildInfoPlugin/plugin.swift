import PackagePlugin

/// Makes the shared Core build identity an output of every SwiftPM build rather
/// than a separate, easy-to-forget release step. The resident engine imports
/// Core, so this is the one place every broker participant can see the exact
/// source build it represents.
@main
struct BuildInfoPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard target.name == "AllnighterCore" else { return [] }

        return [
            .prebuildCommand(
                displayName: "Generating alln build identity",
                executable: context.package.directory.appending("Plugins/BuildInfoPlugin/generate-build-info.sh"),
                arguments: [
                    context.package.directory.string,
                    context.pluginWorkDirectory.string,
                ],
                outputFilesDirectory: context.pluginWorkDirectory
            )
        ]
    }
}
