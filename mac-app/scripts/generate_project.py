#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project deterministically."""
from pathlib import Path
import hashlib
root=Path(__file__).resolve().parents[1]
def uid(key):return hashlib.sha1(key.encode()).hexdigest()[:24].upper()
def q(value):return '"'+value.replace('\\','\\\\').replace('"','\\"')+'"'
objects={}
def obj(key,value):objects[uid(key)]=value;return uid(key)
files=sorted((root/'Sources').rglob('*.swift'))
refs=[];builds=[]
for f in files:
 p=str(f.relative_to(root));r=obj('file:'+p,'{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = '+q(p)+'; sourceTree = SOURCE_ROOT; }');refs.append(r)
 builds.append(obj('build:'+p,'{isa = PBXBuildFile; fileRef = '+r+'; }'))
iconPath='../branding/driveline/DriveLine.icon'
iconRef=obj('icon','{isa = PBXFileReference; lastKnownFileType = folder.iconcomposer.icon; path = '+q(iconPath)+'; sourceTree = SOURCE_ROOT; }');refs.append(iconRef)
iconBuild=obj('icon-build','{isa = PBXBuildFile; fileRef = '+iconRef+'; }')
product=obj('product','{isa = PBXFileReference; explicitFileType = wrapper.application; path = CANConnect.app; sourceTree = BUILT_PRODUCTS_DIR; }')
products=obj('products','{isa = PBXGroup; children = ('+product+',); name = Products; sourceTree = "<group>"; }')
main=obj('group','{isa = PBXGroup; children = ('+','.join(refs+[products])+',); sourceTree = "<group>"; }')
sources=obj('sources','{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ('+','.join(builds)+',); runOnlyForDeploymentPostprocessing = 0; }')
package_ref=obj('package:DriveLineShared','{isa = XCLocalSwiftPackageReference; relativePath = "../shared/DriveLineShared"; }')
package_product=obj('package-product:DriveLineShared','{isa = XCSwiftPackageProductDependency; package = '+package_ref+'; productName = DriveLineShared; }')
package_build=obj('package-build:DriveLineShared','{isa = PBXBuildFile; productRef = '+package_product+'; }')
frameworks=obj('frameworks','{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ('+package_build+',); runOnlyForDeploymentPostprocessing = 0; }')
resources=obj('resources','{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ('+iconBuild+',); runOnlyForDeploymentPostprocessing = 0; }')
common='MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES;'
target_common=common+' ASSETCATALOG_COMPILER_APPICON_NAME = DriveLine; PRODUCT_NAME = CANConnect; PRODUCT_BUNDLE_IDENTIFIER = ca.canconnect.mac; INFOPLIST_FILE = Info.plist; GENERATE_INFOPLIST_FILE = NO; CODE_SIGN_STYLE = Manual; CODE_SIGN_IDENTITY = "-"; ENABLE_HARDENED_RUNTIME = NO; ENABLE_APP_SANDBOX = NO; SWIFT_EMIT_LOC_STRINGS = YES; OTHER_LDFLAGS = ("$(inherited)", "-lsqlite3"); LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/../Frameworks");'
for owner,settings in [('project',common),('target',target_common)]:
 cs=[]
 for config in ['Debug','Release']:
  extra=' SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if config=='Debug' else ' SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
  cs.append(obj(owner+config,'{isa = XCBuildConfiguration; buildSettings = {'+settings+extra+'}; name = '+config+'; }'))
 obj(owner+'configs','{isa = XCConfigurationList; buildConfigurations = ('+','.join(cs)+',); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }')
target=obj('target','{isa = PBXNativeTarget; buildConfigurationList = '+uid('targetconfigs')+'; buildPhases = ('+','.join([sources,frameworks,resources])+',); buildRules = (); dependencies = (); name = CANConnect; packageProductDependencies = ('+package_product+',); productName = CANConnect; productReference = '+product+'; productType = "com.apple.product-type.application"; }')
project=obj('project','{isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600;}; buildConfigurationList = '+uid('projectconfigs')+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = '+main+'; packageReferences = ('+package_ref+',); productRefGroup = '+products+'; projectDirPath = ""; projectRoot = ""; targets = ('+target+',); }')
folder=root/'CANConnect.xcodeproj';folder.mkdir(exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+''.join(k+' = '+v+';\n' for k,v in objects.items())+'}; rootObject = '+project+'; }\n')
scheme='''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="TARGET" BuildableName="CANConnect.app" BlueprintName="CANConnect" ReferencedContainer="container:CANConnect.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"/><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="TARGET" BuildableName="CANConnect.app" BlueprintName="CANConnect" ReferencedContainer="container:CANConnect.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="TARGET" BuildableName="CANConnect.app" BlueprintName="CANConnect" ReferencedContainer="container:CANConnect.xcodeproj"/></BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>
'''.replace('TARGET',target)
schemes=folder/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True);(schemes/'CANConnect.xcscheme').write_text(scheme)
print('Generated',len(files),'Swift source references')
