;; Safety Verification Contract
;; Validates driver credentials and vehicle condition

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-DRIVER-NOT-FOUND (err u401))
(define-constant ERR-VEHICLE-NOT-FOUND (err u402))
(define-constant ERR-INSUFFICIENT-STAKE (err u403))
(define-constant ERR-ALREADY-VERIFIED (err u404))
(define-constant ERR-VERIFICATION-EXPIRED (err u405))
(define-constant ERR-INVALID-RATING (err u406))

;; Data Variables
(define-data-var verification-counter uint u0)
(define-data-var minimum-stake uint u1000000) ;; 1 million micro-tokens
(define-data-var verification-duration uint u52560) ;; ~1 year in blocks

;; Data Maps
(define-map drivers principal {
    license-number: (string-ascii 50),
    license-expiry: uint,
    background-check: bool,
    verification-date: uint,
    verification-expiry: uint,
    stake-amount: uint,
    safety-rating: uint,
    total-trips: uint,
    violations: uint,
    status: (string-ascii 20)
})

(define-map vehicles (string-ascii 50) {
    owner: principal,
    make: (string-ascii 30),
    model: (string-ascii 30),
    year: uint,
    license-plate: (string-ascii 20),
    insurance-expiry: uint,
    last-inspection: uint,
    safety-rating: uint,
    capacity: uint,
    status: (string-ascii 20)
})

(define-map driver-vehicles principal (list 5 (string-ascii 50)))
(define-map verification-history uint {
    driver: principal,
    vehicle-id: (string-ascii 50),
    verifier: principal,
    verification-type: (string-ascii 30),
    result: bool,
    notes: (string-ascii 200),
    timestamp: uint
})

(define-map user-stakes principal uint)
(define-map safety-reports uint {
    reporter: principal,
    subject: principal,
    incident-type: (string-ascii 50),
    description: (string-ascii 300),
    severity: uint,
    resolved: bool,
    timestamp: uint
})

;; Driver Registration and Verification
(define-public (register-driver
    (license-number (string-ascii 50))
    (license-expiry uint)
    (stake-amount uint))
    (begin
        (asserts! (>= stake-amount (var-get minimum-stake)) ERR-INSUFFICIENT-STAKE)
        (asserts! (is-none (map-get? drivers tx-sender)) ERR-ALREADY-VERIFIED)

        ;; Store stake
        (map-set user-stakes tx-sender stake-amount)

        ;; Register driver
        (map-set drivers tx-sender {
            license-number: license-number,
            license-expiry: license-expiry,
            background-check: false,
            verification-date: u0,
            verification-expiry: u0,
            stake-amount: stake-amount,
            safety-rating: u5, ;; Start with perfect rating
            total-trips: u0,
            violations: u0,
            status: "pending"
        })

        (ok true)
    )
)

(define-public (verify-driver (driver principal) (background-check-passed bool))
    (let ((driver-data (unwrap! (map-get? drivers driver) ERR-DRIVER-NOT-FOUND)))
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

        (let ((verification-expiry (+ block-height (var-get verification-duration))))
            (map-set drivers driver (merge driver-data {
                background-check: background-check-passed,
                verification-date: block-height,
                verification-expiry: verification-expiry,
                status: (if background-check-passed "verified" "rejected")
            }))

            ;; Record verification history
            (let ((verification-id (+ (var-get verification-counter) u1)))
                (map-set verification-history verification-id {
                    driver: driver,
                    vehicle-id: "",
                    verifier: tx-sender,
                    verification-type: "background-check",
                    result: background-check-passed,
                    notes: "Initial driver verification",
                    timestamp: block-height
                })
                (var-set verification-counter verification-id)
            )

            (ok background-check-passed)
        )
    )
)

;; Vehicle Registration and Verification
(define-public (register-vehicle
    (vehicle-id (string-ascii 50))
    (make (string-ascii 30))
    (model (string-ascii 30))
    (year uint)
    (license-plate (string-ascii 20))
    (insurance-expiry uint)
    (capacity uint))
    (begin
        (asserts! (is-some (map-get? drivers tx-sender)) ERR-DRIVER-NOT-FOUND)
        (asserts! (is-none (map-get? vehicles vehicle-id)) ERR-ALREADY-VERIFIED)

        (map-set vehicles vehicle-id {
            owner: tx-sender,
            make: make,
            model: model,
            year: year,
            license-plate: license-plate,
            insurance-expiry: insurance-expiry,
            last-inspection: u0,
            safety-rating: u5,
            capacity: capacity,
            status: "pending"
        })

        ;; Add to driver's vehicle list
        (let ((driver-vehicle-list (default-to (list) (map-get? driver-vehicles tx-sender))))
            (map-set driver-vehicles tx-sender
                (unwrap-panic (as-max-len? (append driver-vehicle-list vehicle-id) u5)))
        )

        (ok true)
    )
)

(define-public (verify-vehicle (vehicle-id (string-ascii 50)) (inspection-passed bool))
    (let ((vehicle-data (unwrap! (map-get? vehicles vehicle-id) ERR-VEHICLE-NOT-FOUND)))
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

        (map-set vehicles vehicle-id (merge vehicle-data {
            last-inspection: block-height,
            status: (if inspection-passed "verified" "rejected")
        }))

        ;; Record verification history
        (let ((verification-id (+ (var-get verification-counter) u1)))
            (map-set verification-history verification-id {
                driver: (get owner vehicle-data),
                vehicle-id: vehicle-id,
                verifier: tx-sender,
                verification-type: "vehicle-inspection",
                result: inspection-passed,
                notes: "Vehicle safety inspection",
                timestamp: block-height
            })
            (var-set verification-counter verification-id)
        )

        (ok inspection-passed)
    )
)

;; Safety Rating and Reporting
(define-public (update-safety-rating (subject principal) (new-rating uint))
    (let ((driver-data (unwrap! (map-get? drivers subject) ERR-DRIVER-NOT-FOUND)))
        (asserts! (and (>= new-rating u1) (<= new-rating u5)) ERR-INVALID-RATING)
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

        (map-set drivers subject (merge driver-data {
            safety-rating: new-rating
        }))

        (ok true)
    )
)

(define-public (report-safety-incident
    (subject principal)
    (incident-type (string-ascii 50))
    (description (string-ascii 300))
    (severity uint))
    (let ((report-id (+ (var-get verification-counter) u1)))
        (asserts! (and (>= severity u1) (<= severity u5)) ERR-INVALID-RATING)

        (map-set safety-reports report-id {
            reporter: tx-sender,
            subject: subject,
            incident-type: incident-type,
            description: description,
            severity: severity,
            resolved: false,
            timestamp: block-height
        })

        ;; Update driver violations if it's a driver report
        (match (map-get? drivers subject)
            driver-data (map-set drivers subject (merge driver-data {
                violations: (+ (get violations driver-data) u1)
            }))
            true ;; Not a driver, continue
        )

        (var-set verification-counter report-id)
        (ok report-id)
    )
)

;; Trip Completion and Rating Update
(define-public (complete-trip (driver principal))
    (let ((driver-data (unwrap! (map-get? drivers driver) ERR-DRIVER-NOT-FOUND)))
        (map-set drivers driver (merge driver-data {
            total-trips: (+ (get total-trips driver-data) u1)
        }))
        (ok true)
    )
)

;; Stake Management
(define-public (increase-stake (additional-amount uint))
    (let ((current-stake (default-to u0 (map-get? user-stakes tx-sender)))
          (driver-data (unwrap! (map-get? drivers tx-sender) ERR-DRIVER-NOT-FOUND)))
        (map-set user-stakes tx-sender (+ current-stake additional-amount))
        (map-set drivers tx-sender (merge driver-data {
            stake-amount: (+ current-stake additional-amount)
        }))
        (ok true)
    )
)

(define-public (withdraw-stake (amount uint))
    (let ((current-stake (default-to u0 (map-get? user-stakes tx-sender)))
          (driver-data (unwrap! (map-get? drivers tx-sender) ERR-DRIVER-NOT-FOUND)))
        (asserts! (>= current-stake amount) ERR-INSUFFICIENT-STAKE)
        (asserts! (>= (- current-stake amount) (var-get minimum-stake)) ERR-INSUFFICIENT-STAKE)

        (map-set user-stakes tx-sender (- current-stake amount))
        (map-set drivers tx-sender (merge driver-data {
            stake-amount: (- current-stake amount)
        }))
        (ok true)
    )
)

;; Read-only Functions
(define-read-only (get-driver-info (driver principal))
    (map-get? drivers driver)
)

(define-read-only (get-vehicle-info (vehicle-id (string-ascii 50)))
    (map-get? vehicles vehicle-id)
)

(define-read-only (get-driver-vehicles (driver principal))
    (map-get? driver-vehicles driver)
)

(define-read-only (is-driver-verified (driver principal))
    (match (map-get? drivers driver)
        driver-data (and
            (is-eq (get status driver-data) "verified")
            (> (get verification-expiry driver-data) block-height))
        false
    )
)

(define-read-only (is-vehicle-verified (vehicle-id (string-ascii 50)))
    (match (map-get? vehicles vehicle-id)
        vehicle-data (is-eq (get status vehicle-data) "verified")
        false
    )
)

(define-read-only (get-safety-rating (driver principal))
    (match (map-get? drivers driver)
        driver-data (get safety-rating driver-data)
        u0
    )
)

(define-read-only (get-verification-history (verification-id uint))
    (map-get? verification-history verification-id)
)

(define-read-only (get-safety-report (report-id uint))
    (map-get? safety-reports report-id)
)

(define-read-only (get-user-stake (user principal))
    (default-to u0 (map-get? user-stakes user))
)

(define-read-only (get-minimum-stake)
    (var-get minimum-stake)
)
