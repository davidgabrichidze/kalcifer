# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 0.x.x   | :white_check_mark: |

## Reporting a Vulnerability

**Please do NOT open a public issue for security vulnerabilities.**

Instead, please email: **security@kalcifer.dev**

You should receive a response within 48 hours. We will work with you to understand the issue and coordinate a fix before any public disclosure.

### What to include

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

## Security Practices

- API authentication via hashed Bearer tokens (SHA-256)
- Tenant isolation enforced at the query level
- Input validation on all API endpoints
- Rate limiting per tenant
- No secrets in source code — environment variables only
- Dependencies audited via `mix deps.audit` (when available)
