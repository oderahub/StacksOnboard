;; =============================================================================
;; EASYSTACK - STX Staking and Rewards Protocol
;; =============================================================================
;;
;; OVERVIEW:
;; EasyStack is a flexible staking protocol that allows users to lock up STX
;; tokens and earn rewards in a custom fungible token. The protocol features
;; dual claiming mechanisms tied to both Stacks and Bitcoin block heights,
;; providing flexibility for different user preferences and strategies.
;;
;; USE CASES:
;; 1. DeFi protocols wanting to incentivize STX holders
;; 2. DAOs distributing governance tokens to engaged members
;; 3. Projects building liquidity mining programs
;; 4. Gaming platforms rewarding active participants with quest points
;;
;; KEY FEATURES:
;; - Flexible reward rates (admin adjustable)
;; - Dual claiming: Based on Stacks blocks OR Bitcoin blocks
;; - Quest points system for gamification
;; - Support for any SIP-010 compatible reward token
;;
;; ARCHITECTURE:
;; Admin → Initialize & Configure → Users Register → Users Stack STX
;; → Users Claim Rewards → Receive Reward Tokens + Quest Points
;;
;; =============================================================================

;; -------------------
;; Error Codes
;; -------------------
(define-constant ERR-NOT-REGISTERED u100)      ;; User hasn't registered yet
(define-constant ERR-ALREADY-REGISTERED u101)  ;; User already registered
(define-constant ERR-INVALID-AMOUNT u102)      ;; Amount must be > 0 or within limits
(define-constant ERR-NOT-AUTHORIZED u103)      ;; Caller is not admin
(define-constant ERR-TOO-SOON u104)            ;; Claim interval not reached
(define-constant ERR-NO-STAKE u105)            ;; User has no staked STX
(define-constant ERR-ALREADY-INIT u106)        ;; Contract already initialized

;; -------------------
;; Configuration Parameters
;; -------------------
;; Reward calculation: (stx-amount * reward-rate) / REWARD-DENOMINATOR
(define-constant REWARD-DENOMINATOR u100)

;; Default reward rate: 10% per claim
(define-data-var reward-rate uint u10)

;; Minimum blocks between claims (Stacks block height)
;; ~20 blocks = approximately 2-3 hours on Stacks
(define-constant CLAIM-INTERVAL u20)

;; Minimum blocks between claims (Bitcoin block height)
;; ~20 blocks = approximately 3-4 hours on Bitcoin
(define-constant BURN-CLAIM-INTERVAL u20)

;; Contract administrator (set during initialization)
(define-data-var admin (optional principal) none)

;; Reward token contract address (set by admin)
(define-data-var reward-token (optional principal) none)


;;this sets up a clear, safe foundation. it make the contract predictable, which is key for newbies.



;; -------------------
;; Data Maps
;; -------------------

;; These maps are like the contract’s memory. I keep track of everyone’s staking activity.”


;; User staking information
;; Tracks: amount staked, total rewards earned, and quest points accumulated
(define-map users
  principal
  { 
    stx-stacked: uint,    ;; Total STX currently staked
    total-rewards: uint,  ;; Cumulative rewards earned
    quest-points: uint    ;; Gamification points (1 per claim)
  }
)

;; Claim state for Stacks-block-based claims
;; Prevents spam by enforcing minimum intervals
(define-map claim-state
  principal
  { 
    last-claim-height: uint,  ;; Stacks block height of last claim
    claim-count: uint         ;; Total number of claims made
  }
)

;; Claim state for Bitcoin-block-based claims
;; Separate from Stacks claims to allow dual-strategy claiming
(define-map claim-state-burn
  principal
  { 
    last-claim-burn-height: uint,  ;; Bitcoin block height of last claim
    claim-count: uint              ;; Total number of burn claims made
  }
)

;; -------------------
;; Trait Definition
;; -------------------
;; Custom trait for tokens that support minting
;; Required because SIP-010 doesn't include mint function
(define-trait mintable-token
  (
    ;; mint: (amount recipient) -> (response bool uint)
    (mint (uint principal) (response bool uint))
  )
)

;; -------------------
;; Helper Functions
;; -------------------

;; Get current Stacks block height
(define-private (height-now)
  stacks-block-height
)

;; Get current Bitcoin burn block height
;; Useful for claims tied to Bitcoin's more predictable block times
(define-private (burn-height-now)
  burn-block-height
)

;; -------------------
;; Read-Only Functions
;; -------------------

;; Check if a principal has registered
;; @param who: principal to check
;; @returns: true if registered, false otherwise
(define-read-only (is-registered (who principal))
  (is-some (map-get? users who))
)

;; Get the current admin principal
;; @returns: (optional principal) - admin if set, none if not initialized
(define-read-only (get-admin)
  (var-get admin)
)

;; Get the current reward rate
;; @returns: uint - current rate (out of REWARD-DENOMINATOR)
(define-read-only (get-reward-rate)
  (var-get reward-rate)
)

;; Get user's complete staking information
;; @param user: principal to query
;; @returns: (optional tuple) - user data if registered, none otherwise
(define-read-only (get-user-info (user principal))
  (map-get? users user)
)

;; Get user's Stacks-based claim information
;; @param user: principal to query
;; @returns: (optional tuple) - claim data if registered, none otherwise
(define-read-only (get-claim-info (user principal))
  (map-get? claim-state user)
)

;; -------------------
;; Admin Functions
;; -------------------
;;admin controls. It ensures only the right person can make changes.”


;; Initialize the contract with admin
;; Can only be called once by the deployer
;; @returns: (response bool uint)
(define-public (init)
  (if (is-some (var-get admin))
      (err ERR-ALREADY-INIT)
      (begin
        (var-set admin (some tx-sender))
        (print { event: "init", admin: tx-sender })
        (ok true)
      )
  )
)

;; Update the reward rate
;; Only admin can call this
;; @param new-rate: new rate (must be <= REWARD-DENOMINATOR)
;; @returns: (response uint uint)
(define-public (set-reward-rate (new-rate uint))
  (let ((adm (unwrap! (var-get admin) (err ERR-NOT-AUTHORIZED))))
    (if (is-eq tx-sender adm)
        (if (> new-rate REWARD-DENOMINATOR)
            (err ERR-INVALID-AMOUNT)
            (begin
              (var-set reward-rate new-rate)
              (print { event: "set-rate", by: tx-sender, new-rate: new-rate })
              (ok new-rate)
            )
        )
        (err ERR-NOT-AUTHORIZED)
    )
  )
)

;; Set the reward token contract
;; Only admin can call this
;; @param token: principal of the mintable token contract
;; @returns: (response principal uint)
(define-public (init-reward-token (token principal))
  (let ((adm (unwrap! (var-get admin) (err ERR-NOT-AUTHORIZED))))
    (if (is-eq tx-sender adm)
        (begin
          (var-set reward-token (some token))
          (print { event: "set-token", token: token })
          (ok token)
        )
        (err ERR-NOT-AUTHORIZED)
    )
  )
)

;; -------------------
;; User Functions
;; -------------------
;;Users just register and stake


;; Register a new user in the system
;; Must be called before staking or claiming
;; Initializes all tracking maps with zero values
;; @returns: (response bool uint)
(define-public (register-user)
  (if (is-some (map-get? users tx-sender))
      (err ERR-ALREADY-REGISTERED)
      (begin
        (map-set users tx-sender 
          { stx-stacked: u0, total-rewards: u0, quest-points: u0 })
        (map-set claim-state tx-sender 
          { last-claim-height: u0, claim-count: u0 })
        (map-set claim-state-burn tx-sender 
          { last-claim-burn-height: u0, claim-count: u0 })
        (print { event: "register", user: tx-sender })
        (ok true)
      )
  )
)

;; Add STX to user's stake
;; Note: This is a logical stake - STX stays in user's wallet
;; @param amount: amount of STX to stake
;; @returns: (response uint uint) - new total staked amount
(define-public (stack-stx (amount uint))
  (if (is-eq amount u0)
      (err ERR-INVALID-AMOUNT)
      (let (
            (u (unwrap! (map-get? users tx-sender) (err ERR-NOT-REGISTERED)))
            (new-stacked (+ (get stx-stacked u) amount))
           )
        (map-set users tx-sender
          { stx-stacked: new-stacked,
            total-rewards: (get total-rewards u),
            quest-points: (get quest-points u) }
        )
        (print { event: "stack", user: tx-sender, amount: amount, new-total: new-stacked })
        (ok new-stacked)
      )
  )
)

;; -------------------
;; Claim Reward (Stacks-based timing)
;; -------------------

;; This ties it all together—users stake, wait, and claim rewards easily. Quest points make it social and engaging


;; Claim rewards based on Stacks block height
;; Useful for users who want claims tied to Stacks' microblocks and faster confirmations
;; @param token-contract: the mintable token to receive as rewards
;; @returns: (response uint uint) - amount of rewards claimed
(define-public (claim-reward (token-contract <mintable-token>))
  (let (
        (u (unwrap! (map-get? users tx-sender) (err ERR-NOT-REGISTERED)))
        (cs (unwrap! (map-get? claim-state tx-sender) (err ERR-NOT-REGISTERED)))
        (stx (get stx-stacked u))
        (now (height-now))
        (rate (var-get reward-rate))
       )
    (if (is-eq stx u0)
        (err ERR-NO-STAKE)
        (if (or (is-eq (get last-claim-height cs) u0)
                (>= now (+ (get last-claim-height cs) CLAIM-INTERVAL)))
            (let (
                  (reward (/ (* stx rate) REWARD-DENOMINATOR))
                  (new-total-rewards (+ (get total-rewards u) reward))
                  (new-qp (+ (get quest-points u) u1))
                 )
              ;; Update user stats
              (map-set users tx-sender
                { stx-stacked: stx, total-rewards: new-total-rewards, quest-points: new-qp }
              )
              ;; Update claim state
              (map-set claim-state tx-sender
                { last-claim-height: now, claim-count: (+ (get claim-count cs) u1) }
              )
              ;; Mint reward tokens to user
              (try! (contract-call? token-contract mint reward tx-sender))
              (ok reward)
            )
            (err ERR-TOO-SOON)
        )
    )
  )
)

;; -------------------
;; Claim Reward (Bitcoin-based timing)
;; -------------------
;; Claim rewards based on Bitcoin burn block height
;; Useful for users who want claims tied to Bitcoin's more predictable block times
;; Operates independently from Stacks-based claims
;; @param token-contract: the mintable token to receive as rewards
;; @returns: (response uint uint) - amount of rewards claimed
(define-public (claim-reward-burn (token-contract <mintable-token>))
  (let (
        (u (unwrap! (map-get? users tx-sender) (err ERR-NOT-REGISTERED)))
        (cs-burn (unwrap! (map-get? claim-state-burn tx-sender) (err ERR-NOT-REGISTERED)))
        (stx (get stx-stacked u))
        (now-burn (burn-height-now))
        (rate (var-get reward-rate))
       )
    (if (is-eq stx u0)
        (err ERR-NO-STAKE)
        (if (or (is-eq (get last-claim-burn-height cs-burn) u0)
                (>= now-burn (+ (get last-claim-burn-height cs-burn) BURN-CLAIM-INTERVAL)))
            (let (
                  (reward (/ (* stx rate) REWARD-DENOMINATOR))
                  (new-total-rewards (+ (get total-rewards u) reward))
                  (new-qp (+ (get quest-points u) u1))
                  (new-claim-count (+ (get claim-count cs-burn) u1))
                 )
              ;; Update user stats
              (map-set users tx-sender
                { stx-stacked: stx, total-rewards: new-total-rewards, quest-points: new-qp }
              )
              ;; Update burn claim state
              (map-set claim-state-burn tx-sender
                { last-claim-burn-height: now-burn, claim-count: new-claim-count }
              )
              ;; Mint reward tokens to user
              (try! (contract-call? token-contract mint reward tx-sender))
              (ok reward)
            )
            (err ERR-TOO-SOON)
        )
    )
  )
)