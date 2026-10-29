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

1. Install NixOS-WSL (<https://github.com/nix-community/NixOS-WSL>), open it.
2. Create your config from the template:

   ```bash
   mkdir ~/wsl-config && cd ~/wsl-config
   nix flake init -t github:JesperJ/wsl-reference
   ```

3. Edit `flake.nix`: `hostName`, `user.name`, `user.fullName`, `user.email`.
   `user.name` should be the user you want to log in as -- on the first
   switch NixOS-WSL creates it and makes it the default.
4. Apply:

   ```bash
   git init && git add -A   # flakes only see tracked files
   sudo nixos-rebuild switch --flake .#wsl
   ```

   Then from Windows: `wsl --terminate NixOS` and reopen, so WSL starts as
   the new user.

Updating later: bump the tag in `inputs.wsl-base.url`, run
`nix flake update wsl-base`, then `sudo nixos-rebuild switch --flake .#wsl`.

### Shortcut: a ready-made image

Instead of steps 1-4, a maintainer can build a tarball with a person's
settings already in it, which `wsl --import` installs directly:

```bash
sudo nix run .#nixosConfigurations.wsl.config.system.build.tarballBuilder
wsl --import NixOS $env:USERPROFILE\NixOS nixos.wsl --version 2   # on Windows
```

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
| `company.home.modules` | `[]` | Your own home-manager modules (shell, dotfiles) |
| `company.nix.trustUser` | `true` | User in `trusted-users`, so devenv caches work |
| `company.nix.extraSubstituters` / `extraTrustedPublicKeys` | `[]` | Extra binary caches |
| `company.network.caCertificates` | `[]` | Corporate root CAs |
| `company.network.proxy` / `noProxy` | `null` | HTTP(S) proxy, including for nix-daemon |
| `company.network.windowsDns` | `true` | Let WSL generate `resolv.conf` from Windows |

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

## Design notes

- **Module first, function second.** `lib.mkWsl` only turns arguments into
  `company.*` options. Anything it does not expose is reachable through
  `extraModules`, so nobody has to fork to deviate.
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
- **`flake.lock` is committed.** Consumers get the versions CI tested, not
  whatever the branches moved to today. Bump deliberately with
  `nix flake update <input>`.
- `system.stateVersion` is set at install and never bumped afterwards; it is
  not the NixOS version.

## Checking

```bash
nix flake check                  # builds nixosConfigurations.example
```

`.github/workflows/check.yml` does the same plus evaluates the template. It
is inert while this lives inside `nixos-config` and starts running after the
spin-out.

## Spinning out

This tree is mirrored to <https://github.com/JesperJ/wsl-reference>, which is
where consumers point. History was kept by splitting the subdirectory rather
than copying files:

```bash
cd nixos-config
git subtree split --prefix=wsl-reference -b wsl-reference-export
git push git@github.com:JesperJ/wsl-reference.git wsl-reference-export:main
```

Re-run those two commands to push later changes made here. The standalone
repository is the one CI runs in, and the one `nix flake init -t` reads.

Remaining before a colleague can use it: tag `v0.1.0`, which is the ref
`templates/default/flake.nix` pins.
