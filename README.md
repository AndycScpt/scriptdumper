# Script Dumper

A Roblox script saver that scans scripts and remotes, preserves their hierarchy, and exports a `.rbxlx` file with decompiled sources when supported by your executor.

## Features

- Scan game descendants, nil-parented instances, and loaded modules.
- Include scripts, remote events/functions, and bindable events/functions.
- Decompile with eight workers and a 30-second timeout per script by default.
- Display progress and save the result as `ScriptDump - <game name> - <timestamp>.rbxlx`.

## Usage

Run `scriptdumper.lua` directly in your executor, or load it with:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/AndycScpt/scriptdumper/main/scriptdumper.lua"))()
```

The loader requires internet access. Exported files are written to your executor's workspace.

## Compatibility

Requires an executor that supports `Drawing`, `getnilinstances`, `getloadedmodules`, `decompile`, `writefile`, and instance debug IDs. Source availability and decompilation results depend on the executor and the scripts accessible to the client.

The script skips `CoreGui` and `CorePackages`. Adjust the `Config` table to change scan settings, worker count, and timeouts.
