# Paperless-ngx Organization Guide

Community-proven rules for a clean, scalable document archive.

## Tags (aim for under 30)

Use tags for broad categories. Do NOT duplicate document types as tags.

| Tag | Purpose |
|-----|---------|
| Inbox | Auto-assigned on consumption, remove after manual review |
| Finance | Bank statements, investments, tax-related |
| Medical | Health records, prescriptions, lab results |
| Insurance | Policies, claims, correspondence |
| Legal | Contracts, agreements, legal notices |
| Housing | Rent, utilities, property documents |
| Vehicle | Registration, maintenance, insurance |
| Tax | Tax returns, deductions, assessments |
| Employment | Payslips, contracts, references |
| Warranty | Product warranties, receipts for expensive items |
| Personal | IDs, certificates, personal correspondence |
| Education | Diplomas, transcripts, course materials |
| Action Required | Needs follow-up (payment, response, signature) |

Do NOT create year tags. The document date field handles this.

## Document Types (keep the list short)

| Type | Examples |
|------|----------|
| Invoice | Bills, payment requests |
| Receipt | Proof of payment, purchase confirmations |
| Contract | Agreements, terms of service, leases |
| Letter | General correspondence |
| Statement | Bank/credit card statements |
| Certificate | Birth, marriage, diplomas, licenses |
| Tax Return | Annual tax filings |
| Payslip | Monthly salary statements |
| Insurance Policy | Active insurance documents |
| Manual | Product manuals, instructions |
| ID Document | Passports, driver's licenses, ID cards |
| Medical Record | Lab results, prescriptions, doctor's letters |

## Correspondents

One correspondent per entity (company, authority, person). Use the entity you
are dealing with, not the intermediary delivering the document.

Good: "Deutsche Bank", "TK Krankenkasse", "Finanzamt Berlin"
Bad: "Deutsche Post" (for a letter from your bank)

## Custom Fields

| Field | Type | Purpose |
|-------|------|---------|
| Invoice Number | String | Cross-referencing payments |
| Amount | Float | Invoice/receipt total |
| Due Date | Date | Payment deadlines |
| Paid Date | Date | When payment was made |
| Warranty Expiry | Date | Product warranty tracking |
| Policy Number | String | Insurance/account reference |

## Storage Path

Template: `{created_year}/{correspondent}/{title}`

With `PAPERLESS_FILENAME_FORMAT_REMOVE_NONE=true` to handle documents
without a correspondent cleanly.

## Inbox Workflow

1. Document arrives (scan, email, upload, consume folder)
2. Paperless auto-assigns "Inbox" tag
3. Review document: set correspondent, document type, tags, custom fields
4. Remove "Inbox" tag to mark as processed

Set up the "Inbox" tag assignment via a workflow rule:
- Trigger: Document Added
- Action: Assign tag "Inbox"

## ML Classifier

The Auto matching algorithm needs ~20 manually tagged examples per category
before it becomes reliable. Invest time upfront to tag the first batch of
documents correctly. After that, Paperless learns and auto-assigns with
increasing accuracy.

## OCR Tips

- Scan at 300 DPI, grayscale for text-only documents
- PDF or TIFF format (JPEG degrades OCR accuracy)
- Primary language: `deu+eng` (German + English)
- `pdfa` output type for long-term archival compliance
