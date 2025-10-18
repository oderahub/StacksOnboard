;; -------------------
;; Error Codes
;; -------------------
(define-constant ERR-NOT-REGISTERED u100)
(define-constant ERR-ALREADY-REGISTERED u101)
(define-constant ERR-INVALID-AMOUNT u102)
(define-constant ERR-NOT-AUTHORIZED u103)
(define-constant ERR-TOO-SOON u104)
(define-constant ERR-NO-STAKE u105)
(define-constant ERR-ALREADY-INIT u106)

;; -------------------
;; Parameters
;; -------------------
(define-constant REWARD-DENOMINATOR u100)
(define-data-var reward-rate uint u10) ;; 10%
(define-constant CLAIM-INTERVAL u20)
(define-constant BURN-CLAIM-INTERVAL u20)

(define-data-var admin (optional principal) none)
(define-data-var reward-token (optional principal) none)

;; -------------------
;; State
;; -------------------
(define-map users
  principal
  { stx-stacked: uint, total-rewards: uint, quest-points: uint }
)

(define-map claim-state
  principal
  { last-claim-height: uint, claim-count: uint }
)

(define-map claim-state-burn
  principal
  { last-claim-burn-height: uint, claim-count: uint }
)

;; -------------------
;; Trait Definition
;; -------------------
(define-trait mintable-token
  (
    (mint (uint principal) (response bool uint))
  )
)

;; -------------------
;; Helpers
;; -------------------
(define-private (height-now)
  stacks-block-height
)

(define-private (burn-height-now)
  burn-block-height
)

;; -------------------
;; Read-only
;; -------------------
(define-read-only (is-registered (who principal))
  (is-some (map-get? users who))
)

(define-read-only (get-admin)
  (var-get admin)
)

(define-read-only (get-reward-rate)
  (var-get reward-rate)
)

(define-read-only (get-user-info (user principal))
  (map-get? users user)
)

(define-read-only (get-claim-info (user principal))
  (map-get? claim-state user)
)

;; -------------------
;; Admin Functions
;; -------------------
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
(define-public (register-user)
  (if (is-some (map-get? users tx-sender))
      (err ERR-ALREADY-REGISTERED)
      (begin
        (map-set users tx-sender { stx-stacked: u0, total-rewards: u0, quest-points: u0 })
        (map-set claim-state tx-sender { last-claim-height: u0, claim-count: u0 })
        (map-set claim-state-burn tx-sender { last-claim-burn-height: u0, claim-count: u0 })
        (print { event: "register", user: tx-sender })
        (ok true)
      )
  )
)

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
;; Claim Reward (Stacks cadence)
;; -------------------
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
              (map-set users tx-sender
                { stx-stacked: stx, total-rewards: new-total-rewards, quest-points: new-qp }
              )
              (map-set claim-state tx-sender
                { last-claim-height: now, claim-count: (+ (get claim-count cs) u1) }
              )
              (try! (contract-call? token-contract mint reward tx-sender))
              (ok reward)
            )
            (err ERR-TOO-SOON)
        )
    )
  )
)


;; -------------------
;; Claim Reward (Burn cadence)
;; -------------------
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
              (map-set users tx-sender
                { stx-stacked: stx, total-rewards: new-total-rewards, quest-points: new-qp }
              )
              (map-set claim-state-burn tx-sender
                { last-claim-burn-height: now-burn, claim-count: new-claim-count }
              )
              (try! (contract-call? token-contract mint reward tx-sender))
              (ok reward)
            )
            (err ERR-TOO-SOON)
        )
    )
  )
)