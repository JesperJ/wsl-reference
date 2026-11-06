<#
.SYNOPSIS
  Bootstrap a NixOS-WSL developer machine from the shared baseline.

.DESCRIPTION
  Runs the whole of GETTING-STARTED.md from the Windows side: installs the
  distro if it is not registered yet, writes your flake.nix, builds the first
  generation with `nixos-rebuild boot`, performs the restart sequence that a
  username change needs, and checks the result.

  It is driven from Windows on purpose. The restart sequence cannot be done
  from inside the distro that is being restarted.

.PARAMETER Distro
  WSL registration name, as `wsl -l -v` shows it, and what `wsl -d` takes.
  Defaults to `dev` -- not `NixOS`, the name a stock install registers under,
  so it does not land on a NixOS distro someone already has. It is unrelated
  to HostName.

.PARAMETER HostName
  What the machine calls itself. Defaults to <Windows computer name>-dev.

.PARAMETER UserName
  Your login inside the distro. Needed on the first run only: a rerun on a
  machine that is already set up reads it from who the distro logs in as.

.PARAMETER LocalBaseline
  Windows path to a clone of this repository, for testing baseline changes
  that are not released yet. It redirects both the template and the
  flake.nix wsl-base input at the clone, through /mnt inside the distro,
  uncommitted edits included. (Also the way in for a private fork: Nix
  fetches `github:` refs through the unauthenticated GitHub API, so a
  private repository 404s however good your git credentials are.)

.PARAMETER ImageFile
  Path to a nixos.wsl image. Only used when Distro is not registered yet.

.PARAMETER InstallWsl
  If WSL is missing, install it (`wsl --install --no-distribution`, behind an
  elevation prompt) instead of stopping with instructions.

.EXAMPLE
  .\bootstrap.ps1 -ImageFile '.\nixos.wsl' -UserName anna `
    -FullName "Anna Example" -Email anna@company.com

  A new machine: installs the distro as `dev` from the image, then
  everything else. Open it with `wsl -d dev`.

.EXAMPLE
  .\bootstrap.ps1

  A rerun on a machine that is already set up: applies ~/wsl-config with
  `switch` and checks the result. Renames nothing.

.EXAMPLE
  .\bootstrap.ps1 -ImageFile '.\nixos.wsl' -UserName anna `
    -LocalBaseline C:\Code\repos\wsl-reference

  Try unreleased baseline changes from a local clone.
#>
# PowerShell 7: Windows PowerShell 5.1 turns a native command's stderr into
# terminating errors under ErrorActionPreference=Stop, and nix writes its
# progress to stderr. Refused up front rather than failing mid-build.
#Requires -Version 7.0
[CmdletBinding()]
param(
  [string] $Distro = 'dev',
  [string] $UserName,
  [string] $FullName = '',
  [string] $Email = '',
  [string] $HostName,
  [string] $ImageFile,
  [string] $TemplateUrl = 'github:JesperJ/wsl-reference',
  [string] $LocalBaseline,
  [string] $ConfigDir = 'wsl-config',
  [switch] $Force,
  [switch] $InstallWsl
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- validation

# Anything that reaches a bash command line below is checked here, so the
# in-distro scripts can stay single-quoted with no escaping to get wrong.
# Your name and e-mail are NOT on that list: they travel as base64.
if ($UserName -and $UserName -notmatch '^[a-z_][a-z0-9_-]{0,31}$') {
  throw "UserName '$UserName' is not a valid Linux login name (lower case, starts with a letter or _)."
}
if ($Distro -notmatch '^[A-Za-z0-9._-]{1,64}$') {
  throw "Distro '$Distro' has characters that are awkward to pass through a shell. Pick a simpler name."
}
if ($TemplateUrl -match "'") {
  throw "TemplateUrl must not contain a single quote; it is passed to a shell."
}
if ($ConfigDir -notmatch '^[A-Za-z0-9._-]{1,64}$') {
  throw "ConfigDir '$ConfigDir' must be a single directory name under your home directory."
}
# The distro is named after the Windows machine it runs on, so it is obvious in
# a prompt, a log or a network list which PC a shell belongs to.
if (-not $HostName) { $HostName = "$($env:COMPUTERNAME)-dev" }
if ($HostName -and $HostName -notmatch '^[A-Za-z0-9-]{1,63}$') {
  throw "HostName '$HostName' must be letters, digits and hyphens."
}
if ($UserName -eq 'nixos') {
  Write-Warning "UserName is 'nixos', the name the stock image already uses. Nothing will be renamed."
}


# -LocalBaseline is for a baseline that is not published yet, or not public:
# a Windows clone of this repository, reached from inside the distro through
# /mnt. It redirects BOTH references -- the template this script fetches and
# the wsl-base input of the flake.nix it writes -- because overriding only the
# first leaves the build reaching for github.
$BaselineInDistro = $null
if ($LocalBaseline) {
  if (-not (Test-Path -LiteralPath $LocalBaseline)) {
    throw "LocalBaseline path not found on this machine: $LocalBaseline"
  }
  $full = (Resolve-Path -LiteralPath $LocalBaseline).Path
  if ($full -notmatch '^([A-Za-z]):\\(.*)$') {
    throw "LocalBaseline must be a local Windows path like C:\Users\you\wsl-reference (got '$full')."
  }
  $BaselineInDistro = '/mnt/' + $Matches[1].ToLower() + '/' + ($Matches[2] -replace '\\', '/')
  if ($BaselineInDistro -match "[' ]") {
    throw "LocalBaseline resolves to '$BaselineInDistro', which contains a space or quote. Clone somewhere simpler."
  }
  if (-not (Test-Path -LiteralPath (Join-Path $full 'flake.nix'))) {
    throw "No flake.nix in $full -- that does not look like a clone of wsl-reference."
  }
  if (-not $PSBoundParameters.ContainsKey('TemplateUrl')) {
    $TemplateUrl = "path:$BaselineInDistro"
  }
}

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Note($text) { Write-Host "    $text" -ForegroundColor DarkGray }

# Runs a bash login shell inside the distro. Login shell on purpose: that is
# what puts nix on PATH on a stock image.
#
# -Stream prints each line as it arrives instead of collecting the output, for
# the long builds: a cold build is many minutes, and silence for all of them
# looks exactly like a hang. Nothing is returned then.
function Invoke-InDistro {
  param([Parameter(Mandatory = $true)][string] $Script, [switch] $AsRoot, [switch] $Stream)

  $wslArgs = @('-d', $Distro)
  if ($AsRoot) { $wslArgs += @('--user', 'root') }
  # -e, not --: `wsl -- cmd` hands the whole line to the distro's default
  # shell first, which expands $vars (empty there) and eats quotes before our
  # bash ever sees the script. -e runs bash directly with the script intact.
  $wslArgs += @('-e', 'bash', '-lc', $Script)

  # What runs in the distro prints UTF-8, but PowerShell decodes a native
  # command's output with [Console]::OutputEncoding -- the OEM code page on
  # Windows -- so `•` arrived as `ÔÇó`. UTF-8 for the call, restored after.
  # (wsl.exe's OWN messages are UTF-16: those go through Invoke-WslUtf16.)
  $previous = [Console]::OutputEncoding
  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
  try {
    if ($Stream) {
      # Terminal-title escapes (ESC ] ... BEL) from the login shell are
      # dropped, and so is a line left empty by that.
      & wsl @wslArgs 2>&1 | ForEach-Object {
        $line = "$_" -replace "\x1b\][^\x07]*(\x07|$)", ''
        if ($line.Trim()) { Write-Host "    $line" -ForegroundColor DarkGray }
      }
      if ($LASTEXITCODE -ne 0) {
        throw "Command failed inside '$Distro' (exit $LASTEXITCODE), output above: $Script"
      }
      return
    }

    $output = & wsl @wslArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
      $output | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
      throw "Command failed inside '$Distro' (exit $LASTEXITCODE): $Script"
    }
    return $output
  }
  finally { [Console]::OutputEncoding = $previous }
}

# wsl.exe's own messages (`wsl -l`, `wsl --install`, not a distro's output)
# are UTF-16. Read as anything else they arrive with a NUL after every
# character: spaced out in a log or transcript, and useless to compare. So
# they are decoded as UTF-16 here and returned as plain lines; $LASTEXITCODE
# is wsl's.
function Invoke-WslUtf16 {
  $previous = [Console]::OutputEncoding
  try {
    [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
    & wsl @args 2>&1 | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne '' }
  }
  finally { [Console]::OutputEncoding = $previous }
}

function Get-RegisteredDistros { Invoke-WslUtf16 -l -q }

# ------------------------------------------------------------------- install

# wsl.exe exists on every Windows 10/11 machine as an inbox stub, so finding
# it proves nothing. `wsl --version` only succeeds on the Microsoft Store WSL,
# which is the one NixOS-WSL needs; the stub, or a machine with the feature
# switched off, exits non-zero.
$wslReady = $false
if (Get-Command wsl -ErrorAction SilentlyContinue) {
  & wsl --version *> $null
  $wslReady = ($LASTEXITCODE -eq 0)
}
if (-not $wslReady) {
  if (-not $InstallWsl) {
    throw @"
WSL is not installed or not the Microsoft Store version, which NixOS-WSL needs.
Install it from an elevated PowerShell:
    wsl --install --no-distribution
restart Windows if it asks, then re-run this script.
Or re-run this script with -InstallWsl and it will do that for you (it asks for elevation).
"@
  }
  Step "Installing WSL (an elevation prompt will appear)"
  $proc = Start-Process -FilePath 'wsl.exe' -ArgumentList '--install', '--no-distribution' `
    -Verb RunAs -Wait -PassThru
  if ($proc.ExitCode -ne 0) { throw "wsl --install --no-distribution failed (exit $($proc.ExitCode))." }
  & wsl --version *> $null
  if ($LASTEXITCODE -ne 0) {
    Write-Host "`n==> WSL is installed but needs a Windows restart. Restart, then run this script again." -ForegroundColor Yellow
    return
  }
}

$registered = Get-RegisteredDistros
if ($registered -contains $Distro) {
  Step "Distro '$Distro' is already registered"
  if ($ImageFile) { Note "Ignoring -ImageFile: not reinstalling over an existing distro." }
}
elseif ($ImageFile) {
  if (-not (Test-Path -LiteralPath $ImageFile)) { throw "Image file not found: $ImageFile" }
  Step "Installing '$Distro' from $ImageFile"
  # --no-launch: otherwise wsl opens a shell in the new distro once it is
  # installed and waits for someone to type `exit` in it -- invisibly, since
  # the output is captured, so the script just appears to hang.
  Invoke-WslUtf16 --install --from-file $ImageFile --name $Distro --no-launch | ForEach-Object { Note $_ }
  if ($LASTEXITCODE -ne 0) { throw "wsl --install failed (exit $LASTEXITCODE)." }
}
else {
  throw @"
Distro '$Distro' is not registered and no -ImageFile was given.
Download nixos.wsl from https://github.com/nix-community/NixOS-WSL/releases/latest
then re-run with -ImageFile '<path to nixos.wsl>'.
Registered right now: $($registered -join ', ')
"@
}

# ------------------------------------------------------------------ channels

# The first command NixOS-WSL asks for on a fresh image, before any rebuild.
# The flake build itself does not read channels, but the stock image's tooling
# does, and skipping it leaves the machine in a state upstream never tests.
# Run every time, not only on a fresh install, so the outcome does not depend
# on what was done to the distro by hand before.
Step "Updating the root nix channel in '$Distro'"
Invoke-InDistro -AsRoot "nix-channel --update" | Out-Null

# --------------------------------------------------------------------- state

# Who the distro logs in as says how far an earlier run got. The stock image
# logs in as nixos; after the first build and restart it is your own login.
# So a rerun on a finished machine renames nothing: it applies the flake.nix
# that is already there with `switch`, and checks the result. The last line is
# taken because a stock image prints its welcome banner first.
$currentUser = "$((Invoke-InDistro 'whoami') |
  Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } |
  Select-Object -Last 1)".Trim()
$rerun = $currentUser -ne 'nixos'

if ($rerun) {
  if ($UserName -and $UserName -ne $currentUser) {
    throw "'$Distro' is already set up for '$currentUser'. This script does not rename an existing user; change user.name in ~/$ConfigDir/flake.nix if you really mean to."
  }
  $UserName = $currentUser
  Step "'$Distro' is already set up for '$UserName'"
  foreach ($p in 'HostName', 'FullName', 'Force') {
    if ($PSBoundParameters.ContainsKey($p)) { Note "Ignoring -$p on a rerun: edit ~/$ConfigDir/flake.nix instead." }
  }
}
elseif (-not $UserName) {
  throw "-UserName is required on the first run, while '$Distro' still logs in as nixos."
}

if (-not $rerun) {
  # --------------------------------------------------------------- configure

  Step "Writing ~/$ConfigDir/flake.nix in '$Distro'"

  $existing = (Invoke-InDistro "test -f ~/$ConfigDir/flake.nix && echo yes || echo no") -join ''
  # `nix flake init` refuses to overwrite a file that differs from the
  # template, so -Force has to clear it first.
  if ($existing -match 'yes' -and $Force) {
    Invoke-InDistro "rm -f ~/$ConfigDir/flake.nix" | Out-Null
  }

  if ($existing -match 'yes' -and -not $Force) {
    # An earlier run got this far and stopped -- a failed build, say. Its
    # flake.nix is kept, so finishing the job does not undo hand edits.
    Note "Keeping the existing ~/$ConfigDir/flake.nix (-Force rewrites it from the template)."
  }
  else {
    # The template is fetched rather than embedded here, so there is one copy
    # of it to keep correct. Flakes are not on yet on a stock image, hence the
    # flag.
    Invoke-InDistro "mkdir -p ~/$ConfigDir && cd ~/$ConfigDir && nix --extra-experimental-features 'nix-command flakes' flake init -t '$TemplateUrl'" | Out-Null

    # A login shell on a stock image prints the NixOS-WSL welcome banner to
    # stdout from /etc/profile, so the file is fenced off with a marker and
    # only what follows it is kept. Without this the banner is written back
    # into flake.nix.
    $marker = '__WSL_BOOTSTRAP_FLAKE__'
    $catOutput = @(Invoke-InDistro "echo $marker; cat ~/$ConfigDir/flake.nix" | ForEach-Object { "$_" })
    $at = [array]::IndexOf($catOutput, $marker)
    if ($at -lt 0) { throw "Could not read ~/$ConfigDir/flake.nix back from '$Distro'." }
    $template = ($catOutput | Select-Object -Skip ($at + 1)) -join "`n"
    foreach ($placeholder in @('WSL-CHANGEME', '"changeme"', 'Change Me', 'change.me@company.com')) {
      if ($template -notlike "*$placeholder*") {
        throw "The template no longer contains '$placeholder'; this script needs updating."
      }
    }

    $flake = $template.
      Replace('WSL-CHANGEME', $HostName).
      Replace('"changeme"', '"' + $UserName + '"').
      Replace('Change Me', $FullName).
      Replace('change.me@company.com', $Email)

    if ($BaselineInDistro) {
      # Whatever release the template pins -- matched by pattern, not by
      # value, so a version bump never has to touch this script.
      $pinned = 'github:JesperJ/wsl-reference/v[0-9][^"]*'
      if ($flake -notmatch $pinned) {
        throw "Expected the template to pin a wsl-reference release ($pinned); cannot redirect wsl-base to the local clone."
      }
      $flake = $flake -replace $pinned, "path:$BaselineInDistro"
    }

    # base64 so a name with a quote, an accent or a space cannot break out of
    # the command line it travels on.
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($flake))
    Invoke-InDistro "echo '$encoded' | base64 -d > ~/$ConfigDir/flake.nix" | Out-Null
    Note "hostName = $HostName, user.name = $UserName"
    if ($BaselineInDistro) { Note "wsl-base input: path:$BaselineInDistro" }
  }

  # No git step here: the stock image has no git, and a directory that is not
  # a repository is read as a plain path flake, which sees every file. The
  # repository is made below, once the baseline has installed git.

  # ------------------------------------------------------------------- build

  Step "Building the first generation (this takes a while on a cold store)"
  Note "nixos-rebuild boot, not switch: this build renames the machine's user."
  # devenv.cachix.org is passed by hand on this first build only: the baseline
  # configures it, but has not been applied yet, and without it the pinned
  # devenv release is compiled from source instead of downloaded.
  Invoke-InDistro -Stream "cd ~/$ConfigDir && sudo nixos-rebuild boot --flake .#wsl --option extra-experimental-features 'nix-command flakes' --option extra-substituters 'https://devenv.cachix.org' --option extra-trusted-public-keys 'devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw='"

  # ----------------------------------------------------------------- restart

  Step "Restarting '$Distro' so the new user takes effect"
  & wsl -t $Distro | Out-Null
  & wsl -d $Distro --user root exit | Out-Null
  & wsl -t $Distro | Out-Null
}

# --------------------------------------------------------------- config home

# The flake was written while logged in as nixos, so it sits in /home/nixos,
# but the user it created logs in to /home/<name>. Move it to where
# ~/$ConfigDir finds it. Safe to repeat: it does nothing once moved, and never
# overwrites a config already in the new home.
$src = "/home/nixos/$ConfigDir"
$dst = "/home/$UserName/$ConfigDir"
if ($src -ne $dst) {
  $moved = (Invoke-InDistro -AsRoot "if [ -d $src ] && [ ! -e $dst ]; then mv $src $dst && chown -R ${UserName}:`$(id -gn $UserName) $dst && echo moved; fi") -join ''
  if ($moved -match 'moved') { Note "moved $src to $dst" }
}
$hasFlake = (Invoke-InDistro "test -f ~/$ConfigDir/flake.nix && echo yes || echo no") -join ''
if ($hasFlake -notmatch 'yes') {
  throw "No flake.nix in $dst (nor in $src). Nothing to apply."
}

# -------------------------------------------------------------- devenv shell

# ~/$ConfigDir is also a devenv project, so cd-ing into it gives the tools for
# editing a Nix config: nixd (language server), nixfmt, and `rebuild`. It only
# shapes the shell in that directory; the machine is still flake.nix. Files
# that already exist are left alone, so a user's own edits survive a rerun.
$devenvFiles = [ordered]@{
  'devenv.nix'  = @'
{ pkgs, ... }:

{
  # Tools for editing this machine config. The machine itself is flake.nix
  # (and home.nix, if you use it); this file only shapes the shell you get in
  # this directory.
  packages = [
    pkgs.nixd   # language server, for the editor
    pkgs.nixfmt # formatter
  ];

  scripts.rebuild.exec = ''
    sudo nixos-rebuild switch --flake "$DEVENV_ROOT#wsl" "$@"
  '';
  scripts.update-baseline.exec = ''
    nix flake update wsl-base --flake "$DEVENV_ROOT" && rebuild
  '';

  enterShell = ''
    echo "wsl-config: edit flake.nix, then 'rebuild'. 'update-baseline' pulls the pinned baseline."
  '';
}
'@
  'devenv.yaml' = @'
inputs:
  nixpkgs:
    url: github:cachix/devenv-nixpkgs/rolling
'@
  '.envrc'      = @'
#!/usr/bin/env bash

eval "$(devenv direnvrc)"
use devenv
'@
}

# Everything below travels as base64 and is piped into bash, so the scripts
# can quote freely without going through wsl.exe's command line.
function Invoke-InDistroBash([string] $Bash) {
  $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($Bash -replace "`r", '')))
  Invoke-InDistro "echo $b64 | base64 -d | bash"
}

$writeFiles = foreach ($name in $devenvFiles.Keys) {
  $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($devenvFiles[$name] -replace "`r", '') + "`n"))
  "[ -e '$name' ] || { echo '$b64' | base64 -d > '$name'; echo 'wrote $name'; }"
}
$devenvOut = Invoke-InDistroBash (@"
set -e
cd ~/$ConfigDir
$($writeFiles -join "`n")
touch .gitignore
for l in '.devenv*' 'devenv.local.nix' 'devenv.local.yaml' '.direnv' 'result' '*.swp' '*~'; do
  grep -qxF "`$l" .gitignore || echo "`$l" >> .gitignore
done
# devenv's modules pinned to the devenv installed here, as devenvify does for
# projects: unpinned, the first build locks the newest devenv on GitHub, and
# a devenv command older than its modules prints errors into every shell.
# Only added when missing, so a pin the user moved is theirs.
if ! grep -qE '^[[:space:]]+devenv:' devenv.yaml; then
  v=`$(devenv version 2>/dev/null | sed -nE 's/^devenv ([0-9]+\.[0-9]+\.[0-9]+).*/v\1/p' || true)
  if [ -n "`$v" ]; then
    sed -i -E "0,/^inputs:[[:space:]]*`$/s||inputs:\n  devenv:\n    url: github:cachix/devenv/`$v|" devenv.yaml
    echo "wrote devenv pin `$v in devenv.yaml"
  fi
fi
direnv allow .
"@)
$devenvOut | Where-Object { "$_" -like 'wrote *' } | ForEach-Object { Note "$_" }

# Build the shell once now: that writes devenv.lock, so it is committed below,
# and the user's first cd into this directory is instant rather than a build.
# Streamed and announced: it downloads the shell's own nixpkgs and tools, a
# few minutes on a cold machine, and was silent before.
Step "Building the devenv shell for ~/$ConfigDir (downloads its tools: nixd, nixfmt)"
Invoke-InDistro -Stream "cd ~/$ConfigDir && direnv exec . true"

# A flake in a git repository only sees tracked files, so everything is added.
# git is there now: the baseline installs it, and /etc/gitconfig carries the
# identity. A new repository gets one commit, so the user starts from a clean
# history rather than a tree nix warns is dirty; after that it is theirs, and
# a rerun only commits the files this script itself manages.
Invoke-InDistroBash (@"
set -e
cd ~/$ConfigDir
[ -d .git ] || git init -q
git add -A
own='devenv.nix devenv.yaml devenv.lock .envrc .gitignore'
if ! git rev-parse -q --verify HEAD >/dev/null; then
  git commit -qm 'Machine config, written by bootstrap.ps1'
elif ! git diff --cached --quiet -- `$own; then
  git commit -qm 'Add a devenv shell for editing this config' -- `$own
fi
"@) | Out-Null

# ------------------------------------------------------------- prompt config

# A starting point for the prompt, written once: ~/.config/starship.toml gets
# this only if it does not exist, and from then on the file is the user's --
# no rerun touches it. The baseline itself only provides the starship hook
# (company.shell.starship.enable), so there is one place to change the look,
# and it is in $HOME.
$starshipToml = @'
# Your prompt. bootstrap.ps1 wrote this once and will never touch it again:
# it is yours to change. Every option: https://starship.rs/config/
#
# Start over from a ready-made look:  starship preset --list
#                                     starship preset <name> -o ~/.config/starship.toml
# Back to starship's built-in default: delete this file.
# No starship at all: company.shell.starship.enable = false in ~/wsl-config.

# A blank line before each prompt, so one command's output is easy to tell
# from the next.
add_newline = true

# What the prompt shows, in order. Remove a line to drop it; $all instead
# would show everything starship knows about.
format = """
$hostname\
$directory\
$git_branch\
$git_status\
${env_var.DEVENV_ROOT}\
$dotnet\
$cmd_duration\
$line_break\
$character"""

# Which distro this is -- worth having once there is more than one.
[hostname]
ssh_only = false
format = "[$hostname]($style) in "
style = "bold dimmed green"

# The last three folders, starting at the repository root when inside one.
[directory]
truncation_length = 3
truncate_to_repo = true

[git_branch]
format = "on [$symbol$branch]($style) "

# Inside a devenv project: its shell is loaded. (devenv sets DEVENV_ROOT;
# starship's nix_shell module would say "impure (devenv-shell-env)".)
[env_var.DEVENV_ROOT]
format = "via [❄️ devenv]($style) "
style = "bold blue"

# The .NET SDK the folder's global.json picks.
[dotnet]
format = "via [$symbol($version )(🎯 $tfm )]($style)"

# How long the last command took, when it took more than two seconds.
[cmd_duration]
min_time = 2_000
format = "took [$duration]($style) "

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"
'@
$starshipB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($starshipToml -replace "`r", '') + "`n"))
$seeded = (Invoke-InDistro "mkdir -p ~/.config && { [ -e ~/.config/starship.toml ] || { echo '$starshipB64' | base64 -d > ~/.config/starship.toml && echo wrote; }; }") -join ''
if ($seeded -match 'wrote') { Note "wrote ~/.config/starship.toml -- your prompt, yours to change from now on" }

if ($rerun) {
  Step "Applying ~/$ConfigDir with nixos-rebuild switch"
  Invoke-InDistro -Stream "cd ~/$ConfigDir && sudo nixos-rebuild switch --flake .#wsl"
}

# -------------------------------------------------------------------- verify

Step "Checking the result"
$failures = @()

# Invoke-InDistro merges stderr in, and wsl.exe itself writes warnings there
# (e.g. a systemd user session that failed to start). Compare stdout only, and
# report anything on stderr as its own problem rather than as a wrong user.
$whoOut = @(Invoke-InDistro 'whoami')
$who = ($whoOut | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join ''
$whoErr = ($whoOut | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) -join ' '
if ($who.Trim() -eq $UserName) { Note "whoami: $who" }
else { $failures += "expected to be '$UserName' but the shell opened as '$who'" }
if ($whoErr) { $failures += "wsl reported a problem on login: $whoErr" }

$configuredEmail = (Invoke-InDistro 'git config --get user.email || true') -join ''
if ($Email -and $configuredEmail.Trim() -ne $Email) {
  $failures += "git user.email is '$($configuredEmail.Trim())', expected '$Email'"
}
else { Note "git user.email: $($configuredEmail.Trim())" }

foreach ($tool in @('direnv --version', 'devenv version', 'devenvify --help')) {
  try { Invoke-InDistro "$tool >/dev/null 2>&1" | Out-Null; Note "ok: $($tool.Split(' ')[0])" }
  catch { $failures += "$($tool.Split(' ')[0]) is not on PATH" }
}

if ($failures.Count -gt 0) {
  Write-Host ''
  foreach ($f in $failures) { Write-Host "    FAILED: $f" -ForegroundColor Red }
  throw "Bootstrap finished with $($failures.Count) problem(s). See the troubleshooting section of GETTING-STARTED.md."
}

Write-Host "`n==> Done. Open a shell with: wsl -d $Distro" -ForegroundColor Green
Note "Later changes: cd ~/$ConfigDir, edit flake.nix, then 'rebuild'"
Note "A project: cd <project> && devenvify  (lists the templates and modes)"
