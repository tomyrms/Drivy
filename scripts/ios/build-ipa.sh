#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
cd "$root_dir"
artifact_dir="$root_dir/artifacts/ios"
if [[ -L "$root_dir/artifacts" || -L "$artifact_dir" ]]; then
  echo "Le dossier d'artefacts ne doit pas être un lien symbolique." >&2
  exit 1
fi
mkdir -p "$artifact_dir"
staging_dir=$(mktemp -d "$artifact_dir/.ipa-staging.XXXXXX")
cleanup() {
  case "$staging_dir" in
    "$artifact_dir"/.ipa-staging.*) rm -rf -- "$staging_dir" ;;
    *) echo "Nettoyage refusé hors du staging IPA." >&2 ;;
  esac
}
trap cleanup EXIT
# Une tentative échouée ne doit pas laisser un ancien IPA présenté comme courant.
rm -f -- "$artifact_dir/Drivy.ipa" "$artifact_dir/SHA256SUMS.txt" "$artifact_dir/build-info.json"
python3 - <<'PY'
import os, urllib.parse
names = ('DRIVY_API_BASE_URL', 'DRIVY_OIDC_ISSUER', 'DRIVY_OIDC_CLIENT_ID')
values = [os.environ.get(name, '') for name in names]
if any(values):
    if not all(values):
        raise SystemExit('Configuration scolaire incomplète : les trois variables de build sont nécessaires.')
    for name, value in zip(names[:2], values[:2]):
        url = urllib.parse.urlsplit(value)
        if (url.scheme != 'https' or not url.hostname or url.username or url.password
                or url.query or url.fragment or any(c.isspace() or ord(c) < 32 for c in value)):
            raise SystemExit(name + ' doit être une URL HTTPS sans identifiants, requête ni fragment.')
    if len(values[2]) > 200 or any(c.isspace() or ord(c) < 32 for c in values[2]) or '$(' in values[2]:
        raise SystemExit('Identifiant de client OIDC invalide.')
PY
xcodebuild build \
  -project apps/ios/Drivy.xcodeproj -scheme Drivy -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$staging_dir/DeviceBuild" \
  CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" \
  DRIVY_API_BASE_URL="${DRIVY_API_BASE_URL:-}" \
  DRIVY_OIDC_ISSUER="${DRIVY_OIDC_ISSUER:-}" \
  DRIVY_OIDC_CLIENT_ID="${DRIVY_OIDC_CLIENT_ID:-}" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  2>&1 | tee "$artifact_dir/device-build.log"
mkdir -p "$staging_dir/Payload"
ditto "$staging_dir/DeviceBuild/Build/Products/Release-iphoneos/Drivy.app" "$staging_dir/Payload/Drivy.app"
python3 - "$staging_dir" "$artifact_dir" <<'PY'
import datetime, hashlib, json, os, pathlib, plistlib, re, shutil, subprocess, sys, zipfile

stage, output = (pathlib.Path(value).resolve() for value in sys.argv[1:])
if stage.parent != output or not stage.name.startswith(".ipa-staging."):
    raise SystemExit("Staging IPA hors du dossier d'artefacts.")
app = stage / "Payload/Drivy.app"
if not app.is_dir():
    raise SystemExit("Application iOS absente du produit de compilation.")
for path in app.rglob("*"):
    if not path.resolve().is_relative_to(app):
        raise SystemExit("Lien sortant du bundle : " + str(path.relative_to(app)))

def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True)

def unsigned(path):
    result = subprocess.run(["/usr/bin/codesign", "--display", str(path)], text=True, capture_output=True)
    if result.returncode == 0:
        return False
    if "code object is not signed at all" not in result.stderr.lower():
        raise SystemExit("État de signature indéterminé : " + str(path.relative_to(stage)))
    return True

# Retirer les signatures dans la copie seulement, de l'intérieur vers l'extérieur.
# Références Apple : TN2206 et Security/OSX/libsecurity_codesigning/lib/signer.cpp.
bundles = sorted([app] + [path for path in app.rglob("*") if path.is_dir()
                 and path.suffix in {".app", ".appex", ".framework", ".xpc", ".bundle"}
                 and ((path / "Info.plist").exists() or (path / "_CodeSignature").exists())],
                 key=lambda path: len(path.parts), reverse=True)
for bundle in bundles:
    if not unsigned(bundle):
        run("/usr/bin/codesign", "--remove-signature", str(bundle))

def inspect_binary(path):
    architectures = run("xcrun", "lipo", "-archs", str(path)).stdout.split()
    if not architectures or not set(architectures) <= {"arm64", "arm64e"}:
        raise SystemExit("Architecture autre qu'arm64 appareil : " + str(path.relative_to(stage)))
    slices = []
    for architecture in architectures:
        description = run("xcrun", "vtool", "-arch", architecture, "-show-build", str(path)).stdout
        platforms = re.findall(r"^\s*platform\s+(\S+)", description, re.MULTILINE)
        minimums = re.findall(r"^\s*minos\s+([0-9.]+)", description, re.MULTILINE)
        sdks = re.findall(r"^\s*sdk\s+([0-9.]+)", description, re.MULTILINE)
        if len(platforms) != 1 or platforms[0].upper() != "IOS" or len(minimums) != 1 or len(sdks) != 1:
            raise SystemExit("Plateforme iOS appareil non prouvée : " + str(path.relative_to(stage)))
        slices.append({"architecture": architecture, "platform": "iOS",
                       "minimumOS": minimums[0], "sdk": sdks[0]})
    return slices

binaries = []
for path in app.rglob("*"):
    if path.is_file() and not path.is_symlink():
        description = run("/usr/bin/file", "-b", str(path)).stdout
        if description.startswith("Mach-O "):
            binaries.append(path)
            if not unsigned(path):
                run("/usr/bin/codesign", "--remove-signature", str(path))

# Les profils d'approvisionnement et ressources de signature ne sont pas distribués.
for path in sorted(app.rglob("*"), key=lambda item: len(item.parts), reverse=True):
    if path.name == "_CodeSignature":
        if path.is_symlink():
            path.unlink()
        else:
            shutil.rmtree(path)
    elif path.name == "embedded.mobileprovision" or (path.name == "CodeResources" and path.is_symlink()):
        path.unlink()

with (app / "Info.plist").open("rb") as stream:
    plist = plistlib.load(stream)
executable_name = plist.get("CFBundleExecutable", "")
if not executable_name or pathlib.Path(executable_name).name != executable_name:
    raise SystemExit("CFBundleExecutable invalide.")
executable = app / executable_name
if executable not in binaries or plist.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
    raise SystemExit("Application iPhoneOS non prouvée par le produit réel.")
if not isinstance(plist.get("MinimumOSVersion"), str):
    raise SystemExit("MinimumOSVersion absent de l'Info.plist compilé.")
if not (app / "Frameworks/SQLCipher.framework/SQLCipher").is_file():
    raise SystemExit("Framework SQLCipher dynamique absent de l'application.")

binary_info = []
for path in binaries:
    slices = inspect_binary(path)
    if not unsigned(path):
        raise SystemExit("Une signature reste présente dans " + str(path.relative_to(stage)))
    if path == executable and "executable" not in run("/usr/bin/file", "-b", str(path)).stdout:
        raise SystemExit("Le binaire principal n'est pas un exécutable Mach-O.")
    binary_info.append({"path": str(path.relative_to(stage)),
                        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "slices": slices})
for bundle in bundles:
    if not unsigned(bundle):
        raise SystemExit("Une signature reste présente sur un bundle.")
if any(path.name in {"_CodeSignature", "embedded.mobileprovision"} for path in app.rglob("*")):
    raise SystemExit("Des ressources de signature restent présentes.")

resolved = pathlib.Path("apps/ios/Drivy.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
shutil.copyfile(resolved, stage / "Package.resolved")
# Archive neuve : aucun membre d'un ancien IPA ne peut subsister.
subprocess.run(["/usr/bin/zip", "-q", "-r", "-y", "Drivy.ipa", "Payload"], cwd=stage, check=True)
with zipfile.ZipFile(stage / "Drivy.ipa") as archive:
    if archive.testzip() is not None or any(not name.startswith("Payload/Drivy.app/") for name in archive.namelist() if name != "Payload/"):
        raise SystemExit("Structure ou CRC de l'IPA invalide.")
    for item in binary_info:
        if hashlib.sha256(archive.read(item["path"])).hexdigest() != item["sha256"]:
            raise SystemExit("Le binaire archivé diffère du binaire vérifié.")

ipa_hash = hashlib.sha256((stage / "Drivy.ipa").read_bytes()).hexdigest()
commit = os.environ.get("GITHUB_SHA") or run("git", "rev-parse", "HEAD").stdout.strip()
info = {
    "commit": commit, "run": os.environ.get("GITHUB_RUN_ID"),
    "build": plist["CFBundleVersion"], "version": plist["CFBundleShortVersionString"],
    "bundleIdentifier": plist["CFBundleIdentifier"], "executable": executable_name,
    "builtAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "configuration": "Release", "signed": False,
    "signatureVerification": {"status": "PASSED", "method": "codesign --display après suppression ; plateforme via lipo et vtool",
                              "checkedBundles": len(bundles), "checkedBinaries": len(binaries)},
    "minimumOS": plist["MinimumOSVersion"], "platforms": plist["CFBundleSupportedPlatforms"],
    "sdkName": plist.get("DTSDKName"), "xcodeBuild": plist.get("DTXcodeBuild"),
    "ipaSHA256": ipa_hash, "binaries": binary_info,
    "packageResolvedSHA256": hashlib.sha256((stage / "Package.resolved").read_bytes()).hexdigest(),
    "distribution": "Signature locale avec iLoader",
    "scope": "G0 : séances locales ; accès scolaire, configuration, invitations et profils selon les services déployés ; qualification physique distincte",
    "schoolConnectionConfigured": all(plist.get(name, '') for name in ('DrivyAPIBaseURL', 'DrivyOIDCIssuer', 'DrivyOIDCClientID')),
    "physicalQualification": "NOT_EXECUTED"
}
(stage / "build-info.json").write_text(json.dumps(info, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
checksums = []
for name in ("Drivy.ipa", "build-info.json", "Package.resolved"):
    checksums.append(hashlib.sha256((stage / name).read_bytes()).hexdigest() + "  " + name)
(stage / "SHA256SUMS.txt").write_text("\n".join(checksums) + "\n", encoding="utf-8")
for name in ("Drivy.ipa", "build-info.json", "Package.resolved", "SHA256SUMS.txt"):
    os.replace(stage / name, output / name)
print("IPA vérifié : arm64 iOS appareil, signatures retirées, empreintes et métadonnées du produit réel.")
PY
