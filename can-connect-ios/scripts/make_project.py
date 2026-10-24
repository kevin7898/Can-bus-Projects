#!/usr/bin/env python3
"""Generate the checked-in dependency-free Xcode project deterministically."""
from pathlib import Path
import hashlib
ROOT = Path(__file__).resolve().parents[1]
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def q(value): return '"' + value.replace('\\','\\\\').replace('"','\\"') + '"'
objects = {}
def add(name, isa, body):
    objects[uid(name)] = f'isa = {isa}; {body}'
    return uid(name)
def array(items): return '(' + ', '.join(items) + (',' if items else '') + ')'
sharedfiles = sorted((ROOT/'Shared').glob('*.swift'))
appfiles = sorted((ROOT/'CANConnect').rglob('*.swift')) + sharedfiles
widgetfiles = sorted((ROOT/'CANConnectLiveActivity').glob('*.swift')) + sharedfiles
testfiles = sorted((ROOT/'CANConnectTests').glob('*.swift'))
uifiles = sorted((ROOT/'CANConnectUITests').glob('*.swift'))
resources = sorted(f for f in (ROOT/'CANConnect/Resources').iterdir() if f.suffix in {'.json','.txt'})
fileIDs = {}; buildIDs = {}
for file in dict.fromkeys(appfiles + widgetfiles + testfiles + uifiles + resources + [ROOT/'CANConnect/Info.plist', ROOT/'CANConnectLiveActivity/Info.plist']):
    path = file.relative_to(ROOT).as_posix()
    typ = 'sourcecode.swift' if file.suffix == '.swift' else 'text.json' if file.suffix == '.json' else 'text' if file.suffix == '.txt' else 'text.plist.xml'
    fileIDs[path] = add('file:'+path,'PBXFileReference',f'lastKnownFileType = {typ}; path = {q(path)}; sourceTree = SOURCE_ROOT;')
    if file.suffix != '.plist': buildIDs[path] = add('build:'+path,'PBXBuildFile',f'fileRef = {fileIDs[path]};')
productIDs = {}
for name in ['CANConnect','CANConnectTests','CANConnectUITests','CANConnectLiveActivity']:
    ext = 'app' if name == 'CANConnect' else 'appex' if name == 'CANConnectLiveActivity' else 'xctest'
    typ = 'wrapper.application' if ext == 'app' else 'wrapper.cfbundle'
    productIDs[name] = add('product:'+name,'PBXFileReference',f'explicitFileType = {typ}; includeInIndex = 0; path = {name}.{ext}; sourceTree = BUILT_PRODUCTS_DIR;')
products = add('products','PBXGroup',f'children = {array(list(productIDs.values()))}; name = Products; sourceTree = "<group>";')
mainGroup = add('mainGroup','PBXGroup',f'children = {array(list(fileIDs.values())+[products])}; sourceTree = "<group>";')
projectSettings = {
'ALWAYS_SEARCH_USER_PATHS':'NO','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES',
'IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','SWIFT_VERSION':'5.0',
'ENABLE_USER_SCRIPT_SANDBOXING':'YES','SWIFT_STRICT_CONCURRENCY':'minimal'}
def configlist(name, settings):
    ids=[]
    for mode in ['Debug','Release']:
        values = dict(settings)
        values.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if mode=='Debug' else 'dwarf-with-dsym'})
        if name=='project':
            values['ENABLE_TESTABILITY'] = 'YES' if mode=='Debug' else 'NO'
            if mode=='Debug': values['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG $(inherited)'
        body = ' '.join(f'{k} = {q(v)};' for k,v in sorted(values.items()))
        ids.append(add(name+':'+mode,'XCBuildConfiguration',f'buildSettings = {{{body}}}; name = {mode};'))
    return add(name+':configs','XCConfigurationList',f'buildConfigurations = {array(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
projectConfigs = configlist('project',projectSettings)
for name, files in [('CANConnect',appfiles),('CANConnectTests',testfiles),('CANConnectUITests',uifiles),('CANConnectLiveActivity',widgetfiles)]:
    sourcePhase = add(name+':sources','PBXSourcesBuildPhase',f'buildActionMask = 2147483647; files = {array([buildIDs[f.relative_to(ROOT).as_posix()] for f in files])}; runOnlyForDeploymentPostprocessing = 0;')
    resPhase = add(name+':resources','PBXResourcesBuildPhase',f'buildActionMask = 2147483647; files = {array([buildIDs[f.relative_to(ROOT).as_posix()] for f in resources] if name=="CANConnect" else [])}; runOnlyForDeploymentPostprocessing = 0;')
    fwPhase = add(name+':frameworks','PBXFrameworksBuildPhase','buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    settings={'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'com.canconnect.'+('companion' if name=='CANConnect' else name.lower()),'CODE_SIGN_STYLE':'Automatic','TARGETED_DEVICE_FAMILY':'1','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks','GENERATE_INFOPLIST_FILE':'YES'}
    dependencies=[]
    if name=='CANConnect': settings.update({'GENERATE_INFOPLIST_FILE':'NO','INFOPLIST_FILE':'CANConnect/Info.plist','MARKETING_VERSION':'1.0.0','CURRENT_PROJECT_VERSION':'12','ENABLE_PREVIEWS':'YES'})
    elif name=='CANConnectLiveActivity':
        settings.update({'INFOPLIST_FILE':'CANConnectLiveActivity/Info.plist','PRODUCT_BUNDLE_IDENTIFIER':'com.canconnect.companion.recording','MARKETING_VERSION':'1.0.0','CURRENT_PROJECT_VERSION':'12','APPLICATION_EXTENSION_API_ONLY':'YES','SKIP_INSTALL':'YES'})
    else:
        proxy=add(name+':proxy','PBXContainerItemProxy',f'containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("target:CANConnect")}; remoteInfo = CANConnect;')
        dependencies.append(add(name+':dependency','PBXTargetDependency',f'target = {uid("target:CANConnect")}; targetProxy = {proxy};'))
        settings['LD_RUNPATH_SEARCH_PATHS']='$(inherited) @executable_path/Frameworks @loader_path/Frameworks'
        if name=='CANConnectTests': settings.update({'BUNDLE_LOADER':'$(TEST_HOST)','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/CANConnect.app/CANConnect'})
        else: settings['TEST_TARGET_NAME']='CANConnect'
    phases = [sourcePhase,fwPhase,resPhase]
    if name=='CANConnect':
        proxy=add('widget:proxy','PBXContainerItemProxy',f'containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("target:CANConnectLiveActivity")}; remoteInfo = CANConnectLiveActivity;')
        dependencies.append(add('widget:dependency','PBXTargetDependency',f'target = {uid("target:CANConnectLiveActivity")}; targetProxy = {proxy};'))
        embed=add('widget:embed','PBXBuildFile',f'fileRef = {productIDs["CANConnectLiveActivity"]}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy,);}};')
        phases.append(add('widget:copy','PBXCopyFilesBuildPhase',f'buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ({embed},); name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0;'))
    configs = configlist(name,settings)
    ptype = 'com.apple.product-type.application' if name=='CANConnect' else 'com.apple.product-type.bundle.unit-test' if name=='CANConnectTests' else 'com.apple.product-type.app-extension' if name=='CANConnectLiveActivity' else 'com.apple.product-type.bundle.ui-testing'
    add('target:'+name,'PBXNativeTarget',f'buildConfigurationList = {configs}; buildPhases = {array(phases)}; buildRules = (); dependencies = {array(dependencies)}; name = {name}; productName = {name}; productReference = {productIDs[name]}; productType = {q(ptype)};')
attrs = ' '.join(f'{uid("target:"+n)} = {{CreatedOnToolsVersion = 16.0;'+(f'TestTargetID = {uid("target:CANConnect")};' if n in ['CANConnectTests','CANConnectUITests'] else '')+'};' for n in productIDs)
add('project','PBXProject',f'attributes = {{BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{{attrs}}};}}; buildConfigurationList = {projectConfigs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {mainGroup}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {array([uid("target:"+n) for n in productIDs])};')
project = '// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(f'{k} = {{{v}}};' for k,v in sorted(objects.items())) + f'\n}}; rootObject = {uid("project")};}}\n'
(ROOT/'CANConnect.xcodeproj/project.pbxproj').write_text(project)
def ref(n): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target:"+n)}" BuildableName="{n}.{"app" if n=="CANConnect" else "xctest"}" BlueprintName="{n}" ReferencedContainer="container:CANConnect.xcodeproj"/>'
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref('CANConnect')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO" parallelizable="NO">{ref('CANConnectTests')}</TestableReference><TestableReference skipped="NO" parallelizable="NO">{ref('CANConnectUITests')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref('CANConnect')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref('CANConnect')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>
'''
(ROOT/'CANConnect.xcodeproj/xcshareddata/xcschemes/CANConnect.xcscheme').write_text(scheme)
print(f'Generated project with {len(appfiles)} app sources, {len(resources)} resources and two test targets.')
