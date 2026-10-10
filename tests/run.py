#!/usr/bin/env python3
"""Runs the offline specs in tests/*.spec.luau with the standalone Luau CLI.

The modules under src/shared are written for Roblox (they use `require(script.Parent.x)`), so this
runner bundles the real source files into one program, gives every chunk a virtual `script` /
`require`, and executes the bundle with `luau`. Nothing here talks to Roblox.

Usage:  python3 tests/run.py [--luau PATH_TO_LUAU] [spec-name-filter]
Needs:  python3 and the `luau` CLI (https://github.com/luau-lang/luau/releases).
"""

import argparse
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHARED = ROOT / "src" / "shared"
TESTS = ROOT / "tests"


def long_string(text: str) -> str:
    level = 0
    while "]" + "=" * level + "]" in text:
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{text}]{eq}]"


def module_path(file: pathlib.Path) -> str:
    rel = file.relative_to(ROOT / "src").with_suffix("")
    return "/".join(rel.parts)


RUNTIME = r"""
local nodes: { [string]: any } = {}

local function ensureNode(path: string): any
	local existing = nodes[path]
	if existing then
		return existing
	end
	local parentPath, name = string.match(path, "^(.*)/([^/]+)$")
	local node: any = { __path = path, Name = name or path }
	nodes[path] = node
	if parentPath then
		node.Parent = ensureNode(parentPath)
	end
	setmetatable(node, {
		__index = function(_, key)
			return nodes[path .. "/" .. tostring(key)]
		end,
	})
	return node
end

for path in sources do
	ensureNode(path)
end

local loaded: { [string]: any } = {}
local function virtualRequire(node: any): any
	local path = node.__path
	if loaded[path] ~= nil then
		return loaded[path]
	end
	local source = sources[path]
	assert(source ~= nil, "cannot require " .. tostring(path))
	local fn, err = loadstring("local script, require = ...\n" .. source, "=" .. path)
	assert(fn, err)
	local result = fn(node, virtualRequire)
	loaded[path] = result
	return result
end

local passed, failed = 0, 0
local failures: { string } = {}
local currentSpec = ""

local function test(name: string, body: () -> ())
	local ok, err = pcall(body)
	if ok then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		table.insert(failures, currentSpec .. " > " .. name .. ": " .. tostring(err))
		print("  FAIL " .. name .. "\n       " .. tostring(err))
	end
end

local function check(condition: any, message: string?)
	if not condition then
		error(message or "check failed", 2)
	end
end

local function approx(a: number, b: number, tolerance: number?, message: string?)
	local tol = tolerance or 1e-6
	if math.abs(a - b) > tol then
		error(string.format("%s expected %.9g, got %.9g (tolerance %g)", message or "approx:", b, a, tol), 2)
	end
end

local sharedNode = ensureNode("shared")
for name, source in specs do
	currentSpec = name
	print(name)
	local fn, err = loadstring("local script, require, test, check, approx, shared = ...\n" .. source, "=" .. name)
	assert(fn, err)
	local ok, runErr = pcall(fn, ensureNode("src/shared/" .. name), virtualRequire, test, check, approx, sharedNode)
	if not ok then
		failed += 1
		table.insert(failures, name .. ": " .. tostring(runErr))
		print("  FAIL (spec crashed)\n       " .. tostring(runErr))
	end
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	error("tests failed")
end
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--luau", default=shutil.which("luau"))
    parser.add_argument("filter", nargs="?", default="")
    args = parser.parse_args()
    if not args.luau:
        print("luau CLI not found. Install it or pass --luau PATH.", file=sys.stderr)
        return 2

    sources = []
    for file in sorted(SHARED.rglob("*.luau")):
        sources.append(f"\t[{json.dumps(module_path(file))}] = {long_string(file.read_text())},")
    specs = []
    for file in sorted(TESTS.glob("*.spec.luau")):
        if args.filter in file.name:
            specs.append(f"\t[{json.dumps(file.name)}] = {long_string(file.read_text())},")
    if not specs:
        print("no specs matched", file=sys.stderr)
        return 2

    bundle = "local sources = {\n" + "\n".join(sources) + "\n}\nlocal specs = {\n" + "\n".join(specs) + "\n}\n" + RUNTIME

    with tempfile.TemporaryDirectory() as tmp:
        bundle_file = pathlib.Path(tmp) / "bundle.luau"
        bundle_file.write_text(bundle)
        return subprocess.call([args.luau, str(bundle_file)])


if __name__ == "__main__":
    sys.exit(main())
