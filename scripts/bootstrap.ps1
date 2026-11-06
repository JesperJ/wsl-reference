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
  WSL registration name, as `wsl -l -v` shows it. This is the only name that
  can collide with a distro you already have; it is unrelated to HostName.

.PARAMETER ImageFile
  Path to a nixos.wsl image. Only used when Distro is not registered yet.

.EXAMPLE
  .\bootstrap.ps1 -Distro dev -UserName anna -FullName "Anna Example" `
    -Email anna@company.com

.EXAMPLE
  .\bootstrap.ps1 -Distro dev -ImageFile '.\nixos (1).wsl' -UserName anna
#>
[CmdletBinding()]
param(
  [string] $Distro = 'NixOS',
  [Parameter(Mandatory = $true)][string] $UserName,
  [string] $FullName = '',
  [string] $Email = '',
  [string] $HostName,
  [string] $ImageFile,
  [string] $TemplateUrl = 'github:JesperJ/wsl-reference',
  [string] $ConfigDir = 'wsl-config',
  [switch] $Force
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- validation

# Anything that reaches a bash command line below is checked here, so the
# in-distro scripts can stay single-quoted with no escaping to get wrong.
# Your name and e-mail are NOT on that list: they travel as base64.
if ($UserName -notmatch '^[a-z_][a-z0-9_-]{0,31}$') {
  throw "UserName '$UserName' is not a valid Linux login name (lower case, starts with a letter or _)."
}
if ($Distro -notmatch '^[A-Za-z0-9._-]{1,64}$') {
  throw "Distro '$Distro' has characters that are awkward to pass through a shell. Pick a simpler name."
}
if ($ConfigDir -notmatch '^[A-Za-z0-9._-]{1,64}$') {
  throw "ConfigDir '$ConfigDir' must be a single directory name under your home directory."
}
if (-not $HostName) { $HostName = "WSL-$($UserName.ToUpper())" }
if ($HostName -notmatch '^[A-Za-z0-9-]{1,63}$') {
  throw "HostName '$HostName' must be letters, digits and hyphens."
}
if ($UserName -eq 'nixos') {
  Write-Warning "UserName is 'nixos', the name the stock image already uses. Nothing will be renamed."
}

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Note($text) { Write-Host "    $text" -ForegroundColor DarkGray }

# Runs a bash login shell inside the distro. Login shell on purpose: that is
# what puts nix on PATH on a stock image.
function Invoke-InDistro {
  param([Parameter(Mandatory = $true)][string] $Script, [switch] $AsRoot)

  $wslArgs = @('-d', $Distro)
  if ($AsRoot) { $wslArgs += @('--user', 'root') }
  $wslArgs += @('--', 'bash', '-lc', $Script)

  $output = & wsl @wslArgs 2>&1
  if ($LASTEXITCODE -ne 0) {
    $output | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
    throw "Command failed inside '$Distro' (exit $LASTEXITCODE): $Script"
  }
  return $output
}

# `wsl -l -q` writes UTF-16; without this it arrives full of NUL bytes.
function Get-RegisteredDistros {
  $previous = [Console]::OutputEncoding
  try {
    [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
    return (& wsl -l -q) |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_ -ne '' }
  }
  finally { [Console]::OutputEncoding = $previous }
}

# ------------------------------------------------------------------- install

if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
  throw "wsl.exe not found. Install WSL first: wsl --install --no-distribution"
}

$registered = Get-RegisteredDistros
if ($registered -contains $Distro) {
  Step "Distro '$Distro' is already registered"
  if ($ImageFile) { Note "Ignoring -ImageFile: not reinstalling over an existing distro." }
}
elseif ($ImageFile) {
  if (-not (Test-Path -LiteralPath $ImageFile)) { throw "Image file not found: $ImageFile" }
  Step "Installing '$Distro' from $ImageFile"
  & wsl --install --from-file $ImageFile --name $Distro
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

# ----------------------------------------------------------------- configure

Step "Writing ~/$ConfigDir/flake.nix in '$Distro'"

$existing = Invoke-InDistro "test -f ~/$ConfigDir/flake.nix && echo yes || echo no"
if (($existing -join '') -match 'yes' -and -not $Force) {
  throw "~/$ConfigDir/flake.nix already exists in '$Distro'. Re-run with -Force to overwrite it."
}

# The template is fetched rather than embedded here, so there is one copy of
# it to keep correct. Flakes are not on yet on a stock image, hence the flag.
Invoke-InDistro "mkdir -p ~/$ConfigDir && cd ~/$ConfigDir && nix --extra-experimental-features 'nix-command flakes' flake init -t $TemplateUrl" | Out-Null

$template = (Invoke-InDistro "cat ~/$ConfigDir/flake.nix") -join "`n"
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

# base64 so a name with a quote, an accent or a space cannot break out of the
# command line it travels on.
$encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($flake))
Invoke-InDistro "echo '$encoded' | base64 -d > ~/$ConfigDir/flake.nix" | Out-Null
Note "hostName = $HostName, user.name = $UserName"

# A flake only sees tracked files.
Invoke-InDistro "cd ~/$ConfigDir && git init -q 2>/dev/null; git add -A" | Out-Null

# --------------------------------------------------------------------- build

Step "Building the first generation (this takes a while on a cold store)"
Note "nixos-rebuild boot, not switch: this build renames the machine's user."
Invoke-InDistro "cd ~/$ConfigDir && sudo nixos-rebuild boot --flake .#wsl --option extra-experimental-features 'nix-command flakes'"

# ------------------------------------------------------------------- restart

Step "Restarting '$Distro' so the new user takes effect"
& wsl -t $Distro | Out-Null
& wsl -d $Distro --user root exit | Out-Null
& wsl -t $Distro | Out-Null

# -------------------------------------------------------------------- verify

Step "Checking the result"
$failures = @()

$who = (Invoke-InDistro 'whoami') -join ''
if ($who.Trim() -eq $UserName) { Note "whoami: $who" }
else { $failures += "expected to be '$UserName' but the shell opened as '$who'" }

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
Note "Later changes: cd ~/$ConfigDir && sudo nixos-rebuild switch --flake .#wsl"
Note "A project: cd <project> && devenvify && direnv allow"
