#!/usr/bin/env python3
"""Push files to GitHub via the Git Data API.

Why this exists
---------------
On this machine, `git push` over HTTPS to github.com is blocked (the proxy
answers `CONNECT tunnel failed, response 502`, and direct connections time
out on 443), while `api.github.com` works fine. TCP to `github.com:22` and
`ssh.github.com:443` is reachable, but no SSH key is registered on the
account and the gh token lacks `admin:public_key`.

So the practical path is the Git Data API: upload blobs, build a tree, create
a commit, move the ref. This bypasses git's smart-HTTP transport entirely.

Usage
-----
    python3 tools/push_via_api.py --message "commit message" file1 [file2 ...]
    python3 tools/push_via_api.py --message-file /tmp/msg.txt file1 file2

Files are given as paths relative to the repo root. Deletions are not
supported (this tool only creates/updates blobs).

Requirements
------------
- `gh` CLI authenticated with `repo` scope (`gh auth status`)
- Network access to api.github.com

Notes
-----
- Base64 payloads inflate size by ~33%. A 35 MB APK uploads as a 46 MB
  request and takes roughly 30 s on this network; the default timeout is
  600 s per request.
- The resulting commit sha differs from what a local `git commit` + `git
  push` would produce, because committer identity/timestamp differ. Content
  is identical. After the network recovers, reconcile with:
      git fetch origin && git reset --hard origin/main
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

API_ROOT = "https://api.github.com"
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

EXECUTABLE_EXT = {".sh", ".py"}
EXECUTABLE_NAMES = {"verify_tv", "rescue_on_adb", "watch_adb_and_grab"}


def detect_repo():
    """Read owner/repo from the origin remote."""
    url = subprocess.check_output(
        ["git", "-C", REPO_ROOT, "remote", "get-url", "origin"], text=True
    ).strip()
    for prefix in ("https://github.com/", "git@github.com:"):
        if url.startswith(prefix):
            path = url[len(prefix):]
            if path.endswith(".git"):
                path = path[:-4]
            return path.split("/", 1)
    sys.exit(f"cannot parse origin url: {url}")


def make_client(owner, repo):
    token = subprocess.check_output(["gh", "auth", "token"], text=True).strip()
    api = f"{API_ROOT}/repos/{owner}/{repo}"

    def call(method, path, body=None, timeout=600):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(api + path, data=data, method=method)
        req.add_header("Authorization", f"Bearer {token}")
        req.add_header("Accept", "application/vnd.github+json")
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")[:400]
            print(f"HTTP {e.code} on {method} {path}: {detail}", file=sys.stderr)
            raise

    return call


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+", help="paths relative to repo root")
    ap.add_argument("--message", "-m", help="commit message")
    ap.add_argument("--message-file", help="read commit message from file")
    ap.add_argument("--branch", default="main")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if args.message_file:
        message = open(args.message_file, encoding="utf-8").read().strip()
    elif args.message:
        message = args.message.strip()
    else:
        sys.exit("need --message or --message-file")

    missing = [f for f in args.files if not os.path.isfile(os.path.join(REPO_ROOT, f))]
    if missing:
        sys.exit(f"missing files: {missing}")

    owner, repo = detect_repo()
    call = make_client(owner, repo)

    base = call("GET", f"/git/ref/heads/{args.branch}")["object"]["sha"]
    base_tree = call("GET", f"/git/commits/{base}")["tree"]["sha"]
    print(f"repo   {owner}/{repo}@{args.branch}")
    print(f"base   {base[:8]}  tree {base_tree[:8]}")

    entries = []
    for rel in args.files:
        full = os.path.join(REPO_ROOT, rel)
        size = os.path.getsize(full)
        print(f"  blob   {rel}  ({size/1048576:.2f} MB)", end="", flush=True)
        if args.dry_run:
            print("  [dry-run]")
            continue
        with open(full, "rb") as fh:
            encoded = base64.b64encode(fh.read()).decode()
        t0 = time.time()
        blob = call("POST", "/git/blobs", {"content": encoded, "encoding": "base64"})
        print(f" -> {blob['sha'][:8]}  {time.time()-t0:.1f}s")
        ext = os.path.splitext(rel)[1]
        mode = "100755" if (ext in EXECUTABLE_EXT or rel in EXECUTABLE_NAMES) else "100644"
        entries.append({"path": rel, "mode": mode, "type": "blob", "sha": blob["sha"]})

    if args.dry_run:
        print("dry-run: nothing uploaded")
        return

    tree = call("POST", "/git/trees", {"base_tree": base_tree, "tree": entries})
    print(f"tree   {tree['sha'][:8]}")
    commit = call("POST", "/git/commits", {
        "message": message,
        "tree": tree["sha"],
        "parents": [base],
    })
    print(f"commit {commit['sha'][:8]}")
    call("PATCH", f"/git/refs/heads/{args.branch}",
         {"sha": commit["sha"], "force": False})
    print(f"done   https://github.com/{owner}/{repo}/commit/{commit['sha']}")


if __name__ == "__main__":
    main()
