# Invoicedey

Invoicedey is a calm, global-first invoicing product for freelancers and independent businesses.

## Current foundation

This workspace contains a functional local-first web app. It supports business settings, saved clients, draft/sent invoices, line items, tax, multi-currency display, payment status, and a dashboard. Data is deliberately stored in browser local storage while cloud infrastructure is introduced.

Run locally with `npm run dev`.

## Next delivery milestones

1. Connect Supabase authentication and row-level-secured cloud data.
2. Add immutable invoice lifecycle/audit events and server-side PDF generation.
3. Add hosted invoice links, email delivery, payment providers, and webhook verification.
4. Add localisation, tax configuration by business jurisdiction, reminders, and reporting.

## Data model

The first PostgreSQL migration is at `supabase/migrations/001_core.sql`. Apply it to a new Supabase project before implementing cloud sync.
