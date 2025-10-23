;; -----------------------------------------------------------
;; swap-fee-pool.clar
;; Token Swap Contract with Fee Mechanism (STX compatible)
;; -----------------------------------------------------------
;; Features:
;; - Swap two SIP-010 tokens with configurable fee

;; Define SIP-010 Fungible Token Trait
(define-trait ft-trait
    (
        (transfer (uint principal principal (optional (buff 34))) (response bool uint))
        (get-symbol () (response (string-ascii 32) uint))
    )
)
;; - Fee accumulation in treasury
;; - Admin-controlled fee rate
;; - Error-safe math and validations
;; -----------------------------------------------------------

(define-constant ERR_UNAUTHORIZED u100)
(define-constant ERR_INVALID_AMOUNT u101)
(define-constant ERR_TRANSFER_FAILED u102)
(define-constant ERR_ZERO_ADDRESS u103)

;; Fee precision (basis points, i.e., 100 = 1%)
(define-constant FEE_DENOMINATOR u10000)

;; Contract admin
(define-data-var admin principal tx-sender)

;; Fee rate (e.g., 30 = 0.3%)
(define-data-var swap-fee-bps uint u30)

;; Fee treasury balance
(define-data-var treasury-balance uint u0)

;; -----------------------------------------------------------
;; UTILITIES
;; -----------------------------------------------------------

(define-private (is-admin (caller principal))
  (is-eq caller (var-get admin)))

(define-private (calc-fee (amount uint))
  (/ (* amount (var-get swap-fee-bps)) FEE_DENOMINATOR))

(define-private (get-token-name (token <ft-trait>))
  (unwrap-panic (contract-call? token get-symbol)))

;; -----------------------------------------------------------
;; CORE SWAP LOGIC
;; -----------------------------------------------------------

(define-public (swap-tokens
    (token-x <ft-trait>)
    (token-y <ft-trait>)
    (amount-x uint)
    (rate uint)
    (recipient principal))
  (let
      (
        (fee (calc-fee amount-x))
        (net-amount (- amount-x fee))
        (amount-y (/ (* net-amount rate) u1000000))
      )
    (begin
      (asserts! (> amount-x u0) (err ERR_INVALID_AMOUNT))
      (asserts! (not (is-eq recipient tx-sender)) (err ERR_ZERO_ADDRESS))

      ;; Transfer Token X from sender to contract
      (asserts!
        (is-ok (contract-call? token-x transfer amount-x tx-sender (as-contract tx-sender) none))
        (err ERR_TRANSFER_FAILED))

      ;; Transfer Token Y from contract to recipient
      (asserts!
        (is-ok (contract-call? token-y transfer amount-y (as-contract tx-sender) recipient none))
        (err ERR_TRANSFER_FAILED))

      ;; Add fee to treasury
      (var-set treasury-balance (+ (var-get treasury-balance) fee))

      (ok {
        swapper: tx-sender,
        recipient: recipient,
        sent: amount-x,
        received: amount-y,
        fee: fee
      })
    )
  )
)

;; -----------------------------------------------------------
;; ADMIN MANAGEMENT
;; -----------------------------------------------------------

(define-public (set-fee (new-fee-bps uint))
  (begin
    (asserts! (is-admin tx-sender) (err ERR_UNAUTHORIZED))
    (asserts! (< new-fee-bps FEE_DENOMINATOR) (err ERR_INVALID_AMOUNT))
    (var-set swap-fee-bps new-fee-bps)
    (ok new-fee-bps)
  ))

(define-public (withdraw-fees (token <ft-trait>) (to principal))
  (let ((balance (var-get treasury-balance)))
    (begin
      (asserts! (is-admin tx-sender) (err ERR_UNAUTHORIZED))
      (asserts! (> balance u0) (err ERR_INVALID_AMOUNT))

      (asserts!
        (is-ok (contract-call? token transfer balance (as-contract tx-sender) to none))
        (err ERR_TRANSFER_FAILED))

      (var-set treasury-balance u0)
      (ok balance)
    )
  )
)

;; -----------------------------------------------------------
;; READ-ONLY FUNCTIONS
;; -----------------------------------------------------------

(define-read-only (get-fee-rate) (ok (var-get swap-fee-bps)))
(define-read-only (get-treasury-balance) (ok (var-get treasury-balance)))
(define-read-only (get-admin) (ok (var-get admin)))
