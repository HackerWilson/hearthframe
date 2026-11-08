# Security Policy

## Supported versions

| Version | Supported |
| --- | --- |
| 0.1.x | Yes |

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting:

<https://github.com/HackerWilson/hearthframe/security/advisories/new>

Do not open a public issue for security problems, and never paste real
credentials, NAS hostnames, tokens or personal photos. Include the affected
version, platform, reproduction steps and impact.

We aim to acknowledge reports within a few days. There is no bug bounty.

## Security model and known limitations

- No telemetry, analytics, accounts or cloud service. Network traffic goes
  only to the source configured by the user.
- Credentials are stored in app-private `SharedPreferences`, protected by the
  OS app sandbox; they are not additionally encrypted at rest.
- WebDAV supports plain HTTP for trusted LANs; prefer HTTPS.
- The SMB client supports SMB 1/2.0/2.1. SMB1 is legacy and should not be
  exposed beyond a trusted network. Prefer a dedicated read-only account.
- The Android Local folder source requests all-files access
  (`MANAGE_EXTERNAL_STORAGE`). Use a network source if that is not acceptable.
- `keep_adb` is opt-in and requires `WRITE_SECURE_SETTINGS`, granted manually
  over ADB. Without the grant the feature is a no-op.
- Release builds in this repository are signed with the Android debug key.
  Sign with your own key before distributing builds.
