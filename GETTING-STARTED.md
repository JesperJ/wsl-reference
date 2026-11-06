# Getting started

The path from a Windows machine with nothing installed to a project shell that
loads itself when you `cd` into it. The [README](README.md) is the reference --
what the options are, and why the baseline is shaped the way it is. This is the
walkthrough.

If your distro is not NixOS -- Ubuntu or Debian with Nix on top -- see
[A distro that is not NixOS](README.md#a-distro-that-is-not-nixos) instead;
this walkthrough assumes NixOS-WSL.

If a maintainer handed you a ready-made `nixos.wsl` with your details already
in it, your name and git identity are already set: install it as in step 1 and
skip to step 4.

## The scripted way

`scripts/bootstrap.ps1` does all of steps 1 to 4 below, plus the restart and
the checks, from the Windows side. Download it and the
[latest `nixos.wsl`](https://github.com/nix-community/NixOS-WSL/releases/latest),
then from PowerShell (7, not Windows PowerShell 5.1):

```powershell
.\bootstrap.ps1 -ImageFile '.\nixos.wsl' -UserName anna `
  -FullName "Anna Example" -Email anna@company.com
```

- The distro is registered as `dev`: open it with `wsl -d dev`. `-Distro`
  picks another name (`wsl -l -v` lists the ones you have).
- `-HostName` defaults to your Windows computer name plus `-dev`.
- No WSL yet? It says how to install it, or does it for you with
  `-InstallWsl` (behind an elevation prompt).
- The build prints as it goes. A cold one is many minutes; let it run.

You end up logged in as yourself, with your config in `~/wsl-config` as a git
repository. Entering that directory gives a shell for editing it: `nixd` and
`nixfmt` for the editor, and two commands, `rebuild` (apply your changes) and
`update-baseline` (pull the pinned baseline, then rebuild).

Running the script again on a machine that is already set up is safe, and
needs no arguments (`-Distro` if you picked another name): it renames
nothing, applies `~/wsl-config` with
`switch`, and runs the checks again.

It is a PowerShell script rather than a shell script because the restart in
step 3 cannot be done from inside the distro being restarted.

The rest of this page is the same thing by hand, which is worth reading once:
the script fails on the same things, and the troubleshooting at the bottom
applies either way.

## Step 1: WSL and NixOS-WSL

NixOS-WSL expects the Microsoft Store version of WSL 2, which is available on
both Windows 10 and 11. If you have no WSL yet, from PowerShell:

```powershell
wsl --install --no-distribution
```

Restart if it asks. Then download `nixos.wsl` from the
[latest NixOS-WSL release](https://github.com/nix-community/NixOS-WSL/releases/latest)
and install it. On WSL 2.4.4 or newer you can double-click the file, or:

```powershell
wsl --install --from-file nixos.wsl
```

On older WSL:

```powershell
wsl --import NixOS $env:USERPROFILE\NixOS nixos.wsl --version 2
```

The commands below say `NixOS`, the name a double-clicked image registers
under. If you installed under another name -- `wsl --install --from-file
nixos.wsl --name dev`, say, which is how you keep a second distro from
colliding with one you already have -- substitute it everywhere, including
in the restart sequence in step 3.

Open a shell with `wsl -d NixOS`, or pick NixOS from the Windows Terminal
dropdown. You are the `nixos` user for now, with passwordless sudo.

## Step 2: your own configuration

First, as NixOS-WSL asks of a fresh image:

```bash
sudo nix-channel --update
```

The stock image does not have flakes switched on yet -- this baseline turns
them on, but it has not been applied -- so the first few commands pass the
feature explicitly. Either prefix each with the flag:

```bash
alias nixf="nix --extra-experimental-features 'nix-command flakes'"
mkdir ~/wsl-config && cd ~/wsl-config
nixf flake init -t github:JesperJ/wsl-reference
```

...or skip flakes entirely and use the flakeless route in
[Without flakes](README.md#without-flakes), which needs no experimental
features at all.

Now edit `flake.nix` and set four things:

| Field | What it is |
|---|---|
| `hostName` | What the machine calls itself: your Windows computer name plus `-dev`, e.g. `ANNA-PC-dev` |
| `user.name` | The login name you want. **Not** `nixos` -- this creates your account |
| `user.fullName` | Your name, for git commits |
| `user.email` | Your work email, for git commits |

Leave git for now: the stock image does not have it, and the baseline is what
installs it. Without a repository the directory is read as a plain path flake,
which sees every file, so nothing is lost.

## Step 3: the first switch

This step is the one to do carefully, and only once. You are changing the
machine's username -- the image ships as `nixos` and you are creating your own
account -- and for that NixOS-WSL is explicit that `nixos-rebuild switch` can
leave the new account misconfigured. Use `boot`, then restart the distro in
the prescribed order.

In the WSL shell:

```bash
sudo nixos-rebuild boot --flake .#wsl \
  --option extra-experimental-features 'nix-command flakes' \
  --option extra-substituters 'https://devenv.cachix.org' \
  --option extra-trusted-public-keys 'devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw='
```

The last two lines point this one build at devenv's binary cache, which the
baseline sets up but has not applied yet; without them devenv is compiled from
source.

Then from Windows (PowerShell or Command Prompt):

```powershell
wsl -t NixOS
wsl -d NixOS --user root exit
wsl -t NixOS
```

Open a WSL shell again. `whoami` should be your own name. Your config is
still in the old `nixos` home, so move it into yours and put it under git,
which is installed now -- a flake in a repository only sees tracked files:

```bash
sudo mv /home/nixos/wsl-config ~ && sudo chown -R "$USER:" ~/wsl-config
cd ~/wsl-config && git init && git add -A && git commit -m "My machine config"
```

From here on a change is just:

```bash
sudo nixos-rebuild switch --flake .#wsl
```

No flag, no restart: the baseline has turned flakes on, and `switch` is the
right verb for everything that is not a username change.

## Step 4: check it worked

```bash
whoami                      # your name, not nixos
git config --get user.email # your address, from /etc/gitconfig
direnv --version            # the project bridge
devenv version
devenvify                   # lists the shared project templates
docker run --rm hello-world # native docker in the distro
```

If `git config --get user.email` is empty, `user.email` in your `flake.nix` is
still the placeholder.

## Step 5: your first project

Project tooling does not go in the machine config. It goes in the project, so
it travels with the repository and everyone gets the same shell:

```bash
cd ~/code/my-service
devenvify                          # see the templates, and the three modes
devenvify --shared dotnet-mssql    # set the project up with one
cd .                               # direnv builds the shell
```

`--shared` is the usual choice for your own repos: the project imports the
team's setup and takes improvements when it chooses to. `--copy` gives the
repo its own copy instead, and `--personal` is for a repo you can't commit
devenv files to. `devenvify` with no arguments explains all three.

That writes `devenv.nix`, `devenv.yaml` and `.envrc`, and appends to
`.gitignore` without clobbering it. Existing files are left alone unless you
pass `-f`. From now on, entering the directory loads the project's shell and
leaving it unloads it. `devenv init` still works if you would rather start
empty.

The first time builds the shell and can take a while; afterwards it is
cached and instant.

## VS Code

Install the **WSL** extension on the Windows side, then run `code .` from
inside a project. Two things make that work, both in the baseline: `code` is
a Windows program, which runs because the baseline registers WSL's handler
for `.exe` files; and the server VS Code downloads is a generic Linux binary
that NixOS would normally refuse to start, which runs because the baseline
enables `nix-ld`. Nothing to configure.

A shell opened from the Windows profile folder (`wsl -d dev` from a fresh
terminal) starts there, in `/mnt/c/Users/<you>`. To land in `~` instead,
open it with `wsl -d dev --cd ~`, or set the starting directory to `~` in
your Windows Terminal profile.

## Your prompt

The shell comes with [starship](https://starship.rs): the machine, the
directory, the git branch and its state, the devenv shell you are in, the
.NET SDK. It is a default, not a requirement:

- **Change it:** edit `~/.config/starship.toml`. The bootstrap script wrote
  it once, commented, as a starting point, and never touches it again --
  it is your file. Changes show on the next prompt; no rebuild.
  ([Every option](https://starship.rs/config/); for a different look
  altogether, `starship preset --list`.) Set up by hand rather than by the
  script, there is no file, and starship uses its own defaults until you
  write one.
- **Back to the starting point:** delete the file and run the bootstrap
  script again.
- **Turn it off:** `company.shell.starship.enable = false;` in `extraModules`,
  then rebuild.

If some symbols show as boxes, your terminal font lacks them: pick a
[Nerd Font](https://www.nerdfonts.com) in Windows Terminal, or use the
`plain-text-symbols` preset above.

## Day to day

In `~/wsl-config`, if the script set it up, `rebuild` and `update-baseline`
are shorthand for the first two rows.

| Task | Command |
|---|---|
| Apply a config change | `sudo nixos-rebuild switch --flake .#wsl` |
| Update the baseline | edit the tag in `inputs.wsl-base.url`, then `nix flake update wsl-base` and switch |
| Try a baseline change before it is released | `sudo nixos-rebuild switch --flake .#wsl --override-input wsl-base path:/mnt/c/<clone> --no-write-lock-file` |
| Update project templates | `nix flake update devenv-templates` in your config, then switch |
| See past generations | `sudo nix-env --list-generations -p /nix/var/nix/profiles/system` |
| Go back one | `sudo nixos-rebuild switch --rollback` |
| Free disk space | happens weekly on its own; force with `sudo nix-collect-garbage -d` |
| Shut the distro down | `wsl -t NixOS` from Windows |

## On a corporate network

The things that break first are the same for everyone, so they belong in the
baseline rather than in your flake -- tell whoever maintains it. If you need
them locally in the meantime, they are
[options](README.md#options): `company.network.caCertificates` for a
TLS-inspecting proxy, `company.network.proxy` for an HTTP proxy (it reaches
the nix daemon too, which is what actually fetches), and
`company.network.windowsDns`, on by default, which lets WSL generate
`/etc/resolv.conf` from Windows so VPN DNS works.

## Troubleshooting

**`experimental Nix feature 'nix-command' is disabled`**
You are still on the stock image. Add
`--option extra-experimental-features 'nix-command flakes'` as in step 3, or
use the flakeless route.

**`path ... is not tracked by Git`, or `does not provide attribute`**
A flake only sees tracked files. `git add -A` and try again.

**Still logged in as `nixos` after the first switch**
The restart sequence in step 3 was not completed. Run the three `wsl` commands
and open a fresh shell.

**`error: file 'nixpkgs' was not found in the Nix search path`**
Run `sudo nix-channel --update` once, as NixOS-WSL's install notes say. The
flake does not need channels, but the stock image's tooling can still ask.

**devenv compiles everything instead of downloading it**
A project's binary caches from `devenv.yaml` are only honoured for a trusted
Nix user. The baseline makes you one (`company.nix.trustUser`, on by default),
so this means either that it is switched off, or that the cache needs its key
in `company.nix.extraTrustedPublicKeys`.

**`cannot execute binary file: Exec format error` running `code` or any `.exe`**
WSL's handler for Windows programs is not registered. The baseline registers
it (`wsl.interop.register`), so this means the machine is on a release from
before that: update the baseline. To fix one machine meanwhile, set
`wsl.interop.register = true;` in `extraModules`.

**`structuredAttrs: command not found` when a devenv shell loads**
The devenv command is older than the devenv modules the project pulled. The
baseline pins a current devenv; update the baseline.

**A project tool is missing**
It belongs in that project's `devenv.nix`, not in the machine. If it is
genuinely machine-wide -- something you want in every project -- it is
`company.extraPackages`.

## Where things belong

This is the discipline that keeps a shared baseline shareable:

```
the baseline          -> what every WSL dev box has (nix, devenv, direnv,
                         docker, nix-ld, corporate CA/proxy, git)
your flake.nix        -> who you are: hostname, login name, git identity,
                         and your own extras (extraModules, home.nix)
project/devenv.nix    -> what the project needs: languages, services, tools
```

If you find yourself adding a language or a database to your `flake.nix`, it
almost certainly belongs in a project instead.
