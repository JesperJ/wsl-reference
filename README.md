# wsl-reference

A shared NixOS-WSL baseline for developer machines. A colleague's machine is
a hostname, a username and their git identity; everything a project needs
lives in that project's own `devenv.nix`.

```
this flake         -> what every WSL dev box has (nix, devenv, devenvify,
                      direnv, docker, nix-ld for VS Code, corporate CA/proxy,
                      git)
your flake         -> who you are (hostName, user, optional extras)
project/devenv.nix -> what the project needs (languages, services, tools)
```

## For colleagues: setting up a machine

From PowerShell 7 on Windows, with the
[latest `nixos.wsl`](https://github.com/nix-community/NixOS-WSL/releases/latest)
downloaded:

```powershell
.\scripts\bootstrap.ps1 -ImageFile '.\nixos.wsl' -UserName anna `
  -FullName "Anna Example" -Email anna@company.com
```

That installs the distro, writes your `flake.nix` from the template, builds
it, does the restart a username change needs, and checks the result. Your
config ends up in `~/wsl-config`, a git repository with a devenv shell for
editing it (`rebuild`, `update-baseline`). Running the script again on a
finished machine is safe: it applies the config and checks it, and renames
nothing.

[GETTING-STARTED.md](GETTING-STARTED.md) is the walkthrough: what the script
does, the same steps by hand, the checks and the troubleshooting.

Updating later: bump the tag in `inputs.wsl-base.url`, then
`update-baseline` in `~/wsl-config` -- or by hand, `nix flake update wsl-base`
and `sudo nixos-rebuild switch --flake .#wsl`.

### Shortcut: a ready-made image

Instead of steps 1-4, a maintainer can build a tarball with a person's
settings already in it, which `wsl --import` installs directly:

```bash
sudo nix run .#nixosConfigurations.wsl.config.system.build.tarballBuilder
wsl --import NixOS $env:USERPROFILE\NixOS nixos.wsl --version 2   # on Windows
```

### Without flakes

Flakes are the default and the supported way in, but they are not a
requirement. `default.nix` reads this repository's `flake.lock` through
flake-compat, in ordinary Nix with no experimental features, so a flakeless
consumer still gets the versions CI tested -- it produces a byte-identical
derivation to the flake path, and CI asserts that.

Write a `default.nix` of your own:

```nix
let
  wsl-base = import (builtins.fetchTarball {
    url = "https://github.com/JesperJ/wsl-reference/archive/v0.2.1.tar.gz";
    # Omit for a quick start, at the cost of a re-fetch every hour;
    # `nix-prefetch-url --unpack <url>` prints the value to pin.
    sha256 = "...";
  });
in
{
  nixosConfigurations.wsl = wsl-base.lib.mkWsl {
    hostName = "WSL-CHANGEME";
    user = {
      name = "changeme";
      fullName = "Change Me";
      email = "change.me@company.com";
    };
  };
}
```

and switch to it:

```bash
sudo nixos-rebuild switch -f . -A nixosConfigurations.wsl
```

Note the `import (...)` with no argument after it: `default.nix` evaluates to
an attribute set, not a function.

Everything the flake exposes is on that attribute set, so the module route
works too -- and `wsl-base.inputs.nixpkgs` is the nixpkgs from this lock,
which means no channel to configure:

```nix
wsl-base.inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    wsl-base.nixosModules.default
    { networking.hostName = "ANNA-PC-dev"; company.user.name = "anna";
      system.stateVersion = "26.05"; }
  ];
}
```

Updating later: edit the tag in the URL and re-pin `sha256`.

## For projects: devenv

The machine provides `devenv`, `direnv` and `devenvify`. In a project, start
from a shared template rather than from scratch:

```bash
devenvify                          # list the templates and the modes
devenvify --shared dotnet-mssql    # set the current directory up with one
cd .                               # direnv builds the shell
```

The mode says who owns the setup, and devenvify asks for one:

- `--shared`: the project's `devenv.yaml` imports the shared parts, pinned
  in its `devenv.lock` until someone runs `update-shared`;
- `--copy`: the parts are copied into the repo and are its own from then on;
- `--personal`: nothing goes into the repo's history; the folder is bound to
  the template on this machine only, for a repo you can't commit to.

`--shared` and `--copy` write `devenv.nix`, `devenv.yaml` and `.envrc`, and
append to `.gitignore` without clobbering it; existing files are left alone
unless you pass `-f`. The
[devenv-templates README](https://github.com/JesperJ/devenv-templates#readme)
has the parts and the details. `devenv init` still works if you would rather
begin empty.

The templates come from the `devenv-templates` input and are baked into the
`devenvify` derivation, so nothing needs that repository checked out. After a
template changes upstream: `nix flake update devenv-templates`, then rebuild.

`devenv` itself is not nixpkgs' copy but its own flake input, pinned to a
devenv release (`inputs.devenv.url`), so it can stay current while nixpkgs
stays on the stable release. The command and devenv's modules -- what a
`devenv.nix` can say -- are separate things, and a command older than the
modules a project locked prints errors into every shell it loads. So
`devenvify`, and the bootstrap for `~/wsl-config`, pin a new project's
modules to the devenv installed on the machine (`inputs.devenv` in its
`devenv.yaml`); without that, the first build locks whatever devenv is
newest on GitHub. To move it, edit the tag and run
`nix flake update devenv`. The binary comes prebuilt from devenv.cachix.org,
which is why the input does not follow this flake's nixpkgs -- that would
make every machine compile it.

From then on, entering the directory loads the project's shell. Binary caches
a project lists in `devenv.yaml` (`cachix.pull`) are honoured because the
user is a trusted Nix user (`company.nix.trustUser`).

## Options

Everything is under `company.*` and can be set from `extraModules` in your
flake:

| Option | Default | What it does |
|---|---|---|
| `company.user.{name,fullName,email}` | -- | Login name, git identity |
| `company.user.extraGroups` | `[]` | Groups beyond `wheel` and `docker` |
| `company.docker.enable` | `true` | Native Docker in the distro |
| `company.extraPackages` | `[]` | Machine-wide extras (project tools go in devenv) |
| `company.home.modules` | `[]` | Your own home-manager modules -- only with the opt-in module, see [Dotfiles](#dotfiles-optional) |
| `company.nix.trustUser` | `true` | User in `trusted-users`, so devenv caches work |
| `company.nix.extraSubstituters` / `extraTrustedPublicKeys` | `[]` | Extra binary caches |
| `company.network.caCertificates` | `[]` | Corporate root CAs |
| `company.network.proxy` / `noProxy` | `null` | HTTP(S) proxy, including for nix-daemon |
| `company.network.windowsDns` | `true` | Let WSL generate `resolv.conf` from Windows |
| `company.shell.starship.enable` | `true` | The starship prompt; its look is your `~/.config/starship.toml` |

Most of these mean the same thing on a machine that is not NixOS; they are
declared once in `modules/options.nix` and implemented twice. The exceptions
need a whole system and are NixOS-only: `company.user.extraGroups`,
`company.docker.enable`, `company.nix.trustUser`,
`company.network.windowsDns` and `company.shell.starship.enable`. See
[A distro that is not NixOS](#a-distro-that-is-not-nixos).

The company-wide values (CA, proxy, internal cache) belong in this repository,
set once in `modules/nixos/network.nix` or `nix.nix`, not repeated in every
colleague's flake.

If `mkWsl` is too narrow, skip it and use the module directly:

```nix
nixosConfigurations.wsl = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    wsl-base.nixosModules.default
    { networking.hostName = "ANNA-PC-dev"; company.user.name = "anna";
      system.stateVersion = "26.05"; }
    ./anything-else.nix
  ];
};
```

## Dotfiles (optional)

The baseline does not manage `$HOME` -- see the design note below. If you want
your shell and dotfiles declared too, opt in from your own flake:

```nix
extraModules = [
  wsl-base.nixosModules.home-manager
  { company.home.modules = [ ./home.nix ]; }
];
```

That wires home-manager into the same `nixos-rebuild switch` and layers your
modules over `modules/home`, which also carries a git identity and direnv at
user level -- the part that works unchanged on a WSL distro that is not NixOS.

## A distro that is not NixOS

NixOS-WSL is the supported way to run this, and what the rest of this README
assumes. But the parts of the baseline that live in `$HOME` do not need NixOS
underneath, so Ubuntu or Debian with Nix installed can have most of it through
home-manager:

```bash
mkdir ~/wsl-config && cd ~/wsl-config
nix flake init -t github:JesperJ/wsl-reference#home
# edit flake.nix, then, once:
nix run home-manager/release-26.05 -- switch --flake .#changeme
```

Afterwards it is `home-manager switch --flake .#<name>`. The `company.*`
options mean the same things here -- they are declared once in
`modules/options.nix` and implemented twice, by `modules/nixos` and by
`modules/home/standalone.nix`.

| | NixOS-WSL | This tier |
|---|---|---|
| devenv, devenvify, direnv + nix-direnv | yes | yes |
| git identity | `/etc/gitconfig` | `~/.config/git/config` |
| `company.extraPackages` | `environment.systemPackages` | `home.packages` |
| weekly gc | system timer | systemd *user* timer |
| extra binary caches | `/etc/nix/nix.conf` | `~/.config/nix/nix.conf`, and only for a trusted user |
| CA certificates | system bundle, nix-daemon included | this user's own tools only |
| proxy | shell and nix-daemon | shell only |
| `company.nix.trustUser` | yes | **not possible, see below** |
| docker | `company.docker.enable` | the distro's package manager |
| nix-ld for VS Code | needed, and enabled | not needed: the distro has a real `ld-linux` |
| `/etc/wsl.conf`, WSL DNS | managed | yours to edit |

Three things are root's, once, before the first switch:

1. **Make yourself a trusted Nix user.** Nix reads `trusted-users` only from
   root's `/etc/nix/nix.conf`, by design -- a user who could grant it to
   themselves would not be restricted by it -- so this tier cannot do it for
   you. Skip it and the caches a project names in its `devenv.yaml` are
   silently ignored, and every project builds what a cache already has. Pass
   `--extra-conf "trusted-users = root $USER"` to the Nix installer, or add
   that line to `/etc/nix/nix.conf` and `sudo systemctl restart nix-daemon`.
2. **Enable systemd** if the distro has not: `systemd=true` under `[boot]` in
   `/etc/wsl.conf`, then `wsl -t <distro>` from Windows. The gc timer is a
   user service and needs a session.
3. **Docker and the system CA store**, if you need them: the distro's package
   manager, and `/usr/local/share/ca-certificates` plus
   `update-ca-certificates`. `company.network.caCertificates` still points
   this user's tools at a bundle it builds, but the nix daemon reads its own
   environment and that is root's to set.

## Design notes

- **Module first, function second.** `lib.mkWsl` only turns arguments into
  `company.*` options. Anything it does not expose is reachable through
  `extraModules`, so nobody has to fork to deviate.
- **No home-manager by default.** Everything the baseline needs from it is a
  plain NixOS option: `programs.direnv` installs the hook every devenv project
  relies on, and `programs.git.config` writes the identity to `/etc/gitconfig`,
  which is the right scope for a distro with exactly one user. What
  home-manager would add on top is a managed `$HOME` -- and there
  `~/.config/git/config` becomes a read-only store symlink, so
  `git config --global` fails, while a generated `~/.bashrc` reverts
  hand-edits on the next switch. A fair trade for someone who chose it, a bad
  surprise for someone handed a work machine, so it is
  [opt-in](#dotfiles-optional). NixOS itself is already unfamiliar at the
  system level; `$HOME` is where muscle memory lives.
- **Two tiers, one vocabulary.** `modules/options.nix` declares the options
  both tiers can honour and implements none of them; `modules/nixos` and
  `modules/home/standalone.nix` each implement them in their own terms. So
  there is one set of names to document, and moving a colleague from Ubuntu to
  NixOS-WSL changes the entry point rather than the configuration. Options
  that need a whole system stay declared beside the tier that can honour them,
  which makes asking for one on the home tier an evaluation error -- `The
  option 'company.docker' does not exist` -- instead of a setting that
  silently does nothing.
- **Stable nixpkgs.** Many people rebuild from this; a broken unstable bump
  would break all of them at once. Projects needing newer tools get them from
  devenv, which pins its own nixpkgs.
- **Passwordless sudo is kept.** NixOS-WSL sets it, deliberately: on WSL,
  `wsl -u root` from Windows is root without any password, so a sudo password
  stops no one and locks out the owner. The Windows login is the boundary.
- **No sshd.** A WSL2 distro sits behind NAT, so reaching it from outside
  needs mirrored networking in `.wslconfig` or a `netsh portproxy` on the
  Windows side -- and anyone who can run `wsl.exe` already has a root shell
  without authenticating. So an sshd here adds a listening service and an
  `authorized_keys` file to maintain while protecting nothing. VS Code Remote
  - WSL does not use ssh. If a machine genuinely needs it, `extraModules` can
  set `services.openssh` and
  `users.users.<name>.openssh.authorizedKeys.keys` directly.
- **Flakes are the default, not a requirement.** `default.nix` exists so a
  machine that cannot enable them is not shut out. It resolves the same
  `flake.lock`, and CI asserts it reaches the same derivation as the flake
  path, so the flakeless route is the same machine rather than a second one
  that drifts. The box itself still has `nix-command` and `flakes` switched
  on either way, because devenv needs them -- what is optional is how the
  configuration is consumed, not what the machine can do.
- **`flake.lock` is committed.** Consumers get the versions CI tested, not
  whatever the branches moved to today. Bump deliberately with
  `nix flake update <input>`.
- **Windows programs run from the shell.** With systemd, WSL's binfmt entry
  for `.exe` files does not survive boot, and `code .` -- or any `.exe` --
  fails with "Exec format error". The baseline sets
  `wsl.interop.register` so NixOS registers it itself; NixOS-WSL leaves that
  off by default. `mkDefault`, so a machine can turn it back off.
- `system.stateVersion` is set at install and never bumped afterwards; it is
  not the NixOS version.

## Checking

```bash
nix flake check                  # builds all three examples: the machine, the
                                 # home-manager opt-in, and the non-NixOS tier
```

`.github/workflows/check.yml` does the same, plus: evaluates both templates
against the checkout, checks that `default.nix` reaches the same derivation
as the flake, checks that `scripts/bootstrap.ps1` parses, and checks that
every release pin agrees (`scripts/check-version-pins.sh`) -- on a tag push,
that they name that tag. It runs on pushes to `main`, on `v*` tags and on
pull requests.

## Releasing

A machine gets the baseline through a tag: the templates pin
`github:JesperJ/wsl-reference/vX.Y.Z`, and so does the README's flakeless
example. A release has to move all of them, or new machines quietly get the
previous version. So it is one command, on `main` with a clean tree, once
the changes are merged:

```bash
scripts/release.sh v0.2.0
```

It rewrites every pin to the new tag, checks none was missed, commits
"Release v0.2.0" and tags it -- and stops there. Look it over, then publish:

```bash
git push origin main v0.2.0
```

CI checks the pushed tag again. Existing machines move when their owner
bumps the tag in their own `flake.nix` and runs `update-baseline`.
