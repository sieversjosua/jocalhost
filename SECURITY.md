# Security

jocalhost is currently alpha software.

## LAN Control Boundary

The LAN status/control server is intended for trusted local networks only.

- Do not expose port `48231` to the public internet.
- Keep the LAN bearer token secret.
- Treat anyone with the token as able to inspect project status and start, stop, or restart configured projects.
- LAN traffic is HTTP in the current MVP; there is no TLS between Macs.
- Saved remote-host tokens are stored in the local user config at `~/.config/jocalhost/remote-hosts.plist`.

## Local Process Control

jocalhost starts commands configured by the local user. Only add projects you trust.

If a project lives under protected macOS folders such as `~/Documents`, macOS may require Full Disk Access for `jocalhost.app` before child dev servers can start correctly.

## Reporting Issues

For now, please report vulnerabilities privately to the maintainer before opening a public issue. Once the project has a public security contact, this file should be updated.
