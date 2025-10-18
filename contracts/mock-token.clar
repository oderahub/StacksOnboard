(define-fungible-token mock-token)

(define-constant ERR_NOT_OWNER (err u100))

;; Contract owner captured at deploy-time (tx-sender when deploying using Clarinet)
(define-constant CONTRACT_OWNER tx-sender)

;; Transfer wrapper (for dev/testing: caller must be the owner of tokens being transferred)
(define-public (transfer
    (amount uint)
    (sender principal)
    (recipient principal)
    (memo (optional (buff 34)))
  )
  (begin
    (asserts! (is-eq tx-sender sender) ERR_NOT_OWNER)
    (try! (ft-transfer? mock-token amount sender recipient))
    (match memo
      to-print (print to-print)
      0x
    )
    (ok true)
  )
)

;; SIP-010 metadata helpers
(define-read-only (get-name) (ok "Mock Token"))
(define-read-only (get-symbol) (ok "MT"))
(define-read-only (get-decimals) (ok u6))
(define-read-only (get-total-supply) (ok (ft-get-supply mock-token)))
(define-read-only (get-balance (who principal)) (ok (ft-get-balance mock-token who)))
(define-read-only (get-token-uri) (ok none))

;; Mint function - checks contract-caller instead of tx-sender
;; This allows other contracts to call mint
(define-public (mint (amount uint) (recipient principal))
  (begin
    ;; Allow either the owner directly OR any contract call on behalf of the owner
    (asserts! 
      (or 
        (is-eq tx-sender CONTRACT_OWNER)
        (is-eq contract-caller CONTRACT_OWNER)
      ) 
      ERR_NOT_OWNER
    )
    (ft-mint? mock-token amount recipient)
  )
)