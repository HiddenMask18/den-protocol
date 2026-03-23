# Contributing to DEN

This document covers contributions to the DEN protocol specification and architecture. The reference client (furDEN) is a separate project with its own repository and contributing guidelines — if that's what you're looking for, this isn't the right place yet.

If you're here, you're probably technically capable and care about what this protocol is trying to do. That's the right starting point. You don't need to be a seasoned open source contributor. The founding maintainer isn't either. What matters is that you've read the documents, understood the design decisions, and have something substantive to add.

---

## Read the Documents First

Before contributing anything, read these in order:

- [MANIFESTO.md](./MANIFESTO.md) — why this exists
- [den-architecture.md](./den-architecture.md) — design rationale and rejected alternatives
- [den-spec.md](./den-spec.md) — binding implementation requirements

The architecture document in particular exists so design decisions don't get re-litigated from scratch. If the thing you want to propose is already in Appendix A under "rejected," that section explains why. If you think the rejection reasoning is wrong, make that argument directly — but read the reasoning first.

---

## What Contributions Look Like Right Now

The protocol is in early draft. The most useful contributions at this stage are:

**Design review and pressure-testing** — reading a section and identifying where the reasoning breaks, where there's an unaddressed attack vector, or where implementation would be harder than the spec implies. Open a GitHub Discussion or raise it as an issue with the specific section referenced.

**Spec language** — the specification is written to be precise but it's a first draft. If a requirement is ambiguous, underspecified, or contradicts another section, that's a real problem worth raising.

**Implementation feedback** — if you're building against the spec and something doesn't work the way the spec implies it should, that's valuable signal. The spec is supposed to be implementable. Document what broke and where.

**Governance parameter recommendations** — Section 13 lists all governance parameters with initial values set at launch. If you have informed opinions on what those initial values should be and why, that reasoning is useful now before launch locks them in.

What's not useful right now: feature requests that expand protocol scope, design proposals that haven't engaged with the existing architecture, or anything that conflicts with the foundational principles in Section 1 without a governance process argument for amending them.

---

## How to Raise Something

**GitHub Discussions** is the right place for design questions, open-ended feedback, and anything that needs conversation before it becomes a formal proposal. Use it.

**GitHub Issues** for specific, discrete problems: a requirement that's contradicted elsewhere, a section that's missing a necessary definition, an identified attack vector not addressed by the current architecture.

**Pull requests** for proposed changes to spec or architecture text. PRs without a corresponding discussion or issue explaining the reasoning behind the change will be sent back. The reasoning matters as much as the change — this protocol documents its decisions and why.

A broader community space is planned. For now, GitHub is where the work happens.

---

## On Pace and Scope

This project is maintained by a small number of people, currently one. It moves at a sustainable pace by design — not because of limited ambition, but because burnout is how projects like this die quietly before they accomplish anything.

What that means in practice:

**Scope stays contained.** Each contribution addresses one thing. A PR that fixes a spec ambiguity in Section 5 and also proposes a new governance mechanism and also restructures the definitions section is three separate things pretending to be one. Split it.

**Reviews take the time they take.** There's no SLA on response time right now. If something is sitting without response for a while, a single follow-up is fine. Multiple follow-ups in quick succession are not.

**Urgency is usually manufactured.** If something feels like it needs to be resolved immediately, that's worth examining. The spec is a draft. Almost nothing in it requires a decision today that can't be revisited tomorrow with more thought.

These aren't rules imposed on contributors — they're how this project runs. If that pace doesn't work for you, that's a legitimate mismatch, not a character flaw.

---

## Commit Standards

- Sign your commits with GPG. This is a protocol built on cryptographic identity. Sign your commits.
- Commit messages describe what changed and why, not just what changed.
- One logical change per commit. Clean history is readable history.
- If you're new to signed commits, GitHub's documentation on [commit signature verification](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification) is a reasonable starting point.



---

## Crypto Wallet Requirements

Contributing to this project doesn't require a crypto wallet. Reading, reviewing, and raising issues requires only a GitHub account.

If you're contributing to protocol mechanics that touch payment flows, access control, or smart contract logic, hands-on familiarity with self-custodial wallets is assumed. Documentation on wallet types, custody models, and operational security will live in a separate document. That document doesn't exist yet — it's flagged as forthcoming.

---

## What This Project Is and Isn't

DEN is a protocol, not a platform. This repository is the specification and architecture of that protocol. It is not:

- The reference client (furDEN) — separate project, separate repo, separate contributing guidelines
- A platform you can sign up for — nothing is deployed yet
- A company — there is no entity, no investors, no employees

Contributions here are contributions to a public protocol specification under AGPL. Your contributions will be public, attributed to your GitHub identity (which can be pseudonymous), and governed by the license.

---

*Questions about whether your contribution fits? Open a Discussion and ask.*
