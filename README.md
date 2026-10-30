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

> This directory is self-contained so it can be split out of `nixos-config`
> into its own repository; see [Spinning out](#spinning-out). Nothing in it
> refers to files outside `wsl-reference/`.

## For colleagues: setting up a machine

[GETTING-STARTED.md](GETTING-STARTED.md) is the walkthrough, with the Windows
side, the checks and the troubleshooting. In short:

1. Install NixOS-WSL (<https://github.com/nix-community/NixOS-WSL>), open it.
2. Create your config from the template. The stock image does not have flakes
   on yet -- this baseline is what turns them on -- so pass the feature for
   now, or use [Without flakes](#without-flakes) instead:

   ```bash
   mkdir ~/wsl-config && cd ~/wsl-config
   nix --extra-experimental-features 'nix-command flakes' \
     flake init -t github:JesperJ/wsl-reference
   ```

3. Edit `flake.nix`: `hostName`, `user.name`, `user.fullName`, `user.email`.
   `user.name` should be the user you want to log in as -- on the first
   build NixOS-WSL creates it and makes it the default.
4. Apply. `boot` rather than `switch`, and the restart sequence in full:
   this first build changes the machine's username, and NixOS-WSL warns that
   `switch` can leave the new account misconfigured.

   ```bash
   git init && git add -A   # flakes only see tracked files
   sudo nixos-rebuild boot --flake .#wsl \
     --option extra-experimental-features 'nix-command flakes'
   ```

   Then from Windows:

   ```powershell
   wsl -t NixOS
   wsl -d NixOS --user root exit
   wsl -t NixOS
   ```

   Open a shell again and you are your own user. Every later change is a
   plain `sudo nixos-rebuild switch --flake .#wsl`, with no flag and no
   restart.

Updating later: bump the tag in `inputs.wsl-base.url`, run
`nix flake update wsl-base`, then `sudo nixos-rebuild switch --flake .#wsl`.

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
    url = "https://github.com/JesperJ/wsl-reference/archive/v0.1.0.tar.gz";
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
    { networking.hostName = "WSL-ANNA"; company.user.name = "anna";
      system.stateVersion = "26.05"; }
  ];
}
```

Updating later: edit the tag in the URL and re-pin `sha256`.

## For projects: devenv

The machine provides `devenv`, `direnv` and `devenvify`. In a project, start
from a shared template rather than from scratch:

```bash
devenvify                 # list the available templates
devenvify dotnet-mssql    # copy one into the current directory
direnv allow
```

That writes `devenv.nix`, `devenv.yaml` and `.envrc`, and appends to
`.gitignore` without clobbering it; existing files are left alone unless you
pass `-f`. `devenv init` still works if you would rather begin empty.

The templates come from the `devenv-templates` input and are baked into the
`devenvify` derivation, so nothing needs that repository checked out. After a
template changes upstream: `nix flake update devenv-templates`, then rebuild.

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

Most of these mean the same thing on a machine that is not NixOS; they are
declared once in `modules/options.nix` and implemented twice. The exceptions
need a whole system and are NixOS-only: `company.user.extraGroups`,
`company.docker.enable`, `company.nix.trustUser` and
`company.network.windowsDns`. See
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
    { networking.hostName = "WSL-ANNA"; company.user.name = "anna";
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
- `system.stateVersion` is set at install and never bumped afterwards; it is
  not the NixOS version.

## Checking

```bash
nix flake check                  # builds all three examples: the machine, the
                                 # home-manager opt-in, and the non-NixOS tier
```

`.github/workflows/check.yml` does the same, plus evaluates the template and
checks that `default.nix` reaches the same derivation as the flake. It
runs in the standalone repository; the copy inside `nixos-config` is inert,
because GitHub only reads workflows from a repository root.

## Spinning out

This tree is mirrored to <https://github.com/JesperJ/wsl-reference>, which is
what consumers point at and where CI runs. History was kept by splitting the
subdirectory rather than copying files, so the standalone repository carries
the commits that made each change here.

To push later changes made in `nixos-config`:

```bash
cd nixos-config
git subtree push --prefix=wsl-reference \
  git@github.com:JesperJ/wsl-reference.git main
```

`git subtree push` re-splits and pushes in one step, which is what makes it
repeatable -- the `git subtree split -b <branch>` form used for the first
export refuses to run again once that branch exists.

Remaining before a colleague can use it: tag `v0.1.0`, which is the ref
`templates/default/flake.nix` pins, and make the repository public.
