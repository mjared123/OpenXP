#!/usr/bin/env python3
"""Build the release zip and upload it to CurseForge.

Used by .github/workflows/release.yml when a version tag (v1.3.57) is pushed,
but it also runs by hand:

    CF_API_KEY=... python3 tools/curseforge_upload.py [git-ref]
    python3 tools/curseforge_upload.py --dry-run      # build + show, no upload

The zip comes from tools/package.py, so it is the same OpenXP-<version>.zip
you'd build yourself. The changelog is the newest WelcomeFrame.lua CHANGELOG
entry, written as a bold version header plus bullets.

Settings (environment variables):
  CF_API_KEY          CurseForge API token (needed unless --dry-run)
  CF_PROJECT_ID       CurseForge project id, default 1792509
  CF_GAME_VERSIONS    comma-separated game version names, default 1.60.1
  CF_RELEASE_TYPE     release, beta or alpha; default release
"""
import json, os, re, subprocess, sys, tempfile, urllib.request, uuid

API = "https://wow.curseforge.com/api"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def lua_string(s):
    return s.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")


def newest_changelog(ref):
    """(version, [changes]) from the first CHANGELOG entry at ref."""
    text = subprocess.run(["git", "-C", REPO, "show", "%s:WelcomeFrame.lua" % ref],
                          check=True, capture_output=True, text=True).stdout
    body = text[text.index("local CHANGELOG = {"):]
    version = re.search(r'version\s*=\s*"([^"]+)"', body).group(1)
    block = re.search(r"changes\s*=\s*\{(.*?)\n\s*\},", body, re.S).group(1)
    changes = [lua_string(m) for m in re.findall(r'"((?:[^"\\]|\\.)*)"', block)]
    return version, changes


def request(method, url, token, data=None, headers=None):
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("X-Api-Token", token)
    req.add_header("User-Agent", "OpenXP-release")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read().decode() or "null")
    except urllib.error.HTTPError as e:
        sys.exit("CurseForge %s %s failed: %s %s" % (method, url, e.code, e.read().decode(errors="replace")))


def game_version_ids(token, names):
    all_versions = request("GET", API + "/game/versions", token)
    ids = []
    for name in names:
        found = [v for v in all_versions if v["name"] == name]
        if len(found) != 1:
            hint = ", ".join("%s (id %s, type %s)" % (v["name"], v["id"], v["gameVersionTypeID"])
                             for v in all_versions if name.split(".")[0] in v["name"])[:2000]
            sys.exit("game version %r matched %d CurseForge versions. Close ones: %s"
                     % (name, len(found), hint))
        ids.append(found[0]["id"])
    return ids


def multipart(fields, file_field, file_path):
    boundary = uuid.uuid4().hex
    out = []
    for k, v in fields.items():
        out.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n"
                    % (boundary, k, v)).encode())
    out.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\n"
                "Content-Type: application/zip\r\n\r\n"
                % (boundary, file_field, os.path.basename(file_path))).encode())
    out.append(open(file_path, "rb").read())
    out.append(("\r\n--%s--\r\n" % boundary).encode())
    return b"".join(out), "multipart/form-data; boundary=" + boundary


def main():
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    dry = "--dry-run" in sys.argv
    ref = args[0] if args else "HEAD"

    version, changes = newest_changelog(ref)
    changelog = "**%s**\n" % version + "".join("- %s\n" % c for c in changes)

    out_dir = os.environ.get("OUT_DIR") or tempfile.mkdtemp()
    subprocess.run([sys.executable, os.path.join(REPO, "tools", "package.py"), out_dir, ref], check=True)
    zip_path = os.path.join(out_dir, "OpenXP-%s.zip" % version)
    if not os.path.exists(zip_path):
        sys.exit("expected %s after packaging" % zip_path)

    tag = os.environ.get("GITHUB_REF_NAME", "")
    if tag.startswith("v") and tag[1:] != version:
        sys.exit("tag %s doesn't match the version in OpenXP.toc / WelcomeFrame.lua (%s)" % (tag, version))

    project = os.environ.get("CF_PROJECT_ID", "1792509")
    names = [n.strip() for n in os.environ.get("CF_GAME_VERSIONS", "1.60.1").split(",") if n.strip()]
    release_type = os.environ.get("CF_RELEASE_TYPE", "release")
    print("version:", version)
    print("zip:", zip_path)
    print("game versions:", names, "release type:", release_type)
    print("changelog:\n" + changelog)
    if dry:
        return

    token = os.environ.get("CF_API_KEY")
    if not token:
        sys.exit("CF_API_KEY is not set")
    metadata = {
        "changelog": changelog,
        "changelogType": "markdown",
        "displayName": "OpenXP-%s" % version,
        "gameVersions": game_version_ids(token, names),
        "releaseType": release_type,
    }
    body, ctype = multipart({"metadata": json.dumps(metadata)}, "file", zip_path)
    res = request("POST", "%s/projects/%s/upload-file" % (API, project), token, body,
                  {"Content-Type": ctype})
    print("uploaded to CurseForge, file id", (res or {}).get("id"))


if __name__ == "__main__":
    main()
