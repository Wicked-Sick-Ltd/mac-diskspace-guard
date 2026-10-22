# Security Policy

## Reporting a vulnerability

Do not disclose vulnerabilities, credentials, customer data, or exploit details in public issues or pull requests.

Use this repository's **Security → Report a vulnerability** option when available. Otherwise contact a Wicked Sick Ltd repository maintainer through an existing private channel to arrange secure disclosure. Do not assume GitHub private reporting is enabled.

Include the affected version or commit, impact, reproduction steps, and a minimal redacted example. Do not send live secrets or production datasets. Coordinate disclosure with the maintainers.

## Supported versions

Report issues against the latest default branch. Older releases are assessed individually; this repository does not promise maintenance for every historical version.

## Development precautions

Keep secrets in approved local environment or secret-store configuration, never in source control. Use isolated test accounts and synthetic data. Preserve authentication, authorization, tenant isolation, and audit controls. Do not test against live infrastructure without explicit authorization for that target.
