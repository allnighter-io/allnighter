import PackagePlugin

/// Makes the CLI's build identity an output of every SwiftPM build rather than
/// a separate, easy-to-forget release step.
@main
struct BuildInfoPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard target.name == "AllnighterCLI" else { return [] }

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
