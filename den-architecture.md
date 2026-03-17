# DEN — Decentralized Encrypted Network
## Architecture Document v0.1

This document describes the design rationale, structural decisions, and section scope of the DEN protocol specification. It is a companion to the protocol specification itself (`DEN-SPEC.md`), which contains binding implementation requirements. Where the spec says what implementations must do, this document explains why those decisions were made, what alternatives were considered, and what pressure points each decision is designed to close.

The protocol is designed to be client-agnostic — any compliant client can connect to any compliant instance. A companion reference client (working title furDEN) is planned as a separate open-source project under AGPL. Client-layer concerns — user interfaces, terms of use, privacy policies, jurisdiction-specific compliance — are that project's responsibility, not the protocol's.

Decisions recorded here as resolved are not open for re-litigation without a governance process. Open questions are flagged explicitly and represent known gaps to be resolved before the corresponding spec sections are finalized.

---

## Foundational Design Principles

These are the non-negotiable architectural assumptions against which every other decision is measured. If a proposed feature or mechanism conflicts with any of these, the feature changes — not the principle.

**Crypto-native payments are primary.** Fiat payment infrastructure is a sandboxed guest with no structural power over the protocol. Any architecture that gives fiat processors a kill switch — a single point of control that outside actors can use to shut down or coerce the protocol — fails this principle.

**End-to-end encryption is non-optional.** Instance operators store ciphertext — the encrypted form of content, unreadable without the subscriber's key. The protocol has no plaintext access layer. There is no scanning infrastructure. Architectural impossibility is the defense against both payment processor pressure and legislative mandated backdoor demands.

**No single entity holds a kill switch.** Not the founding maintainer. Not any instance operator. Not any payment processor. Not any government acting on a single jurisdiction. The protocol survives the removal of any single participant.

**Creator portability is a protocol guarantee, not a feature.** A creator's identity, subscriber relationships, and content references are theirs independently of any instance. No participant in the ecosystem can hold these hostage.

**Vagueness is an attack surface.** Every policy position has a clear answer with documented reasoning. Ambiguity hands leverage to bad actors.

**The protocol serves human creative labor.** Economic and architectural decisions are evaluated against whether they sustain the creators the protocol exists for.

---

## Section 0 — Definitions

**Purpose:** Establish shared vocabulary used throughout the spec. Every subsequent section references these terms without re-definition.

**Scope:**
- The three denizen types formally defined
- Key protocol terms defined precisely
- Relationship model between denizen types stated

**The Three Denizens:**

*Hoster* — provides infrastructure. Runs an instance of the protocol: storage, compute, bandwidth. Compensated by the protocol via resource-based smart contract transaction settlement for storage consumed and bandwidth served. Stores only ciphertext and is architecturally incapable of reading hosted content. Sets above-floor community standards for their instance. Cannot hold creator identity, subscriber relationships, or content references hostage. Is a peer participant in the ecosystem, not a platform owner or gatekeeper.

*Creator* — produces content. Holds their own keys, identity, and subscriber relationships independently of any instance. Earns directly via smart contract with no platform intermediary. Subject to trust tier graduation based on verified transaction history recorded on the blockchain. Carries legal liability for uploaded content. Portable across instances by protocol guarantee.

*Subscriber* — funds the ecosystem. Pays creators directly via smart contract. Subscription state governs decryption key access automatically. The only denizen type with plaintext access to content, making them the primary detection layer for protocol floor violations. Pseudonymous by default at the protocol level.

**Relationship model:** Hosters serve creators and subscribers by providing infrastructure. Creators serve subscribers by producing content. Subscribers sustain creators by paying directly. The protocol governs relationships between all three without sitting in the middle of any transaction. No denizen type holds structural power over another's core participation.

**Open questions:** None. This section is fully resolved.

---

## Section 1 — Purpose and Design Principles

**Purpose:** State the non-negotiable architectural assumptions as the binding foundation of the spec. Everything else in the spec is measured against this section.

**Scope:**
- Formal statement of each foundational principle with implementation implications
- Named pressure points the architecture is designed to close: payment processor capture pattern, legislative backdoor mandate pattern ([EARN IT Act](https://www.eff.org/deeplinks/2020/03/earn-it-act-violates-constitutionl), [Online Safety Act](https://www.eff.org/pages/uk-online-safety-bill-massive-threat-online-privacy-security-and-speech), [Chat Control](https://www.patrick-breyer.de/en/posts/chat-control/))
- Architectural impossibility as the defense against both
- What it means structurally that no single entity holds a kill switch

**Design rationale:** This section exists because protocol rules that are not grounded in explicit principles can be eroded one exception at a time. Named principles with documented reasoning make erosion visible and require explicit justification rather than quiet drift.

**Open questions:** None. This section is fully resolved.

---

## Section 2 — Identity Layer

**Purpose:** Define how participants are identified within the protocol and what identity information the protocol holds.

**Scope:**
- Pseudonymous by default — no real name required at protocol level
- Wallet address as primary identity anchor
- Wallet address is pseudonymous, not anonymous. On-chain transaction history is publicly visible and outside the protocol's control.
- Authentication standard: [EIP-4361 (Sign-In with Ethereum)](https://eips.ethereum.org/EIPS/eip-4361) for Ethereum Virtual Machine (EVM) compatible chains, [Wallet Adapter](https://github.com/anza-xyz/wallet-adapter) for Solana, TronWeb for TRON
- KYC (identity verification required by financial regulations) only at fiat payout edge, held by the fiat processor, never by the protocol
- Protocol never holds real identity information
- Creator identity portability — minimum portable data set formally defined: keys, subscriber list, content references, pseudonymous identity
- Multi-role wallet handling — same wallet address can hold multiple denizen roles simultaneously; roles are governed by identical protocol rules regardless of who holds them
- Hoster identity — instance operator wallet address as instance identity anchor
- Subscription state (wallet address, tier, active period) is publicly visible on-chain as a necessary consequence of smart contract-based access control. This is not obscured.

**Design rationale — pseudonymous by default:** Real identity requirements at the protocol level create a single point of pressure. A protocol that knows who its creators are can be compelled to reveal them. A protocol that architecturally does not hold that information cannot be compelled to reveal what it does not have.

**Design rationale — EIP-4361 and equivalent standards:** Specifying connection standards rather than wallet applications keeps the spec stable as the wallet application landscape changes. Any compliant wallet works. Instance operators cannot restrict wallet compatibility because doing so becomes a mechanism for locking creators into a specific instance.

**Design rationale — multi-role handling:** A creator who also hosts their own instance is a legitimate and likely common use case. The protocol does not penalize it. The trust tier definition (Section 9) explicitly handles the self-transaction exploit this introduces.

**Open questions:** None. This section is fully resolved.

---

## Section 3 — Payment Layer

**Purpose:** Define how value moves through the protocol, what rails are supported, and what structural power fiat processors do and do not hold.

**Scope:**
- Self-custodial wallets — wallets where only the creator holds the keys, meaning no platform can freeze or seize the funds — as the primary payment method and first-class design priority
- Supported chains: Ethereum Layer 2 networks (L2s) — Base, Arbitrum, Optimism — as primary smart contract rails; TRON's token standard (TRC-20) and Solana as parallel rails
- Chain support is a governance parameter — adding or removing chains requires community approval, not instance operator decision
- Token neutrality — the protocol does not privilege any token type over another; creators choose what token they price in and accept; subscribers pay in whatever supported token they hold; the protocol's job is to support the transaction, not to recommend a financial instrument
- Supported token categories and their tradeoffs, documented honestly in the spec:
  - Native cryptocurrencies (ETH, SOL, TRX): fully decentralized, no third party can freeze them, exchange rate varies — creator bears price volatility risk
  - Stablecoins (USDC, DAI, USDT): price-stable against USD, useful for predictable subscription pricing, but carry varying degrees of centralization risk — USDC can be frozen by Circle at government request, USDT carries Tether counterparty risk, DAI is more decentralized but still USD-pegged
  - Privacy-preserving tokens (Monero and equivalents): maximum decentralization and transaction privacy, most aligned with the protocol's values, but exchange access is restricted in multiple jurisdictions — flagged as a known tension, not resolved at this stage
- Exchange rate display: [Chainlink](https://docs.chain.link/) price feeds (or equivalent decentralized price oracle — an on-chain service that provides reliable real-world pricing data) for display only; transaction settlement occurs in the token agreed at subscription time, no protocol-level conversion
- Smart contract subscription mechanics — payment triggers subscription state, subscription state governs content access
- Payment verification before transaction settlement — technical failure surfaces before money moves
- Fiat sandboxing — what structural power fiat processors explicitly do and do not hold; what happens to active subscriptions if a fiat processor exits
- No platform intermediary holds funds at any point

**Design rationale — token neutrality over stablecoin preference:** Calling any token category "first-class" creates a hierarchy that is inconsistent with the protocol's values and introduces structural risk. Stablecoins in particular are not fully decentralized — USDC can be frozen by Circle at government request, which is a kill switch by a different name held by a different entity than Visa. The protocol naming stablecoins as preferred would contradict the foundational principle that no single entity holds a kill switch. Token neutrality preserves creator choice and does not embed the protocol's infrastructure in any specific token's centralization risk profile. Creators who want price predictability can choose stablecoins. Creators who want maximum decentralization can use native tokens. The protocol is neutral.

**Design rationale — privacy token tension acknowledged:** Monero and similar privacy-preserving tokens are the most philosophically aligned with DEN's values — they offer exactly the kind of transaction privacy the protocol is built around. Their restricted exchange access in multiple jurisdictions is a real constraint that the protocol cannot resolve by spec declaration. The tension is documented here so it is not forgotten and can be revisited by governance as the regulatory landscape changes.

**Design rationale — chain support as governance parameter:** The blockchain infrastructure landscape changes. Hardcoding chain support in the spec creates a document that requires revision for infrastructure reasons rather than policy reasons. Community approval for chain changes keeps the decision transparent and community-controlled without requiring a full spec amendment process.

**Design rationale — fiat as sandboxed guest:** Fiat processor capability to operate as a guest within the ecosystem does not translate to structural power over the protocol. The spec defines precisely what sandboxed means: fiat processors can offer onramp and offramp services at the edges of the ecosystem; they cannot influence content policy, creator account decisions, or protocol governance; their exit does not affect the primary payment rails.

**Precise smart contract subscription logic:** direct on-chain transfer triggering subscription state; auto-renewal via pre-approved allowance is client-layer opt-in; manual renewal always available.

**Open questions:** None. This section is fully resolved.

---

## Section 4 — Content and Storage Layer

**Purpose:** Define what gets encrypted, how content is stored, what instance operators can and cannot access, and how content lifecycle is managed.

**Scope:**
- Encryption architecture — what is encrypted, at what point, by whom, with what keys
- On-instance storage vs [IPFS](https://ipfs.tech/) content addressing — IPFS stores content by what it is rather than where it is, meaning the same file exists on any node that holds it rather than at a single location; this is the redundancy model
- What instance operators store (ciphertext) vs what they can read (nothing) — architectural impossibility formally stated
- Storage allocation governed by creator trust tier (Section 9)
- Post and file size limits — governed by creator trust tier, defined as governance parameters
- Content lifecycle — active, sunset notice issued, subscriber protection window, deleted
- Passive data deletion — inactivity grace period defined as governance parameter; creator notification window; subscriber access protection during active subscription period
- Instance failure vs deliberate eviction — spec distinguishes these cases explicitly

**Design rationale — architectural impossibility:** The strongest legal and political position available to this protocol is not "we promise not to abuse our access." It is "we have no access." This forecloses the legislative backdoor mandate argument — you cannot mandate a backdoor into a system that has no backdoor — and forecloses the "why don't you scan for it" argument for the same reason. This is not a privacy preference. It is a structural design decision with legal and political implications that are intentional.

**Design rationale — passive data deletion:** The protocol is not a data warehouse. Content persistence is tied to continued economic activity — a creator with active subscribers has active storage. A creator who has gone quiet will see subscriber counts fall, revenue stop, and storage allocation wind down passively. This is self-regulating and avoids the "free storage is a cost of business" assumption that creates infrastructure sustainability problems. It also means the protocol does not accumulate liability for abandoned content indefinitely.

**Design rationale — instance failure distinction:** Deliberate operator-initiated removal is a governed process with defined timelines (see Section 7). Instance failure is an infrastructure event handled by the portability guarantee and IPFS redundancy. The spec must distinguish these so the governed process cannot be bypassed by claiming infrastructure failure.

**Precise encryption key derivation model:** on-demand derivation from master secret; master secret stored on instance encrypted to creator wallet public key; no stored content keys; no key bundles; no rotation schedule.

**Open questions:** Flagged for future: Parallel non-superset tiers are a common creator use case. The v0.1 hierarchical constraint covers the standard subscription model but excludes creators who want distinct content tracks at the same tier level. This is a governance extension candidate, not a protocol floor concern.

---

## Section 5 — Access Control Layer

**Purpose:** Define exactly how subscription state maps to content access, how access is granted and revoked, and what happens at edge cases.

**Scope:**
- Subscription state to decryption key access mapping via smart contract
- Key derivation model
- Access validation at request time — subscription window recorded on the blockchain at payment time, validated at access time
- Access timing precision — defined behavior at subscription expiry; grace period defined as governance parameter
- Access revocation on lapse — automatic, governed by contract state, no manual process
- In-progress access behavior on subscription lapse
- Technical failure edge case — verification step before payment finalizes; if key delivery fails, payment does not complete
- Subscriber protection window during sunset process — read-only access for active subscribers at notice time until their paid period lapses; no new subscriptions accepted during wind-down

**Design rationale — math decides:** No platform intermediary, no human discretionary decision, no support ticket required to access content you have paid for or to lose access to content you have stopped paying for. The contract state is the authority. This removes both the "platform decides who can see what" pressure point and the "platform can cut off a creator's subscribers" pressure point simultaneously.

**Design rationale — verification before settlement:** A subscriber should not pay for content they cannot access due to a technical failure. The verification step before payment finalization means the failure surfaces before money moves, not after. This is a creator protection as much as a subscriber protection — disputed payments due to technical failures are a burden on creators.

**Open questions:** None. This section is fully resolved architecturally. Technical implementation details to be resolved during spec drafting.

---

## Section 6 — Public Discovery Layer

**Purpose:** Define what the protocol exposes publicly — without a subscription, without an account, without any third-party social protocol — so that a link to a creator's DEN profile is sufficient for anyone to understand what they're subscribing to and how.

**How the furry community actually uses subscription platforms:** Discovery of creators happens on the platforms creators already post on — Furaffinity, Bluesky, Twitter/X, Telegram, Discord, e621 tags. A creator posts their work publicly somewhere, includes a DEN link in their post or bio, and an interested person follows that link. Patreon and SubscribeStar are destinations after discovery, not discovery platforms themselves. DEN does not need to solve discovery. It needs the link that gets followed to work well.

**Scope:**
- Public creator profile — accessible without a subscription, without an account, without any wallet connection; displays creator name, description, subscription tiers and pricing, and any content the creator has designated as publicly visible
- Designated public preview posts — creators can mark specific posts as publicly visible without a subscription; this gives a non-subscriber enough context to decide whether to subscribe; these are the creator's choice, not a protocol requirement
- Stable creator URL — because identity is wallet-based and instance-independent, a creator's public profile URL is stable regardless of which instance they are currently on; the link a creator posts on Furaffinity today works the same way after they migrate instances
- What requires no account to see: creator profile, subscription tiers, public preview posts, content warnings on paywalled posts
- What requires a subscription: all paywalled content, decryption access
- No login wall before the subscription decision point — a non-subscriber should be able to evaluate a creator fully before being asked to connect a wallet or create any kind of account

**Design rationale — DEN is a destination, not a discovery platform:** The community this protocol serves has never used Patreon or SubscribeStar to find new creators. Discovery happens on public social platforms the community already uses. Adding a social graph layer, a federated protocol integration, or any discoverability feature to DEN would add architectural complexity and ongoing maintenance burden while solving a problem that does not exist for the target use case. The protocol's job is to be the best possible destination after discovery has already happened elsewhere.

**Design rationale — stable URL as the core requirement:** The one thing that breaks the current workflow with existing platforms is that a creator's presence is tied to the platform. If Patreon bans a creator, the link stops working and the audience has to find them again. DEN's wallet-based identity makes the creator's public profile URL platform-independent. This is the meaningful improvement over the current state, and it costs nothing to implement — it falls out of the identity architecture already defined in Section 2.

**Design rationale — ActivityPub rejected for protocol-level integration:** ActivityPub was considered as a federation layer for discoverability. Rejected because: the actual usage pattern of subscription platforms does not require fediverse discoverability; ActivityPub's core assumptions — content readable by federated instances, identity coupled to instance address — directly conflict with DEN's architecture; integrating ActivityPub would require defining custom activity types for payment-gated content that no ActivityPub client natively understands, producing a shim that adds complexity without adding value. If a client or instance operator wants to broadcast post notifications to the fediverse as an optional feature, that is a client implementation decision outside the scope of this protocol. See Appendix A.

**Open questions:** None. This section is fully resolved.

---

## Section 7 — Instance and Hosting Layer

**Purpose:** Define what it means to run an instance, how hosters are compensated, what obligations they carry, and what power they do and do not hold.

**Scope:**
- Resource-based fee model — hosters compensated for storage consumed and bandwidth served, not for a percentage of creator revenue
- Periodic batch settlement — usage metered continuously, transaction settlement to the blockchain in defined intervals; settlement period defined as governance parameter
- Content unique fingerprint (hash) verification as overclaim deterrent — protocol can verify claimed storage against fingerprints recorded on the blockchain
- Instance operator minimum obligations — what running a compliant instance requires
- Above-floor content standard publishing requirement — operators must state their standards publicly and apply them uniformly to all creators on the instance
- Store the encrypted master secret blob for each hosted Creator
- The uniformity requirement — above-floor standards cannot be applied selectively; selective application is an abuse of operator position
- The defined removal process:
  - Active → sunset notice issued (creator and subscriber notification, migration tools activate automatically, window duration is governance parameter, suggested range 30-90 days)
  - Sunset window → subscriber protection window (read-only access for subscribers active at notice time, no new subscriptions)
  - Subscriber protection window → deleted (after all subscriptions active at notice time have lapsed)
  - Sunset notice is immutable once issued — cannot be retracted as ongoing leverage
- Instance failure vs deliberate eviction — distinguished explicitly; failure is handled by portability guarantee, not governed removal process
- What an instance cannot do: cannot hold creator identity, subscriber list, content references, or decryption keys; cannot issue immediate deletion outside the defined process; cannot selectively apply standards; cannot retract a sunset notice

**Design rationale — resource-based fee model:** A revenue-share hoster compensation model creates direct incentive to host only profitable creators and reject new or small creators. Decoupling hoster compensation from creator earnings removes this incentive structurally. Hosters earn the same per gigabyte regardless of whether the creator earns five dollars or five thousand. The incentive becomes efficient infrastructure, not extractive creator selection.

**Design rationale — immutable sunset notice:** A revocable sunset notice can be used as ongoing coercive leverage — "comply or I complete the deletion." Making the notice immutable once issued converts it from a threat into an administrative process. The operator retains the ability to remove content through a defined process. They do not retain the ability to use the threat of removal as indefinite control.

**Design rationale — uniformity requirement:** An operator who applies above-floor standards selectively — enforcing them against creators they dislike while ignoring violations by creators they favor — is using the moderation layer as a tool for control rather than community management. Uniform application is auditable; selective application is not. The requirement makes abuse visible.

**Open questions:** Precise batch settlement mechanics and transaction fee optimization. Technical implementation decision.

---

## Section 8 — Creator Portability

**Purpose:** Define precisely what a creator owns independently of any instance and what the protocol requires to make that ownership real.

**Scope:**
- Minimum portable data set: cryptographic keys, subscriber list (wallet addresses and subscription states), content references (unique fingerprints and metadata), pseudonymous identity
- What a creator holds independently of any instance at all times — not something they request on departure, something they always have
- Migration process at protocol level — what receiving instances are required to accept; what departing instances are required to release
- Automatic migration tool activation on sunset notice issued
- Instance failure as migration event — IPFS content addressing means content persists if stored elsewhere; access control layer survives on the blockchain; instance-specific metadata migrates via portability guarantee
- The slow-capture pattern at instance level — an operator who attracts creators with favorable terms and gradually tightens standards is replicating the Fansly pattern at instance scale; portability guarantee is the architectural defense because the audience cannot be made captive regardless of how the operator changes their standards

**Design rationale — portability as always-held, not requested:** If portability requires the creator to request their data from an operator who has decided to remove them, the request can be delayed, complicated, or denied in practice even if required in spec. A creator who always holds their own keys, subscriber list, and content references cannot be denied portability because there is nothing to request — they already have it.

**Open questions:** None. This section is fully resolved.

---

## Section 9 — Creator Trust Tiers

**Purpose:** Define how storage allocation and rate limits are governed in a way that is self-regulating, does not penalize new creators, and cannot be gamed by multi-role denizens.

**Scope:**
- What tiers govern: storage allocation per post, post rate limits, file size limits
- Tier graduation basis: verified inbound transactions from distinct external wallet addresses over a defined lookback window
- Self-transaction exclusion: transactions from the creator's own wallet addresses, or from wallets on the same instance they operate, do not count toward tier graduation — closes the self-hosting exploit where a creator-hoster could artificially inflate their own transaction history
- New creator baseline: defined as governance parameter; must be sufficient for normal creative output without being punitive; not zero
- Tier thresholds: defined as governance parameters, not fixed spec values — adjustable by community vote as ecosystem matures without requiring spec revision
- Graduation is automatic and passive — no moderator approval, no application process, no human discretionary decision

**Design rationale — income-based rather than time-based:** Time-based tier graduation can be gamed by simply waiting. Income-based graduation tied to verified external transactions reflects actual participation in the ecosystem. A creator with real subscribers has demonstrated that the ecosystem is being used for its intended purpose.

**Design rationale — governance parameters for thresholds:** The right tier thresholds at protocol launch are not the right tier thresholds two years in. Encoding them as fixed spec values would require spec amendments for what are essentially operational adjustments. Governance parameters allow adjustment through the community approval process without triggering a full spec revision.

**Design rationale — self-transaction exclusion:** A creator who also operates an instance could route payments through their own infrastructure in ways that inflate apparent transaction volume. Explicitly excluding same-wallet and same-instance transactions from tier graduation calculation closes this without penalizing creator-hosters for legitimate self-hosting.

**Open questions:** Precise lookback window duration and tier threshold values — to be set as governance parameters at protocol launch. The spec will define the parameter names and adjustment process; the initial values are a governance launch decision.

---

## Section 10 — Governance Layer

**Purpose:** Define how the protocol spec itself changes, who has what voice, and what structural protections exist against capture of the governance process.

**Scope:**
- Proposal and community approval process — how changes to the spec are proposed, reviewed, and adopted
- Governance parameter vs fixed spec value distinction — which values can be adjusted through governance without full spec revision; governance parameters are explicitly listed in Section 13
- Founding maintainer role formally defined: first among equals; voice and direction-setting authority earned by building the protocol and being accountable to the community; not a veto; removable; explicitly stated
- No entity including the founding maintainer holds unilateral decision power
- Fork interaction with governance — a fork is always available; forking is not a governance failure, it is the designed response when consensus cannot be reached
- Founding maintainer sustainability: community-funded stewardship via transparent voluntary contribution ([OpenCollective](https://opencollective.com/) or equivalent); no equity; no revenue share; no investor with growth expectations
- Chain support approval process — adding or removing supported chains goes through governance, not instance operator decision

**Design rationale — fixed principles vs governance parameters:** Some things should never be changeable by a simple governance vote — the protocol floor, the encryption architecture, the portability guarantee. These are fixed spec values. Other things are operational — tier thresholds, settlement intervals, storage limits — and should be adjustable without the friction of a full spec amendment. The distinction between fixed values and governance parameters is itself a fixed spec value: only the full governance process can reclassify something from governance parameter to fixed value or vice versa.

**Design rationale — fork as designed response:** A governance process that produces no dissenters is not a healthy governance process; it is a captured one. The fork option is not a threat or a failure mode. It is the mechanism by which the community retains ultimate sovereignty over the protocol. The founding maintainer being removable and the fork option being always available are both stated publicly and by design, not as disclaimers but as features.

**Precise approval mechanics:** Two-phase model; Bootstrap thresholds are 3 non-founding maintainers + 5 independent instances + 12 months elapsed; Bootstrapping circularity acknowledged plainly.

**Open questions:** None. This section is fully resolved.

---

## Section 11 — Content Policy Layer

**Purpose:** State the protocol floor exhaustively with explicit reasoning for each position, define instance-level authority above the floor, and establish why exhaustive specificity is the defense against organized pressure campaigns.

**Scope:**
- Protocol floor stated exhaustively — every category with a clear answer and documented reasoning
- Vagueness as attack surface — every ambiguous category is leverage for organizations like Collective Shout; exhaustive clarity removes that leverage
- CSAM prohibition: absolute, no jurisdiction carveout, no exceptions; architectural impossibility framing — the protocol cannot scan, liability flows to creators, enforcement is through accountability not surveillance; legislative pressure defense — [EARN IT Act](https://www.eff.org/deeplinks/2022/02/earn-it-act-back-and-its-still-unconstitutional), [Chat Control](https://www.patrick-breyer.de/en/posts/chat-control/), [Online Safety Act](https://www.eff.org/pages/uk-online-safety-bill-massive-threat-online-privacy-security-and-speech) named explicitly
- Photographic content: out of scope — different legal and technical problem, not a moral judgment on photographic content communities
- AI-primary content: prohibited — human creative labor must be the primary authorship; tools that assist human creativity are not the same as tools that replace it; instance moderators enforce; no technical detection requirement in the spec (unreliable and gameable)
- Real person content without consent: prohibited — defamation and privacy surface
- Feral content: allowed — fictional animals are not real animals
- Vore, gore, taboo kink: allowed — fiction is not endorsement; content warnings required
- Illustrated and written adult content between adult characters: allowed
- Instance-level authority: instances may add standards above the floor; they may not go below it; above-floor standards must be published and applied uniformly

**Design rationale — AI content enforcement acknowledgment:** The spec acknowledges honestly that AI content is the hardest violation category to enforce because "primarily AI-generated" requires creative judgment rather than a binary determination. No reliable technical test exists. Enforcement relies on instance operator judgment and community norms, with the protocol providing the appeal framework. This is a known limitation stated explicitly rather than papered over with a technical requirement that cannot be reliably implemented.

**Open questions:** None. This section is fully resolved.

---

## Section 12 — Moderation and Reporting Layer

**Purpose:** Define how protocol floor violations are detected, reported, reviewed, and acted upon in a way that prevents both violations and abuse of the removal process.

**Scope:**
- Subscriber reporting as the primary detection layer — the only participants with plaintext access
- Minimum evidentiary requirements per violation category — a report without evidence is not actionable; a unique content fingerprint (hash), timestamp, and specific violation claim are required
- Suspend before delete — immediate deletion is not available through the moderation process; suspension of access is the first step
- Creator notification — full report contents delivered to creator immediately on suspension; pseudonymous reporter identifier included
- Creator response window — defined as governance parameter; creator can contest the claim within this window
- Tiered determination by violation category:
  - AI content and real-person content: creator response window → instance operator determination → creator appeal to governance process → deletion only after appeal exhausted or waived; sunset window protection applies during appeal
  - CCSAM: immediate access suspension + mandatory referral to NCMEC CyberTipline (US), IWF (UK), and the INHOPE network (international); creator notified of suspension and referral immediately; the protocol conducts no independent adjudication; suspension is time-bounded — automatic reinstatement after a governance-parameter period (suggested 30 days) unless law enforcement has issued a preservation order or opened an active investigation, in which case suspension continues until that process concludes; deletion only after legal process finds claim substantiated; suspension lifted and outcome recorded on-chain if claim found unsubstantiated
- False report consequences: reporter wallet flagged on instance; repeated false reports result in loss of subscriber status; false report recorded on the blockchain permanently (pseudonymously) alongside the outcome — unsubstantiated claims are marked as such in the same record; exoneration is part of the permanent record, not just the allegation
- Operator-subscriber conflict of interest: reports filed by wallet addresses with a demonstrable operator relationship to the instance hosting the reported content are treated as operator assertions regardless of subscriber status; these reports are automatically elevated to governance review and MUST NOT be adjudicated by the instance operator — the reporter and adjudicator cannot be the same entity
- Creator appeal: any protocol floor violation determination resulting in content removal is appealable to the governance process; governance can overturn determination, reinstate content, and find abuse of process
- Instance operator accountability: documented pattern of false violation claims reviewed by governance process; finding of abuse affects instance's standing as protocol participant; other instances may decline to accept Creator migrations from a flagged instance and may exclude it from their instance directory listings
- Distributed jury concept: explicitly not adopted — dropped in favor of tiered determination and governance appeal; reasoning: legal exposure for jurors on CSAM-adjacent content, gameable selection, inconsistent verdicts contradict the principle that vagueness is an attack surface

**Design rationale — operator cannot self-assert a violation:** The E2EE architecture means instance operators store ciphertext and cannot see content. An operator's assertion that content violates the protocol floor is architecturally meaningless because they cannot verify it independently. Abuse of the removal process requires a subscriber willing to provide false evidence — coordinated false reporting is still possible but significantly harder than unilateral operator action, and carries on-blockchain consequences.

**Design rationale — suspend before delete:** Immediate deletion as an available action converts content removal into a coercive tool. Suspension as the mandatory first step means the process has a visible state, the creator has a response window, and deletion requires process completion. The operator retains the ability to remove genuinely violating content. They do not retain the ability to use deletion as a weapon that bypasses the sunset process.

**Design rationale — why the jury was dropped:** The jury concept was proposed to distribute moderation power and prevent single-actor decisions. The goals were correct. The mechanism introduced three unresolved problems: legal exposure for jurors viewing CSAM-adjacent content in order to make a determination; gameable selection through trust tier manipulation by patient bad actors; inconsistent verdicts on edge cases, which hands ambiguity back as an attack surface. The tiered determination process plus governance appeal achieves the same distribution of power without these problems. The governance process handles genuine edge cases by treating them as evidence that the spec needs clarification — the resolution is a spec amendment that sets precedent, not a one-off jury verdict.

**Design rationale — routing is not knowledge:** The instance routes reports filed by Subscribers who had plaintext access to the reported content. The instance never processed plaintext content at any point in this flow. Routing a report filed by a third party does not constitute knowledge of the content that report describes. This distinction is the structural answer to legislative arguments that a referral mechanism implies sufficient content knowledge to support a scanning mandate. TCP/IP routes packets containing illegal content without knowledge of those packets. This protocol routes reports filed by Subscribers without knowledge of the content those reports describe. The routing obligation exists; the knowledge does not.

**Open questions:** None. CSAM escalation resolved: mandatory referral to NCMEC/IWF/INHOPE, no internal adjudication, time-bounded suspension with law enforcement action as the threshold for extension. Suspension duration is a governance parameter. See Appendix A for rejection reasoning on internal adjudication alternatives.

---

## Section 13 — Fee Transparency Layer

**Purpose:** State every fee in the protocol explicitly and define which values are fixed and which are governance parameters.

**Scope:**
- Every protocol-level fee stated explicitly in the spec — no hidden fees, no fees changeable without governance approval
- Resource-based hoster compensation formula: storage (per GB) + bandwidth (per GB transferred) = hoster fee; settled via smart contract transaction in periodic batches
- No central treasury — all fees route peer-to-peer via smart contract
- Protocol-level fee if any: encoded in spec, publicly visible, changeable only by governance vote
- Fee change process: governance approval only; not configurable by any individual or instance operator
- Governance parameters list — complete list of all values adjustable without full spec revision:
  - Creator tier thresholds and lookback window
  - New creator baseline storage and rate limits
  - Sunset notice window duration
  - Subscriber protection window duration (minimum, tied to subscription period)
  - Inactivity grace period before passive data deletion
  - Batch settlement interval
  - Subscription expiry grace period
  - Creator response window for moderation reports

**Design rationale — governance parameters list in fee transparency section:** Collecting all governance parameters in one place makes the boundary between fixed spec values and adjustable parameters auditable. Anyone can see exactly what the community can change through normal governance and what requires a full spec amendment. This closes the quiet drift problem — changes to governance parameters are visible and require approval.

**Open questions:** Initial values for all governance parameters — to be set as launch decisions through the initial governance approval process.

---

## Section 14 — Protocol Scope and the Reference Client

**Purpose:** Define clearly what is and is not the protocol's responsibility with respect to legal compliance, user-facing terms, and platform-level concerns — and establish the planned reference client as the layer where those concerns are addressed.

**The protocol's legal posture is already stated in the foundational principles:** architectural impossibility means the protocol stores ciphertext it cannot read; creator liability means legal accountability for uploaded content sits with creators; no plaintext access means there is nothing to subpoena at the protocol level. These are architectural facts, not legal claims. They are stated once in the foundational principles and do not need a separate legal architecture section in the protocol spec.

**What is explicitly out of scope for the protocol:**
- Terms of service or EULA — the protocol is not a platform and has no users to present terms to; a protocol cannot present terms any more than TCP/IP presents terms
- Privacy policies — the protocol holds no personal data; individual clients and instance operators hold whatever data their implementation collects, and they are responsible for their own privacy posture under their local law
- Jurisdictional legal compliance — instance operators run under their local law; the protocol cannot and does not override local jurisdiction; operators are responsible for their own legal analysis
- Platform-level content moderation interfaces — these are client concerns
- User account management — these are client concerns

**What belongs to the reference client layer:**
Everything a user actually sees and interacts with — the interface for subscribing, the content browsing experience, the wallet connection flow, the terms a user encounters, the privacy disclosure about what the client collects — belongs to the client, not the protocol. The protocol defines what data exists and how it moves. The client defines how humans interact with it.

**The reference client:** A companion open-source reference client — working title furDEN, final name to be decided — is planned as the standard interface for creators and subscribers accessing DEN. It will be released under [AGPL](https://www.gnu.org/licenses/agpl-3.0.en.html), the same license as the protocol, meaning anyone who forks it and runs it as a hosted service must open source their changes. The reference client is a separate project from the protocol spec. Its legal disclosures, privacy policy, and terms of use are its own responsibility and are not specified here. The protocol is designed to be client-agnostic — any compliant client can connect to any compliant instance.

**Design rationale — keeping legal concerns at the client layer:** A protocol spec that attempts to specify legal compliance becomes either wrong (because law varies by jurisdiction and changes over time) or so hedged as to be useless. The correct approach is to specify the architectural facts that determine legal posture — ciphertext storage, no plaintext access, creator liability — and leave jurisdiction-specific compliance to the operators and clients who are actually subject to specific legal systems.

**Open questions:** Reference client name, scope, and development timeline — these are project decisions outside the protocol spec.

---

## Section 15 — Onboarding and Migration

**Purpose:** Define what the protocol supports to make the path from existing platforms to DEN navigable for creators and subscribers.

**Scope:**
- New creator onboarding: baseline trust tier sufficient for normal creative output; graduation path passive and automatic; no penalty for lack of transaction history
- Creator migration from existing platforms: what migration tooling the protocol supports at spec level; subscriber notification of creator departure with forwarding to new instance; content reference migration
- Subscriber onboarding: fiat-to-crypto onramp considerations; protocol does not mandate specific onramp services but should not make the path unnecessarily opaque
- Voluntary creator departure process: creator sets their own migration timeline; subscriber notification required for active subscribers; no mandatory sunset window (sunset window is a protection against involuntary removal, not a constraint on voluntary migration)

**Design rationale — voluntary vs involuntary departure distinction:** The defined sunset process in Section 7 exists to protect creators against operators. It does not need to apply when the creator is leaving voluntarily on their own timeline. Conflating the two would create unnecessary friction for creators who want to migrate quickly. The obligation that remains in voluntary departure is subscriber notification — active subscribers have a right to know where their creator is going.

**Open questions:** Specific migration tooling design — what the protocol supports at spec level vs what is left to client implementation. To be resolved during spec drafting.

---

## Appendix A — Resolved Design Decisions

A record of decisions that were considered, alternatives that were evaluated, and why the adopted approach was chosen over alternatives. Maintained here so future governance discussions have context for what was already considered.

**Distributed jury for moderation — rejected**
Considered as a mechanism for distributed content violation determination. Rejected due to: legal exposure for jurors on CSAM-adjacent content; gameable selection through trust tier manipulation; inconsistent verdicts contradicting the vagueness-as-attack-surface principle. Replaced by tiered determination process and governance appeal.

**Revenue-share hoster compensation — rejected**
Considered as the hoster fee model. Rejected because it directly creates incentive to host only profitable creators and reject new or small creators. Replaced by resource-based compensation (storage + bandwidth) which decouples hoster income from creator earnings and removes the selective hosting incentive.

**Hash-matching and client-side scanning for CSAM — rejected**
Considered as a technical enforcement mechanism for the CSAM prohibition. Rejected because: introduces scanning infrastructure that can be mandated, expanded, or corrupted; [PhotoDNA](https://www.microsoft.com/en-us/photodna)-style databases require trusting an external authority to define the database, which creates the same outside leverage point the protocol is designed to eliminate; client-side scanning is general surveillance infrastructure regardless of its stated first use case; once the infrastructure exists it can be updated to cover other content categories. Replaced by architectural impossibility as the primary defense, subscriber reporting as the detection layer, creator liability as the enforcement anchor.

**Time-based trust tier graduation — rejected**
Considered as an alternative to income-based graduation. Rejected because time-based graduation can be gamed by simply waiting without participating in the ecosystem. Income-based graduation tied to verified external transactions reflects actual ecosystem participation.

**ActivityPub as protocol-level federation — rejected**
Considered as a discoverability and social graph layer. Rejected for three reasons: the actual usage pattern of subscription platforms in the furry community does not require fediverse discoverability — creators post on public platforms and link to their subscription page, DEN is a destination not a discovery platform; ActivityPub's foundational assumptions (content readable by federated instances, identity coupled to instance address) directly conflict with DEN's foundational assumptions (encrypted content, wallet-based instance-independent identity); integrating ActivityPub would require custom activity types for payment-gated content that no existing ActivityPub client understands, producing a maintenance burden with no commensurate benefit. Optional fediverse broadcast features remain available to client implementations and instance operators who want them — this is not a protocol concern.

**Per-content key bundle delivery — rejected**
Considered as the model for delivering decryption access to subscribers: each piece of content encrypted with a unique key, keys bundled and delivered to subscribers encrypted to their wallet public key, bundles stored on instance and updated at subscription renewal.
Rejected for three compounding reasons.
First, unbounded bundle growth. A creator active for five years with five subscription tiers and monthly key rotation accumulates 5 × 12 × 5 = 300 keys per subscriber at minimum, growing indefinitely. At 1,000 subscribers, routine maintenance requires generating and storing 300,000 encrypted key payloads. This is not a theoretical scale problem — it is a guaranteed operational cost that grows with creator longevity regardless of whether the creator's subscriber count grows. The protocol's foundational principle is honest infrastructure costs; a mechanism that guarantees ever-increasing storage and compute overhead for no additional subscriber benefit is inconsistent with that principle.
Second, bundle storage creates a data target. Instances storing bundles of encrypted key material — even ciphertext — hold something more valuable than content: the keys to content. An instance under legal or extra-legal pressure to hand over decryption access becomes a higher-value target when it holds bundles that, if the encryption were broken, would unlock everything. The on-demand derivation model means the instance never holds a store of key material at rest — it derives keys transiently at access time. There is nothing to seize.
Third, superset tier access becomes a storage and management problem. If tier 2 is a superset of tier 1, the bundle model requires either encrypting content twice (once per tier) or including all lower-tier keys in higher-tier bundles, compounding the growth problem. On-demand derivation handles superset access cleanly through the key derivation logic without any additional storage.
Replaced by on-demand key derivation from master secret at access time. Subscription state is the sole authority. No bundles stored. No rotation schedule. Infrastructure cost is proportional to active access requests, not to content volume or subscriber history.

**Monthly key rotation — rejected**
Considered as a mechanism to protect against former subscribers retaining access to content from after their subscription lapsed. If keys rotate monthly, a former subscriber's keys from their active period become useless for new content automatically.
Rejected because the problem it solves is not a real problem given the correct access model, and the cost it introduces is real.
The access model adopted is: lapse means immediate loss of access. A former subscriber cannot access any content — not historical content, not new content — after their subscription lapses, because subscription state is the access authority. The concern that motivated monthly rotation ("former subscribers could retain access to new content") simply does not arise when access is governed by current subscription state rather than key possession.
Monthly rotation would protect against a scenario where a subscriber locally cached their keys and continued accessing content after lapsing. In the on-demand derivation model, there is nothing to locally cache — the key is derived transiently per request and verified against current on-chain subscription state at derivation time. A former subscriber with no active subscription state gets no key derived. There is no possession of keys to protect against.
The cost of rotation is real: new key generation per tier per month, re-delivery to all active subscribers, update of all content encrypted under old keys. At meaningful subscriber counts this is a routine but non-trivial infrastructure operation every 30 days, indefinitely, solving a problem that does not exist in the chosen architecture.
Former subscriber access to content from their paid period being retained is standard subscription platform behavior. Every major platform — Netflix, Patreon, OnlyFans — operates on the same implicit contract: you paid for that month, your local copy of anything you downloaded is yours, access to new content ends when payment ends. Attempting to revoke access to already-delivered content is both technically impossible in practice (you cannot unsee something) and contrary to reasonable user expectation. Stating this plainly in the spec is more honest than building rotation infrastructure that cannot accomplish the goal it appears to serve.

**Protocol-level wallet recovery infrastructure — rejected**
Considered as a usability accommodation for participants who lose wallet access. Possible forms included: designated recovery wallet requiring dual-signed transaction; social recovery requiring M-of-N signatures from trusted wallets; custodial recovery where the protocol or a trusted third party holds an encrypted recovery key.
Rejected because any recovery mechanism the protocol holds creates a target that is equivalent to the identity it purports to protect.
The identity model of this protocol ties creator identity, subscriber relationships, content references, and master secret access to a wallet address. Wallet authentication is the mechanism by which the protocol verifies that a participant is who they claim to be. Any recovery infrastructure — regardless of form — is a pathway by which someone who does not hold the private key can be granted the access rights of someone who does. That pathway is the attack surface.
An entity that can compel the protocol to activate recovery infrastructure can impersonate any creator or subscriber. "Compel" includes legal process, social engineering, operational security failures at the recovery infrastructure provider, and any other mechanism by which access to the recovery pathway is obtained. The broader the recovery infrastructure, the broader the attack surface.
The comparison to non-recovery is instructive. A protocol with no recovery infrastructure cannot be compelled to hand over wallet access — there is nothing to hand over. A protocol with recovery infrastructure can always be compelled to hand it over by a sufficiently motivated adversary with the right leverage. For a protocol whose primary design goal is resistance to exactly this kind of compelled disclosure, building recovery infrastructure is a direct contradiction.
Wallet private key custody being the participant's responsibility is not a gap in the protocol — it is the designed position. The same is true for every self-custodial wallet, hardware wallet, and comparable system. The friction of owning your wallet is load-bearing: it is what makes the identity genuinely portable and genuinely uncapturable. That friction cannot be removed without also removing the guarantee.
Client implementations may provide password-based convenience layers over locally-stored wallet key material. This is not protocol-level recovery — it is the client encrypting your keys on your device under your password. If you lose both the client password and the seed phrase, you lose the wallet. This is the same contract as any self-custodial wallet and should be communicated clearly at onboarding.

**On-chain CSAM adjudication process — rejected**
Considered as an internal protocol-level review panel for CSAM reports. Rejected for three compounding reasons. First, any internal review process requires someone to view reported content to make a determination, creating legal exposure for reviewers in every jurisdiction where possession is criminal regardless of intent. Second, building internal review infrastructure creates a mandate surface — infrastructure that exists can be legislatively expanded and repurposed; routing to NCMEC/IWF/INHOPE means the protocol has no infrastructure to mandate, only a referral pathway to organizations already legally constituted for this purpose. Third, internal adjudication produces liability without protection — an incorrect determination in either direction creates liability for the protocol and its maintainers that does not exist when determination is made by legally authorized authorities. Replaced by mandatory referral to existing legal infrastructure with time-bounded suspension to prevent indefinite suspension as a harassment strategy.

**Creator master secret held on creator device only — rejected**
Considered as the maximum-privacy model for master secret storage: the master secret never leaves the creator's device, key derivation for all subscriber access requests requires the creator's client to be online and participating, and the instance holds no sensitive creator key material whatsoever.
Rejected because it introduces a liveness dependency that is incompatible with how creators actually use subscription platforms, and because it transfers infrastructure burden to creators in a way that contradicts the protocol's economic principles.
The liveness dependency is: if the creator's device is offline, no subscriber can access any content. Every access request requires the creator's client to be running, connected, and responsive. For a creator who posts content and then goes offline — which is the normal operating pattern for any creator who treats this as a source of income rather than a full-time infrastructure management job — subscribers would be unable to access content during any period the creator is not actively online. This is a fundamental UX failure that would make DEN materially worse than any existing subscription platform for subscriber experience.
The alternative of requiring creators to run always-on infrastructure to keep their master secret available is simply cost and operational burden transferred from instances to creators. Instances are operated by Hosters who are compensated for providing exactly this kind of always-on reliability. A creator who must also maintain always-on infrastructure to make their content accessible is being asked to be their own Hoster without the compensation model that makes Hosting economically rational. This contradicts the principle that the protocol serves human creative labor — it imposes infrastructure obligations on the people the infrastructure is supposed to serve.
The adopted model stores the master secret on the instance encrypted to the creator's wallet public key. The instance holds ciphertext it cannot read. The Hoster rule holds — an instance operator who cannot read the encrypted master secret blob is in the same position as an instance operator who cannot read encrypted content. The creator's key material is protected by the same architectural guarantee as their content. The instance can serve subscriber access requests autonomously because it can derive keys from the encrypted master secret using a valid subscriber wallet signature as the decryption trigger — without the creator being present, and without the instance ever having access to the plaintext master secret.

---

## Appendix B — Open Questions Summary

A consolidated list of all open questions flagged in the sections above, for tracking before spec drafting begins.

| Section | Open Question | Spec Impact | Status |
|---------|--------------|-------------|--------|

All questions are currently resolved.

---

*DEN — Decentralized Encrypted Network*
*Architecture Document v0.1 — companion to DEN-SPEC.md*
*Decisions recorded here are not open for revision without governance process.*
