# DEN — Decentralized Encrypted Network
## Protocol Specification v0.1-draft

This document contains binding implementation requirements for the DEN protocol. Implementations claiming DEN compliance MUST satisfy all MUST requirements in this specification. SHOULD requirements are strong recommendations whose deviation requires documented justification. MAY requirements are explicitly optional.

This document is a companion to `den-architecture.md`, which records design rationale and rejected alternatives. Where this document says what implementations must do, the architecture document explains why.

The key words MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

---

## Section 0 — Definitions

These terms are used throughout this specification without re-definition. Where natural-language inference would lead to an incorrect meaning, terms are defined precisely here.

**Instance** — a running deployment of the DEN protocol operated by a Hoster. An instance provides storage, compute, and bandwidth for Creators and Subscribers. Multiple instances form the network. No single instance is authoritative over any other.

**Protocol floor** — the minimum content policy that every compliant instance MUST enforce. Defined exhaustively in Section 11. Instance-level standards may exceed the floor but MUST NOT go below it.

**Governance parameter** — a protocol value that MAY be adjusted through the community governance process defined in Section 10 without requiring a full specification amendment. All governance parameters are listed exhaustively in Section 13.

**Subscription state** — the on-chain record of whether a specific wallet address holds an active subscription to a specific Creator tier on a specific instance. Subscription state is the authoritative source for content access decisions. It is publicly visible on-chain by design.

**Ciphertext** — the encrypted form of content or key material. Ciphertext is unreadable without the corresponding decryption key. Instances store ciphertext. Instances MUST NOT store plaintext content.

**Master secret** — the Creator-held cryptographic secret from which content encryption keys are derived. The master secret is stored on the instance in encrypted form, accessible only via the Creator's wallet private key. Defined in Section 4.

**Content key** — a symmetric encryption key derived from the Creator's master secret, used to encrypt a specific piece of content. Derived on demand at access time. Never stored independently on the instance.

**Sunset notice** — a formal notification issued by an instance operator that a Creator's content will be removed from that instance. Governed by Section 7. Immutable once issued.

**Protocol floor violation** — any content that violates the prohibitions defined in Section 11. Detection, reporting, and removal of protocol floor violations is governed by Section 12.

**Migration** — the process by which a Creator moves their identity, content references, subscriber relationships, and master secret from one instance to another. Governed by Section 8 and Section 15.

---

### The Three Denizens

**Hoster** — a participant who provides infrastructure by operating an instance. A Hoster MUST store only ciphertext and is architecturally incapable of reading hosted content without also being an active paying Subscriber to that content. A Hoster sets above-floor community standards for their instance. A Hoster MUST NOT hold Creator identity, subscriber relationships, content references, or the master secret hostage. A Hoster is a peer participant in the ecosystem, not a platform owner or gatekeeper.

**Creator** — a participant who produces content. A Creator holds their own keys, identity, and subscriber relationships independently of any instance. A Creator earns directly via smart contract with no platform intermediary. A Creator is subject to trust tier graduation defined in Section 9. A Creator carries legal liability for uploaded content. A Creator is portable across instances by protocol guarantee.

**Subscriber** — a participant who funds the ecosystem by paying Creators directly via smart contract. Subscription state governs content access automatically. A Subscriber is the only denizen type with plaintext access to content, making Subscribers the primary detection layer for protocol floor violations. Subscribers are pseudonymous by default at the protocol level.

**Relationship model:** Hosters serve Creators and Subscribers by providing infrastructure. Creators serve Subscribers by producing content. Subscribers sustain Creators by paying directly. The protocol governs the relationships between all three without sitting in the middle of any transaction. No denizen type holds structural power over another's core participation.

---

## Section 1 — Purpose and Design Principles

These principles are the binding foundation of this specification. Every other section is measured against them. A proposed change that conflicts with any principle requires amendment of this section through the full governance process — not amendment of the conflicting section alone.

---

**Principle 1 — Crypto-native payments are primary.**

Fiat payment infrastructure is a sandboxed guest with no structural power over the protocol.

*Implementation implication:* The protocol's primary payment rails MUST operate independently of any fiat processor. Fiat processors MAY offer onramp and offramp services at the edges of the ecosystem. A fiat processor's exit or refusal to operate MUST NOT affect active subscriptions, content access, or Creator earnings on the primary rails.

---

**Principle 2 — End-to-end encryption is non-optional.**

Instance operators store ciphertext. The protocol has no plaintext access layer. There is no scanning infrastructure.

*Implementation implication:* Instances MUST NOT store plaintext content at any point in the content lifecycle. Implementations MUST NOT introduce any mechanism — hash-matching, client-side scanning, or otherwise — that processes plaintext content at the protocol layer. Decryption MUST occur only on the Subscriber's device, after subscription state is verified.

---

**Principle 3 — No single entity holds a kill switch.**

Not the founding maintainer. Not any instance operator. Not any payment processor. Not any government acting within a single jurisdiction.

*Implementation implication:* No single instance, wallet address, or organizational entity MUST be a required participant for protocol operation. The protocol MUST survive the removal of any single participant. Governance MUST NOT grant any single participant unilateral authority over protocol rules or participant access.

---

**Principle 4 — Creator portability is a protocol guarantee, not a feature.**

A Creator's identity, subscriber relationships, content references, and master secret are theirs independently of any instance.

*Implementation implication:* The minimum portable data set defined in Section 8 MUST be held by the Creator at all times — not archived on departure, not requestable on departure. Instances MUST release this data on migration. Instances MUST NOT impose friction on migration beyond the technical requirements of the migration process itself.

---

**Principle 5 — Vagueness is an attack surface.**

Every policy position has a clear answer with documented reasoning.

*Implementation implication:* The protocol floor defined in Section 11 is exhaustive. Categories not addressed by name are governed by the general clause in Section 11. Ambiguous cases are resolved by governance amendment that sets binding precedent — not by ad hoc instance operator judgment.

---

**Principle 6 — The protocol serves human creative labor.**

Economic and architectural decisions are evaluated against whether they sustain the Creators the protocol exists for.

*Implementation implication:* Fee structures, tier mechanics, and access controls MUST be designed against Creator sustainability as the primary metric. Mechanisms that extract value from Creators without providing commensurate infrastructure value are inconsistent with this principle.

---

### Named Pressure Points

This specification is designed to structurally close the following known attack vectors against encrypted content platforms:

**Payment processor capture** — the pattern by which platforms capitulate to content restrictions imposed by Visa, Mastercard, PayPal, or equivalent processors under threat of payment infrastructure withdrawal. Closed by Principle 1: fiat processors are guests with no structural power.

**Legislative backdoor mandate** — the pattern by which legislation such as the [EARN IT Act](https://www.eff.org/deeplinks/2020/03/earn-it-act-violates-constitutionl), the [Online Safety Act](https://www.eff.org/pages/uk-online-safety-bill-massive-threat-online-privacy-security-and-speech), and [Chat Control](https://www.patrick-breyer.de/en/posts/chat-control/) attempts to compel platforms to break encryption or introduce scanning infrastructure. Closed by Principle 2: architectural impossibility means there is no backdoor to mandate and no scanning infrastructure to expand.

**Platform capture via subscription lock-in** — the pattern by which platforms attract Creators with favorable terms then tighten standards after audience relationships are established, holding subscriber relationships as leverage. Closed by Principle 4: subscriber relationships live in on-chain state, not instance databases.

---

## Section 2 — Identity Layer

### 2.1 Identity Anchors

**Wallet address is the primary identity anchor for all denizen types.** A wallet address is a pseudonymous identifier derived from a cryptographic public key. It is not a secret. It is publicly visible. It is the identifier by which the protocol recognizes participants.

Wallet address is pseudonymous, not anonymous. On-chain transaction history is publicly visible and outside the protocol's control. Participants who require stronger anonymity SHOULD use a wallet address with no prior transaction history linkable to their real identity. This is an operational security concern for the participant, not a protocol guarantee.

### 2.2 Authentication

Authentication MUST be implemented via challenge-response wallet signing:

1. The instance generates a unique nonce for the session
2. The participant signs the nonce locally with their wallet private key
3. The signature is transmitted to the instance
4. The instance verifies the signature against the claimed wallet address mathematically
5. The instance grants session access on successful verification

The private key MUST NOT be transmitted at any point in this flow. Implementations using [EIP-4361 (Sign-In with Ethereum)](https://eips.ethereum.org/EIPS/eip-4361) for EVM-compatible chains, [Wallet Adapter](https://github.com/anza-xyz/wallet-adapter) for Solana, and TronWeb for TRON are compliant with this requirement.

### 2.3 Protocol Identity Requirements

The protocol MUST NOT require real name, email address, government-issued identity, or any personally identifying information as a condition of participation.

Email addresses MAY be collected at the client layer for notification purposes only. Email MUST NOT be used as a primary identity anchor. Email MUST NOT be required for protocol participation. Email collection and storage is a client-layer concern subject to the client's own privacy posture.

KYC requirements MAY apply at fiat payout edges, enforced by the fiat processor. KYC data MUST be held by the fiat processor, never by the protocol or any instance.

### 2.4 Multi-role Participation

A single wallet address MAY hold multiple denizen roles simultaneously. A Creator who also operates an instance as a Hoster is a valid and expected participant configuration. Protocol rules apply identically regardless of which roles a wallet address holds. The self-transaction exclusion in Section 9 governs the trust tier implications of multi-role participation.

### 2.5 Wallet Recovery and Key Custody

Wallet private key custody is the participant's sole responsibility. The protocol MUST NOT store wallet private keys or seed phrases. The protocol MUST NOT provide wallet recovery infrastructure.

Wallet rotation is a supported protocol operation. A Creator MAY rotate their primary wallet address via a signed transaction from both the old and new wallet addresses, updating their on-chain identity record. This operation transfers all associated subscription state, content references, and trust tier history to the new address.

Client implementations MAY provide username and password authentication as a convenience layer over wallet signing. In this pattern, the client stores the wallet key material encrypted by the user's password locally. The protocol never receives the password or the unencrypted key material. If a participant loses both their client password and their wallet seed phrase, their wallet access is unrecoverable. This is the designed behavior. Client implementations SHOULD communicate this clearly during onboarding.

**Open question:** The mechanism by which active smart contract subscription state referencing the old wallet address is migrated to the new address requires a defined on-chain identity indirection layer. Specifically: subscriptions should reference a stable creator identity record rather than a wallet address directly, so rotation updates one record rather than requiring all active subscriber contracts to be migrated. This is flagged for resolution before the Section 3 smart contract mechanics are finalized.

### 2.6 On-Chain Subscription State Visibility

Subscription state — which wallet addresses hold active subscriptions to which Creator tiers — is publicly visible on-chain as a necessary consequence of smart contract-based access control. The protocol does not obscure this. Participants who consider their subscription relationships sensitive information SHOULD use a wallet address not otherwise linked to their identity.

---

## Section 3 — Payment Layer

### 3.1 Supported Payment Rails

The following chains are supported as primary payment rails:

**EVM Layer 2 networks (primary):** Base, Arbitrum, Optimism. Smart contract subscription logic is deployed on these networks. Additional EVM L2 networks MAY be added through the governance process defined in Section 10.

**Parallel rails:** TRON (TRC-20 standard), Solana. Supported for payment but smart contract subscription logic implementation on these chains is defined separately.

Chain support additions and removals MUST be approved through the governance process. Instance operators MUST NOT unilaterally restrict chain support below the protocol-approved list.

### 3.2 Self-Custodial Wallets

All payments MUST route through self-custodial wallets — wallets where only the participant holds the private keys. No platform intermediary MUST hold funds at any point in the payment flow. Custodial wallet services MAY be used by participants as a client-layer choice but MUST NOT be required by the protocol or any compliant instance.

### 3.3 Token Neutrality

The protocol does not privilege any supported token over another. Creators choose what token they price subscriptions in. Subscribers pay in whatever supported token they hold. The protocol's responsibility is to support the transaction, not to recommend a financial instrument.

Supported token categories and their properties, stated honestly:

**Native cryptocurrencies (ETH, SOL, TRX):** Fully decentralized. No third party can freeze them. Exchange rate varies — the Creator bears price volatility risk when pricing in native tokens.

**Stablecoins (USDC, DAI, USDT):** Price-stable relative to USD. Useful for predictable subscription pricing. Carry varying degrees of centralization risk: USDC can be frozen by Circle at government request; USDT carries Tether counterparty risk; DAI is more decentralized but remains USD-pegged. Creators choosing stablecoins accept this centralization tradeoff.

**Privacy-preserving tokens (Monero and equivalents):** Maximum decentralization and transaction privacy. Most philosophically aligned with this protocol's values. Exchange access is restricted in multiple jurisdictions. This tension is documented and unresolved at this protocol version. Governance MAY revisit as the regulatory landscape changes.

### 3.4 Subscription Payment Flow

Subscription payments MUST be implemented as direct on-chain transfers triggering subscription state on the smart contract.

**Auto-renewal** via pre-approved token allowance (ERC-20 `approve`/`transferFrom` or equivalent) MAY be offered by client implementations. Auto-renewal MUST be explicit opt-in by the Subscriber. Subscribers MUST be able to set an allowance cap. Auto-renewal failure (insufficient balance or allowance) MUST result in subscription lapse at the end of the current period, with the Subscriber notified by the client. Silent failure is not acceptable.

**Manual renewal** MUST always be available as an alternative to auto-renewal regardless of client implementation.

### 3.5 Price Display

Exchange rates for display purposes SHOULD use [Chainlink](https://docs.chain.link/) price feeds or equivalent decentralized price oracles. Price display is for informational purposes only. Transaction settlement MUST occur in the token agreed at subscription time. The protocol MUST NOT perform automatic token conversion.

### 3.6 Fiat Sandboxing

Fiat processors MAY operate as onramp and offramp services at the edges of the ecosystem under the following constraints:

- Fiat processors MUST NOT influence content policy decisions
- Fiat processors MUST NOT influence Creator account decisions
- Fiat processors MUST NOT participate in protocol governance
- A fiat processor's exit MUST NOT affect subscriptions on primary crypto rails
- No fiat processor holds a kill switch over protocol operation

---

## Section 4 — Content and Storage Layer

### 4.1 Encryption Architecture

All content MUST be encrypted before storage on any instance. Instances MUST store only ciphertext. The encryption and decryption model is as follows:

**Master secret:** Each Creator holds a master secret — a cryptographic secret from which all content keys for that Creator are derived. The master secret is generated by the Creator's client at account creation. The master secret is stored on the instance encrypted to the Creator's wallet public key. The instance cannot read the master secret without the Creator's wallet private key.

**Content key derivation:** Content keys are derived on demand from the master secret at access time. Content keys are NOT stored independently on the instance. Key derivation requires the master secret to be decrypted by the Creator's client, or delegated to an instance-side derivation service operating on the encrypted master secret unlocked by a valid wallet signature.

**Content encryption:** Each piece of content is encrypted with a content key derived from the Creator's master secret and the content's tier assignment. Content at tier N is accessible to Subscribers holding an active subscription to tier N or any higher tier that is a superset of tier N. Superset access is governed by key delivery, not by duplicate content storage — content is encrypted once per tier, not once per Subscriber.

In this version of the protocol, Creator tiers MUST be defined as a strict hierarchy — each tier is a superset of all tiers below it. Parallel non-superset tiers (distinct tiers at the same level with non-overlapping content) are not supported in v0.1 and are flagged as a future protocol extension.

### 4.2 Instance Storage Requirements

Instances MUST store the following for each hosted Creator:

- Encrypted content (ciphertext only)
- Encrypted master secret blob (ciphertext, accessible only via Creator's wallet private key)
- Content metadata: unique content fingerprint (hash), tier assignment, timestamp, public content warnings
- Subscriber subscription state: wallet addresses, tier, active period (this is public on-chain state mirrored locally for access performance)

Instances MUST NOT store:

- Plaintext content at any point
- Decryption keys in recoverable form
- Creator or Subscriber real identity information
- Wallet private keys or seed phrases

### 4.3 Content Addressing

Content MUST be addressed by cryptographic hash (content fingerprint). The same content at the same hash is the same content regardless of which instance holds it. [IPFS](https://ipfs.tech/) content addressing or equivalent content-addressed storage is the reference model. New ciphertext produced by key rotation or re-encryption produces a new hash automatically — old references become orphaned without requiring explicit invalidation.

### 4.4 Storage Allocation

Storage allocation per Creator is governed by the Creator's trust tier as defined in Section 9. Tier thresholds and storage limits are governance parameters defined in Section 13.

### 4.5 Content Lifecycle

Content exists in one of the following states:

- **Active:** Accessible to Subscribers with valid subscription state
- **Sunset notice issued:** Creator has been notified of pending removal; migration tools active; no new subscriptions accepted; existing Subscribers retain access
- **Subscriber protection window:** Read-only access for Subscribers active at notice time; access persists until their paid period lapses naturally
- **Deleted:** Content removed from instance storage; content fingerprint record retained for audit purposes

Transitions between states are governed by Section 7 (operator-initiated removal) and Section 15 (voluntary Creator departure).

### 4.6 Passive Data Deletion

Content storage is tied to continued economic activity. An instance MAY begin passive data deletion procedures when a Creator has no active Subscribers and no inbound transactions within the inactivity grace period. The inactivity grace period is a governance parameter defined in Section 13.

Passive deletion MUST follow the content lifecycle defined in Section 4.5 — the Creator MUST be notified and a sunset notice issued before deletion begins. Passive deletion MUST NOT bypass the subscriber protection window for any Subscribers active at notice time.

### 4.7 Key Rotation

A Creator MAY rotate their master secret at any time. Key rotation is a supported protocol operation with the following effects:

- New content key is derived from the new master secret
- All existing content is re-encrypted with new keys — the Creator's client pulls existing content, decrypts, re-encrypts, pushes new ciphertext, and updates content references
- New content fingerprints are registered; old fingerprints become orphaned
- Active Subscribers receive updated access via the new key derivation on their next access request

Re-encryption cost is proportional to total content volume and is borne by the Creator. The protocol does not subsidize re-encryption. Key rotation is the correct response to a compromised master secret. Re-encryption protects forward access; content already accessed by a party holding the old key cannot be retroactively protected. Re-encryption and the associated on-chain content reference updates are initiated by the Creator. Transaction fees are borne by the Creator.

---

## Section 5 — Access Control Layer

### 5.1 Access Model

Content access is governed entirely by on-chain subscription state. No platform logic, no human discretionary decision, and no instance operator judgment determines whether a Subscriber can access content. Subscription state is the sole authority.

### 5.2 Access Flow

1. Subscriber authenticates via wallet signing (Section 2.2)
2. Instance verifies subscription state on-chain for the requested tier
3. If subscription state is active: instance returns the content key derived from the Creator's master secret for the requested content
4. Subscriber's client decrypts content locally
5. If subscription state is inactive: instance returns an access denial; no key is derived or transmitted

### 5.3 Subscription Window

Subscription state is recorded on-chain at payment time. The subscription window begins at payment confirmation and ends at the expiry of the paid period. Expiry is determined by the subscription period agreed at payment time, recorded on-chain, and enforced by the smart contract.

A subscription expiry grace period MAY be defined as a governance parameter to accommodate minor clock or confirmation delays. This grace period MUST NOT exceed 24 hours. The grace period is a technical accommodation, not a free access extension.

### 5.4 Access Revocation

Access revocation on subscription lapse is automatic and governed by contract state. No manual process, no support ticket, no human decision is required or permitted. A Subscriber whose subscription lapses loses access at the end of the paid period plus any applicable grace period.

### 5.5 Verification Before Settlement

Payment finalization MUST be preceded by a verification step confirming that key delivery is technically possible for the subscribing wallet. If key delivery would fail due to a technical error, payment MUST NOT complete. A Subscriber MUST NOT pay for content they cannot access due to a protocol-layer technical failure.

### 5.6 Subscriber Protection During Sunset

When a sunset notice is issued (Section 7), Subscribers active at the time of notice retain read-only access to content through the natural expiry of their paid period. No new subscriptions MUST be accepted after a sunset notice is issued. A Subscriber whose paid period expires during the sunset window loses access at natural expiry — their access is not extended by the sunset process.

---

## Section 6 — Public Discovery Layer

### 6.1 Design Principle

DEN is a destination, not a discovery platform. Creators are discovered on the public social platforms they already use — Furaffinity, Bluesky, Twitter/X, Telegram, Discord — and follow a link to their DEN profile. The public discovery layer exists to make that link work well, not to replicate the social features of those platforms.

### 6.2 Public Profile

Every Creator MUST have a public profile accessible without a subscription, without an account, and without any wallet connection. The public profile MUST display:

- Creator pseudonymous name
- Creator description
- Available subscription tiers and their pricing
- Any content the Creator has designated as publicly visible (Section 6.3)
- Content warnings for paywalled content (titles and warnings only, not content)

The public profile MUST NOT require login, wallet connection, or account creation to view.

### 6.3 Public Preview Content

Creators MAY designate specific posts as publicly visible without a subscription. This is a Creator choice, not a protocol requirement. Public preview content is the Creator's primary tool for giving prospective Subscribers enough context to make a subscription decision.

### 6.4 Stable Creator URL

A Creator's public profile URL MUST be stable and instance-independent. Because Creator identity is wallet-based, the profile URL resolves correctly regardless of which instance the Creator is currently hosted on. A link posted on an external platform today MUST resolve correctly after a Creator migrates instances.

The URL scheme MUST address Creators by wallet address or a registered pseudonymous identifier, never by instance address alone.

### 6.5 No Login Wall Before Subscription Decision

A prospective Subscriber MUST be able to fully evaluate a Creator's public profile — tiers, pricing, public preview content, content warnings — before being asked to connect a wallet or create any account. Wallet connection is requested only at the point of initiating a subscription.

---

## Section 7 — Instance and Hosting Layer

### 7.1 Hoster Obligations

A compliant instance operator MUST:

- Store only ciphertext for all hosted content
- Store the encrypted master secret blob for each hosted Creator
- Maintain on-chain subscription state records
- Publish above-floor content standards publicly before accepting Creators
- Apply above-floor content standards uniformly to all Creators on the instance
- Follow the defined removal process for any Creator content removal
- Release Creator portable data on migration request
- Participate in batch settlement as defined in Section 7.3

### 7.2 Hoster Compensation

Hosters are compensated by the protocol via resource-based smart contract settlement. The compensation formula is:

`hoster_fee = (storage_consumed_GB × storage_rate) + (bandwidth_served_GB × bandwidth_rate)`

Storage and bandwidth rates are governance parameters defined in Section 13. Compensation routes peer-to-peer via smart contract. No platform intermediary holds or distributes Hoster compensation.

Hoster compensation is deliberately decoupled from Creator earnings. A Hoster earns identically per gigabyte regardless of whether the hosted Creator earns five dollars or five thousand. The incentive is efficient infrastructure, not selective hosting of profitable Creators.

### 7.3 Batch Settlement

Resource usage is metered continuously. Settlement to the blockchain occurs in defined intervals. The settlement interval is a governance parameter defined in Section 13. Claimed storage MUST be verifiable against content fingerprints recorded on-chain — overclaimed storage is detectable and constitutes a protocol violation.

The Hoster initiates settlement transactions and bears the associated transaction fees as an operating cost. Storage and bandwidth rates set at launch SHOULD account for transaction fee overhead.

### 7.4 Above-Floor Content Standards

Instance operators MAY set content standards above the protocol floor defined in Section 11. Above-floor standards MUST be:

- Published publicly before the instance accepts Creators
- Applied uniformly to all Creators on the instance
- Not applied selectively based on Creator identity, earnings, or any factor other than the content itself

Selective application of above-floor standards is an abuse of operator position and constitutes a protocol violation. A documented pattern of selective application MAY be reviewed by the governance process and MAY affect the instance's standing as a protocol participant.

### 7.5 Content Removal Process

Operator-initiated content removal MUST follow this process:

**Step 1 — Sunset notice issued:** Instance operator notifies the Creator and all active Subscribers. Migration tools activate automatically. The sunset window duration is a governance parameter (Section 13), with a suggested range of 30 to 90 days. No new subscriptions are accepted from this point.

**Step 2 — Sunset window:** Creator migrates to a new instance. Existing Subscribers retain full access during this window.

**Step 3 — Subscriber protection window:** After the sunset window closes, Subscribers active at notice time retain read-only access until their paid period lapses naturally. No new content is served; existing content remains accessible.

**Step 4 — Deletion:** After all Subscriptions active at notice time have lapsed, content is deleted from instance storage. Content fingerprint records are retained.

**Sunset notice is immutable once issued.** An operator MUST NOT retract a sunset notice. A sunset notice that has been issued converts the removal from a potential threat into an administrative process. The operator retains the ability to remove content through the process. They do not retain the ability to use the threat of removal as ongoing leverage.

### 7.6 What an Instance MUST NOT Do

- Store plaintext content
- Hold the Creator's wallet private key or unencrypted master secret
- Issue immediate deletion outside the defined removal process
- Apply above-floor standards selectively
- Retract a sunset notice once issued
- Impose friction on Creator migration beyond technical process requirements
- Restrict chain or wallet compatibility in ways that lock Creators to the instance

### 7.7 Instance Failure vs Deliberate Eviction

**Instance failure** — unplanned infrastructure event — is handled by the portability guarantee and content-addressed storage redundancy. It is not governed by the removal process. Creators and Subscribers affected by instance failure initiate migration under Section 8 and Section 15.

**Deliberate eviction** — operator-initiated removal — MUST follow the removal process in Section 7.5 without exception. An operator MUST NOT claim infrastructure failure to bypass the removal process.

---

## Section 8 — Creator Portability

### 8.1 The Minimum Portable Data Set

The following data belongs to the Creator at all times and MUST be held by the Creator independently of any instance:

- Cryptographic wallet keys (private key or hardware wallet custody)
- Subscriber list: wallet addresses and current subscription states
- Content references: fingerprints (hashes) and metadata for all uploaded content
- Pseudonymous Creator identity record
- Encrypted master secret blob (encrypted to Creator's wallet, readable only by Creator)

This data is always-held, not requestable-on-departure. A Creator who needs to migrate does not request their data from an instance — they already have it. An instance stores copies of this data to serve the protocol, not as the authoritative holder.

### 8.2 Instance Migration Requirements

**Departing instance MUST:**
- Release all elements of the minimum portable data set immediately on migration request
- Release the encrypted master secret blob
- Not impose waiting periods, fees, or procedural friction on migration beyond technical process requirements

**Receiving instance MUST:**
- Accept a Creator presenting valid portable data and a signed wallet authentication
- Restore subscription state from the portable subscriber list
- Accept content references and make content addressable under the new instance
- Store the encrypted master secret blob in the same manner as any hosted Creator

### 8.3 Automatic Migration Tool Activation

Migration tools MUST activate automatically when a sunset notice is issued. Activation requires no manual trigger by the Creator. Migration tools MUST remain active through the full sunset window.

### 8.4 Subscriber Continuity on Migration

Active Subscribers MUST be notified of a Creator's migration. Notification MUST include the new instance address. Subscription state follows the Creator — active subscriptions at migration time remain active at the receiving instance without requiring the Subscriber to resubscribe.

---

## Section 9 — Creator Trust Tiers

### 9.1 What Tiers Govern

Creator trust tiers govern:

- Maximum storage allocation per post
- Post rate limits (maximum posts per period)
- Maximum file size per upload

Tier thresholds, storage limits, rate limits, and file size limits are governance parameters defined in Section 13.

### 9.2 Tier Graduation Basis

Tier graduation is based on verified inbound transactions from distinct external wallet addresses over a defined lookback window. Graduation is automatic, passive, and requires no moderator approval, application process, or human decision.

The lookback window duration is a governance parameter defined in Section 13.

### 9.3 Self-Transaction Exclusion

Transactions from the Creator's own wallet addresses MUST NOT count toward tier graduation. Transactions from wallet addresses on the same instance the Creator operates as a Hoster MUST NOT count toward tier graduation.

This exclusion closes the self-hosting exploit where a Creator-Hoster could artificially inflate their own transaction history by routing payments through infrastructure they control. The exclusion MUST NOT penalize Creator-Hosters for legitimate self-hosting in other respects.

### 9.4 New Creator Baseline

New Creators begin at a baseline tier sufficient for normal creative output. The baseline MUST NOT be zero — a new Creator MUST be able to upload content and begin building an audience from day one. The baseline tier values are governance parameters defined in Section 13.

---

## Section 10 — Governance Layer

### 10.1 What Governance Controls

The governance process controls:

- Amendments to this specification
- Adjustment of governance parameters (Section 13)
- Addition or removal of supported chains (Section 3.1)
- Reclassification of values between fixed spec values and governance parameters
- Review of instance standing and protocol violation determinations

### 10.2 Fixed Values vs Governance Parameters

**Fixed spec values** MUST NOT be changed by governance parameter adjustment. They require a full spec amendment through the process in Section 10.4. Fixed values include: the foundational principles (Section 1), the protocol floor (Section 11), the encryption architecture (Section 4), the portability guarantee (Section 8), and the distinction between fixed values and governance parameters itself.

**Governance parameters** MAY be adjusted through the community approval process without a full spec amendment. All governance parameters are listed exhaustively in Section 13.

### 10.3 Founding Maintainer Role

The founding maintainer role is defined as first among equals. The founding maintainer has direction-setting authority and editorial control during the bootstrap phase (Section 10.5). This authority is earned by building the protocol and being publicly accountable to the community. It is not a veto. It is not permanent. The founding maintainer is removable by maintainer supermajority.

No entity including the founding maintainer holds unilateral decision power over this protocol.

### 10.4 Amendment Process

**During bootstrap phase (Section 10.5):**

1. Proposal published publicly with full reasoning
2. Minimum 30-day public comment period
3. All substantive objections MUST be addressed in writing — either incorporated into the proposal or explicitly overruled with documented reasoning
4. Founding maintainer editorial decision on adoption
5. Decision and reasoning published publicly

**During post-bootstrap phase (Section 10.6):**

1. Proposal published publicly with full reasoning
2. Minimum 30-day public comment period
3. All substantive objections MUST be addressed in writing
4. Rough consensus determination by the maintainer group — no formal vote required; unresolved substantive objections block adoption
5. Decision and reasoning published publicly

In both phases: emergency bypass is available only for cryptographically verified security vulnerabilities requiring immediate remediation. Emergency changes expire after 90 days and MUST be ratified through the full process or reverted.

### 10.5 Bootstrap Phase

The bootstrap phase begins at the first public release of this specification and ends when all three of the following thresholds are met simultaneously:

1. **3 non-founding maintainers** with demonstrated sustained contribution across multiple specification or implementation decisions
2. **5 independent instances** operating publicly — instances operated by distinct organizations or individuals; instances operated by the same party do not count as independent
3. **12 months elapsed** from the date of the first public instance

The bootstrap phase cannot be shortened by any single party. All three thresholds must be met simultaneously.

**On the bootstrapping circularity:** This specification was authored by the founding maintainer and has not been ratified by a community, because no community existed at the time of authorship. It takes effect as the founding document of record from first public release. Amendments from that point require the process defined in this section. This circularity is stated openly rather than obscured. The community's ability to fork this protocol is the ultimate check on founding maintainer authority.

### 10.6 Post-Bootstrap Phase

After bootstrap thresholds are met, the protocol transitions to community governance. The founding maintainer role becomes one vote among the maintainer group. The founding maintainer is removable by maintainer supermajority. Rough consensus replaces founding maintainer editorial decision on adoption.

### 10.7 Fork

A fork of this protocol is always available to any participant or community. Forking is the designed response when consensus cannot be reached through the amendment process. Forking is not a governance failure. It is the mechanism by which the community retains ultimate sovereignty over the protocol. The existence of the fork option is a feature, stated publicly and by design.

### 10.8 Founding Maintainer Sustainability

The founding maintainer is sustained by voluntary community contribution, transparently managed via [OpenCollective](https://opencollective.com/) or equivalent public platform. No equity. No revenue share. No investor with growth expectations. Nothing in the founding maintainer's economic position creates incentive to compromise the community the protocol serves.

---

## Section 11 — Content Policy Layer

### 11.1 Design Principle

Vagueness is an attack surface. The protocol floor is stated exhaustively with explicit reasoning for every position. Every category has a clear answer. Ambiguity is leverage for organizations that use pressure campaigns to restrict content without winning legal arguments. Exhaustive clarity removes that leverage.

### 11.2 Protocol Floor — Prohibited Content

The following content categories are prohibited at the protocol floor. No instance MAY host this content regardless of above-floor standards:

**Sexual content depicting minors.** Absolute prohibition. No jurisdiction carveout. No exceptions. This will not change through governance. The reasoning is not ambiguous and will not be re-litigated. For enforcement approach, see Section 11.4 and Section 12.

**Photographic content of real human beings.** Out of scope for this protocol. This is a different legal and technical problem from the illustrated and written content this protocol is designed for. It is not a moral judgment on photographic content communities. Instances focused on photographic content should use infrastructure designed for that purpose.

**Content generated primarily by artificial intelligence prompt.** This protocol exists to sustain human creative labor. Content where AI generation is the primary authorship — not a tool assisting human creativity, but the primary generator — is prohibited. The distinction between AI-assisted human creativity and AI-primary generation requires creative judgment and is enforced by instance operator determination (Section 12). No reliable automated technical test exists for this distinction; the spec acknowledges this honestly rather than specifying an unimplementable requirement.

**Real person content without consent.** Content depicting a real, identifiable person in a sexual or defamatory context without their documented consent is prohibited. This category addresses defamation and privacy exposure, not fictional characters who resemble real people incidentally.

### 11.3 Protocol Floor — Allowed Content

The following content categories are explicitly allowed at the protocol floor. Instances MUST NOT go below the floor by prohibiting these categories entirely, though above-floor standards MAY restrict or require content warnings:

**Illustrated, 3D rendered, and written adult content between adult characters.** Core to the community this protocol serves.

**Feral content.** Fictional animals are not real animals. This category is allowed without reservation.

**Vore, gore, and taboo kink content.** Fiction is not endorsement. Content warnings are required for all content in this category.

**Anthro and human characters.** Core to what the community this protocol serves creates.

**Any content type not explicitly prohibited** in Section 11.2, with appropriate content warnings where the content type warrants them.

### 11.4 On the CSAM Prohibition and Scanning Infrastructure

The prohibition on sexual content depicting minors is enforced through accountability, not surveillance. DEN MUST NOT build scanning infrastructure — no hash-matching database, no client-side scanning, no PhotoDNA integration. The reasons are architectural and intentional:

The E2EE architecture means the protocol has no plaintext access layer. There is no content to scan. Introducing scanning infrastructure would require breaking the encryption architecture, which is a fixed spec value not subject to governance amendment.

Scanning infrastructure, once introduced, can be mandated, expanded by legislative pressure, and updated to cover content categories beyond its original stated purpose. It never stays limited. The absence of scanning infrastructure is the architectural defense against this pattern — it cannot be mandated because it does not exist.

Legal liability for uploaded content sits with Creators. Subscribers — the only participants with plaintext access — are the detection layer. The reporting process is defined in Section 12.

---

## Section 12 — Moderation and Reporting Layer

### 12.1 Detection Layer

Subscribers are the primary detection layer for protocol floor violations. They are the only participants with plaintext access to content. Instance operators store ciphertext and MUST NOT assert protocol floor violations based on content they cannot read — such an assertion is architecturally meaningless and any attempt to use it constitutes abuse of the removal process.

### 12.2 Report Requirements

A report MUST include:

- The unique content fingerprint (hash) of the content in question
- Timestamp of access
- Specific violation category claimed (Section 11.2)
- Evidence supporting the claim

A report without all four elements is not actionable and MUST NOT trigger the moderation process. Reports from wallets without an active subscription to the reported content are not valid — the reporter MUST have had plaintext access to the content they are reporting.

Reports filed by a wallet address that is identical to or has a demonstrable operator relationship with the instance hosting the reported content MUST be treated as operator assertions regardless of Subscriber status. These reports MUST be automatically elevated to governance review and MUST NOT be adjudicated by the instance operator. The reporter and adjudicator MUST NOT be the same entity. Where the reporting wallet is identical to the operator wallet, this is auto-detectable. Where a different wallet is used, governance determination applies.

### 12.3 Suspend Before Delete

Immediate deletion is not available as a moderation action. Suspension of access is the mandatory first step for all violation claims. Suspension makes the content's state visible, gives the Creator a response window, and ensures deletion requires process completion. This MUST NOT be bypassed.

### 12.4 Creator Notification

On suspension, the Creator MUST receive immediately:

- Full report contents
- Pseudonymous identifier of the reporting Subscriber
- The specific violation category claimed
- The response window duration

### 12.5 Tiered Determination

**AI content and real-person content violations:**

1. Creator response window (duration: governance parameter, Section 13)
2. Instance operator determination after response window
3. Creator MAY appeal to the governance process
4. Deletion only after appeal is exhausted or waived
5. Sunset window subscriber protection applies during appeal

**CSAM violations:**

1. Immediate access suspension
2. Automatic mandatory referral to legal reporting infrastructure: [NCMEC CyberTipline](https://www.missingkids.org/gethelpnow/cybertipline) (US), [IWF](https://www.iwf.org.uk/) (UK), [INHOPE](https://inhope.org/) network (international)
3. Creator notified of suspension and referral
4. Protocol does not conduct independent adjudication of CSAM reports — this is a legal matter handled by the appropriate authorities
5. Suspension is time-bounded — automatic reinstatement after the csam_suspension_duration governance parameter period unless law enforcement has issued a preservation order or opened an active investigation, in which case suspension continues until that process concludes. Suspension lifted and outcome recorded on-chain if claim found unsubstantiated. If no law enforcement action is taken within the suspension period, reinstatement is automatic.

The protocol deliberately does not build its own CSAM review infrastructure. No internal panel, no distributed jury, no protocol-level adjudication. The legal referral infrastructure exists for this purpose. The protocol routes to it.

### 12.6 False Report Consequences

False reports carry on-chain consequences:

- Reporting wallet flagged on instance after first substantiated false report
- Repeated false reports result in loss of Subscriber status on the instance
- False report record written to the blockchain pseudonymously and permanently

Coordinated false reporting campaigns are detectable through on-chain records. A pattern of false reports from related wallets MAY be reviewed by the governance process as a protocol violation.

### 12.7 Creator Appeal

Any protocol floor violation determination resulting in content removal is appealable to the governance process. The governance process MAY overturn the determination, reinstate content, and find abuse of the removal process. A finding of abuse of process MAY affect the instance's standing as a protocol participant.

---

## Section 13 — Fee Transparency Layer

### 13.1 Principle

Every fee in this protocol is stated explicitly in this specification. No fee may exist that is not listed here. No fee listed here MAY be changed without governance approval. Hidden fees and unilateral fee changes are protocol violations.

### 13.2 Hoster Compensation Formula

`hoster_fee = (storage_consumed_GB × storage_rate) + (bandwidth_served_GB × bandwidth_rate)`

Storage rate and bandwidth rate are governance parameters. All compensation routes peer-to-peer via smart contract. There is no central treasury.

### 13.3 Protocol-Level Fee

If a protocol-level fee is introduced, it MUST be encoded in this specification, publicly visible, and changeable only by governance vote. No protocol-level fee is defined in this version of the specification.

### 13.4 Governance Parameters — Complete List

The following values MAY be adjusted through the governance process without a full spec amendment. This list is exhaustive — values not listed here are fixed spec values.

| Parameter | Description | Initial Value |
|-----------|-------------|---------------|
| `storage_rate` | Hoster compensation per GB stored | Set at launch |
| `bandwidth_rate` | Hoster compensation per GB served | Set at launch |
| `tier_thresholds` | Transaction counts required for Creator trust tier graduation | Set at launch |
| `tier_lookback_window` | Period over which tier graduation transactions are counted | Set at launch |
| `new_creator_baseline` | Baseline storage and rate limits for new Creators | Set at launch |
| `post_size_limits` | Maximum file size per tier | Set at launch |
| `post_rate_limits` | Maximum posts per period per tier | Set at launch |
| `sunset_window_duration` | Minimum duration of sunset window (suggested 30–90 days) | Set at launch |
| `subscriber_protection_window` | Minimum subscriber read-only access after sunset notice | Set at launch |
| `inactivity_grace_period` | Period of inactivity before passive deletion procedures begin | Set at launch |
| `batch_settlement_interval` | How frequently resource usage settles on-chain | Set at launch |
| `subscription_expiry_grace_period` | Buffer after subscription expiry before access revocation (max 24 hours) | Set at launch |
| `creator_response_window` | Time Creator has to respond to a moderation report | Set at launch |
| `csam_suspension_duration` | Automatic reinstatement duration after no law enforcement action is taken within the suspension period of CSAM suspension | Suggested: 30 days |

Initial values for all governance parameters are set through the initial governance process at protocol launch. This specification defines the parameter names and the adjustment process. It does not fix initial values.

---

## Section 14 — Protocol Scope and the Reference Client

### 14.1 What Is Out of Scope for This Protocol

The following are explicitly not protocol concerns:

**Terms of service or EULA.** The protocol is not a platform and has no users to present terms to. A protocol cannot present terms any more than TCP/IP presents terms.

**Privacy policies.** The protocol holds no personal data. Individual clients and instance operators hold whatever data their implementation collects and are responsible for their own privacy posture under their local law.

**Jurisdictional legal compliance.** Instance operators run under their local law. The protocol cannot and does not override local jurisdiction. Operators are responsible for their own legal analysis.

**Platform-level content moderation interfaces.** Client concern.

**User account management.** Client concern.

**Fiat-to-crypto onramp services.** Client concern. The protocol SHOULD NOT make the path unnecessarily opaque but MUST NOT mandate specific onramp providers.

### 14.2 The Reference Client

A companion open-source reference client — working title furDEN — is planned as the standard interface for Creators and Subscribers accessing DEN. It will be released under [AGPL](https://www.gnu.org/licenses/agpl-3.0.en.html). The reference client is a separate project from this protocol specification. Its legal disclosures, privacy policy, and terms of use are its own responsibility and are not specified here.

This protocol is client-agnostic. Any compliant client MAY connect to any compliant instance.

---

## Section 15 — Onboarding and Migration

### 15.1 New Creator Onboarding

New Creators begin at the baseline trust tier (Section 9.4). The baseline MUST be sufficient for normal creative output. No transaction history is required to begin. Tier graduation is passive and automatic (Section 9.2).

### 15.2 Creator Migration from Existing Platforms

The protocol supports Creator migration from existing subscription platforms. At the protocol level, migration support consists of:

- Accepting a Creator's existing subscriber list (external wallet addresses) as the starting point for subscription state migration
- Subscriber notification with forwarding address to the new DEN instance
- Content reference migration via portable data set

Specific migration tooling for importing data from specific external platforms is a client implementation concern.

### 15.3 Subscriber Onboarding

The protocol MUST NOT make the path from fiat currency to active subscription unnecessarily opaque. The protocol does not mandate specific fiat-to-crypto onramp services. Client implementations SHOULD surface onramp options clearly to prospective Subscribers who do not hold supported tokens.

### 15.4 Voluntary Creator Departure

A Creator MAY leave an instance voluntarily on their own timeline. Voluntary departure differs from operator-initiated removal: the Creator sets the migration timeline, there is no mandatory sunset window imposed by the operator, and the process is not governed by Section 7.5.

Obligations on voluntary departure:

- Active Subscribers MUST be notified with the new instance address before departure
- The Creator MUST allow active Subscriptions to lapse naturally or offer refunds for unexpired periods — the Creator MUST NOT simply disappear from an instance while holding active subscriber payments
- The departing instance MUST release the minimum portable data set immediately on Creator request

---

## Appendix A — Resolved Design Decisions

A record of design decisions where alternatives were evaluated, for governance reference. Decisions listed here are not open for re-litigation without the governance process.

**Distributed jury for moderation — rejected**
Considered as distributed content violation determination. Rejected: legal exposure for jurors on CSAM-adjacent content; gameable selection through trust tier manipulation; inconsistent verdicts contradict the vagueness-as-attack-surface principle. Replaced by tiered determination and governance appeal (Section 12).

**Revenue-share hoster compensation — rejected**
Rejected because it directly incentivizes hosting only profitable Creators. Replaced by resource-based compensation decoupled from Creator earnings (Section 7.2).

**Hash-matching and client-side scanning for CSAM — rejected**
Rejected: introduces scanning infrastructure that can be mandated and expanded; [PhotoDNA](https://www.microsoft.com/en-us/photodna)-style databases require trusting an external authority over database contents; client-side scanning is general surveillance infrastructure regardless of stated first use. Replaced by architectural impossibility as primary defense, subscriber reporting as detection layer, creator liability as enforcement anchor (Section 11.4, Section 12).

**Time-based trust tier graduation — rejected**
Rejected because time-based graduation is gameable by waiting without ecosystem participation. Replaced by income-based graduation tied to verified external transactions (Section 9.2).

**ActivityPub as protocol-level federation — rejected**
Rejected: furry community subscription platform usage does not require fediverse discoverability — DEN is a destination, not a discovery platform; ActivityPub's foundational assumptions (content readable by federated instances, identity coupled to instance address) directly conflict with DEN's foundational assumptions; custom activity types for payment-gated content would add maintenance burden with no benefit. Optional fediverse broadcast remains available to client implementations (Section 6.1).

**Per-content key bundle delivery — rejected**
Considered as the primary key model. Rejected: key bundle size scales with content volume and subscription history, producing unbounded growth (5 years × 5 tiers × 12 months = 300+ keys per subscriber); bundle maintenance at scale is expensive infrastructure; bundle storage creates a data target on instances. Replaced by on-demand key derivation from master secret at access time, with subscription state as the sole access authority (Section 4, Section 5).

**Monthly key rotation — rejected**
Considered as a subscriber churn protection mechanism. Rejected: rotation cost scales with subscriber count; former subscriber access to paid-period content is standard and expected behavior on subscription platforms — lapse means loss of access. Replaced by lapse-equals-loss-of-access model matching standard subscription platform expectations (Section 5.4).

**Protocol-level wallet recovery infrastructure — rejected**
Considered as a usability accommodation. Rejected: any recovery mechanism the protocol holds creates a target — an entity that can compel recovery infrastructure can impersonate any participant; custody of recovery information is equivalent to custody of identity. Wallet private key custody is the participant's responsibility. Client implementations MAY provide password-based convenience layers over local key storage (Section 2.5).

**On-chain CSAM adjudication process — rejected**
Considered as an internal protocol-level review panel for CSAM reports. Rejected: the protocol should not be in the business of adjudicating CSAM claims; legal reporting infrastructure exists for this purpose; building parallel infrastructure creates liability without commensurate benefit. Replaced by mandatory referral to NCMEC/IWF/INHOPE (Section 12.5).

**Creator master secret held on creator device only — rejected**
Considered as maximum privacy model. Rejected: requires Creator device to be online for all Subscriber access requests, creating a liveness dependency incompatible with normal Creator behavior. Replaced by master secret stored on instance encrypted to Creator wallet public key — ciphertext the instance cannot read (Section 4.1).

## Appendix B — Open Questions Summary

A consolidated list of all open questions flagged in the sections above, for tracking before spec drafting begins.

| Section | Open Question | Spec Impact | Status |
|---------|--------------|-------------|--------|
| 2.5 | Active smart contract Subscription state referencing potential old wallet indentity | Implementation decision| Open |
| 14 | Reference client name, scope, and development timeline | Project decision — outside protocol spec | Open |

---

*DEN — Decentralized Encrypted Network*
*Protocol Specification v0.1-draft*
*This document contains binding implementation requirements. Companion document: `den-architecture.md`.*
*Amendments require the governance process defined in Section 10.*