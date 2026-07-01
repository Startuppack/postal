![GitHub Header](https://github.com/postalserver/.github/assets/4765/7a63c35d-2f47-412f-a6b3-aebc92a55310)

> **This is a fork maintained by [Startup Pack](https://startuppack.xyz).** It is not affiliated with the official [postalserver/postal](https://github.com/postalserver/postal) project.
>
> Changes introduced in this fork:
> - **Admin REST API v2** — a provisioning API (`/api/v2/`) created by Startup Pack to automate organization, server, domain, credential and user management without going through the web UI or the Rails console. The official Postal project provides no such API. See [API v2 documentation](#api-v2) below.
> - SCIM v2 endpoint with OIDC auto-provisioning
> - Admin user impersonation

---

**Postal** is a complete and fully featured mail server for use by websites & web servers. Think Sendgrid, Mailgun or Postmark but open source and ready for you to run on your own servers. 

* [Documentation](https://docs.postalserver.io)
* [Installation Instructions](https://docs.postalserver.io/getting-started)
* [FAQs](https://docs.postalserver.io/welcome/faqs) & [Features](https://docs.postalserver.io/welcome/feature-list)
* [Discussions](https://github.com/postalserver/postal/discussions) - ask for help or request a feature
* [Join us on Discord](https://discord.postalserver.io)

---

## API v2

The official Postal API (`/api/v1/`) is limited to sending and retrieving messages. This fork adds a full **admin provisioning API** under `/api/v2/`, created by Startup Pack.

> This API is not part of the upstream Postal project and is not officially supported by Krystal / postalserver.io.

### Enable

```yaml
# postal.yml
api:
  enabled: true
  bearer_token: <your-secret-token>
```

### Authentication

All requests require:

```
Authorization: Bearer <your-secret-token>
```

### Endpoints

#### Organizations

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v2/organizations` | List all organizations |
| `POST` | `/api/v2/organizations` | Create an organization |
| `GET` | `/api/v2/organizations/:permalink` | Get an organization |
| `PATCH` | `/api/v2/organizations/:permalink` | Update an organization |
| `DELETE` | `/api/v2/organizations/:permalink` | Delete an organization |
| `POST` | `/api/v2/organizations/:permalink/suspend` | Suspend |
| `POST` | `/api/v2/organizations/:permalink/unsuspend` | Unsuspend |

Create body: `{ "name": "Acme", "permalink": "acme", "time_zone": "UTC", "owner_email": "admin@acme.com" }`

#### Servers

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v2/organizations/:org/servers` | List servers |
| `POST` | `/api/v2/organizations/:org/servers` | Create a server |
| `GET` | `/api/v2/organizations/:org/servers/:server` | Get a server |
| `PATCH` | `/api/v2/organizations/:org/servers/:server` | Update a server |
| `DELETE` | `/api/v2/organizations/:org/servers/:server` | Delete a server |
| `POST` | `/api/v2/organizations/:org/servers/:server/suspend` | Suspend |
| `POST` | `/api/v2/organizations/:org/servers/:server/unsuspend` | Unsuspend |

Create body: `{ "name": "Transactional", "mode": "Live" }`

#### Domains

Domains can be attached to a server or directly to an organization.

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v2/organizations/:org/servers/:server/domains` | List server domains |
| `POST` | `/api/v2/organizations/:org/servers/:server/domains` | Add a domain to a server |
| `GET` | `/api/v2/organizations/:org/servers/:server/domains/:uuid` | Get domain (includes DKIM record) |
| `DELETE` | `/api/v2/organizations/:org/servers/:server/domains/:uuid` | Remove a domain |
| `POST` | `/api/v2/organizations/:org/servers/:server/domains/:uuid/verify` | Force-mark as verified |
| `POST` | `/api/v2/organizations/:org/servers/:server/domains/:uuid/dns_check` | Run DNS record check |

Create body: `{ "name": "example.com", "verification_method": "DNS" }`

The `GET` response includes `dkim_record_name` and `dkim_record` — publish these as a TXT record in your DNS to enable DKIM signing.

Org-level domain routes follow the same pattern under `/api/v2/organizations/:org/domains/`.

#### Credentials

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v2/organizations/:org/servers/:server/credentials` | List credentials |
| `POST` | `/api/v2/organizations/:org/servers/:server/credentials` | Create a credential |
| `GET` | `/api/v2/organizations/:org/servers/:server/credentials/:uuid` | Get a credential |
| `DELETE` | `/api/v2/organizations/:org/servers/:server/credentials/:uuid` | Delete a credential |

Create body: `{ "name": "SMTP Main", "type": "SMTP" }` — `type` is `SMTP`, `API`, or `SMTP-IP`.  
The `key` field in the response is the generated credential key (API key or SMTP password).

#### Users

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v2/users` | List users |
| `POST` | `/api/v2/users` | Create a user |
| `GET` | `/api/v2/users/:uuid_or_email` | Get a user |
| `PATCH` | `/api/v2/users/:uuid_or_email` | Update a user |
| `DELETE` | `/api/v2/users/:uuid_or_email` | Delete a user |

Create body: `{ "first_name": "Alice", "last_name": "Smith", "email_address": "alice@example.com", "password": "..." }`

### Pagination

All list endpoints support `?page=1&per_page=50` (max 200).

### Error format

```json
{ "errors": ["Name can't be blank"] }
```

HTTP status codes are used conventionally: `200`, `201`, `204`, `401`, `404`, `422`.
