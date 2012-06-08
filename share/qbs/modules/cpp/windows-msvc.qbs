import qbs.base 1.0
import qbs.fileinfo 1.0 as FileInfo
import '../utils.js' as ModUtils
import 'msvc.js' as MSVC

CppModule {
    condition: qbs.hostOS === 'windows' && qbs.targetOS === 'windows' && qbs.toolchain === 'msvc'

    id: module

    platformDefines: ['UNICODE']
    compilerDefines: ['_WIN32']
    warningLevel: "default"

    property bool generateManifestFiles: true
    property string toolchainInstallPath: "UNKNOWN"
    property string windowsSDKPath: "UNKNOWN"
    property string architecture: qbs.architecture || "x86"
    property int responseFileThreshold: 32000
    staticLibraryPrefix: ""
    dynamicLibraryPrefix: ""
    executablePrefix: ""
    staticLibrarySuffix: ".lib"
    dynamicLibrarySuffix: ".dll"
    executableSuffix: ".exe"
    property string dynamicLibraryImportSuffix: "_imp.lib"

    setupBuildEnvironment: {
        var v = new ModUtils.EnvironmentVariable("INCLUDE", ";", true)
        v.prepend(toolchainInstallPath + "/VC/ATLMFC/INCLUDE")
        v.prepend(toolchainInstallPath + "/VC/INCLUDE")
        v.prepend(windowsSDKPath + "/include")
        v.set()

        if (architecture == 'x86') {
            v = new ModUtils.EnvironmentVariable("PATH", ";", true)
            v.prepend(windowsSDKPath + "/bin")
            v.prepend(toolchainInstallPath + "/Common7/IDE")
            v.prepend(toolchainInstallPath + "/VC/bin")
            v.prepend(toolchainInstallPath + "/Common7/Tools")
            v.set()

            v = new ModUtils.EnvironmentVariable("LIB", ";", true)
            v.prepend(toolchainInstallPath + "/VC/ATLMFC/LIB")
            v.prepend(toolchainInstallPath + "/VC/LIB")
            v.prepend(windowsSDKPath + "/lib")
            v.set()
        } else if (architecture == 'x86_64') {
            v = new ModUtils.EnvironmentVariable("PATH", ";", true)
            v.prepend(windowsSDKPath + "/bin/x64")
            v.prepend(toolchainInstallPath + "/Common7/IDE")
            v.prepend(toolchainInstallPath + "/VC/bin/amd64")
            v.prepend(toolchainInstallPath + "/Common7/Tools")
            v.set()

            v = new ModUtils.EnvironmentVariable("LIB", ";", true)
            v.prepend(toolchainInstallPath + "/VC/ATLMFC/LIB/amd64")
            v.prepend(toolchainInstallPath + "/VC/LIB/amd64")
            v.prepend(windowsSDKPath + "/lib/x64")
            v.set()
        }
    }

    Artifact {
        // This adds the filename in precompiledHeader to the set of source files.
        // If its already in there, then this makes sure it has the right file tag.
        condition: precompiledHeader != null
        fileName: precompiledHeader
        fileTags: ["hpp_pch"]
    }

    Rule {
        id: pchCompiler
        inputs: ["hpp_pch"]
        Artifact {
            fileTags: ['obj']
            // ### make the object file dir overridable
            fileName: ".obj/" + product.name + "/" + input.baseName + '.obj'
        }
        Artifact {
            fileTags: ['c++_pch']
            // ### make the object file dir overridable
            fileName: ".obj/" + product.name + "/" + product.name + '.pch'
        }
        TransformProperties {
            property var platformDefines: ModUtils.appendAll(input, 'platformDefines')
            property var defines: ModUtils.appendAll(input, 'defines')
            property var includePaths: ModUtils.appendAll(input, 'includePaths')
            property var cFlags: ModUtils.appendAll(input, 'cFlags')
            property var cxxFlags: ModUtils.appendAll(input, 'cxxFlags')
        }
        prepare: {
            return MSVC.prepareCompiler(product, input, outputs, platformDefines, defines, includePaths, cFlags, cxxFlags)
        }
    }

    Rule {
        id: compiler
        inputs: ["cpp", "c"]
        explicitlyDependsOn: ["c++_pch"]
        Artifact {
            fileTags: ['obj']
            // ### make the object file dir overridable
            fileName: ".obj/" + product.name + "/" + input.baseDir + "/" + input.baseName + ".obj"
        }
 
        TransformProperties {
            property var platformDefines: ModUtils.appendAll(input, 'platformDefines')
            property var defines: ModUtils.appendAll(input, 'defines')
            property var includePaths: ModUtils.appendAll(input, 'includePaths')
            property var cFlags: ModUtils.appendAll(input, 'cFlags')
            property var cxxFlags: ModUtils.appendAll(input, 'cxxFlags')
        }

        prepare: {
            return MSVC.prepareCompiler(product, input, outputs, platformDefines, defines, includePaths, cFlags, cxxFlags)
        }
    }

    Rule {
        id: applicationLinker
        multiplex: true
        inputs: ['obj']
        usings: ['staticlibrary', 'dynamiclibrary_import']
        Artifact {
            fileTags: ["application"]
            fileName: product.destinationDirectory + "/" + product.module.executablePrefix + product.targetName + product.module.executableSuffix
        }

        TransformProperties {
            property var libraryPaths: ModUtils.appendAll(product, 'libraryPaths')
            property var dynamicLibraries: ModUtils.appendAllFromArtifacts(product, inputs.dynamiclibrary_import, 'cpp', 'dynamicLibraries')
            property var staticLibraries: ModUtils.appendAllFromArtifacts(product, (inputs.staticlibrary || []).concat(inputs.obj), 'cpp', 'staticLibraries')
            property var linkerFlags: ModUtils.appendAll(product, 'linkerFlags')
        }

        prepare: {
            return MSVC.prepareLinker(product, inputs, outputs, libraryPaths, dynamicLibraries, staticLibraries, linkerFlags)
        }
    }

    Rule {
        id: dynamicLibraryLinker
        multiplex: true
        inputs: ['obj']
        usings: ['staticlibrary', 'dynamiclibrary_import']

        Artifact {
            fileTags: ["dynamiclibrary"]
            fileName: product.destinationDirectory + "/" + product.module.dynamicLibraryPrefix + product.targetName + product.module.dynamicLibrarySuffix
        }

        Artifact {
            fileTags: ["dynamiclibrary_import"]
            fileName: product.destinationDirectory + "/" + product.module.dynamicLibraryPrefix + product.targetName + product.module.dynamicLibraryImportSuffix
        }

        TransformProperties {
            property var libraryPaths: ModUtils.appendAll(product, 'libraryPaths')
            property var dynamicLibraries: ModUtils.appendAll(product, 'dynamicLibraries')
            property var staticLibraries: ModUtils.appendAllFromArtifacts(product, (inputs.staticlibrary || []).concat(inputs.obj), 'cpp', 'staticLibraries')
            property var linkerFlags: ModUtils.appendAll(product, 'linkerFlags')
        }

        prepare: {
            return MSVC.prepareLinker(product, inputs, outputs, libraryPaths, dynamicLibraries, staticLibraries, linkerFlags)
        }
    }

    Rule {
        id: libtool
        multiplex: true
        inputs: ["obj"]
        usings: ["staticlibrary"]

        Artifact {
            fileTags: ["staticlibrary"]
            fileName: product.destinationDirectory + "/" + product.module.staticLibraryPrefix + product.targetName + product.module.staticLibrarySuffix
            cpp.staticLibraries: {
                var result = []
                for (var i in inputs.staticlibrary) {
                    var lib = inputs.staticlibrary[i]
                    result.push(lib.fileName)
                    var impliedLibs = ModUtils.appendAll(lib, 'staticLibraries')
                    result.concat(impliedLibs)
                }
                return result
            }
        }

        prepare: {
            var toolchainInstallPath = product.module.toolchainInstallPath

            var args = ['/nologo']
            var nativeOutputFileName = FileInfo.toWindowsSeparators(output.fileName)
            args.push('/OUT:' + nativeOutputFileName)
            for (var i in inputs.obj) {
                var fileName = FileInfo.toWindowsSeparators(inputs.obj[i].fileName)
                args.push(fileName)
            }
            var is64bit = (product.module.architecture == "x86_64")
            var linkerPath = toolchainInstallPath + '/VC/bin/'
            if (is64bit)
                linkerPath += 'amd64/'
            linkerPath += 'lib.exe'
            var cmd = new Command(linkerPath, args)
            cmd.description = 'creating ' + FileInfo.fileName(output.fileName)
            cmd.highlight = 'linker';
            cmd.workingDirectory = FileInfo.path(output.fileName)
            cmd.responseFileThreshold = product.module.responseFileThreshold
            cmd.responseFileUsagePrefix = '@';
            return cmd;
         }
    }

    FileTagger {
        pattern: "*.rc"
        fileTags: ["rc"]
    }

    Rule {
        inputs: ["rc"]

        Artifact {
            fileName: ".obj/" + product.name + "/" + input.baseDir + "/" + input.baseName + ".res"
            fileTags: ["obj"]
        }

        TransformProperties {
            property var platformDefines: ModUtils.appendAll(input, 'platformDefines')
            property var defines: ModUtils.appendAll(input, 'defines')
            property var includePaths: ModUtils.appendAll(input, 'includePaths')
        }

        prepare: {
            var args = [];
            var i;
            for (i in platformDefines) {
                args.push('/d');
                args.push(platformDefines[i]);
            }
            for (i in defines) {
                args.push('/d');
                args.push(defines[i]);
            }
            for (i in includePaths) {
                args.push('/i');
                args.push(includePaths[i]);
            }

            args = args.concat(['/fo', output.fileName, input.fileName]);
            var cmd = new Command('rc', args);
            cmd.description = 'compiling ' + FileInfo.fileName(input.fileName);
            cmd.highlight = 'compiler';

            // Remove the first two lines of stdout. That's the logo.
            // Unfortunately there's no command line switch to turn that off.
            cmd.stdoutFilterFunction = function(output) {
                var idx = 0;
                for (var i = 0; i < 3; ++i)
                    idx = output.indexOf('\n', idx + 1);
                return output.substr(idx + 1);
            }

            return cmd;
        }
    }
}
