# mTLS Runbook: step-ca + Caddy + Keycloak

End-to-end setup for X.509 client certificate authentication.
Caddy terminates mTLS on the VPS, forwards the cert as Base64-DER
to Keycloak via the `haproxy` SPI provider.

```
Browser ──TLS+ClientCert──> Caddy (VPS)
                             | verify_if_given
                             | trust: keycloak-client-ca.crt
                             |
                             | header: X-SSL-Client-Cert (Base64-DER)
                             |
                       WireGuard (Bifrost)
                             |
                             v
                        Keycloak (Homelab)
                             | haproxy SPI provider
                             | reads X-SSL-Client-Cert header
                             | decodes Base64-DER -> X.509
                             | extracts CN -> maps to username
                             v
                        step-ca (Homelab)
                             | issues client certs
                             | root_ca.crt -> Caddy
```

## Prerequisites

- step-ca container running (defined in `stacks/keycloak/compose.yml`)
- `step` CLI installed: https://smallstep.com/docs/step-cli/installation/
- SSH access to both VPS (proxy) and homelab host (FeelsDataMan)

## Phase 1: Initialize step-ca

step-ca auto-initializes on first start using `DOCKER_STEPCA_INIT_*` env vars.

### 1.1 Start step-ca

```bash
docker compose up -d step-ca
```

### 1.2 Get the root CA fingerprint

```bash
docker logs step-ca 2>&1 | grep "Root fingerprint"
```

Save this fingerprint — you need it for every `step` CLI operation.

### 1.3 Bootstrap the step CLI (on the homelab host)

```bash
step ca bootstrap \
  --ca-url https://localhost:9000 \
  --fingerprint <ROOT_FINGERPRINT>
```

> **Gotcha**: On first bootstrap you may need `--insecure` if step-ca
> uses a self-signed HTTPS cert that your OS doesn't trust yet.
> After bootstrap, the root CA is stored locally and future commands
> work without `--insecure`.

### 1.4 Configure 2-year certificate lifetime

The default provisioner only allows short-lived certs. Update it:

```bash
step ca provisioner update admin \
  --x509-max-dur=17520h \
  --x509-default-dur=17520h
```

Then restart step-ca to pick up the change:

```bash
docker compose restart step-ca
```

> **Why this survives restarts**: The provisioner config lives in
> `/home/step/config/ca.json` inside the container, which is
> persisted via the volume mount (`/docker/keycloak/step-ca:/home/step`).

## Phase 2: Issue client certificates

### 2.1 Issue a certificate

```bash
step ca certificate "stefan" stefan.crt stefan.key --not-after=17520h
```

The CN (`stefan`) must match the Keycloak username exactly.

### 2.2 Export as PKCS#12 for device installation

```bash
openssl pkcs12 -export \
  -in stefan.crt \
  -inkey stefan.key \
  -certfile $(step path)/certs/root_ca.crt \
  -out stefan.p12 \
  -name "stefan - Sloth Homelab"
```

You'll be prompted for an export password — this protects the .p12 file
during transfer to devices.

### 2.3 Install on devices

| Platform | Steps |
|----------|-------|
| Windows  | Double-click `.p12` -> import to Personal store |
| macOS    | Double-click `.p12` -> Keychain Access -> trust the CA |
| Android  | Settings -> Security -> Install certificate -> select `.p12` |
| iOS      | AirDrop/email `.p12` -> Settings -> Profile Downloaded -> Install |
| Firefox  | Settings -> Privacy -> Certificates -> View -> Import `.p12` |

> **Important**: Chromium-based browsers use the OS cert store.
> Firefox uses its own — you must import into both if using both.

### 2.4 Clean up private key material

After exporting to `.p12`, delete the loose key file:

```bash
rm stefan.key
```

The `.crt` can be kept for renewal. The `.p12` should be transferred
securely and then deleted from the issuing machine.

## Phase 3: Deploy root CA to Caddy (VPS)

The VPS needs the root CA public cert to validate client certificates.

### 3.1 Export root CA cert

On the homelab host:

```bash
cp $(step path)/certs/root_ca.crt /tmp/keycloak-client-ca.crt
```

### 3.2 Copy to VPS

```bash
scp /tmp/keycloak-client-ca.crt vps:/docker/proxy/caddy/certs/keycloak-client-ca.crt
```

> **This is a public certificate** — no SOPS encryption needed.
> But if the root CA is ever rotated, this file MUST be updated
> on the VPS too, or mTLS silently stops working.

### 3.3 Verify Caddy can read it

```bash
# On the VPS
docker exec caddy cat /etc/caddy/certs/keycloak-client-ca.crt | head -1
# Should print: -----BEGIN CERTIFICATE-----
```

### 3.4 Reload Caddy

Caddy watches its config file but not certificates. After placing a
new CA cert, restart:

```bash
docker compose restart caddy
```

## Phase 4: Verify end-to-end

### 4.1 Without client cert (password fallback)

Open the Keycloak domain in a browser without a client cert installed.
You should see the standard username/password login form.

### 4.2 With client cert (X.509 auto-login)

Open the Keycloak domain in a browser with the client cert installed.
The browser should prompt to select a certificate, then Keycloak
authenticates you automatically based on the CN.

### 4.3 Debug: Check what Caddy sends

```bash
# Temporarily add a debug endpoint to see headers
curl -v --cert stefan.crt --key stefan.key https://keycloak.example.com/
```

The response headers in Caddy's access log should show
`X-SSL-Client-Cert` with a Base64-DER string (single line, no PEM markers).

### 4.4 Debug: Keycloak not recognizing cert

If Keycloak shows the password form despite a valid cert:

1. Check SPI config: `docker exec keycloak env | grep X509`
   - Must show `KC_SPI_X509CERT_LOOKUP_PROVIDER=haproxy`
2. Check auth flow: Admin Console -> Authentication -> browser-with-x509
   - X.509 authenticator must be ALTERNATIVE, before the forms subflow
3. Check CN matching: The cert CN must exactly match a Keycloak username
4. Check header: Caddy must send `X-SSL-Client-Cert` (not `SSL_CLIENT_CERT`)
5. Check format: Must be Base64-DER (no `-----BEGIN` markers, no newlines)

## Certificate lifecycle

### Renew a certificate

```bash
# Manual renewal (must be done before expiry)
step ca renew stefan.crt stefan.key

# Automatic renewal daemon (runs in background, renews at 2/3 lifetime)
step ca renew --daemon stefan.crt stefan.key
```

> **Note**: After renewal, you must re-export as `.p12` and reinstall
> on devices. The `--daemon` mode is useful for server-side certs,
> not for mobile device certs.

### Revoke a certificate

```bash
step ca revoke --cert stefan.crt --key stefan.key
```

Revoked certs are rejected by step-ca but Keycloak doesn't check CRL/OCSP
in this setup (Caddy validates against the CA, not a revocation list).
To immediately block a revoked cert: remove the user from Keycloak or
change the auth flow.

## User enrollment

Admin-driven workflow — no self-registration.

### Create a new user

Via Keycloak Admin Console:

1. Go to **Users** -> **Add user**
2. Set username, email, first/last name
3. Assign to group: **tier-guest**, **tier-media**, or **tier-homelab**
4. Under **Required user actions**, select: **Update Password**, **Configure OTP**
5. Click **Create**

Via Admin CLI:

```bash
docker exec keycloak /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 --realm master --user admin --password <ADMIN_PASS>

docker exec keycloak /opt/keycloak/bin/kcadm.sh create users -r homelab \
  -s username=alice \
  -s email=alice@example.com \
  -s firstName=Alice \
  -s enabled=true \
  -s 'requiredActions=["UPDATE_PASSWORD","CONFIGURE_TOTP"]'
```

### Send password reset email

```bash
# Get user ID
USER_ID=$(docker exec keycloak /opt/keycloak/bin/kcadm.sh get users -r homelab \
  -q username=alice --fields id --format csv --noquotes)

# Send email with required actions
docker exec keycloak /opt/keycloak/bin/kcadm.sh update \
  users/$USER_ID/execute-actions-email -r homelab \
  -b '["UPDATE_PASSWORD","CONFIGURE_TOTP"]'
```

The user receives an email with a link to set their password and configure TOTP.

### Issue client certificate for new user

After the user has set up their Keycloak account, issue a client cert
(see Phase 2 above). The cert CN must match the Keycloak username.

Alternatively, if the step-ca OIDC provisioner is configured, the user
can self-service:

```bash
step ca certificate "alice@example.com" alice.crt alice.key --provisioner keycloak
# Browser opens -> Keycloak login -> cert issued
```

## step-ca OIDC provisioner

After step-ca is initialized (Phase 1), add the Keycloak-backed OIDC
provisioner for self-service certificate issuance:

```bash
docker exec -it step-ca step ca provisioner add keycloak --type OIDC \
  --client-id step-ca \
  --client-secret <KC_CLIENT_STEPCA_SECRET> \
  --configuration-endpoint https://<KEYCLOAK_DOMAIN>/realms/homelab/.well-known/openid-configuration \
  --listen-address :10000 \
  --domain <YOUR_EMAIL_DOMAIN>
```

Then restart step-ca:

```bash
docker compose restart step-ca
```

Users can now request certs via:

```bash
step ca certificate "user@example.com" user.crt user.key --provisioner keycloak
```

The browser opens Keycloak login. After authentication, the cert is issued
with the user's email as SAN. Default lifetime follows the admin provisioner
settings (see Phase 1.4).

## Architecture details

### Why haproxy provider (not rfc9440)

Caddy can't put PEM in HTTP headers (Go rejects newlines). It only
offers `certificate_der_base64` (Base64-encoded DER, single line).

The `haproxy` SPI provider accepts exactly this format. The `rfc9440`
provider (added in Keycloak 26.5.0) would also work but requires
colon-wrapping (`:base64:`), which is fragile in Caddyfiles.

### Security: header spoofing prevention

Caddy's `header_up` directive overwrites any existing header with
the same name. An attacker cannot inject a fake `X-SSL-Client-Cert`
header because Caddy replaces it with the actual cert (or nothing,
if no cert was presented). This is critical — without overwrite
semantics, an attacker could bypass mTLS entirely.

### Files involved

| File | Purpose |
|------|---------|
| `stacks/keycloak/compose.yml` | step-ca + Keycloak with SPI env vars |
| `stacks/proxy/caddy/sites/keycloak.caddy` | mTLS termination + header forwarding |
| `stacks/proxy/caddy/certs/keycloak-client-ca.crt` | Root CA public cert (deployed manually) |
| `stacks/keycloak/realm-config/00-realm.yaml` | X.509 auth flow + authenticator config |
