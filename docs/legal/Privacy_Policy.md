# Allnighter — Privacy Policy

**Version 1.3 · Effective August 14, 2026**

This policy explains what **Happy Moose Apps Inc.** ("we", "us") collects when
you use Allnighter — the `alln` command-line tool, the Allnighter Mac
application, the website at allnighter.io, and, when available, the Allnighter
iOS companion.

We are a company incorporated in British Columbia, Canada. For privacy
questions, or to exercise any right described in §7, email
**support@allnighter.io**.

---

## 1. The Short Version

Allnighter runs on your computer. It is not a cloud service, and the work you do
with it does not pass through us. The four facts below are not promises bolted
on afterwards — they are how the software is built.

1. **We never see your prompts, your code, or your files.** They never leave
   your machine — unless you paste them into an `alln feedback` note you chose
   to send.
2. **We never see your AI provider credentials.** Allnighter starts the vendor's
   own command-line tool, which authenticates itself with your own login. We do
   not read, store, proxy, extract, or transmit API keys or OAuth tokens, and we
   are never part of an authentication flow.
3. **We never see your model outputs.** What the tools produce is written to
   your disk, not to ours.
4. **We do not sell data, run advertising, or use anything you produce to train
   anything.**

What is left is the small amount of information needed to run entitlement,
payments, and updates — and, only if you send it, a short feedback note. That
is the subject of the rest of this policy.

## 2. What We Do Not Collect

To be explicit, because the distinction matters more here than in most software:

- the contents of your prompts, instructions, or conversations;
- your source code, files, repositories, or directory names;
- output produced by any AI model you run through Allnighter;
- your credentials, API keys, authentication tokens, or OAuth tokens for any
  third-party provider;
- your run history — it is stored locally on your machine, and you can export or
  delete it at any time. We do not receive a copy.

## 3. What We Collect

### If you create an account or buy something

| What | Why | Source |
| --- | --- | --- |
| Email address | Receipts, support, and service notices | Stripe Checkout, or you, when you write to us |
| Subscription state and its dates | To know whether you are entitled to the paid tier | Us and Stripe |
| Billing country, card brand, and last four digits | Receipts, tax, and fraud prevention | Stripe |

**We never receive your full card number.** See §5.

### On every install, whether or not you have an account

| What | Why |
| --- | --- |
| An irreversible hash derived from your computer's hardware identifiers | Solely to record that a free trial has been used on that machine. The underlying identifiers never leave your computer, and we cannot reverse the hash back to them or to you. |
| The date your installation last checked for a software release | To serve update checks and to understand which versions are still in use |
| IP address and basic request metadata, in server logs | An unavoidable part of serving any network request. Used for security, abuse prevention, and debugging; not used to build a profile of you. |

### If you send feedback (`alln feedback`)

This is opt-in. Nothing is sent unless you (or an agent quoting **your** words)
run the command. We never attach your repo, prompts, run history, or files.

| What | Why |
| --- | --- |
| The message you typed | So a person can read it |
| The CLI version (`alln` binaryVersion) | So we know which build you are on |
| Operating system version (for example `macOS 15.6.0`) | So we can tell Mac-only issues from everything else |

The command prints that exact payload before it is sent. `--dry-run` prints it and sends nothing.

### On the website

Our website host records aggregate page views so we can tell whether anyone is
reading. The site sets no advertising cookies, runs no third-party trackers, and
does not follow you across other sites.

## 4. Why We Are Allowed To Process It

Under Canadian law (PIPEDA) we rely on your consent, given when you install the
software or create an account, and on the reasonable purposes described above.

If you are in the UK or the European Economic Area, our lawful bases under the
UK/EU GDPR are:

- **Contract** — account, entitlement, subscription state, and payment data. We
  cannot sell you a subscription without them.
- **Consent** — a feedback note you typed and sent with `alln feedback`.
- **Legitimate interests** — trial-abuse prevention, security logging, update
  checks, and aggregate site analytics. We have kept each of these to the
  minimum that works; the hardware hash exists specifically so that trial
  enforcement does not require identifying you.
- **Legal obligation** — retaining transaction records for tax and accounting.

## 5. Who Else Touches It

We keep this list short on purpose. These are our only processors:

| Processor | What they handle | Where |
| --- | --- | --- |
| **Stripe** | Payment processing. Card details go directly from you to Stripe over an encrypted connection and are never transmitted through or stored by us. Stripe is PCI-DSS Level 1 certified. | Global — [privacy policy](https://stripe.com/privacy) |
| **Apple** | App Store distribution, and Sign in with Apple if you later use device pairing | Global — [privacy policy](https://www.apple.com/legal/privacy/) |
| **Our hosting and website providers** | Serving the website, update checks, the entitlement service, and the feedback inbox | Canada / United States |
| **Discord or Slack** (only if a webhook is configured for feedback) | Relaying the same three-field postcard so a person sees it quickly | United States — their privacy policies |

We do not sell your personal information, and we do not share it with anyone for
their own marketing.

We may disclose information if we are legally required to — a court order, a
valid legal process — or to protect our rights or someone's safety. Note that
the design in §1 sharply limits what could ever be produced in response to such
a demand: we cannot hand over prompts, code, or credentials we never had.

## 6. How Long We Keep It

- **Account and entitlement data** — while your account exists, and for up to 90
  days after you delete it.
- **Transaction records** — seven years, because Canadian tax law requires it.
  This survives account deletion; we cannot delete a receipt we are obliged to
  keep.
- **Trial hardware hash** — retained while the product operates, because its
  whole function is to remember that a trial was used. It does not identify you.
- **Server logs** — 30 days, then deleted.
- **Feedback notes** — kept only as long as needed to reply, then deleted. We do not build a profile from them.
- **Aggregate site analytics** — retained in aggregate, with no identifier that
  points back to a person.

## 7. Your Rights

Wherever you live, you may ask us to:

- **tell you** what we hold about you;
- **correct** anything inaccurate;
- **delete** your account and the data attached to it, subject to the tax
  retention above;
- **export** your data in a portable form;
- **withdraw consent**, which for most of what we hold means closing your
  account.

If you are in the UK or EEA you also have the right to object to processing
based on legitimate interests, and the right to restrict processing.

Email **support@allnighter.io**. We will respond within 30 days. We do not
charge for this and we will not make it difficult.

Most of your data is already in your hands: your run history lives on your own
machine, and you can export or delete it without asking us.

**Complaints.** If you think we have handled your information badly, please tell
us first. You can also complain to the Office of the Privacy Commissioner of
Canada (priv.gc.ca), or, in the UK/EEA, to your local supervisory authority.

## 8. International Transfers

We are in Canada. Our processors operate in Canada, the United States, and
elsewhere, so information may be processed outside your country and may be
accessible to authorities there under local law. Where we transfer personal data
out of the UK or EEA, we rely on the European Commission's adequacy decision for
Canada and, where it does not apply, on Standard Contractual Clauses.

## 9. Security

Data in transit is encrypted with TLS. Access to the entitlement service is
limited to those who need it. Payment card data is handled entirely by Stripe
and never reaches our systems.

The strongest security property here is architectural rather than procedural:
the material most people would care about — your code, your prompts, your
provider credentials — is never collected, so it cannot be exposed by a breach
of ours.

No system is perfectly secure. If we suffer a breach affecting your personal
information, we will notify you and the relevant regulator as required by law.

## 10. Children

Allnighter is a developer tool and is not directed at children. We do not
knowingly collect personal information from anyone under 16. If you believe a
child has given us information, email us and we will delete it.

## 11. Changes

We may update this policy. Material changes will be announced before they take
effect, and the version and effective date at the top of this document will
change. Previous versions remain available on request.

---

**Contact:** support@allnighter.io

Happy Moose Apps Inc., British Columbia, Canada.
