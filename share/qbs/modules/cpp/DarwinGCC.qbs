import qbs 1.0
import '../utils.js' as ModUtils
import "bundle-tools.js" as BundleTools

UnixGCC {
    condition: false

    compilerDefines: ["__GNUC__", "__APPLE__"]
    dynamicLibrarySuffix: ".dylib"

    property var defaultInfoPlist
    property var infoPlist: defaultInfoPlist
    property bool buildDsym: qbs.buildVariant === "release"

    Rule {
        multiplex: true
        inputs: ["qbs"]

        Artifact {
            fileName: product.destinationDirectory + "/" + BundleTools.pkgInfoPath(product)
            fileTags: ["pkginfo"]
        }

        prepare: {
            var cmd = new JavaScriptCommand();
            cmd.description = "generating PkgInfo";
            cmd.highlight = "codegen";
            var pkgType = 'BNDL';
            if (product.type.indexOf("applicationbundle") !== -1)
                pkgType = 'APPL';
            if (product.type.indexOf("frameworkbundle") !== -1)
                pkgType = 'FMWK';
            var infoPlist = product.moduleProperty("cpp", "infoPlist");
            if (infoPlist && infoPlist.hasOwnProperty('CFBundlePackageType'))
                pkgType = infoPlist['CFBundlePackageType'];
            var pkgSign = '????';
            if (infoPlist && infoPlist.hasOwnProperty('CFBundleSignature'))
                pkgSign = infoPlist['CFBundleSignature'];
            cmd.pkgInfo =  pkgType + pkgSign;
            cmd.sourceCode = function() {
                var pkginfo = new TextFile(outputs.pkginfo[0].fileName, TextFile.WriteOnly);
                pkginfo.write(pkgInfo);
                pkginfo.close();
            }
            return cmd;
        }
    }

    Rule {
        multiplex: true
        inputs: ["qbs"]

        Artifact {
            fileName: product.destinationDirectory + "/" + BundleTools.infoPlistPath(product)
            fileTags: ["infoplist"]
        }

        prepare: {
            var cmd = new JavaScriptCommand();
            cmd.description = "generating Info.plist";
            cmd.highlight = "codegen";
            cmd.infoPlist = ModUtils.moduleProperty(product, "infoPlist") || {};
            cmd.platformPath = product.moduleProperty("cpp", "platformPath");
            cmd.sourceCode = function() {
                var defaultValues = ModUtils.moduleProperty(product, "defaultInfoPlist");
                var key;
                for (key in defaultValues) {
                    if (defaultValues.hasOwnProperty(key) && !(key in infoPlist))
                        infoPlist[key] = defaultValues[key];
                }

                var process;
                if (platformPath) {
                    process = new Process();
                    process.start("plutil", ["-convert", "json", "-o", "-",
                                             platformPath + "/Info.plist"]);
                    process.waitForFinished();
                    platformInfo = JSON.parse(process.readAll());

                    var additionalProps = platformInfo["AdditionalInfo"];
                    for (key in additionalProps) {
                        if (additionalProps.hasOwnProperty(key) && !(key in infoPlist)) // override infoPlist?
                            infoPlist[key] = defaultValues[key];
                    }

                    if (product.moduleProperty("qbs", "targetOS") === "ios") {
                        key = "UIDeviceFamily";
                        if (key in platformInfo && !(key in infoPlist))
                            infoPlist[key] = platformInfo[key];
                    }
                } else {
                    print("Missing platformPath property");
                }

                process = new Process();
                process.start("sw_vers", ["-buildVersion"]);
                process.waitForFinished();
                infoPlist["BuildMachineOSBuild"] = process.readAll().trim();

                var infoplist = new TextFile(outputs.infoplist[0].fileName, TextFile.WriteOnly);
                infoplist.write(JSON.stringify(infoPlist));
                infoplist.close();

                process = new Process();
                process.start("plutil", ["-convert",
                                        product.moduleProperty("qbs", "targetOS") === "ios"
                                            ? "binary1" : "xml1",
                                        outputs.infoplist[0].fileName]);
                process.waitForFinished();
            }
            return cmd;
        }
    }

    Rule {
        condition: product.moduleProperty("cpp", "buildDsym")
        inputs: ["application"]

        Artifact {
            fileName: product.destinationDirectory + "/" + PathTools.dwarfDsymFileName()
            fileTags: ["dsym"]
        }

        prepare: {
            var cmd = new Command("dsymutil", ["--out=" + outputs.dsym[0].fileName, input.fileName]);
            cmd.description = "generating dsym";
            cmd.highlight = "codegen";
            return cmd;
        }
    }

    Rule {
        multiplex: true
        inputs: {
            var res = ["application", "infoplist", "pkginfo", "dsym"];
            if (product.moduleProperty("qbs", "targetOS") === "ios") {
                res.push("resourcerules");
                // if (ModUtils.moduleProperty(product, "buildIpa")) // ditto
                    res.push("ipa");
            }
            return res;
        }

        Artifact {
            fileName: product.destinationDirectory + "/" + BundleTools.wrapperName(product)
            fileTags: ["applicationbundle"]
        }

        prepare: {
            // This command is intentionally empty; it just lets the user know a bundle has been made
            var cmd = new JavaScriptCommand();
            cmd.description = "creating app bundle";
            cmd.highlight = "codegen";
            return cmd;
        }
    }

    Rule {
        multiplex: true
        inputs: ["dynamiclibrary", "infoplist", "pkginfo", "dsym"]

        Artifact {
            fileName: product.destinationDirectory + "/" + BundleTools.wrapperName(product)
            fileTags: ["frameworkbundle"]
        }

        prepare: {
            var commands = [];
            var cmd = new Command("ln", ["-s", BundleTools.frameworkVersion(product), "Current"]);
            cmd.workingDirectory = output.fileName + "/Versions";
            cmd.description = "creating framework " + product.targetName;
            cmd.highlight = "codegen";
            commands.push(cmd);

            cmd = new Command("ln", ["-s", "Versions/Current/Headers", "Headers"]);
            cmd.workingDirectory = output.fileName;
            commands.push(cmd);

            cmd = new Command("ln", ["-s", "Versions/Current/Resources", "Resources"]);
            cmd.workingDirectory = output.fileName;
            commands.push(cmd);

            cmd = new Command("ln", ["-s", "Versions/Current/" + product.targetName, product.targetName]);
            cmd.workingDirectory = output.fileName;
            commands.push(cmd);
            return commands;
        }
    }
}
