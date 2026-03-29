# DEN — Decentralized Encrypted Network
## Protocol Specification v0.1-draft

This document contains binding implementation requirements for the DEN protocol. Implementations claiming DEN compliance MUST satisfy all MUST requirements in this specification. SHOULD requirements are strong recommendations whose deviation requires documented justification. MAY requirements are explicitly optional.

This document is a companion to [`den-architecture.md`](./den-architecture.md), which records design rationale and rejected alternatives. Where this document says what implementations must do, the architecture document explains why.

The key words MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

---

## Section 0 — Definitions

These terms are used throughout this specification without re-definition. Where natural-language inference would lead to an incorrect meaning, terms are defined precisely here.

**Instance** — a running deployment of the DEN protocol operated by a Hoster. An instance provides storage, compute, and bandwidth for Creators and Subscribers. Multiple instances form the network. No single instance is authoritative over any other.

**Protocol floor** — the structural prohibitions that every compliant instance MUST enforce, defined in Section 11. The floor consists of prohibitions grounded in legal liability for real people. Instance-level standards may exceed the floor but MUST NOT claim to enforce the floor against content that does not meet the specific prohibitions stated in Section 11.2.

**Governance parameter** — a protocol value that MAY be adjusted through the community governance process defined in Section 10 without requiring a full specification amendment. All governance parameters are listed exhaustively in Section 13.

**Subscription state** — the on-chain record of whether a specific wallet address holds an active subscription to a specific Creator tier on a specific instance. Subscription state is the authoritative source for content access decisions. It is publicly visible on-chain by design.

**Ciphertext** — the encrypted form of content or key material. Ciphertext is unreadable without the corresponding decryption key. Instances store ciphertext. Instances MUST NOT store plaintext content.

**Master secret** — the Creator-held cryptographic secret from which content encryption keys are derived. The master secret is stored on the instance in encrypted form, accessible only via the Creator's wallet private key. Defined in Section 4.

**Content key** — a symmetric encryption key derived from the Creator's master secret, used to encrypt a specific piece of content. Derived on demand at access time. Never stored independently on the instance.

**Sunset notice** — a formal notification issued by an instance operator that a Creator's content will be removed from that instance. Governed by Section 7. Immutable once issued.

**Protocol floor violation** — any content that violates the prohibitions defined in Section 11. Detection, reporting, and removal of protocol floor violations is governed by Section 12.

**Migration** — the process by which a Creator moves their identity, content references, subscriber relationships, and master secret from one instance to another. Governed by Section 8 and Section 15.

**Purchase state** — the on-chain record of whether a specific wallet address has completed a one-time purchase of a specific shop item or pack. Purchase state is permanent and does not expire. It is publicly visible on-chain by design.

**Shop item** — an individual piece of content available for one-time purchase independent of subscription state. Access is perpetual after purchase, governed by purchase state.

**Pack** — a content object whose payload is an access grant declaration listing which shop item derivation paths the purchase unlocks. A pack is purchasable as a single transaction. Pack membership reflects current pack state — purchase grants access to items the pack currently declares, not a historical snapshot.

**Access grant declaration** — a creator-authored record stored on the instance as part of the portable data set, declaring which derivation paths a subscription tier or pack purchase unlocks. Access grant declarations are required for key derivation at any instance and MUST be included in the portable data set.

**Identity contract** — a per-participant proxy smart contract deployed on the canonical identity chain at first registration. The identity contract holds the participant's current active wallet address and any registered emergency wallet addresses. The contract address never changes and is the stable DEN identifier for that participant. Subscriptions, purchase state, and content references address participants by identity contract address, not by wallet address directly. The proxy pattern allows the participant to upgrade contract logic without changing the contract address or requiring migration of downstream references.

**Canonical identity chain** — Base (EVM L2). Identity contracts are deployed on Base. Identity resolution is authoritative on Base. Participants transacting on non-EVM rails (TRON, Solana) still require an EVM wallet for identity contract operations. TRON and Solana are payment rails; they are not identity rails.

**Emergency wallet** — a secondary wallet address registered by a participant against their identity contract as an additional authorized key. The emergency wallet can independently authenticate, decrypt the master secret blob, initiate wallet rotation, cancel pending rotations, and initiate revocation of other registered wallets. Registration is optional but strongly recommended. An emergency wallet SHOULD be kept in cold storage and used only for the operations above.

**Wallet rotation** — the protocol operation by which a participant updates the active wallet address recorded in their identity contract. Rotation does not change the identity contract address. All subscriptions, purchase state, content references, and trust tier history continue to resolve against the same identity contract address after rotation.

**On-chain identity record** — a structured record held within a Creator's identity contract containing: the Creator's current instance URL, current active handle (if registered), recent handle aliases within the `handle_alias_retention_window`, and chronological instance migration history. The on-chain identity record is the authoritative resolver for mapping a Creator's stable identity contract address to their current serving instance. Instance migration updates require both a signed Creator transaction and a countersignature from the receiving instance confirming the migration has landed before the record is updated.

**Handle** — a human-readable pseudonymous identifier a participant MAY register against their identity contract as a convenience alias. A handle resolves to the participant's identity contract address. Handle registration requires the registering wallet to have at least one prior on-chain transaction. Handles are unique across the protocol — first registration wins, enforced by the smart contract. Handle changes are rate-limited by the `handle_change_allowance` and `handle_change_period` governance parameters. There is no fee for registration or change within the allowance.

**Handle alias** — a previously active handle superseded by a new handle registration. Handle aliases continue to resolve to the same identity contract address for the duration of the `handle_alias_retention_window` governance parameter. Resolution of a handle alias SHOULD return deprecation metadata indicating the participant's current active handle. After the retention window expires, the alias is released for re-registration by any participant.

**Active migration tag** — an on-chain flag set on a Creator's identity record when a migration is in progress, from the point of sunset notice or voluntary departure initiation until the receiving instance countersigns the migration confirmation. The active migration tag exempts the Creator from the `storage_compensation_lookback` threshold calculation for the duration of the migration.

**Compliance registry** — a governance-maintained public record of instance compliance status. Two states: recognized (default, no active compliance findings) and non-compliant (requires a governance finding with documented reasoning and community process under Section 10). The founding maintainer MUST NOT unilaterally add or remove instances from the compliance registry. Community instance directories are a separate concern and are not a protocol function.

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

*Implementation implication:* The protocol floor defined in Section 11 states structural prohibitions with explicit legal grounding. Everything not prohibited at the protocol floor is unrestricted at the protocol level. Content policy beyond the floor is instance-level community standards. Ambiguous cases at the protocol floor are resolved by governance amendment that sets binding precedent — not by ad hoc instance operator judgment.

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

#### 2.5.1 Root of Trust

The wallet private key, secured by the seed phrase, is the sole protocol-level credential. Instance authentication, content key derivation, rotation operations, and identity recovery all ultimately require a wallet private key registered against the participant's identity contract. Wallet private key custody is the participant's sole responsibility. The protocol MUST NOT store wallet private keys or seed phrases. The protocol MUST NOT provide wallet recovery infrastructure.

Client-layer convenience mechanisms — passwords, biometrics, email recovery — operate below this layer. They protect against casual unauthorized access to the client. They do not protect against an adversary who holds the seed phrase. A participant who holds their seed phrase can always recover full protocol access regardless of client state. A participant who loses all registered wallet access loses their protocol identity. This is the designed behavior, consistent with all self-custodial wallet systems.

#### 2.5.2 Identity Contract

At first registration each participant deploys an identity contract on the canonical identity chain (Base). The identity contract address is the participant's stable DEN identifier. All subscriptions, purchase state, content references, and trust tier history address the participant by identity contract address, not by wallet address directly.

The identity contract holds:
- The current active wallet address
- Any registered emergency wallet addresses
- Pending rotation or revocation announcements and their expiry times

The identity contract MUST be deployed as a participant-controlled proxy. The participant holds the upgrade key. The protocol publishes reference implementation addresses. Participants upgrade their contract logic at will by pointing their proxy to a new implementation. No protocol authority holds upgrade keys over any participant's identity contract.

#### 2.5.3 Emergency Wallet

A participant MAY register one or more emergency wallet addresses against their identity contract. Registration MAY occur at account creation or at any later time while the primary wallet is accessible. An emergency wallet SHOULD be kept in cold storage with no prior transaction history linking it to the participant's daily activity. It SHOULD be treated with the same security discipline as the primary wallet.

An emergency wallet can independently:
- Authenticate to any instance
- Decrypt the master secret blob (for Creators — requires multi-key encryption, Section 4.1)
- Initiate wallet rotation
- Cancel pending rotation or revocation announcements
- Initiate revocation of another registered wallet

An emergency wallet SHOULD maintain a small token balance sufficient to cover transaction fees for the operations above. A wallet with zero balance cannot submit transactions regardless of what it authorizes.

Registration of an emergency wallet is optional. Participants who do not register one accept that the compromise or loss scenarios below have no recovery path.

**Subscriber emergency wallets:** Subscribers MAY register emergency wallets under the same mechanism. Subscribers without significant purchase state MAY omit this. Subscribers with material purchase history SHOULD register one — purchase state is permanent and on-chain, and represents accumulated value that cannot be recovered if wallet access is lost.

#### 2.5.4 Wallet Rotation

**Clean rotation — both wallets accessible:**
Dual-signature rotation requires signatures from both the old and new wallet addresses. The identity contract updates the active wallet immediately on dual-signature verification. No time delay applies.

**Compromise rotation — old wallet inaccessible or untrusted:**
Any wallet registered against the identity contract MAY announce a unilateral rotation. The announcement is recorded on-chain. A time-delay window begins, duration governed by the `wallet_rotation_delay` governance parameter. During this window, any other wallet registered against the same identity contract MAY cancel the rotation. If the window expires without cancellation, the rotation completes and the new wallet becomes the active wallet.

Cancellation is on-chain and visible. A pattern of announced-then-canceled rotations is a signal that an account is under active attack. Client implementations SHOULD surface this state visibly to the participant.

Completing a compromise rotation via the emergency wallet when the primary wallet is inaccessible is the primary designed use case for the emergency wallet.

#### 2.5.5 Wallet Revocation

Any wallet registered against an identity contract MAY announce revocation of another registered wallet. Revocation follows the same time-delay mechanism as unilateral rotation — `wallet_rotation_delay` duration, cancellable by any registered wallet during the window.

Revocation removes the target wallet from the identity contract's registered key set. It does not rotate the active wallet. Revocation is the correct response when an emergency wallet is known to be compromised — the legitimate participant uses their primary wallet to announce revocation of the compromised emergency wallet, waits out the delay, and the compromised wallet loses all identity contract authority.

#### 2.5.6 Griefing and Rate Limiting

An attacker holding a registered wallet MAY announce rotations or revocations repeatedly as harassment without intending to complete them. The `rotation_announcement_cooldown` governance parameter defines the minimum period between rotation or revocation announcements from the same identity contract. This limits harassment cost without creating urgency friction in legitimate operations.

The structural resolution to a compromised registered wallet is revocation (Section 2.5.5), not cancellation of individual announcements.

#### 2.5.7 Master Secret Re-encryption on Rotation

When a Creator's active wallet changes via rotation, the master secret blob MUST be re-encrypted to the new wallet public key. If an emergency wallet is registered, the blob MUST be re-encrypted to both. Re-encryption requires access to the current master secret, which requires the current active wallet or any registered emergency wallet to decrypt the existing blob. See Section 4.7 for re-encryption mechanics.

#### 2.5.8 Client Convenience Layers

Client implementations MAY provide username and password authentication as a convenience layer over wallet signing. In this pattern, the client stores wallet key material encrypted by the user's password locally on the device.

Client implementations MAY offer email-based password recovery. In this pattern, email resets the local client password only. Email recovery requires device access — the encrypted key material lives on the device, not on any server. A participant who loses both their device and their seed phrase loses wallet access regardless of email recovery. Email recovery is not a substitute for the seed phrase.

Client implementations offering convenience authentication layers MUST:
- Never transmit wallet private key material or seed phrases to any external party, including the instance
- Store wallet key material encrypted locally on the participant's device only
- Be open source to permit community auditability of the above guarantees
- Communicate clearly at onboarding what each recovery path does and does not protect against

The instance MUST NOT receive the client password or unencrypted wallet key material at any point.

#### 2.5.9 On-Chain Identity Record and Handle System

Identity record contents: A Creator's identity contract holds an on-chain identity record containing:

- Current instance URL — where the Creator's content is currently served
- Current active handle, if registered
- Recent handle aliases within the handle_alias_retention_window, with deprecation metadata
- Chronological instance migration history

This record is the authoritative resolver for all Creator discovery. Compliant clients MUST resolve Creator identity via this on-chain record before routing.
Migration record updates: When a Creator migrates to a new instance, the identity record update MUST follow this two-step process:

1. Signed transaction from the Creator's active wallet announcing the migration and new instance URL
2. Countersignature from the receiving instance confirming it has the Creator's portable data set and is ready to serve Subscribers

The record MUST NOT update to the new instance URL until both signatures are present. The active migration tag is set on the Creator's identity record from announcement until countersign.

**Handle registration:** Handle registration requires the registering wallet to have at least one prior on-chain transaction. Fresh wallets with no transaction history MUST NOT register handles. This limits mass squatting without imposing a financial barrier. Handle changes are rate-limited by the `handle_change_allowance` and `handle_change_period` governance parameters. Allowance refreshes after each period. There is no fee for registration or change within allowance.

**Handle uniqueness and collision:** Handles are unique across the protocol. First registration wins, enforced by the smart contract. A handle already registered as either an active handle or a current alias MUST NOT be registered by another participant.

**Handle aliases:** When a participant changes their handle, the old handle becomes an alias resolving to the same identity contract address for the duration of the `handle_alias_retention_window`. Alias resolution SHOULD return deprecation metadata indicating the current active handle so clients can surface "this creator now goes by X." After the retention window expires the alias releases and becomes available for re-registration by any participant.

**Client resolution requirements:**
- For profile browsing: clients MAY cache identity record resolution results for up to resolver_cache_ttl. Stale routing during the cache window is acceptable — the Creator's prior instance continues serving during any migration window.
- For any transaction (subscription payment, shop item purchase, pack purchase): clients MUST perform a fresh on-chain identity record resolution immediately before initiating the transaction. Cached results MUST NOT be used for payment routing under any circumstances.

**Canonical identifier requirement:** A compliant client MUST NOT present an instance-specific URL as the canonical or shareable Creator identifier in any context where a Subscriber would store or share it. The canonical identifier is always the Creator's identity contract address or registered handle. Shareable links generated by compliant clients MUST use the form `den://[handle]` or `den://[identity-contract-address]`, never an instance-domain URL. Presenting instance-specific URLs as canonical identifiers is a compliance violation — it creates soft migration lock-in by training Subscribers to store URLs that break on instance change.

**Instance hopping:** A pattern of rapid successive migrations is detectable through the on-chain migration history. A Creator with anomalous migration frequency MAY be reviewed by the governance process as a potential compliance issue. The on-chain migration history exists in part to make this pattern auditable.

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

### 3.7 Shop Item and Pack Purchase Flow

Shop item and pack purchases MUST be implemented as direct on-chain transfers triggering purchase state on the smart contract, following the same direct transfer model as subscription payments (Section 3.4).

Purchase state is permanent and does not expire. A wallet address that holds purchase state for a shop item or pack retains that state indefinitely and across Creator migration.

**No refunds.** Cryptocurrency transactions are final by design. The protocol does not support refunds for shop item or pack purchases. The verification-before-settlement principle (Section 5.5) applies: if key delivery would fail due to a protocol-layer technical error, the purchase transaction MUST NOT complete. If the transaction completes, it is final.

Auto-renewal does not apply to shop item or pack purchases. Auto-renewal is a subscription mechanism only.

Shop item and pack purchases count toward Creator trust tier graduation under the same rules as subscription transactions (Section 9.2).

The protocol fee `protocol_fee_pct` applies to shop item and pack purchases identically to subscription payments. The fee is collected at the smart contract level at the point of purchase and routed to the per-creator escrow, from which the Hoster claims resource compensation under the standard formula (Section 7.2).

---

## Section 4 — Content and Storage Layer

### 4.1 Encryption Architecture

All content MUST be encrypted before storage on any instance. Instances MUST store only ciphertext. The encryption and decryption model is as follows:

**Master secret:** Each Creator holds a master secret — a cryptographic secret from which all content keys for that Creator are derived. The master secret is generated by the Creator's client at account creation. The master secret is stored on the instance encrypted to the Creator's wallet public key. The instance cannot read the master secret without the Creator's wallet private key.

When an emergency wallet is registered, the master secret blob MUST be re-encrypted to both the primary wallet public key and the emergency wallet public key. Either wallet can decrypt the blob independently. The instance stores one blob encrypted to multiple recipients. This re-encryption MUST occur at the time of emergency wallet registration. Subsequent wallet rotations MUST update the blob accordingly (Section 4.7, Section 2.5.7).

**Content key derivation:** Content keys are derived on demand from the master secret at access time. Content keys are NOT stored independently on the instance. Key derivation requires the master secret to be decrypted by the Creator's client, or delegated to an instance-side derivation service operating on the encrypted master secret unlocked by a valid wallet signature.

Each tier and each shop item has an independent derivation path. Keys are derived as:

- Subscription content: `derive(master_secret, "tier:" + tier_id)`
- Shop item content: `derive(master_secret, "item:" + item_id)`

The type namespace prefix prevents collisions between derivation paths. Content keys are NOT stored independently on the instance.

**Access grant declarations:** The relationship between tiers — whether a higher tier also grants access to lower tier content — is a creator-authored access grant declaration stored on the instance as part of the portable data set. It is NOT hardcoded into the derivation logic. The access predicate for a given subscriber wallet evaluates: does this wallet's on-chain state, combined with the creator's access grant declarations, authorize derivation of the requested path?

This model supports both hierarchical tiers (where higher tiers declare grants to lower tiers) and parallel tiers (distinct tiers at the same level with no declared grant between them). Parallel tiers are fully supported.

**Content encryption:** Each piece of content is encrypted with a content key derived from the Creator's master secret and the content's tier or item assignment. Content is encrypted once per tier or item — not once per Subscriber. Superset access is governed by access grant declarations, not by duplicate content storage.

**Shop item and pack derivation:** Shop item content is encrypted under a derivation path keyed by item ID. Pack purchases are on-chain purchase state records referencing a pack ID. The pack, as a content object, declares which item derivation paths the purchase unlocks via its access grant declaration. Pack state is current, not historical: access reflects what the pack currently declares.

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
- The encrypted master secret blob client-local only — the instance is the authoritative store; the client MAY cache it locally for performance but MUST NOT be the sole holder

### 4.3 Content Addressing

Content MUST be addressed by cryptographic hash (content fingerprint). The same content at the same hash is the same content regardless of which instance holds it. [IPFS](https://ipfs.tech/) content addressing or equivalent content-addressed storage is the reference model. New ciphertext produced by key rotation or re-encryption produces a new hash automatically — old references become orphaned without requiring explicit invalidation.

### 4.4 Storage Allocation

Storage allocation per Creator is governed by the Creator's trust tier as defined in Section 9. Tier thresholds and storage limits are governance parameters defined in Section 13.

### 4.5 Content Lifecycle

Content exists in one of the following states:

- **Active:** Accessible to Subscribers with valid subscription state
- **Archived:** Creator-designated state indicating content is no longer actively maintained. Content remains accessible to Subscribers with valid subscription state and to buyers with valid purchase state. No new access tiers may be assigned to archived content. Hosters MAY treat archived content differently in internal storage management provided it remains accessible as required. Archiving is creator-initiated and voluntary. Access for purchase state holders is conditioned on the content continuing to exist on the instance — hosters are not permanent file keepers for purchased content.
- **Sunset notice issued:** Creator has been notified of pending removal; migration tools active; no new subscriptions accepted; existing Subscribers retain access
- **Subscriber protection window:** Read-only access for Subscribers active at notice time; access persists until their paid period lapses naturally
- **Deleted:** Content removed from instance storage; content fingerprint record retained for audit purposes

Transitions between states are governed by Section 7 (operator-initiated removal) and Section 15 (voluntary Creator departure). The archived state is creator-initiated at any time and does not affect subscriber access or the compensation formula.

### 4.6 Passive Data Deletion

Content storage is tied to continued participation, not economic activity alone. An instance MAY begin passive data deletion procedures only when BOTH of the following conditions are met within the inactivity grace period:

1. The Creator has no active Subscribers on this instance
2. The Creator has had no content activity — uploads, edits, or archiving — within the inactivity grace period

Both conditions MUST be present simultaneously. A Creator with no subscribers but who is actively uploading content is NOT inactive. A Creator with no recent content activity but who retains active subscribers is NOT inactive. New Creators with zero subscribers are explicitly protected by this dual-condition requirement — the deletion clock does not start at account creation.

The `storage_compensation_lookback` threshold (Section 7.2) is a separate mechanism governing whether a hoster can claim compensation for a given Creator's storage. It does not govern deletion. A Creator may exist in a state where they generate no compensable storage claim but are still protected from deletion by ongoing content activity.

The inactivity grace period is a governance parameter defined in Section 13.

**Purchase state does not block passive deletion.** Active on-chain purchase state for shop items or packs is not a condition that protects content from passive deletion. A Creator with no active subscribers and no content activity meets the deletion conditions regardless of how many buyers hold purchase state for their content. Purchase state is permanent on-chain; content availability is not. Client implementations MUST communicate clearly at the point of purchase that access to purchased content is contingent on the content continuing to exist on the instance, and that buyers who wish to retain content permanently SHOULD download it at time of purchase.

Passive deletion MUST follow the content lifecycle defined in Section 4.5 — the Creator MUST be notified and a sunset notice issued before deletion begins. Passive deletion MUST NOT bypass the subscriber protection window for any Subscribers active at notice time.

### 4.7 Key Rotation

A Creator MAY rotate their master secret at any time. Key rotation is a supported protocol operation and is explicitly a normal proactive operation — not an emergency-only one. A Creator who suspects future compromise SHOULD re-encrypt before compromise is confirmed rather than after. The protocol supports this without restriction.

**Who can initiate re-encryption:** Re-encryption MAY be initiated by the Creator's primary wallet or by any registered emergency wallet independently. Primary wallet presence is not required. This is the designed path when the primary wallet is inaccessible or untrusted.

**Effects of key rotation:**

- New master secret generated
- New content keys derived from new master secret
- All existing content re-encrypted — Creator's client (or emergency wallet client) pulls existing ciphertext, decrypts with old keys, re-encrypts with new keys, pushes new ciphertext
- New content fingerprints registered on-chain; old fingerprints become orphaned
- Master secret blob re-encrypted to current active wallet and any registered emergency wallets (Section 4.1)
- Active Subscribers receive updated access via new key derivation on their next access request — no Subscriber action required

**Tier-level atomicity:** Re-encryption proceeds tier by tier. Access to a tier in progress is briefly suspended while that tier re-encrypts, then restored. Subscribers on tiers not yet reached retain normal access throughout. Full library lockout is not required. Client implementations SHOULD communicate the re-encryption state to affected Subscribers transparently.

**On-chain reference updates:** Each piece of re-encrypted content produces a new fingerprint requiring an on-chain content reference update. Client implementations SHOULD batch content reference updates into as few transactions as possible. Per-item transactions at meaningful content volumes produce unnecessary fee overhead that is entirely avoidable.

**Cost:** Re-encryption cost is proportional to total content volume and is borne by the Creator. The protocol does not subsidize re-encryption. Transaction fees for on-chain reference updates are borne by the Creator.

**Scope:** Re-encryption protects forward access. Content already accessed and locally retained by a party holding the old key cannot be retroactively protected. This is stated honestly and is consistent with all encrypted content systems.

### 4.8 Shop Item and Pack Storage

**Shop items** are content objects following the standard content lifecycle (Section 4.5). They are encrypted under a derivation path keyed by item ID (Section 4.1). Storage allocation for shop items is governed by the Creator's trust tier in the same manner as subscription content.

**Packs** are content objects whose payload is an access grant declaration — a machine-readable record of which item IDs the pack purchase unlocks. Packs are created, stored, and addressed by content fingerprint following the same process as any content object.

Pack membership reflects current pack state. A Creator MAY add or remove items from a pack by updating the pack content object, producing a new content fingerprint. Buyers whose purchase state references the pack ID access whatever the pack currently declares. Pack modification SHOULD trigger notification to existing buyers — this is a client-layer notification obligation, not a protocol enforcement requirement.

Pack deletion follows the standard content lifecycle (Section 4.5). If a pack is deleted, existing buyers retain purchase state on-chain but the access grant declaration no longer exists to resolve. This is consistent with how content deletion affects Subscribers generally. Creators SHOULD NOT delete packs with active buyers without providing reasonable notice.

Instance storage requirements (Section 4.2) apply to shop items and packs identically to subscription content. Current pack state MUST be included in the Creator's portable data set (Section 8.1).

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

### 5.7 Purchase-Based Access (Shop items)

Purchase-based access follows the same verification structure as subscription-based access with the following differences:

**Access flow:**

1. Buyer authenticates via wallet signing (Section 2.2)
2. Instance verifies purchase state on-chain for the requested item or pack ID
3. For pack purchases: instance resolves the pack's current access grant declaration to determine which item derivation paths the purchase unlocks
4. Instance derives the content key for the requested item path
5. Buyer's client decrypts content locally
6. If no purchase state exists: instance returns access denial; no key is derived or transmitted

**No expiry.** Purchase state does not expire. Access revocation on lapse does not apply to purchase-based access. A wallet with valid purchase state retains access as long as the content exists on the instance. Purchase state is permanent; content availability is not. Buyers SHOULD download purchased content they wish to retain permanently.

**Pack resolution.** For pack purchases, the instance resolves the pack's current access grant declaration at access time. Access reflects current pack state.

**Purchase state survives migration.** Purchase state is on-chain and survives Creator migration identically to subscription state. A receiving instance MUST accept on-chain purchase state from migrating Creators and serve access accordingly. The receiving instance MUST have the current pack access grant declarations from the Creator's portable data set to resolve pack purchases correctly.

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

A Creator's public profile URL MUST be stable and instance-independent. A link posted on an external platform today MUST resolve correctly after a Creator migrates instances.

The mechanism is the on-chain identity record defined in Section 2.5.9. The Creator's identity contract address and registered handle are the canonical identifiers. These never change on migration — only the serving instance URL within the identity record updates, via the countersigned migration process.

Compliant clients MUST resolve Creator identity via the on-chain identity record before routing. Direct routing to a cached instance URL without checking the identity record will break after migration when the cache expires. Clients MUST follow the resolution and caching requirements in Section 2.5.9.

A compliant client MUST NOT present an instance-specific URL as the canonical or shareable Creator identifier. This is a compliance violation equivalent in effect to operator-side migration friction — it trains Subscribers to store URLs that break on migration, converting client behavior into soft lock-in. The specific requirement: shareable links MUST use `den://[handle]` or `den://[identity-contract-address]` format.

Community links and external sites that use instance-specific URLs are outside protocol control. The compliance requirement applies to clients claiming DEN compliance.

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
- Pin all active content tiers to IPFS or equivalent content-addressed redundant storage. Pinning MUST be maintained for the duration of any active subscription period. Archived content SHOULD be pinned. Content in the subscriber protection window MUST remain pinned until all active subscriptions at notice time have lapsed.

#### 7.2 Hoster Compensation

Hosters are compensated via a per-creator escrow model. The flow is:

1. A protocol fee of `protocol_fee_pct` is collected from each subscription payment at the smart contract level and routed to a per-creator escrow — not a central treasury
2. The Hoster claims from each Creator's escrow based on the resource formula:

`hoster_claim = (storage_consumed_GB × storage_rate) + (bandwidth_served_GB × bandwidth_rate)`

3. Unclaimed escrow above the hoster's formula-based claim returns to the Creator at each settlement interval

All compensation routes peer-to-peer via smart contract. No platform intermediary holds or distributes Hoster compensation. There is no central treasury.

**Rate design intent:** Storage and bandwidth rates are governance parameters set deliberately above market infrastructure cost. The margin embedded in the rate compensates for operational overhead — maintenance time, variance, infrastructure risk — without requiring explicit labor accounting. The design target is economic viability for a technically capable community member running a small instance as a side operation, not just hardware reimbursement. An ecosystem of sustainable small operators is the distributed hosting model working correctly. Rates set at pure cost recovery produce centralization pressure because only well-capitalized operators survive operational variance, which is the precondition for institutional capture. Rates for smaller instances SHOULD be calibrated higher than for larger instances — the governance rate table SHOULD reflect that per-creator overhead is higher at small scale. The progressive calibration intent is a governance design constraint, not a fixed spec value.

**Storage compensation threshold:** A Hoster MUST NOT claim storage compensation from a Creator's escrow if that Creator has had zero verified active subscribers on that instance within the `storage_compensation_lookback` window. A Creator with no verified subscribers within this window generates no compensable storage claim regardless of content volume. This is the arithmetic consequence of the escrow model — no subscription revenue means no fee pool means no compensable claim. The threshold and the passive deletion trigger in Section 4.6 are separate mechanisms: the threshold stops hoster compensation; the dual-condition deletion trigger governs when content is actually removed.

**Migration window exclusion:** The storage compensation threshold MUST NOT apply during an active migration — from the point of sunset notice or voluntary departure initiation until the receiving instance countersigns the migration confirmation (Section 2.5.9). A Creator mid-migration may have zero local subscribers while actively migrating an existing subscriber base. Applying the threshold during this window would penalize legitimate migration.

**Hoster compensation is decoupled from Creator earnings.** A Hoster's claim is determined by resources consumed, not by how much the Creator earns. The incentive is efficient infrastructure, not selective hosting of profitable Creators.

### 7.3 Batch Settlement

Resource usage is metered continuously. Settlement to the blockchain occurs in defined intervals. The settlement interval is a governance parameter defined in Section 13. The Hoster initiates settlement transactions and bears the associated transaction fees as an operating cost. Storage and bandwidth rates set at launch SHOULD account for transaction fee overhead.

**Storage verification:** Claimed storage MUST be verifiable against content fingerprints recorded on-chain. Overclaimed storage is detectable and constitutes a protocol violation.

**Bandwidth verification:** Bandwidth cannot be verified on-chain with the same precision as storage. The first version of this protocol uses a declared-plus-auditable model: Hosters declare bandwidth consumption; the declaration is recorded on-chain and is auditable by the community. Systematic overclaiming of bandwidth is detectable through anomaly analysis — bandwidth claims that are implausible relative to subscriber count and content volume are a signal of abuse. The governance process handles substantiated overclaim findings. A more rigorous on-chain bandwidth verification mechanism is a named governance evolution item and MAY be added by amendment without requiring redesign of the storage verification model.

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
- Present instance-specific URLs as canonical or shareable Creator identifiers in client interfaces (see Section 2.5.9 and Section 6.4)

### 7.7 Instance Failure vs Deliberate Eviction

**Instance failure** — unplanned infrastructure event — is handled by the portability guarantee and content-addressed storage redundancy. It is not governed by the removal process. Creators and Subscribers affected by instance failure initiate migration under Section 8 and Section 15.

**Deliberate eviction** — operator-initiated removal — MUST follow the removal process in Section 7.5 without exception. An operator MUST NOT claim infrastructure failure to bypass the removal process.

### 7.8 Compliance Registry

The protocol maintains a governance-operated compliance registry — a public record of instance compliance status. The registry has two states:

**Recognized** — default state for any instance operating without active compliance findings. Recognition is not an endorsement of community standards or content policy. It means the instance has no substantiated protocol violation findings against it.

**Non-compliant** — applied only after a governance finding with documented reasoning following the community process defined in Section 10. The finding MUST state the specific spec requirement violated and the evidence supporting the finding.

A compliant instance MAY decline to accept Creator migrations from an instance with an active non-compliant finding. A compliant instance MAY surface non-compliant status to users when routing to such an instance. These are permissions, not requirements.

The founding maintainer MUST NOT unilaterally add or remove instances from the compliance registry. Registry changes are governance decisions, not editorial decisions.

Community instance directories — lists maintained by community members recommending instances based on content standards, reliability, or community fit — are explicitly not a protocol function. The protocol does not maintain, endorse, or control any instance recommendation list. The compliance registry records compliance; recommendation is the community's domain.

---

## Section 8 — Creator Portability

### 8.1 The Minimum Portable Data Set

The following data belongs to the Creator at all times and MUST be held by the Creator independently of any instance:

- Cryptographic wallet keys (private key or hardware wallet custody)
- Subscriber list: wallet addresses and current subscription states
- Buyer list: wallet addresses and purchase state records (item IDs and pack IDs purchased)
- Content references: fingerprints (hashes) and metadata for all uploaded content, including shop items and packs
- Access grant declarations: the creator's declared tier access grants and current pack access grant declarations
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

Tier graduation is based on verified inbound transactions from distinct external wallet addresses over a defined lookback window. Qualifying transactions include subscription payments and shop item or pack purchases. Graduation is automatic, passive, and requires no moderator approval, application process, or human decision.

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

The protocol floor consists exclusively of structural prohibitions grounded in legal liability and protocol integrity. Content policy beyond this floor is instance-level community standards. The protocol does not enumerate allowed content — everything not explicitly prohibited at the protocol floor is unrestricted at the protocol level.

### 11.2 Protocol Floor — Prohibited Content

The following prohibitions apply to all compliant instances. No instance MAY host this content:

**Sexual content depicting real, identifiable minors.** Content depicting a real, identifiable person under the age of 18 in a sexual context is prohibited. This prohibition activates the mandatory reporting requirement defined in Section 12.5. It does not extend to fictional characters — fictional content policy is instance-level community standards.

**Content depicting real, identifiable persons in a sexual or defamatory context without documented consent.** This prohibition addresses defamation and privacy liability. It does not apply to fictional characters who resemble real people incidentally.

### 11.3 Scanning Infrastructure

DEN MUST NOT build scanning infrastructure — no hash-matching database, no client-side scanning, no PhotoDNA integration. The reasons are architectural and intentional:

The E2EE architecture means the protocol has no plaintext access layer. There is no content to scan. Introducing scanning infrastructure would require breaking the encryption architecture, which is a fixed spec value not subject to governance amendment.

Scanning infrastructure, once introduced, can be mandated, expanded by legislative pressure, and updated to cover content categories beyond its original stated purpose. It never stays limited. The absence of scanning infrastructure is the architectural defense against this pattern — it cannot be mandated because it does not exist.

Legal liability for uploaded content sits with Creators. Subscribers — the only participants with plaintext access — are the detection layer. The reporting process is defined in Section 12.

### 11.4 Instance-Level Content Standards

Instance operators MAY set content standards above the protocol floor. Above-floor standards MUST be published publicly before the instance accepts Creators and MUST be applied uniformly to all Creators on the instance. Selective application is an abuse of operator position and constitutes a protocol violation.

The protocol floor is a ceiling on restriction — instances MUST NOT prohibit content on the grounds that it violates the protocol floor unless it meets the specific prohibitions stated in Section 11.2.

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

**Protocol floor violations (real person content without consent):**

1. Creator response window (duration: governance parameter, Section 13)
2. Instance operator determination after response window
3. Creator MAY appeal to the governance process
4. Deletion only after appeal is exhausted or waived
5. Sunset window subscriber protection applies during appeal

**Sexual content depicting real, identifiable minors:**

1. Immediate access suspension
2. Automatic mandatory referral to legal reporting infrastructure: [NCMEC CyberTipline](https://www.missingkids.org/gethelpnow/cybertipline) (US), [IWF](https://www.iwf.org.uk/) (UK), [INHOPE](https://inhope.org/) network (international)
3. Creator notified of suspension and referral
4. Protocol does not conduct independent adjudication — this is a legal matter handled by the appropriate authorities
5. Suspension is time-bounded — automatic reinstatement after the csam_suspension_duration governance parameter period unless law enforcement has issued a preservation order or opened an active investigation, in which case suspension continues until that process concludes. Suspension lifted and outcome recorded on-chain if claim found unsubstantiated. If no law enforcement action is taken within the suspension period, reinstatement is automatic.

The protocol deliberately does not build its own review infrastructure for this category. No internal panel, no distributed jury, no protocol-level adjudication. The legal referral infrastructure exists for this purpose. The protocol routes to it.

**Above-floor violations (instance-level content standards):**

Instance-level content standard violations are governed entirely by the instance operator. The process MUST follow Section 7.5 removal procedures. Creator appeal to governance is available only where the Creator claims the instance applied above-floor standards in violation of Section 11.4 — selectively, without publication, or below the protocol floor.

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

### 13.2 Hoster Compensation Model

The protocol fee is collected from each subscription payment, shop item purchase, and pack purchase and routed to a per-creator escrow. The Hoster claims from the escrow based on the resource formula. Surplus above the hoster's claim returns to the Creator. All flows are peer-to-peer via smart contract. There is no central treasury.

`hoster_claim = (storage_consumed_GB × storage_rate) + (bandwidth_served_GB × bandwidth_rate)`

Storage rate and bandwidth rate are governance parameters. The protocol fee percentage is a governance parameter defined in Section 13.3.

### 13.3 Protocol-Level Fee

A protocol fee of `protocol_fee_pct` is applied to each subscription payment, shop item purchase, and pack purchase. This fee is collected at the smart contract level and routed to a per-creator escrow from which the Hoster claims resource compensation. Surplus returns to the Creator (Section 7.2).

The fee percentage is a governance parameter. Initial value: 2.5%.

**Adjustment intent:** Downward adjustments are preferred when surplus consistently exceeds hoster compensation requirements — this directly benefits Creator take-home. Upward adjustments require explicit justification against the creator sustainability principle in Section 1. The fee is evaluated against Creator sustainability as the primary metric; hoster compensation sustainability as the secondary metric.

Every fee in this protocol is stated in this specification. No fee may exist that is not listed here. No fee listed here MAY be changed without governance approval. Hidden fees and unilateral fee changes are protocol violations.

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
| `wallet_rotation_delay` | Time-delay window for unilateral wallet rotation or revocation before it completes without the old wallet's signature; any registered wallet can cancel during this window | Set at launch |
| `rotation_announcement_cooldown` | Minimum period between rotation or revocation announcements from the same identity contract; limits griefing cost from a compromised registered wallet | Set at launch |
| `handle_change_allowance` | Number of handle changes permitted per `handle_change_period` before allowance refreshes | Set at launch |
| `handle_change_period` | Period over which the handle change allowance applies before refreshing | Set at launch |
| `handle_alias_retention_window` | Duration a superseded handle continues resolving as an alias before release for re-registration | Suggested: 180 days |
| `resolver_cache_ttl` | Maximum duration a client MAY cache on-chain identity record resolution results; mandatory fresh resolution always required before any transaction regardless of cache state | Set at launch |
| `protocol_fee_pct` | Protocol fee as percentage of each subscription payment, shop item purchase, and pack purchase, routed to per-creator escrow. Initial value: 2.5%. Downward adjustments preferred when surplus consistently exceeds hoster compensation requirements. | 2.5% |
| `storage_compensation_lookback` | Window within which a Creator must have at least one verified active subscriber for hoster storage compensation to be claimable from that Creator's escrow. Migration window excluded from calculation. | Set at launch |
| `progressive_rate_parameters` | Governance-calibrated rate table mapping instance size brackets to storage and bandwidth rate multipliers. Smaller instances receive higher effective rates reflecting higher per-creator overhead at small scale. Instance size is computed as `creator_count + subscription_relationship_count`, where `subscription_relationship_count` is the total number of active subscription relationships on the instance — a subscriber to multiple creators on the same instance counts once per relationship. Same-instance subscription relationships are excluded by the same logic as Section 9.3. Specific bracket thresholds and multipliers set at launch and recalibrated by governance as operational data accumulates. | Set at launch |
| `instance_size_brackets` | The numeric thresholds defining small, medium, and large instance size brackets for progressive rate calculation. Values are counts of the instance size formula output. | Set at launch |

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

**Client-layer convenience authentication.** Email recovery, password recovery, biometric authentication, and MFA are client-layer concerns with no protocol-level definition. They protect against casual unauthorized device access. They do not constitute protocol-level security guarantees. Client implementations offering these features MUST NOT transmit wallet private key material or seed phrases to any external party including the instance. Client implementations offering these features MUST be open source to permit community auditability of that guarantee. Client implementations MUST communicate clearly at onboarding what each convenience recovery path does and does not protect against — specifically that email recovery resets a local client password only and does not recover wallet access if the device is lost, and that the seed phrase remains the sole true last-resort recovery mechanism.

**Photographic content of real human beings.** This protocol is designed for illustrated and written content. Photographic content platforms have different legal and technical requirements — rights management, real identity verification, DMCA infrastructure — that this protocol is not designed to address. Communities built around photographic content should use infrastructure designed for that purpose.

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
Rejected: introduces scanning infrastructure that can be mandated and expanded; [PhotoDNA](https://www.microsoft.com/en-us/photodna)-style databases require trusting an external authority over database contents; client-side scanning is general surveillance infrastructure regardless of stated first use. Replaced by architectural impossibility as primary defense, subscriber reporting as detection layer, creator liability as enforcement anchor (Section 11.3, Section 12).

**Time-based trust tier graduation — rejected**
Rejected because time-based graduation is gameable by waiting without ecosystem participation. Replaced by income-based graduation tied to verified external transactions (Section 9.2).

**ActivityPub as protocol-level federation — rejected**
Rejected: furry community subscription platform usage does not require fediverse discoverability — DEN is a destination, not a discovery platform; ActivityPub's foundational assumptions (content readable by federated instances, identity coupled to instance address) directly conflict with DEN's foundational assumptions; custom activity types for payment-gated content would add maintenance burden with no benefit. Optional fediverse broadcast remains available to client implementations (Section 6.1).

**Pack purchase history snapshot — rejected**
Considered as a mechanism to protect buyers against pack modification: record the full pack state at purchase time either on-chain (writing all item IDs into the purchase transaction) or as instance-side historical state. Rejected on two grounds. Full on-chain snapshots scale poorly — pack purchase transaction cost grows linearly with pack size multiplied by purchase volume, producing unbounded chain cost borne by buyers. Instance-side historical state introduces an undetectable corruption failure mode: a malicious or migrating instance can silently provide corrupted historical state with no way for the buyer to verify what they were originally entitled to. Replaced by treating packs as content objects with current-state access semantics, consistent with how content deletion affects Subscribers generally. Pack modification notification is a client-layer obligation. The no-refund model and verification-before-settlement principle (Section 5.5, Section 3.7) are the buyer protections available within the trustless architecture.

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

**EVM as canonical identity chain — decided**
Base (EVM L2) is the canonical identity chain. Identity contracts are deployed on Base. All participants require an EVM wallet for identity contract operations regardless of which payment rail they transact on. TRON and Solana are payment rails; they are not identity rails. Rationale: EVM smart contract tooling is the most mature available; Base is the chosen primary L2; the identity contract proxy pattern is well-validated on EVM; stating this explicitly prevents inconsistent cross-chain identity assumptions across client and instance implementations. Genuine multi-chain identity parity — where a Solana-native participant could hold identity state on Solana with no EVM requirement — is deferred to V2. The V1 position is stated honestly rather than implied.

**Per-participant proxy identity contract — decided**
Each participant deploys a proxy smart contract on Base at first registration. The contract address is their stable DEN identifier. The proxy holds their current active wallet and registered emergency wallets. Wallet rotation updates the proxy's internal state; the address never changes; downstream references require no migration. The participant holds the upgrade key — no central protocol authority can upgrade any participant's contract. The protocol publishes reference implementation addresses; participants upgrade at will. Rationale: no global registry means no single point of failure; stable address means no downstream migration on rotation; participant-held upgrade key means no centralization vector for contract logic changes; the proxy pattern is the standard EVM solution to the immutable-contract upgrade problem without reintroducing central authority.

**Emergency wallet as participant-held mitigation — decided**
Participants MAY register emergency wallets against their identity contract. The emergency wallet is encrypted as an additional recipient on the master secret blob and holds independent authority over high-stakes identity operations. This is distinct from protocol-held recovery infrastructure (rejected — see above): the protocol stores nothing additional; the participant controls all key material; the instance stores one blob encrypted to multiple participant-held keys. The mechanism mitigates the lost-primary-wallet scenario without creating a compellable target. Registration is optional; participants who omit it accept the full loss risk of single-wallet custody. Rationale: removes the false binary between "no recovery" and "protocol-held recovery"; the participant's own second wallet is not a new attack surface on the protocol, it is an extension of the participant's own custody model.

**ZK pseudonymous rotation deliberately deferred to V2**
Zero-knowledge proof of identity continuity — allowing wallet rotation without publishing the old-to-new wallet linkage on-chain — is technically feasible but deferred. Rationale: ZK tooling ecosystem is not yet mature enough for V1 without adding significant maintenance burden; the proxy contract model is designed to be participant-upgradeable, providing the correct upgrade path when tooling matures; the V1 position (on-chain linkage visible to chain analysts) is stated honestly in Section 2.6 rather than obscured. Participants who require stronger rotation privacy SHOULD use operational security practices at the wallet level rather than relying on protocol-layer privacy guarantees not yet available.

**Protocol-level wallet recovery infrastructure — rejected** *(expanded)*
Considered as a usability accommodation. Rejected: any recovery mechanism the protocol holds creates a compellable target — an entity that can compel recovery infrastructure can impersonate any participant; custody of recovery information is functionally equivalent to custody of identity. This rejection applies specifically to protocol-held recovery infrastructure. It does not apply to participant-held emergency wallets (see above), which are a different mechanism: the participant controls all key material, the protocol holds nothing, and no new compellable target is created. Client implementations MAY provide password-based and email-based convenience layers over locally-stored encrypted wallet key material — these are not protocol-level recovery, they are the client encrypting the participant's own keys on the participant's own device (Section 2.5.8, Section 14).

## Appendix B — Open Questions Summary

A consolidated list of all open questions flagged in the sections above, for tracking before spec drafting begins.

| Section | Open Question | Spec Impact | Status |
|---------|--------------|-------------|--------|
| 2.5 | ZK pseudonymous rotation — on-chain wallet linkage on rotation is visible to chain analysts; ZK proof of identity continuity would allow rotation without publishing the link; deferred pending tooling maturity; proxy contract upgrade path is designed to accommodate this | V2 scope — deliberately deferred | Deferred |
| 2.5 | TRON/Solana identity parity — participants on non-EVM rails currently require an EVM wallet for identity operations; genuine multi-chain identity parity is a significant engineering problem | V2 scope — deliberately deferred | Deferred |
| 14 | Reference client name, scope, and development timeline | Project decision — outside protocol spec | Open |

---

*DEN — Decentralized Encrypted Network*
*Protocol Specification v0.1-draft*
*This document contains binding implementation requirements. Companion document: `den-architecture.md`.*
*Amendments require the governance process defined in Section 10.*