;; sha256-innovative-workspace Health Access Control Contract
;; 
;; This contract provides a secure, privacy-preserving framework for managing 
;; health data access and user consent on the blockchain.
;;
;; Core principles:
;; - User-controlled data permissions
;; - Granular access management
;; - Comprehensive audit trail

;; Error classifications
(define-constant err-unauthorized u1)
(define-constant err-identity-exists u2)
(define-constant err-identity-missing u3)
(define-constant err-endpoint-registered u4)
(define-constant err-endpoint-unknown u5)
(define-constant err-verifier-invalid u6)
(define-constant err-verifier-duplicate u7)
(define-constant err-permission-denied u8)
(define-constant err-data-type-invalid u9)
(define-constant err-access-expiry-invalid u10)

;; Supported health data domains
(define-constant domain-cardiac "cardiac-metrics")
(define-constant domain-metabolic "metabolic-indicators")
(define-constant domain-sleep-pattern "sleep-analysis")
(define-constant domain-physical-activity "activity-tracking")
(define-constant domain-glucose-monitoring "glucose-levels")
(define-constant domain-respiratory "oxygen-saturation")
(define-constant domain-thermal "body-temperature")
(define-constant domain-mass-index "weight-metrics")

;; Identity registry mapping
(define-map user-identities 
  { identity: principal } 
  { registered: bool, registration-timestamp: uint }
)

;; Endpoint (device) registry mapping
(define-map user-endpoints 
  { identity: principal, endpoint-id: (string-ascii 64) } 
  { active: bool, endpoint-type: (string-ascii 64), registration-timestamp: uint }
)

;; Verified data consumers mapping
(define-map authorized-consumers
  { consumer: principal }
  { verified: bool, consumer-category: (string-ascii 64), verification-timestamp: uint }
)

;; Data access permission mapping
(define-map access-permissions
  { identity: principal, consumer: principal, domain: (string-ascii 64) }
  { granted: bool, expiration: (optional uint), grant-timestamp: uint }
)

;; Access event tracking
(define-map access-audit
  { audit-id: uint }
  { 
    identity: principal, 
    consumer: principal, 
    domain: (string-ascii 64), 
    timestamp: uint,
    rationale: (string-ascii 128)
  }
)

;; Audit trail counter
(define-data-var audit-sequence uint u0)

;; Private utility functions
(define-private (is-valid-domain (domain (string-ascii 64)))
  (or
    (is-eq domain domain-cardiac)
    (is-eq domain domain-metabolic)
    (is-eq domain domain-sleep-pattern)
    (is-eq domain domain-physical-activity)
    (is-eq domain domain-glucose-monitoring)
    (is-eq domain domain-respiratory)
    (is-eq domain domain-thermal)
    (is-eq domain domain-mass-index)
  )
)

(define-private (is-identity-registered (identity principal))
  (default-to false (get registered (map-get? user-identities { identity: identity })))
)

(define-private (is-endpoint-registered (identity principal) (endpoint-id (string-ascii 64)))
  (default-to false (get active (map-get? user-endpoints { identity: identity, endpoint-id: endpoint-id })))
)

(define-private (is-consumer-verified (consumer principal))
  (default-to false (get verified (map-get? authorized-consumers { consumer: consumer })))
)

(define-private (check-access-permission (identity principal) (consumer principal) (domain (string-ascii 64)))
  (let ((permission (map-get? access-permissions { identity: identity, consumer: consumer, domain: domain })))
    (if (is-none permission)
      false
      (let ((permission-details (unwrap-panic permission)))
        (if (not (get granted permission-details))
          false
          (match (get expiration permission-details)
            expiry-time (< block-height expiry-time)
            true
          )
        )
      )
    )
  )
)

(define-private (next-audit-sequence)
  (let ((current (var-get audit-sequence)))
    (var-set audit-sequence (+ current u1))
    current
  )
)

;; Read-only query functions
(define-read-only (verify-identity-status (identity principal))
  (ok (is-identity-registered identity))
)

(define-read-only (verify-consumer-status (consumer principal))
  (ok (is-consumer-verified consumer))
)

(define-read-only (check-data-access (identity principal) (consumer principal) (domain (string-ascii 64)))
  (ok (check-access-permission identity consumer domain))
)

(define-read-only (retrieve-access-record (audit-id uint))
  (ok (map-get? access-audit { audit-id: audit-id }))
)

;; Public state modification functions
(define-public (register-identity)
  (let ((sender tx-sender))
    (asserts! (not (is-identity-registered sender)) (err err-identity-exists))
    
    (map-set user-identities
      { identity: sender }
      { registered: true, registration-timestamp: block-height }
    )
    
    (ok true)
  )
)

(define-public (register-endpoint (endpoint-id (string-ascii 64)) (endpoint-type (string-ascii 64)))
  (let ((sender tx-sender))
    (asserts! (is-identity-registered sender) (err err-identity-missing))
    (asserts! (not (is-endpoint-registered sender endpoint-id)) (err err-endpoint-registered))
    
    (map-set user-endpoints
      { identity: sender, endpoint-id: endpoint-id }
      { active: true, endpoint-type: endpoint-type, registration-timestamp: block-height }
    )
    
    (ok true)
  )
)

(define-public (remove-endpoint (endpoint-id (string-ascii 64)))
  (let ((sender tx-sender))
    (asserts! (is-identity-registered sender) (err err-identity-missing))
    (asserts! (is-endpoint-registered sender endpoint-id) (err err-endpoint-unknown))
    
    (map-set user-endpoints
      { identity: sender, endpoint-id: endpoint-id }
      { active: false, endpoint-type: "", registration-timestamp: u0 }
    )
    
    (ok true)
  )
)

(define-public (authorize-consumer (consumer principal) (consumer-category (string-ascii 64)))
  (let ((sender tx-sender))
    ;; In production, this would require administrative privileges
    (asserts! (is-eq sender (as-contract tx-sender)) (err err-unauthorized))
    (asserts! (not (is-consumer-verified consumer)) (err err-verifier-duplicate))
    
    (map-set authorized-consumers
      { consumer: consumer }
      { verified: true, consumer-category: consumer-category, verification-timestamp: block-height }
    )
    
    (ok true)
  )
)

(define-public (grant-domain-access 
  (consumer principal) 
  (domain (string-ascii 64)) 
  (expiration (optional uint)))
  (let ((sender tx-sender))
    (asserts! (is-identity-registered sender) (err err-identity-missing))
    (asserts! (is-consumer-verified consumer) (err err-verifier-invalid))
    (asserts! (is-valid-domain domain) (err err-data-type-invalid))
    
    ;; Validate expiration if provided
    (match expiration
      expiry-time (asserts! (> expiry-time block-height) (err err-access-expiry-invalid))
      true
    )
    
    (map-set access-permissions
      { identity: sender, consumer: consumer, domain: domain }
      { granted: true, expiration: expiration, grant-timestamp: block-height }
    )
    
    (ok true)
  )
)

(define-public (revoke-domain-access (consumer principal) (domain (string-ascii 64)))
  (let ((sender tx-sender))
    (asserts! (is-identity-registered sender) (err err-identity-missing))
    (asserts! (is-valid-domain domain) (err err-data-type-invalid))
    
    (map-set access-permissions
      { identity: sender, consumer: consumer, domain: domain }
      { granted: false, expiration: none, grant-timestamp: block-height }
    )
    
    (ok true)
  )
)