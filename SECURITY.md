# Security

## Do not publish account material

Never commit or attach any of the following to an issue:

- Roblox `.ROBLOSECURITY` cookies or Cordial profile `cookies` files.
- Cordial `identity` files.
- `data/panel.db` from a real installation.
- Mail.tm passwords or other email credentials.
- Screenshots containing passwords or one-time verification codes.

The repository intentionally excludes these paths through `.gitignore`.

## Network exposure

The FastAPI panel and noVNC viewers do not provide their own authentication layer. Run them only on a trusted LAN/VPN/Tailscale network or behind an authenticated reverse proxy. Do not expose ports `8090` or `6090`–`6094` directly to the public Internet.

## Roblox / Cordial

Cordial is a third-party compatibility client and is not approved by Roblox. This repository does not ship Roblox binaries and does not provide anti-cheat bypasses, exploit executors, hooks, memory access or credential automation.

Report vulnerabilities privately to the repository owner rather than posting secrets in a public issue.
