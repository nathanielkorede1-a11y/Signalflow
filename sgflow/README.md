# SignalFlow — developer release candidate

SignalFlow is a Next.js 15 application starter for a trading-signal distribution service. It includes a responsive dashboard preview, Supabase email/password authentication, server-side signal reads, protected MQL5 ingestion, a server-verified ad callback adapter, Stripe Checkout/webhook handling, and a secret-protected signal administration API.

**Important:** this is a deployable application foundation, not a fully live commercial service. Real Supabase, Stripe, and ad-provider credentials and configuration are required. The ad endpoint is an adapter and does not itself serve advertisements. The dashboard still contains illustrative sample metrics; do not market those figures as verified results. Review the production checklist below before accepting payments or distributing live signals.

## Requirements

- Node.js 20.9+ (Node 22 LTS recommended)
- npm
- A Supabase project for authentication and database operations

## Run locally

1. Extract the ZIP and open a terminal in the `signalflow` directory.
2. Install dependencies:

   ```bash
   npm install
   ```

3. Copy `.env.example` to `.env.local`.
4. For a UI-only preview, leave external credentials blank and retain `SIGNALFLOW_DEMO_MODE=true`.
5. Start the development server:

   ```bash
   npm run dev
   ```

6. Open http://localhost:3000.

The project does not include `node_modules`; `npm install` creates it on your machine. If port 3000 is occupied, Next.js will display the alternate local URL.

## Environment variables

| Variable | Purpose |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase publishable/anon key |
| `SUPABASE_SERVICE_ROLE_KEY` | Server-only privileged Supabase key |
| `MT5_WEBHOOK_SECRET` | Shared secret for the MQL5 ingestion endpoint |
| `SIGNALFLOW_ADMIN_SECRET` | Server-only secret for admin signal API |
| `STRIPE_SECRET_KEY` | Stripe secret API key |
| `STRIPE_WEBHOOK_SECRET` | Stripe webhook signing secret |
| `STRIPE_PREMIUM_PRICE_ID` | Recurring Premium price ID |
| `NEXT_PUBLIC_APP_URL` | Canonical app URL, including https in production |
| `AD_PROVIDER_WEBHOOK_SECRET` | HMAC secret for ad provider callback adapter |
| `SIGNALFLOW_DEMO_MODE` | `true` for local preview only; `false` for real services |

Never put service-role, webhook, admin, or MT5 secrets in a `NEXT_PUBLIC_` variable or browser code. Do not commit `.env.local`.

## Supabase setup

1. Create a Supabase project.
2. Copy its Project URL, anon/publishable key, and service-role key into `.env.local`.
3. In Supabase SQL Editor, run these migrations in order:
   - `supabase/migrations/0001_initial.sql`
   - `supabase/migrations/0002_hardening.sql`
4. Set `SIGNALFLOW_DEMO_MODE=false` and restart Next.js.
5. Register at `/signup`, confirm the email if confirmation is enabled, then sign in at `/login`.

The service-role key is used only in server routes. Row-level security is enabled; signal mutations are not available to ordinary browser-authenticated users.

## MQL5 signal ingestion

Endpoint: `POST /api/mt5/signals`

Headers:

```text
Content-Type: application/json
x-signalflow-secret: YOUR_MT5_WEBHOOK_SECRET
```

Body:

```json
{
  "external_id": "EA-2026-00001",
  "symbol": "XAUUSD",
  "direction": "BUY",
  "entry": 2642.80,
  "stop_loss": 2631.40,
  "take_profit": 2688.40,
  "rr": 4,
  "status": "active"
}
```

`external_id` is required and used as the idempotency/upsert key. Accepted status values: `active`, `closed`, `tp_hit`, `sl_hit`, `breakeven`, `cancelled`. BUY requires SL below entry and TP above entry; SELL requires SL above entry and TP below entry. The endpoint publishes the received signal immediately.

A starter MQL5 helper is provided at `examples/mql5/SignalFlowWebhook.mqh`. Include it in your EA and call `SignalFlowSend(...)` when your algorithm confirms a signal. Adapt it to your EA event flow and verify the response handling in the Strategy Tester/demo environment. For a deployed site, use its HTTPS URL from the VPS/MT5 terminal, not localhost. Add the domain to MT5 Tools → Options → Expert Advisors → Allow WebRequest for listed URL. Your EA must send the secret header. Do not hardcode one shared production secret into an EA distributed to customers; use per-install credentials or a brokered ingestion service and rotate credentials.

## Admin signal API

This release includes a server-to-server admin API, not a graphical admin dashboard. Authenticate with the `x-signalflow-admin` header containing `SIGNALFLOW_ADMIN_SECRET`.

- `GET /api/admin/signals` — list the latest 200 signals.
- `POST /api/admin/signals` — create a signal. Required JSON fields: `symbol`, `direction`, `entry`, `stop_loss`, `take_profit`; optional: `external_id`, `rr`, `status`, `is_published`.
- `PATCH /api/admin/signals` — update publication/status. Required `id`; optional `is_published` and/or `status`.

Example publish/update body:

```json
{ "id": "SIGNAL_UUID", "is_published": true, "status": "active" }
```

Keep this secret in a trusted admin environment only. Do not call these endpoints directly from public browser code. A proper staff login/role system and graphical admin interface should replace the shared-secret adapter before a multi-admin production launch.

## Free signal access and ad-provider adapter

`POST /api/ads/session` requires a signed-in Supabase user and creates a short-lived pending session. A real ad provider must display the ad and call the server callback after independently verifying completion.

Callback endpoint: `POST /api/ads/callback`

Expected JSON:

```json
{ "sessionId": "PROVIDER_SESSION_ID", "event": "completed" }
```

Header: `x-ad-signature` containing the HMAC-SHA256 hex digest of the exact raw request body using `AD_PROVIDER_WEBHOOK_SECRET`.

Migration `0002_hardening.sql` adds a database function that serializes unlock attempts and enforces one free unlock per user per UTC day. The callback grants access only after a valid provider signature. **No ad network is connected by default**; choose a provider and implement its SDK/session mapping and callback contract according to that provider's documentation before enabling this flow for users. The current dashboard preview does not claim an ad was watched or unlock a real signal.

## Stripe Premium subscriptions

Configure `STRIPE_SECRET_KEY`, `STRIPE_PREMIUM_PRICE_ID`, `STRIPE_WEBHOOK_SECRET`, and `NEXT_PUBLIC_APP_URL`. Create a recurring Premium price in Stripe. Set a webhook endpoint to:

`https://YOUR_DOMAIN/api/billing/webhook`

Subscribe to `customer.subscription.created`, `customer.subscription.updated`, and `customer.subscription.deleted`. Checkout is created by `POST /api/billing/checkout` for the signed-in user. The webhook validates Stripe's signature and updates the profile plan and Stripe IDs.

Before launch, test subscription lifecycle events, webhook retries, failed invoices, refunds, cancellation, and customer-portal flows. Add a Stripe Customer Portal endpoint if customers need self-service cancellation/payment updates. Do not trust plan values submitted by a browser.

## Production checklist — required before launch

- Replace all sample dashboard figures/activity with database-backed, audited data. Label verified performance methodology and date ranges.
- Build the graphical admin/staff interface with Supabase role-based authorization, MFA, audit trails, and controlled publishing.
- Connect a real ad provider and test its server-to-server signature verification and fraud/duplicate callback behavior.
- Add a protected signal detail/reveal flow. The current API returns the user's already-accessible signals; build UI reveal states that call the server, never trust a client-side ad-completed flag.
- Add rate limiting, abuse protection, CAPTCHA where appropriate, monitoring, alerting, backups, log redaction, and automated tests.
- Add privacy policy, terms, risk disclosure, support/contact pages, consent/cookie handling as applicable, and review local financial/consumer/privacy/tax/advertising requirements.
- Add Stripe Customer Portal, failed-payment handling, reconciliation jobs, and tested cancellation/renewal flows.
- Review MT5 authentication architecture; a static shared EA secret is not appropriate for a publicly distributed commercial EA.
- Deploy to a supported Node host, configure HTTPS and environment secrets, run database migrations, then run `npm run build` before release.

## Commands

- `npm run dev` — development server
- `npm run lint` — TypeScript check
- `npm run build` — production build
- `npm start` — production server

## Database migration recovery / existing Supabase projects

The SQL migrations are now safe for a project where an older `signals` table already exists without `is_published`. Run `0001_initial.sql` first, then `0002_hardening.sql`, in the Supabase SQL Editor. If the earlier version failed, rerun the updated files in that order; the statements use `IF NOT EXISTS` where appropriate. Do not run `0002_hardening.sql` before `0001_initial.sql`.

If Supabase reports a duplicate-key error while creating `signal_access_one_free_unlock_per_day`, inspect `public.signal_access` for users who already have more than one row on the same UTC date before creating the unique index.

## Connecting the Consecutive Candles Cover EA

The project includes:

- `examples/mql5/SignalFlowWebhook.mqh` — HTTP helper.
- `examples/mql5/ConsecutiveCandlesCover_SignalFlow.mq5` — your Consecutive Candles Cover strategy with SignalFlow publishing added.

Copy both files into the same folder under `MQL5/Experts` (or put the `.mqh` in `MQL5/Include` and adjust the include path). Compile the `.mq5` file in MetaEditor. In the EA inputs, set `SignalFlowBaseUrl` to your deployed HTTPS domain and `SignalFlowWebhookSecret` to the same value as `MT5_WEBHOOK_SECRET` in the server's environment. In MT5, add that domain under Tools → Options → Expert Advisors → Allow WebRequest for listed URL.

The EA publishes only after MT5 confirms that the market order executed. It sends the actual execution price, stop loss, take profit, direction, symbol, RR, and a unique external ID. A failed webhook does not close or modify the MT5 position.

Security: do not distribute an EA containing your production webhook secret. Anyone who obtains the secret can submit signals to your endpoint. Use a unique secret for each private deployment and rotate it if exposed. The webhook is not a substitute for a production secret-management or per-terminal authentication strategy.
