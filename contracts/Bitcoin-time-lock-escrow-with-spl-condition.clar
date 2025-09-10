
;; Bitcoin-time-lock-escrow-with-spl-condition
;; A Bitcoin time-locked escrow service where funds are locked in a Stacks smart contract
;; but can only be released after a specific Bitcoin block height. The "SPL condition" 
;; allows the sender to reclaim funds if the recipient doesn't fulfill their obligation 
;; (e.g., providing a secret key/preimage) before the time lock expires.

;; constants
(define-constant CONTRACT-OWNER tx-sender)

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ESCROW-NOT-FOUND (err u101))
(define-constant ERR-ESCROW-ALREADY-EXISTS (err u102))
(define-constant ERR-AMOUNT-MUST-BE-POSITIVE (err u103))
(define-constant ERR-INVALID-BITCOIN-HEIGHT (err u104))
(define-constant ERR-ESCROW-LOCKED (err u105))
(define-constant ERR-BITCOIN-HEIGHT-NOT-REACHED (err u106))
(define-constant ERR-INVALID-SECRET (err u107))
(define-constant ERR-ESCROW-ALREADY-CLAIMED (err u108))
(define-constant ERR-ESCROW-EXPIRED (err u109))
(define-constant ERR-INSUFFICIENT-BALANCE (err u110))

;; data maps and vars
(define-map escrows
  { escrow-id: uint }
  {
    sender: principal,
    recipient: principal,
    amount: uint,
    bitcoin-unlock-height: uint,
    secret-hash: (buff 32),
    is-claimed: bool,
    is-refunded: bool,
    created-at-height: uint
  }
)

;; Track next escrow ID
(define-data-var next-escrow-id uint u1)

;; Track total escrows created
(define-data-var total-escrows uint u0)

;; private functions
(define-private (get-next-escrow-id)
  (begin
    (var-set next-escrow-id (+ (var-get next-escrow-id) u1))
    (- (var-get next-escrow-id) u1)
  )
)

;; Calculate Bitcoin block height from Stacks height (approximate)
;; Bitcoin blocks are mined roughly every 10 minutes, Stacks every ~10 minutes
;; This is a simplified conversion - in production, you'd use burn block height
(define-private (convert-to-bitcoin-height (stacks-blocks-ahead uint))
  (+ burn-block-height stacks-blocks-ahead)
)

;; public functions

;; Create a new escrow with time lock and secret hash condition
(define-public (create-escrow 
  (recipient principal) 
  (amount uint) 
  (blocks-ahead uint) 
  (secret-hash (buff 32)))
  (let
    (
      (escrow-id (get-next-escrow-id))
      (bitcoin-height (convert-to-bitcoin-height blocks-ahead))
    )
    (begin
      ;; Validate inputs
      (asserts! (> amount u0) ERR-AMOUNT-MUST-BE-POSITIVE)
      (asserts! (> blocks-ahead u0) ERR-INVALID-BITCOIN-HEIGHT)
      (asserts! (>= (stx-get-balance tx-sender) amount) ERR-INSUFFICIENT-BALANCE)
      
      ;; Check escrow doesn't already exist for this ID
      (asserts! (is-none (map-get? escrows { escrow-id: escrow-id })) ERR-ESCROW-ALREADY-EXISTS)
      
      ;; Transfer STX to contract
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      
      ;; Create escrow record
      (map-set escrows 
        { escrow-id: escrow-id }
        {
          sender: tx-sender,
          recipient: recipient,
          amount: amount,
          bitcoin-unlock-height: bitcoin-height,
          secret-hash: secret-hash,
          is-claimed: false,
          is-refunded: false,
          created-at-height: block-height
        }
      )
      
      ;; Update counters
      (var-set total-escrows (+ (var-get total-escrows) u1))
      
      ;; Return escrow ID
      (ok escrow-id)
    )
  )
)

;; Get escrow details by ID
(define-read-only (get-escrow (escrow-id uint))
  (map-get? escrows { escrow-id: escrow-id })
)

;; Get total number of escrows created
(define-read-only (get-total-escrows)
  (var-get total-escrows)
)

;; Check if Bitcoin unlock height has been reached
(define-read-only (is-bitcoin-height-reached (escrow-id uint))
  (match (map-get? escrows { escrow-id: escrow-id })
    escrow-data 
      (>= burn-block-height (get bitcoin-unlock-height escrow-data))
    false
  )
)

;; Validate secret preimage against stored hash
(define-private (validate-secret (secret (buff 32)) (expected-hash (buff 32)))
  (is-eq (sha256 secret) expected-hash)
)

;; Check if escrow can be claimed by recipient
(define-read-only (can-claim-escrow (escrow-id uint))
  (match (map-get? escrows { escrow-id: escrow-id })
    escrow-data
      (and 
        (not (get is-claimed escrow-data))
        (not (get is-refunded escrow-data))
        (>= burn-block-height (get bitcoin-unlock-height escrow-data))
      )
    false
  )
)

;; Check if escrow can be refunded by sender  
(define-read-only (can-refund-escrow (escrow-id uint))
  (match (map-get? escrows { escrow-id: escrow-id })
    escrow-data
      (and 
        (not (get is-claimed escrow-data))
        (not (get is-refunded escrow-data))
        (>= burn-block-height (get bitcoin-unlock-height escrow-data))
      )
    false
  )
)

;; Claim escrow by providing the secret preimage
(define-public (claim-escrow (escrow-id uint) (secret (buff 32)))
  (let
    (
      (escrow-opt (map-get? escrows { escrow-id: escrow-id }))
    )
    (begin
      ;; Check if escrow exists
      (asserts! (is-some escrow-opt) ERR-ESCROW-NOT-FOUND)
      
      (match escrow-opt
        escrow-data
        (begin
          ;; Only recipient can claim
          (asserts! (is-eq tx-sender (get recipient escrow-data)) ERR-NOT-AUTHORIZED)
          
          ;; Escrow must not be already claimed or refunded
          (asserts! (not (get is-claimed escrow-data)) ERR-ESCROW-ALREADY-CLAIMED)
          (asserts! (not (get is-refunded escrow-data)) ERR-ESCROW-ALREADY-CLAIMED)
          
          ;; Bitcoin height must be reached
          (asserts! (>= burn-block-height (get bitcoin-unlock-height escrow-data)) ERR-BITCOIN-HEIGHT-NOT-REACHED)
          
          ;; Validate secret against stored hash
          (asserts! (validate-secret secret (get secret-hash escrow-data)) ERR-INVALID-SECRET)
          
          ;; Transfer STX to recipient
          (try! (as-contract (stx-transfer? (get amount escrow-data) tx-sender (get recipient escrow-data))))
          
          ;; Mark as claimed
          (map-set escrows
            { escrow-id: escrow-id }
            (merge escrow-data { is-claimed: true })
          )
          
          (ok true)
        )
        ERR-ESCROW-NOT-FOUND
      )
    )
  )
)

;; Refund escrow to sender if recipient doesn't claim in time
(define-public (refund-escrow (escrow-id uint))
  (let
    (
      (escrow-opt (map-get? escrows { escrow-id: escrow-id }))
    )
    (begin
      ;; Check if escrow exists
      (asserts! (is-some escrow-opt) ERR-ESCROW-NOT-FOUND)
      
      (match escrow-opt
        escrow-data
        (begin
          ;; Only sender can refund
          (asserts! (is-eq tx-sender (get sender escrow-data)) ERR-NOT-AUTHORIZED)
          
          ;; Escrow must not be already claimed or refunded
          (asserts! (not (get is-claimed escrow-data)) ERR-ESCROW-ALREADY-CLAIMED)
          (asserts! (not (get is-refunded escrow-data)) ERR-ESCROW-ALREADY-CLAIMED)
          
          ;; Bitcoin height must be reached (escrow expired)
          (asserts! (>= burn-block-height (get bitcoin-unlock-height escrow-data)) ERR-BITCOIN-HEIGHT-NOT-REACHED)
          
          ;; Transfer STX back to sender
          (try! (as-contract (stx-transfer? (get amount escrow-data) tx-sender (get sender escrow-data))))
          
          ;; Mark as refunded
          (map-set escrows
            { escrow-id: escrow-id }
            (merge escrow-data { is-refunded: true })
          )
          
          (ok true)
        )
        ERR-ESCROW-NOT-FOUND
      )
    )
  )
)

;; Emergency function: Cancel escrow before Bitcoin height is reached (contract owner only)
(define-public (emergency-cancel-escrow (escrow-id uint))
  (let
    (
      (escrow-opt (map-get? escrows { escrow-id: escrow-id }))
    )
    (begin
      ;; Only contract owner can call this
      (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
      
      ;; Check if escrow exists
      (asserts! (is-some escrow-opt) ERR-ESCROW-NOT-FOUND)
      
      (match escrow-opt
        escrow-data
        (begin
          ;; Escrow must not be already claimed or refunded
          (asserts! (not (get is-claimed escrow-data)) ERR-ESCROW-ALREADY-CLAIMED)
          (asserts! (not (get is-refunded escrow-data)) ERR-ESCROW-ALREADY-CLAIMED)
          
          ;; Can only cancel before Bitcoin height is reached
          (asserts! (< burn-block-height (get bitcoin-unlock-height escrow-data)) ERR-ESCROW-EXPIRED)
          
          ;; Transfer STX back to sender
          (try! (as-contract (stx-transfer? (get amount escrow-data) tx-sender (get sender escrow-data))))
          
          ;; Mark as refunded (using same flag for emergency cancellation)
          (map-set escrows
            { escrow-id: escrow-id }
            (merge escrow-data { is-refunded: true })
          )
          
          (ok true)
        )
        ERR-ESCROW-NOT-FOUND
      )
    )
  )
)

;; Get escrow status summary
(define-read-only (get-escrow-status (escrow-id uint))
  (match (map-get? escrows { escrow-id: escrow-id })
    escrow-data
      (ok {
        exists: true,
        is-claimed: (get is-claimed escrow-data),
        is-refunded: (get is-refunded escrow-data),
        bitcoin-height-reached: (>= burn-block-height (get bitcoin-unlock-height escrow-data)),
        sender: (get sender escrow-data),
        recipient: (get recipient escrow-data),
        amount: (get amount escrow-data)
      })
    (ok { 
      exists: false,
      is-claimed: false,
      is-refunded: false,
      bitcoin-height-reached: false,
      sender: CONTRACT-OWNER,
      recipient: CONTRACT-OWNER,
      amount: u0
    })
  )
)

;; Get contract statistics
(define-read-only (get-contract-stats)
  {
    total-escrows: (var-get total-escrows),
    contract-balance: (stx-get-balance (as-contract tx-sender)),
    current-bitcoin-height: burn-block-height,
    contract-owner: CONTRACT-OWNER
  }
)
