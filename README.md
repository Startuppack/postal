![GitHub Header](https://github.com/postalserver/.github/assets/4765/7a63c35d-2f47-412f-a6b3-aebc92a55310)

**Postal** is a complete, self-hosted mail server — the open-source alternative to Sendgrid, Mailgun or Postmark, ready to run on your own infrastructure.

This is a fork maintained by [Startup Pack](https://startuppack.eu) that extends Postal with a full **provisioning API**, multi-tenant SCIM, and enterprise SSO features not available in the upstream project.

> ⚠️ **Still running in dev mode.** The Startup Pack deployment currently runs in **development** mode (Rails `development` — `RAILS_ENV` is not set, hence the "dev" badge in the UI footer). Before real production use, switch it to **production**: set `RAILS_ENV=production` (and `NODE_ENV=production`) on the web/smtp/worker processes, confirm `secret_key_base` and precompiled assets. Until then expect verbose logs, no asset caching and dev-mode behaviour.

* [Documentation](https://startuppack.github.io/postal/)
* [What this fork adds](#what-this-fork-adds)
* [API v2 reference](https://startuppack.github.io/postal/#api)
* [SCIM v2](https://startuppack.github.io/postal/#scim)
* [SSO / OIDC](https://startuppack.github.io/postal/#oidc)
* [Upstream project](https://github.com/postalserver/postal) — official Postal (Krystal Hosting Ltd, not affiliated)

---

## What this fork adds

> 🚧 **Major rewrite in progress.** The provisioning API, SCIM and SSO layers described below are being redesigned as a proper Rails engine with a stable public contract. The current implementation works but is considered **alpha** — interfaces may change without notice until the rewrite ships.

| Feature | Description |
|---|---|
| **Admin REST API v2** | Provision orgs, servers, domains, credentials and users over HTTP — no Rails console needed |
| **Per-user API access** | JWT (RS256) via any OIDC provider; role-enforced per endpoint |
| **Multi-user orgs** | `admin`, `member`, `readonly` roles per org, managed via API or SCIM |
| **SCIM v2 per-tenant** | `/scim/v2/tenants/:org/Users` — user lifecycle and org params managed by your IdP |
| **Multi-provider OIDC** | Multiple IdPs (Keycloak, Entra, Google…) with one login button each |
| **Back-Channel Logout** | IdP-initiated session invalidation via signed `logout_token` |
| **RP-Initiated Logout** | Postal redirects to the IdP `end_session_endpoint` on sign-out |
| **SSO auto-org** | New SSO users get a default org created from their username |
| **Auto SMTP server** | Every new org gets a Live server + credential automatically |

> This fork is not affiliated with the official [postalserver/postal](https://github.com/postalserver/postal) project.

---

## Documentation

Full API reference, configuration examples, SCIM and OIDC guides:

**[startuppack.github.io/postal](https://startuppack.github.io/postal/)**
