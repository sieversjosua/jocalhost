# Development Distribution

## Goal

During development, one Mac can act as the build source and deploy the current app bundle plus CLI tools to another Mac over SSH.

This is an internal development channel, not a public release mechanism:

```txt
source Mac -> release build -> SSH/rsync -> target Mac user install
```

For public users, prefer a signed and notarized release once that exists.

## One-Time Target Mac Setup

On the target Mac:

1. Open System Settings.
2. Go to General -> Sharing.
3. Enable Remote Login.
4. Allow your user account.
5. Note the host name, for example `Target-Mac.local`.

From the source Mac, test SSH:

```sh
ssh user@Target-Mac.local
```

If this asks for a password every time, add your source Mac SSH key to the target Mac:

```sh
ssh-copy-id user@Target-Mac.local
```

If `ssh-copy-id` is not installed, copy the source Mac public key into `~/.ssh/authorized_keys` on the target Mac.

## Deploy From Source Mac

From this repo:

```sh
./scripts/deploy-remote-mac.sh user@Target-Mac.local
```

The script does this:

1. Builds release artifacts with `scripts/build-app.sh`.
2. Copies `dist.noindex/jocalhost.app`, `dist/jocalhostctl`, and `dist/jocalhost-mcp` to the target Mac.
3. Stops the old `jocalhost` process on the target Mac.
4. Installs the app into `~/Applications/jocalhost.app`.
5. Installs CLI tools into `~/.local/bin`.
6. Removes quarantine attributes.
7. Opens the updated app.

Override install locations when needed:

```sh
JOCALHOST_REMOTE_APP_DIR=Applications \
JOCALHOST_REMOTE_BIN_DIR=.local/bin \
./scripts/deploy-remote-mac.sh user@Target-Mac.local
```

Deploy without opening the app:

```sh
JOCALHOST_OPEN_AFTER_INSTALL=0 ./scripts/deploy-remote-mac.sh user@Target-Mac.local
```

## Connect A Client Mac To A Host Mac

On the host Mac:

```sh
./dist/jocalhostctl lan-info
```

On the client Mac:

```sh
~/.local/bin/jocalhostctl remote-add "Workstation" <host-ip-or-name> --token "<token-from-lan-info>"
```

Then open `~/Applications/jocalhost.app` on the client Mac. The host should appear in the Remote section.

If the host serves projects under protected folders such as `~/Documents`, give the host's `jocalhost.app` Full Disk Access. Without that, remote start/stop can work while the child dev server hangs before opening its port.

Development builds are ad-hoc signed with a stable designated requirement. After upgrading from older cdhash-only builds, toggle Full Disk Access once for `/Applications/jocalhost.app`; future dev rebuilds should keep the same macOS privacy identity.

## Recommended Development Loop

1. Change code on the source Mac.
2. Run:
   ```sh
   swift build
   swift test
   swift run jocalhost-checks
   ```
3. Deploy:
   ```sh
   ./scripts/deploy-remote-mac.sh user@Target-Mac.local
   ```
4. Use the target Mac menu bar app against the configured remote host.

## Later Production Channel

For public release, replace this SSH channel with:

- Developer ID signing.
- Notarization.
- Versioned release artifacts.
- Auto-update feed or package manager distribution.
- In-app update checks.

The SSH deploy script should remain the fast internal development channel.
