#!/opt/homebrew/anaconda3/bin/python3
"""Prepare isolated Lathe models for automatically discovered Maven roots."""
from pathlib import Path
import argparse
import contextlib
import fcntl
import hashlib
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET
import zipfile

PYTHON = sys.executable
SCRIPT = Path(__file__).resolve()
CHILD = None
POM_FINGERPRINTS = {}
ANALYSIS_LOMBOK = (1, 18, 38)
COMPATIBLE_COMPILER = '3.13.0'
DEPENDENCY_OVERRIDES = 'dependency-overrides.json'
SKIP = {'.git', '.lathe', 'target', 'node_modules', '.venv', '__pycache__', '.idea', '.gradle',
        '.claude', '.codex', '.agents', '.opencode', '.gitnexus'}


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + '.tmp')
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2))
    tmp.replace(path)


def copy_atomic(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(target.name + '.copy-tmp')
    shutil.copy2(source, tmp)
    tmp.replace(target)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def run(command, cwd=None, env=None, timeout=30):
    return subprocess.run(command, cwd=cwd, env=env, timeout=timeout, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def git(*args, cwd):
    result = run(['git', *args], cwd=cwd, env={**os.environ, 'GIT_OPTIONAL_LOCKS': '0'})
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()


def pom(path):
    tree = ET.parse(path)
    for node in tree.iter():
        node.tag = node.tag.rsplit('}', 1)[-1]
    return tree.getroot()


def module_paths(directory):
    tree = pom(directory / 'pom.xml')
    props = {n.tag: n.text or '' for n in tree.findall('./properties/*')}
    paths = []
    for module in tree.findall('./modules/module') + tree.findall('./profiles/profile/modules/module'):
        value = (module.text or '').strip()
        for _ in range(8):
            changed = re.sub(r'\$\{([^}]+)\}', lambda m: props.get(m[1], m[0]), value)
            if changed == value:
                break
            value = changed
        if value and '${' not in value:
            p = (directory / value).resolve()
            paths.append(p.parent if p.name == 'pom.xml' else p)
    return paths


def discover(filename):
    file = Path(filename).expanduser().resolve()
    start = file if file.is_dir() else file.parent
    probe = run(['git', '-C', str(start), 'rev-parse', '--show-toplevel'])
    repo = Path(probe.stdout.strip()).resolve() if probe.returncode == 0 else None
    if repo in (Path.home(), Path('/')):
        repo = None  # A home-level dotfiles repo is not a Java checkout.
    candidates = []
    for directory in (start, *start.parents):
        if (directory / 'pom.xml').is_file():
            candidates.append(directory)
        if directory == repo or directory == Path.home():
            break
    if not candidates:
        raise RuntimeError('No Maven pom.xml found above this file')
    root = candidates[0]
    for directory in candidates[1:]:
        if root in module_paths(directory):
            root = directory
    # Keep the repository boundary even when the nearest Maven root is nested.
    return root, repo


def context(root, repo, args):
    identity = hashlib.sha256(str(root).encode()).hexdigest()[:20]
    state = (Path(args.state_root).expanduser().resolve() / 'projects' / identity)
    if repo:
        sandbox = Path(args.worktree_root).expanduser().resolve() / ('lathe-' + identity)
        build_repo = sandbox / repo.name
        build = build_repo / root.relative_to(repo)
    else:
        sandbox = state
        build_repo = state / 'build'
        build = build_repo
    return {'id': identity, 'source': str(root), 'checkout': str(repo or root),
            'git': repo is not None, 'state': str(state), 'build_repository': str(build_repo),
            'build': str(build), 'sandbox': str(sandbox), 'analysis': str(state / 'live'),
            'cache': str(state / 'cache'), 'model_ready': (state / 'live/.lathe/workspace.json').is_file()}


def prepare_paths(info, args):
    global TRIAL, SOURCE, WORKTREE, LIVE, SHARED_REPO, RESOURCES, JDK, PROJECT_JDK, CHECKOUT, BUILD_REPO
    TRIAL = Path(info['state']); SOURCE = Path(info['source']); WORKTREE = Path(info['build'])
    CHECKOUT = Path(info['checkout']); BUILD_REPO = Path(info['build_repository']); LIVE = Path(info['analysis'])
    RESOURCES = Path(args.resources).expanduser().resolve()
    SHARED_REPO = RESOURCES / 'vim-trial/m2'
    JDK = Path('/Library/Java/JavaVirtualMachines/zulu-21.jdk/Contents/Home')
    PROJECT_JDK = Path('/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home')
    TRIAL.mkdir(parents=True, exist_ok=True, mode=0o700)
    (TRIAL / 'logs').mkdir(exist_ok=True)
    identity_file = TRIAL / 'identity.json'
    if identity_file.exists():
        old = json.loads(identity_file.read_text())
        for key in ('source', 'checkout', 'build_repository'):
            if old[key] != info[key]:
                raise RuntimeError('Analysis identity mismatch: ' + key)
    else:
        atomic_json(identity_file, info)


def create_build(info):
    if info['git']:
        if BUILD_REPO.exists():
            if not (BUILD_REPO / '.git').is_file():
                raise RuntimeError('Existing analysis directory is not a managed worktree: ' + str(BUILD_REPO))
            if git('rev-parse', '--git-common-dir', cwd=BUILD_REPO) != git('rev-parse', '--path-format=absolute', '--git-common-dir', cwd=CHECKOUT):
                # rev-parse from a linked worktree normally already returns an absolute common dir.
                a = Path(git('rev-parse', '--git-common-dir', cwd=BUILD_REPO))
                b = Path(git('rev-parse', '--git-common-dir', cwd=CHECKOUT))
                if (BUILD_REPO / a).resolve() != (CHECKOUT / b).resolve():
                    raise RuntimeError('Worktree repository identity mismatch')
        else:
            BUILD_REPO.parent.mkdir(parents=True, exist_ok=True)
            git('worktree', 'add', '--detach', str(BUILD_REPO), 'HEAD', cwd=CHECKOUT)
    else:
        BUILD_REPO.mkdir(parents=True, exist_ok=True)


def source_files():
    for directory, dirs, files in os.walk(CHECKOUT, followlinks=False):
        dirs[:] = [n for n in dirs if n not in SKIP]
        for name in list(dirs):
            p = Path(directory) / name
            if p.is_symlink():
                dirs.remove(name)
                yield p
        for name in files:
            if name not in {'.git', '.DS_Store'}:
                yield Path(directory) / name


def signature(path):
    if path.is_symlink():
        return 'link:' + os.readlink(path)
    return digest(path)


def sync_source():
    record = TRIAL / 'managed-inputs.json'
    old = json.loads(record.read_text()) if record.exists() else {}
    wanted = {}
    for src in source_files():
        name = str(src.relative_to(CHECKOUT)); dst = BUILD_REPO / name
        if src.is_symlink():
            resolved = src.resolve()
            if not resolved.is_relative_to(CHECKOUT):
                raise RuntimeError('External source symlink cannot be mirrored safely: ' + name)
            target = os.path.relpath(BUILD_REPO / resolved.relative_to(CHECKOUT), dst.parent)
            wanted[name] = ('link:' + target, src)
        else:
            wanted[name] = (digest(src), src)
    changes = []
    removed_java = False
    for name in set(old) | set(wanted):
        dst = BUILD_REPO / name; expected = wanted.get(name, (None, None))[0]; actual = signature(dst)
        if name in old and actual not in (old[name], expected):
            raise RuntimeError('Analysis input was edited independently; refusing overwrite: ' + name)
        if actual != expected:
            changes.append((name, expected))
            removed_java |= expected is None and name.endswith(('.java', '.groovy'))
    for name, expected in changes:
        dst = BUILD_REPO / name
        if expected is None:
            dst.unlink(missing_ok=True)
        elif expected.startswith('link:'):
            dst.parent.mkdir(parents=True, exist_ok=True); dst.unlink(missing_ok=True); dst.symlink_to(expected[5:])
        else:
            copy_atomic(wanted[name][1], dst)
    atomic_json(record, {name: item[0] for name, item in wanted.items()})
    return removed_java


def validate_outputs(info):
    # Reject explicit destinations escaping the private sandbox before running any build.
    sandbox = Path(info['sandbox']).resolve()
    for source_pom in CHECKOUT.rglob('pom.xml'):
        if not source_pom.is_relative_to(SOURCE) and not SOURCE.is_relative_to(source_pom.parent):
            continue
        relative = source_pom.relative_to(CHECKOUT)
        if any(p in SKIP for p in relative.parts):
            continue
        directory = BUILD_REPO / relative.parent
        tree = pom(source_pom)
        props = {n.tag: n.text or '' for n in tree.findall('./properties/*')}
        props.update({'basedir': str(directory), 'project.basedir': str(directory),
                      'project.parent.basedir': str(directory.parent), 'user.home': str(Path.home()),
                      'project.build.directory': str(directory / 'target')})
        nodes = tree.findall('./build/directory') + tree.findall('./build/outputDirectory') + tree.findall('./build/testOutputDirectory')
        nodes += tree.findall('.//plugin/configuration/outputDirectory') + tree.findall('.//plugin/configuration/generatedSourcesDirectory')
        for node in nodes:
            value = (node.text or '').strip()
            for _ in range(8):
                nxt = re.sub(r'\$\{([^}]+)\}', lambda m: props.get(m[1], m[0]), value)
                if nxt == value:
                    break
                value = nxt
            if not value:
                continue
            if '${' in value:
                # A literal absolute prefix remains unsafe even with unresolved properties.
                if value.startswith('/'):
                    raise RuntimeError('Unresolved absolute build output: ' + value)
                continue
            if not (directory / value).resolve().is_relative_to(sandbox):
                raise RuntimeError('Build output escapes the isolated directory: ' + value)


def refresh_local_dependencies():
    with (RESOURCES / 'vim-trial/repository-sync.lock').open('a+') as lock:
        fcntl.lockf(lock, fcntl.LOCK_EX)
        origin = Path.home() / '.m2/repository'
        for directory, _, files in os.walk(origin):
            for name in files:
                src = Path(directory) / name
                if src.is_symlink() or not name.endswith(('.jar', '.pom', '.xml')):
                    continue
                dst = SHARED_REPO / src.relative_to(origin)
                a = src.stat(); b = dst.stat() if dst.exists() else None
                if b and (a.st_mtime_ns, a.st_size) == (b.st_mtime_ns, b.st_size):
                    continue
                if name.endswith('-sources.jar') and not zipfile.is_zipfile(src):
                    continue
                copy_atomic(src, dst)
        # Cached range metadata may belong to a different mirror ID. Publish only
        # locally available versions as local metadata; Maven stays strictly offline.
        handled = set()
        for metadata in SHARED_REPO.rglob('maven-metadata-*.xml'):
            directory = metadata.parent
            if directory in handled:
                continue
            try:
                data = ET.parse(metadata).getroot()
            except ET.ParseError:
                continue
            if data.find('versioning/versions') is None:
                continue
            group, artifact = data.findtext('groupId'), data.findtext('artifactId')
            if not group or not artifact:
                continue
            handled.add(directory)
            versions = sorted(p.name for p in directory.iterdir() if p.is_dir()
                              and any(p.glob(artifact + '-*.pom')))
            if not versions:
                continue
            local = ET.Element('metadata')
            ET.SubElement(local, 'groupId').text = group
            ET.SubElement(local, 'artifactId').text = artifact
            versioning = ET.SubElement(local, 'versioning')
            entries = ET.SubElement(versioning, 'versions')
            for version in versions:
                ET.SubElement(entries, 'version').text = version
            text = ET.tostring(local, encoding='unicode')
            target = directory / 'maven-metadata-local.xml'
            if not target.exists() or target.read_text() != text:
                temp = target.with_suffix('.xml.tmp'); temp.write_text(text); temp.replace(target)


def watch_files(info):
    paths = [str(p) for p in CHECKOUT.rglob('pom.xml') if not any(x in SKIP for x in p.relative_to(CHECKOUT).parts)]
    paths += [str(p) for p in CHECKOUT.rglob('lombok.config') if not any(x in SKIP for x in p.relative_to(CHECKOUT).parts)]
    paths += [str(SOURCE / 'lombok.config'), str(Path.home() / '.m2/settings.xml'),
              str(TRIAL / DEPENDENCY_OVERRIDES)]
    for directory in (SOURCE, *SOURCE.parents):
        paths += [str(directory / '.mvn' / name) for name in ('maven.config', 'jvm.config', 'extensions.xml')]
        if directory == CHECKOUT:
            break
    return sorted(set(paths))


def file_stat(path):
    try:
        s = Path(path).stat()
        return f'{path}:{s.st_size}:{s.st_mtime_ns // 1000000000}:{s.st_mtime_ns % 1000000000}'
    except FileNotFoundError:
        return path + ':missing'


def missing_dependencies(log):
    coordinate = re.compile(
        r'([\w-]+(?:\.[\w-]+)*):([\w.-]+):(jar|pom|maven-plugin):'
        r'(?:([\w.+-]+):)?([\w.+-]+)'
    )
    paths, first = set(), None
    for line in log.splitlines():
        if not (re.match(r'^\[ERROR\]\s+dependency:', line)
                or (line.startswith('[ERROR]') and re.search(
                    r'\b(?:absent|offline mode|not been downloaded|could not find|non-resolvable parent POM)\b',
                    line, re.I))):
            continue
        for group, artifact, kind, classifier, version in coordinate.findall(line):
            if artifact in {'.', '..'} or version in {'.', '..'}:
                continue
            identifier = f'{group}:{artifact}:{version}'
            first = first or identifier
            relative = Path(group.replace('.', '/')) / artifact / version
            stem = f'{artifact}-{version}'
            names = [stem + '.pom']
            if kind != 'pom':
                names.append(stem + (f'-{classifier}' if classifier else '') + '.jar')
            for repository in (Path.home() / '.m2/repository', SHARED_REPO):
                paths.update(str(repository / relative / name) for name in names)
    return first, paths


CRC_TABLE = []


for _n in range(256):
    for _ in range(8):
        _n = (_n >> 1) ^ (0x82F63B78 if _n & 1 else 0)
    CRC_TABLE.append(_n)


def fingerprint(path):
    data = path.read_bytes()
    crc = 0xFFFFFFFF
    for byte in data:
        crc = CRC_TABLE[(crc ^ byte) & 255] ^ (crc >> 8)
    return {"size": len(data), "checksum": crc ^ 0xFFFFFFFF}


def capture_compatibility(log, previous):
    """Keep compatibility decisions tied to concrete failures in this project's capture."""
    modules = set(previous.get('compiler_modules', ()))
    for names in re.findall(r'maven-compiler-plugin [\w.-]+ \(([^)]+)\) is older than', log):
        modules.update(name.strip() for name in names.split(','))
    native_git = {}
    for coordinate in previous.get('native_git', ()):
        group, artifact, *versions = coordinate.split(':')
        if not versions:
            # Older captures recorded the plugin identity without its version.
            versions = re.findall(r'--- git-commit-id:([\w.-]+):revision', log)
        if versions:
            native_git[f'{group}:{artifact}'] = versions[0]
    for group, artifact, version in re.findall(
            r'Failed to execute goal ([\w.-]+):(git-commit-id-(?:maven-)?plugin):([\w.-]+):[^\n]+Missing unknown', log):
        native_git[f'{group}:{artifact}'] = version
    javafx = previous.get('javafx', False) or bool(re.search(r'package javafx\.[\w.]+ does not exist', log))
    class_versions = re.findall(r'class file has wrong version (\d+)\.\d+, should be 52\.0', log)
    maven_java = previous.get('maven_java', False) or any(int(version) > 52 for version in class_versions)
    return {'compiler_modules': sorted(modules),
            'native_git': [f'{key}:{value}' for key, value in sorted(native_git.items())],
            'javafx': javafx, 'maven_java': maven_java}


def capture_jdk(compatibility):
    if compatibility['maven_java']:
        return JDK
    if not compatibility['javafx']:
        return PROJECT_JDK
    for home in sorted(PROJECT_JDK.parents[2].glob('*.jdk/Contents/Home')):
        release = home / 'release'
        if (release.is_file() and 'JAVA_VERSION="1.8.' in release.read_text()
                and (home / 'bin/javac').is_file() and (home / 'jre/lib/ext/jfxrt.jar').is_file()):
            return home
    raise RuntimeError('This project needs a local Java 8 JDK with JavaFX for Lathe capture')


def local_dependency_overrides():
    config = TRIAL / DEPENDENCY_OVERRIDES
    overrides = {}
    if config.is_file():
        for item in json.loads(config.read_text()):
            relative = Path(item['pom'])
            coordinate = (item['groupId'], item['artifactId'])
            versions = (item['from'], item['to'])
            if (relative.is_absolute() or '..' in relative.parts or relative.name != 'pom.xml'
                    or not (BUILD_REPO / relative).resolve().is_relative_to(WORKTREE)):
                raise RuntimeError('Dependency override must select a POM inside the analysis reactor')
            if not all(re.fullmatch(r'[A-Za-z0-9][\w.+-]*', part) for part in (*coordinate, *versions)):
                raise RuntimeError('Dependency overrides require literal Maven coordinates')
            module = overrides.setdefault(relative, {})
            if coordinate in module:
                raise RuntimeError('Duplicate local dependency override: ' + ':'.join(coordinate))
            module[coordinate] = versions
    return overrides


def build_compatibility(compatibility, build_jdk, overrides, log):
    """Adapt compiler and Git plugin settings in the managed build copy only."""
    records = json.loads((TRIAL / 'managed-inputs.json').read_text())
    changes = {}
    applied = []
    for path in BUILD_REPO.rglob('pom.xml'):
        rel = path.relative_to(BUILD_REPO)
        original = CHECKOUT / rel
        if any(part in SKIP for part in rel.parts) or not original.is_file():
            continue
        if not original.is_relative_to(SOURCE) and not SOURCE.is_relative_to(original.parent):
            continue
        key = str(original)
        if key not in POM_FINGERPRINTS:
            POM_FINGERPRINTS[key] = fingerprint(path)
        tree = ET.parse(path); root = tree.getroot()
        ns = root.tag.split('}')[0] + '}' if root.tag.startswith('{') else ''

        def child(parent, name):
            node = parent.find(ns + name)
            return node if node is not None else ET.SubElement(parent, ns + name)

        before = ET.tostring(root)
        module_overrides = overrides.get(rel, {})
        override_active = False
        for dep in root.findall(f'./{ns}dependencies/{ns}dependency'):
            coordinate = (dep.findtext(ns + 'groupId'), dep.findtext(ns + 'artifactId'))
            versions = module_overrides.get(coordinate)
            version = dep.find(ns + 'version')
            if versions and version is not None and version.text == versions[0]:
                version.text = versions[1]
                override_active = True
                applied.append(f'{rel}: {":".join(coordinate)} {versions[0]} -> {versions[1]}')
        legacy_compiler = root.findtext(ns + 'artifactId') in compatibility['compiler_modules']
        if legacy_compiler or override_active:
            plugins = child(child(root, 'build'), 'plugins')
            compiler = next((node for node in plugins.findall(ns + 'plugin')
                             if node.findtext(ns + 'artifactId') == 'maven-compiler-plugin'), None)
            if compiler is None:
                compiler = ET.SubElement(plugins, ns + 'plugin')
                child(compiler, 'artifactId').text = 'maven-compiler-plugin'
            if legacy_compiler:
                child(compiler, 'version').text = COMPATIBLE_COMPILER
            if override_active:
                # Even a navigation-only reactor retry must compile this module successfully.
                child(child(compiler, 'configuration'), 'failOnError').text = 'true'

        for coordinate in compatibility['native_git']:
            group, artifact, version = coordinate.split(':')
            # Maven's JGit implementation cannot read the objects of some linked worktrees.
            # Supply a default for inherited plugins and fix explicit local configurations.
            managed = child(child(child(root, 'build'), 'pluginManagement'), 'plugins')
            plugins = [node for node in root.iter(ns + 'plugin')
                       if node.findtext(ns + 'groupId') == group and node.findtext(ns + 'artifactId') == artifact]
            if not any(node in list(managed) for node in plugins):
                plugin = ET.SubElement(managed, ns + 'plugin')
                child(plugin, 'groupId').text = group
                child(plugin, 'artifactId').text = artifact
                child(plugin, 'version').text = version
                plugins.append(plugin)
            for plugin in plugins:
                child(child(plugin, 'configuration'), 'useNativeGit').text = 'true'
                for config in plugin.findall(f'./{ns}executions/{ns}execution/{ns}configuration'):
                    child(config, 'useNativeGit').text = 'true'

        legacy_plugins = () if compatibility['maven_java'] else root.iter(ns + 'plugin')
        for plugin in legacy_plugins:
            if plugin.findtext(ns + 'artifactId') != 'maven-compiler-plugin':
                continue
            for config in plugin.iter(ns + 'configuration'):
                bootclasspath = config.find(f'{ns}compilerArguments/{ns}bootclasspath')
                if bootclasspath is not None and bootclasspath.text:
                    # Maven runs on a modern JDK, while the forked compiler uses Java 8.
                    for archive in ('rt.jar', 'jce.jar'):
                        bootclasspath.text = bootclasspath.text.replace(
                            '${java.home}/lib/' + archive, str(build_jdk / 'jre/lib' / archive))
                release = config.find(ns + 'release')
                fork = config.findtext(ns + 'fork')
                executable = config.findtext(ns + 'executable')
                if release is None and fork != 'false' and not executable:
                    continue
                if release is not None:
                    value = (release.text or '').strip()
                    if value and '${' not in value and value not in ('8', '1.8'):
                        raise RuntimeError('Automatic analysis is configured for Java 8, not release ' + value)
                    config.remove(release)
                for name, value in [('source', '1.8'), ('target', '1.8'), ('fork', 'true'),
                                    ('executable', str(build_jdk / 'bin/javac'))]:
                    child(config, name).text = value
        if ET.tostring(root) != before:
            if ns:
                ET.register_namespace('', ns[1:-1])
            changes[path] = ET.tostring(root, encoding='utf-8', xml_declaration=True)
    for path, content in changes.items():
        temporary = path.with_name('pom.xml.lathe-tmp')
        temporary.write_bytes(content)
        temporary.replace(path)
        records[str(path.relative_to(BUILD_REPO))] = hashlib.sha256(content).hexdigest()
    atomic_json(TRIAL / 'managed-inputs.json', records)
    if applied:
        with log.open('a') as stream:
            for item in applied:
                stream.write('[Lathe analysis dependency override] ' + item + '\n')
    return applied


def attach_legacy_jdk_sources(workspace, capture, cache):
    """Associate pre-module JDK classes with their own sources, without changing attribution."""
    jdk_home = Path(capture["build_jdk"])
    runtime = jdk_home / "jre/lib/rt.jar"
    archive = jdk_home / "src.zip"
    if not runtime.is_file() or not archive.is_file():
        return False
    key = hashlib.sha256(file_stat(str(archive)).encode()).hexdigest()[:20]
    source_dir = cache / key
    cache.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (cache / "extract.lock").open("a+") as lock:
        fcntl.lockf(lock, fcntl.LOCK_EX)
        if not source_dir.is_dir():
            with tempfile.TemporaryDirectory(prefix="extract-", dir=cache) as scratch:
                staging = Path(scratch) / "sources"
                staging.mkdir()
                with zipfile.ZipFile(archive) as sources:
                    if "java/lang/Object.java" not in sources.namelist():
                        return False
                    for entry in sources.infolist():
                        path = Path(entry.filename)
                        if path.suffix == ".java" and not path.is_absolute() and ".." not in path.parts:
                            sources.extract(entry, staging)
                staging.rename(source_dir)
    entries = workspace.setdefault("dependencySources", [])
    entry = {"gav": "jdk:rt:8", "jar": str(runtime), "status": "PRESENT", "dir": str(source_dir),
             "classpath": [str(runtime)], "typeIndex": None}
    for index, existing in enumerate(entries):
        if existing["jar"] == str(runtime):
            if existing == entry:
                return False
            entries[index] = entry
            return True
    entries.append(entry)
    return True


def publish_live(stale_params=()):
    """Publish metadata under the same record lock used by Lathe's writer."""
    raw = WORKTREE / ".lathe"
    workspace = json.loads((raw / "workspace.json").read_text())
    capture = json.loads((TRIAL / "capture-result.json").read_text())
    attach_legacy_jdk_sources(workspace, capture, TRIAL.parents[1] / "legacy-jdk-sources")
    generation = digest(TRIAL / "capture-result.json")
    state_path = LIVE / "live-state.json"
    if state_path.exists() and json.loads(state_path.read_text()).get("generation") == generation:
        return
    stage = TRIAL / "live-staging"
    if stage.exists():
        shutil.rmtree(stage)
    shutil.copytree(raw, stage, ignore=shutil.ignore_patterns("*.lock", "*.log", "*.pid", "lathe.lock"))
    for rel in stale_params:
        params = stage / rel
        source_tree = params.stem.removeprefix('lsp-params-')
        generated = 'generated-test-sources' if source_tree == 'test-classes' else 'generated-sources'
        params.unlink()
        params.with_name(f'lsp-stamps-{source_tree}.json').unlink(missing_ok=True)
        for name in (source_tree, generated):
            mirror = params.with_name(name)
            if mirror.is_dir():
                shutil.rmtree(mirror)
    for output in workspace.get("outputs", []):
        output["path"] = str(WORKTREE / output["path"])
    for resource in workspace.get("resourceRoots", []):
        resource["directory"] = str(SOURCE / resource["directory"])
        resource["outputDir"] = str(WORKTREE / resource["outputDir"])
    watched = set()
    build_fingerprints = {}
    for build in workspace.get("buildFiles", []):
        path = Path(build["path"])
        if not path.is_absolute():
            path = SOURCE / path
        elif path.is_relative_to(WORKTREE):
            path = SOURCE / path.relative_to(WORKTREE)
        build["path"] = str(path)
        if str(path.resolve()) in POM_FINGERPRINTS:
            build["fingerprint"] = POM_FINGERPRINTS[str(path.resolve())]
        watched.add(str(path))
        build_fingerprints[str(path)] = build.get("fingerprint")
    for params_path in stage.rglob("lsp-params-*.json"):
        params = json.loads(params_path.read_text())
        params["sourceRoots"] = [str(SOURCE / Path(p).relative_to(WORKTREE))
                                 if Path(p).is_relative_to(WORKTREE) and "target" not in Path(p).relative_to(WORKTREE).parts
                                 else p for p in params["sourceRoots"]]
        # Pure path migration must not invalidate byte-for-byte identical captures.
        stamps_path = params_path.with_name(params_path.name.replace("params", "stamps"))
        if stamps_path.exists():
            stamps = json.loads(stamps_path.read_text())
            for name, stamp in stamps.get("stamps", {}).items():
                for root in params["sourceRoots"]:
                    p = Path(root) / name
                    if p.is_file():
                        before = p.stat()
                        content = fingerprint(p)
                        after = p.stat()
                        identity = lambda s: (s.st_ino, s.st_size, s.st_mtime_ns)
                        if identity(before) == identity(after) and content == stamp.get("content"):
                            stamp["mtime"] = before.st_mtime_ns // 1000000
                            break
            atomic_json(stamps_path, stamps)
        atomic_json(params_path, params)
        for p in params.get("classpath", []) + params.get("processorPath", []):
            path = Path(p)
            if path.is_relative_to(SHARED_REPO):
                original = Path.home() / ".m2/repository" / path.relative_to(SHARED_REPO)
                if original.exists():
                    watched.add(str(original))
                    watched.add(str(original.with_suffix(".pom")))
    workspace["workspaceRoot"] = str(LIVE)
    # Same-coordinate SNAPSHOT jars may change without a classpath string change.
    # The pinned server ignores unknown fields but reloads on manifest content change.
    workspace["liveCaptureGeneration"] = generation
    atomic_json(stage / "workspace.json", workspace)
    sync = stage / "lathe-sync.sh"
    command = [PYTHON, str(SCRIPT), 'prepare', '--root', str(SOURCE), *COMMON_ARGS]
    sync.write_text('#!/bin/sh\nexec ' + shlex.join(command) + '\n')
    sync.chmod(0o700)
    destination = LIVE / ".lathe"
    destination.mkdir(parents=True, exist_ok=True)
    with (destination / "write.lock").open("a+") as lock:
        deadline = time.monotonic() + 90
        while True:
            try:
                fcntl.lockf(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() > deadline:
                    raise RuntimeError("Lathe is busy; publication timed out")
                time.sleep(0.15)
        # Replace complete files, keep the lock inode, and publish the manifest last.
        staged = {p.relative_to(stage) for p in stage.rglob("*") if p.is_file()}
        for p in destination.rglob("*"):
            if p.is_file() and p.name != "write.lock" and p.relative_to(destination) not in staged:
                p.unlink()
        for rel in sorted(staged - {Path("workspace.json")}):
            copy_atomic(stage / rel, destination / rel)
        copy_atomic(stage / "workspace.json", destination / "workspace.json")
    values = []
    for name in sorted(watched):
        path = Path(name)
        stat_path = path
        if path.is_relative_to(Path.home() / ".m2/repository"):
            stat_path = SHARED_REPO / path.relative_to(Path.home() / ".m2/repository")
        if name in build_fingerprints and path.is_file() and fingerprint(path) != build_fingerprints[name]:
            values.append(name + ":capture-differs")
        elif stat_path.is_file():
            s = stat_path.stat()
            values.append(f"{name}:{s.st_size}:{s.st_mtime_ns // 1000000000}:{s.st_mtime_ns % 1000000000}")
        else:
            values.append(name + ":missing")
    atomic_json(state_path, {"source": str(SOURCE), "build": str(WORKTREE), "generation": generation,
                            "analysis_lombok": list(ANALYSIS_LOMBOK),
                            "watch": sorted(watched), "watch_values": values, "published_at": time.time()})
    shutil.rmtree(stage)


def stop_owned_child(signum=None, frame=None):
    if CHILD is not None:
        with contextlib.suppress(ProcessLookupError):
            os.killpg(CHILD.pid, signal.SIGTERM)
        try:
            CHILD.wait(timeout=4)
        except subprocess.TimeoutExpired:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(CHILD.pid, signal.SIGKILL)
            CHILD.wait()
    if signum is not None:
        raise SystemExit(128 + signum)



def owned(command, cwd, log, timeout=600):
    global CHILD
    try:
        with log.open('a') as stream:
            CHILD = subprocess.Popen(command, cwd=cwd, env=BUILD_ENV, stdout=stream,
                                     stderr=subprocess.STDOUT, start_new_session=True)
            return CHILD.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        stop_owned_child()
        return 124
    finally:
        stop_owned_child()
        CHILD = None


def compiler_targets(log):
    # Lathe's Maven capture records --release but omits explicit -source/-target.
    targets = {}
    module = None
    for line in log.read_text(errors='replace').splitlines():
        if line.startswith('[INFO] --- '):
            match = re.match(r'\[INFO\] --- (?:maven-)?compiler:[^:]+:compile .* @ (\S+) ---', line)
            module = match[1] if match else None
        if module and line.startswith('[INFO] Compiling '):
            level = re.search(r'\b(?:target|release) (?:1\.)?(\d+)\]', line)
            if level:
                targets[module] = level[1]
    return targets


def analysis_parameters(build_jdk, maven_java, log, stale_params):
    version_text = '.'.join(map(str, ANALYSIS_LOMBOK))
    default_lombok = SHARED_REPO / f'org/projectlombok/lombok/{version_text}/lombok-{version_text}.jar'
    binding = SHARED_REPO / 'org/projectlombok/lombok-mapstruct-binding/0.2.0/lombok-mapstruct-binding-0.2.0.jar'
    raw = WORKTREE / '.lathe'
    targets = compiler_targets(log) if maven_java else {}
    releases = set()
    for path in raw.rglob('lsp-params-*.json'):
        if path.relative_to(raw) in stale_params:
            continue
        value = json.loads(path.read_text())
        if not maven_java:
            value['release'] = '8'
            value.pop('source', None); value.pop('target', None)
        elif not value.get('release'):
            descriptor = WORKTREE / path.parent.relative_to(raw) / 'pom.xml'
            if descriptor.is_file():
                target = targets.get(pom(descriptor).findtext('artifactId'))
                if target:
                    value['release'] = target
        level = str(value.get('release') or value.get('target') or value.get('source') or '').removeprefix('1.')
        if level.isdigit():
            releases.add(int(level))
        for key in ('classpath', 'processorPath'):
            updated = []
            for item in value.get(key, []):
                if '/org/projectlombok/lombok/' in item:
                    version = re.search(r'lombok-(\d+)\.(\d+)\.(\d+)', Path(item).name)
                    # The live compiler needs @lombok.Generated to link accessors to fields.
                    if not version or tuple(map(int, version.groups())) < ANALYSIS_LOMBOK:
                        if not default_lombok.is_file():
                            raise RuntimeError(f'Lathe analysis requires Lombok {version_text} in the local Maven cache')
                        item = str(default_lombok)
                updated.append(item)
            value[key] = updated
        for runtime in (build_jdk / 'jre/lib/rt.jar', build_jdk / 'jre/lib/ext/jfxrt.jar'):
            if runtime.is_file() and str(runtime) not in value['classpath']:
                value['classpath'].append(str(runtime))
        processors = value.get('processorPath') or value['classpath']
        if str(binding) not in processors:
            processors.append(str(binding))
        atomic_json(path, value)
    return sorted(releases)


def prepare(info, args):
    global BUILD_ENV
    prepare_paths(info, args)
    guard = (TRIAL / 'prepare.lock').open('a+')
    try:
        fcntl.lockf(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return {**info, 'status': 'busy'}, 75
    signal.signal(signal.SIGTERM, stop_owned_child); signal.signal(signal.SIGINT, stop_owned_child)
    if BUILD_REPO.is_relative_to(CHECKOUT):
        raise RuntimeError('Analysis build directory must be outside the original checkout')
    old_state = json.loads((TRIAL / 'state.json').read_text()) if (TRIAL / 'state.json').exists() else {}
    initial_watch = sorted(set(watch_files(info)) | set(old_state.get('input_stats', {}))
                           | set(old_state.get('dependency_watch', [])))
    initial_stats = {p: file_stat(p) for p in initial_watch}
    previous = old_state.get('input_stats', {})
    build_changed = any(previous.get(p) != v and (p in previous or not v.endswith(':missing'))
                        for p, v in initial_stats.items())
    configuration_changed = any(previous.get(p) != v and (p in previous or not v.endswith(':missing'))
                                for p, v in initial_stats.items()
                                if Path(p).name in {'pom.xml', 'maven.config', 'extensions.xml', 'settings.xml'})
    result = {**info, 'status': 'preparing', 'pid': os.getpid(), 'watch': initial_watch,
              'watch_values': list(initial_stats.values()), 'input_stats': initial_stats}
    log = TRIAL / 'logs/capture.log'
    prior_log = log.read_text(errors='replace') if log.exists() and not configuration_changed else ''
    prior_compatibility = {} if configuration_changed else old_state.get('capture_compatibility', {})
    compatibility = capture_compatibility(prior_log, prior_compatibility)
    atomic_json(TRIAL / 'state.json', result)
    log.write_text('')
    started = time.monotonic()
    BUILD_ENV = {**os.environ, 'JAVA_HOME': str(JDK), 'LATHE_JAVA_HOME': str(JDK),
                 'LATHE_CACHE': str(TRIAL / 'cache'), 'GIT_OPTIONAL_LOCKS': '0'}
    for name in ('MAVEN_OPTS', 'JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS'):
        BUILD_ENV.pop(name, None)
    try:
        # Worktree creation is the only Git mutation, entirely in the private analysis namespace.
        if info['git'] and not BUILD_REPO.exists():
            BUILD_REPO.parent.mkdir(parents=True, exist_ok=True)
            code = owned(['git', 'worktree', 'add', '--detach', str(BUILD_REPO), 'HEAD'], CHECKOUT, log, 180)
            if code:
                raise RuntimeError('Could not create the private Git worktree; see capture.log')
        create_build(info)
        removed_java = sync_source()
        validate_outputs(info)
        refresh_local_dependencies()
        overrides = local_dependency_overrides()
        # Maven skips unchanged compiles, so retain their captures. The official
        # full-reactor sync already prunes removed modules and source trees.
        raw = WORKTREE / '.lathe'
        if raw.is_symlink():
            raise RuntimeError('Refusing a symlink at the private metadata directory')
        needs_capture = not (raw / 'workspace.json').is_file()
        extension_paths = (RESOURCES / 'extension-classpath.txt').read_text().strip().split(os.pathsep)
        extension = os.pathsep.join(str(SHARED_REPO / Path(p).relative_to(RESOURCES / 'm2')) for p in extension_paths)
        clean = (args.clean or removed_java or needs_capture or old_state.get('navigation_only')
                 or (old_state.get('input_stats') and build_changed))
        navigation_only = False
        manifest = raw / 'workspace.json'
        for attempt in range(4):
            result['capture_compatibility'] = compatibility
            build_jdk = capture_jdk(compatibility)
            applied_overrides = build_compatibility(compatibility, build_jdk, overrides, log)
            if compatibility['maven_java'] and not raw.exists():
                reactor = pom(WORKTREE / 'pom.xml')
                if (reactor.find('parent') is None and reactor.find('modules/module') is not None
                        and not any(reactor.iter('lathe.disabled'))):
                    # An aggregator that is not a module parent can run lathe:init after its modules.
                    raw.mkdir()
            command = ['/opt/homebrew/bin/mvn', '-o', '-B', '-ntp',
                       '-Dmaven.repo.local=' + str(SHARED_REPO), '-Dmaven.ext.class.path=' + extension,
                       '-Dlathe.cache=' + str(TRIAL / 'cache'), '-Dlathe.disabled=false',
                       '-Dmaven.compiler.fork=true', '-Dmaven.compiler.executable=' + str(build_jdk / 'bin/javac'),
                       '-Dmaven.test.skip=true', '-DskipTests=true', '-Djacoco.skip=true']
            if not compatibility['maven_java']:
                command.extend(['-Dmaven.compiler.source=1.8', '-Dmaven.compiler.target=1.8', '-Dmaven.compiler.release='])
            if navigation_only:
                command.extend(['--fail-at-end', '-Dmaven.compiler.failOnError=false'])
            if clean or attempt:
                command.append('clean')
            offset = log.stat().st_size
            previous_manifest = file_stat(str(manifest))
            attempt_started_ns = time.time_ns()
            code = owned([*command, 'process-test-classes'], WORKTREE, log)
            if code == 0:
                break
            with log.open('rb') as stream:
                stream.seek(offset)
                attempt_log = stream.read().decode(errors='replace')
            retry = capture_compatibility(attempt_log, compatibility)
            if retry == compatibility:
                # Lathe still records javac parameters when Java source has unresolved symbols.
                # Build the source index, and keep the project's actual compile errors visible.
                if navigation_only or 'COMPILATION ERROR' not in attempt_log or 'cannot find symbol' not in attempt_log:
                    break
                navigation_only = True
            else:
                compatibility = retry
            sync_source()
        # A failed reactor can still sync an index for its independent modules. Only
        # publish a manifest written by this invocation, and keep Maven's failure visible.
        partial_model = bool(code and navigation_only and manifest.is_file()
                             and file_stat(str(manifest)) != previous_manifest)
        if code != 0 and not partial_model:
            raise RuntimeError('Offline Maven capture failed; original POM and Lombok were not changed')
        if not manifest.is_file():
            raise RuntimeError('Maven completed without producing a Lathe workspace model')
        stale_params = set()
        if partial_model:
            params = list(raw.rglob('lsp-params-*.json'))
            stale_params = {p.relative_to(raw) for p in params if p.stat().st_mtime_ns < attempt_started_ns}
            if len(stale_params) == len(params):
                raise RuntimeError('The failed Maven build produced no fresh Java compiler parameters')
        releases = analysis_parameters(build_jdk, compatibility['maven_java'], log, stale_params)
        atomic_json(TRIAL / 'capture-result.json', {'exit_code': code, 'time_ns': time.time_ns(),
                    'source': str(SOURCE), 'build_jdk': str(build_jdk), 'analysis_releases': releases,
                    'navigation_only': navigation_only, 'partial_model': partial_model,
                    'dependency_overrides': applied_overrides,
                    'analysis_lombok': list(ANALYSIS_LOMBOK)})
        publish_live(stale_params)
        live_state = json.loads((LIVE / 'live-state.json').read_text())
        extra = {name: value for name, value in zip(live_state['watch'], live_state['watch_values'])}
        extra.update(initial_stats)
        live_state['watch'] = sorted(extra)
        live_state['watch_values'] = [extra[p] for p in live_state['watch']]
        atomic_json(LIVE / 'live-state.json', live_state)
        result.update(status='ready', model_ready=True, java_releases=releases,
                      navigation_only=navigation_only, partial_model=partial_model,
                      dependency_override_count=len(applied_overrides),
                      watch=live_state['watch'], watch_values=live_state['watch_values'])
    except BaseException as error:
        result.update(status='failed', error=str(error), model_ready=(LIVE / '.lathe/workspace.json').is_file())
        text = log.read_text() if log.exists() else ''
        first_missing, dependency_watch = missing_dependencies(text)
        if first_missing:
            result['missing_dependency'] = first_missing
        result['dependency_watch'] = sorted(dependency_watch)
        paths = sorted(set(initial_watch) | dependency_watch)
        result.update(watch=paths, watch_values=[initial_stats.get(p, file_stat(p)) for p in paths])
        if isinstance(error, (SystemExit, KeyboardInterrupt)):
            result['error'] = 'Preparation cancelled'
        result['log'] = str(log)
    result['seconds'] = round(time.monotonic() - started, 3)
    result.pop('pid', None)
    atomic_json(TRIAL / 'state.json', result)
    return result, 0 if result['status'] == 'ready' else 1


def main():
    global COMMON_ARGS
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['inspect', 'prepare'])
    parser.add_argument('--file'); parser.add_argument('--root')
    parser.add_argument('--state-root', default=str(Path.home() / '.local/state/nvim/lathe'))
    parser.add_argument('--worktree-root', default=str(Path.home() / '.codex/worktrees'))
    parser.add_argument('--resources', default=str(Path.home() / '.codex/experiments/lathe-java8-20261116-side'))
    parser.add_argument('--clean', action='store_true')
    args = parser.parse_args()
    COMMON_ARGS = ['--state-root', args.state_root, '--worktree-root', args.worktree_root, '--resources', args.resources]
    try:
        root, repo = discover(args.file or args.root or os.getcwd())
        info = context(root, repo, args)
        if args.action == 'inspect':
            live_state = Path(info['analysis']) / 'live-state.json'
            if info['model_ready']:
                version = json.loads(live_state.read_text()).get('analysis_lombok') if live_state.is_file() else None
                info['needs_analysis_refresh'] = version != list(ANALYSIS_LOMBOK)
            state_file = Path(info['state']) / 'state.json'
            if state_file.exists():
                state = json.loads(state_file.read_text())
                override_file = str(Path(info['state']) / DEPENDENCY_OVERRIDES)
                attempted = state.get('input_stats', {}).get(override_file, override_file + ':missing')
                if info['model_ready'] and file_stat(override_file) != attempted:
                    info['needs_analysis_refresh'] = True
                for key in ('status', 'watch', 'watch_values', 'error', 'log', 'missing_dependency',
                            'java_releases', 'navigation_only', 'partial_model', 'dependency_override_count'):
                    if key in state:
                        info[key] = state[key]
            print(json.dumps(info, ensure_ascii=False)); return 0
        result, code = prepare(info, args)
        print(json.dumps(result, ensure_ascii=False)); return code
    except Exception as error:
        print(json.dumps({'status': 'failed', 'error': str(error)}, ensure_ascii=False)); return 1


if __name__ == '__main__':
    sys.exit(main())
