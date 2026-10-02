# Security

ShipNotes handles App Store Connect private keys, optional AI API keys, and separate Apple Ads credentials. Problems involving credential disclosure, unintended remote writes, or data sent to the wrong endpoint should be reported privately.

## Reporting a vulnerability

When private vulnerability reporting is enabled, use the **Report a vulnerability** button on the repository's [Security advisories page](https://github.com/HuangCodes233/ShipNotes/security/advisories).

If that button is unavailable, do not put sensitive details in a public issue. Open an issue containing only a request for a private security contact, with no exploit details, credentials, or account information. Wait for a private channel before sending the report.

A useful report includes the affected commit, environment, minimal reproduction, impact, and a suggested fix if available. Use fictitious credentials and sanitized fixtures. This project does not provide a bug bounty or guarantee a response time.

## Scope and verification

Security fixes target the current default branch. There is no supported stable release series yet. Mock tests and automated secret scans help detect regressions, but do not establish that the app has received an independent security audit.

See [credentials and data flow](docs/privacy-and-data.md) for storage and network behavior. If an actual credential is exposed, revoke or rotate it with its issuing service; removing it from a file or Git history does not invalidate it.
