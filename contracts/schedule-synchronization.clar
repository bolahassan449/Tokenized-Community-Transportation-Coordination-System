;; Schedule Synchronization Contract
;; Coordinates pickup times and locations

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-SCHEDULE-NOT-FOUND (err u501))
(define-constant ERR-TIME-CONFLICT (err u502))
(define-constant ERR-INVALID-TIME (err u503))
(define-constant ERR-SCHEDULE-LOCKED (err u504))
(define-constant ERR-PARTICIPANT-NOT-FOUND (err u505))

;; Data Variables
(define-data-var schedule-counter uint u0)
(define-data-var notification-counter uint u0)

;; Data Maps
(define-map schedules uint {
    organizer: principal,
    title: (string-ascii 100),
    departure-time: uint,
    arrival-time: uint,
    pickup-location: (string-ascii 100),
    destination: (string-ascii 100),
    max-participants: uint,
    current-participants: uint,
    status: (string-ascii 20),
    locked: bool,
    created-at: uint
})

(define-map schedule-participants uint (list 20 {
    participant: principal,
    pickup-time: uint,
    pickup-location: (string-ascii 100),
    confirmed: bool,
    joined-at: uint
}))

(define-map user-schedules principal (list 50 uint))
(define-map time-slots uint (list 100 {
    schedule-id: uint,
    participant: principal,
    start-time: uint,
    end-time: uint
}))

(define-map notifications uint {
    recipient: principal,
    sender: principal,
    schedule-id: uint,
    message: (string-ascii 200),
    notification-type: (string-ascii 30),
    read: bool,
    timestamp: uint
})

(define-map user-notifications principal (list 100 uint))

;; Schedule Creation and Management
(define-public (create-schedule
    (title (string-ascii 100))
    (departure-time uint)
    (pickup-location (string-ascii 100))
    (destination (string-ascii 100))
    (max-participants uint))
    (let ((schedule-id (+ (var-get schedule-counter) u1))
          (estimated-arrival (+ departure-time u3600))) ;; Add 1 hour travel time
        (asserts! (> departure-time block-height) ERR-INVALID-TIME)
        (asserts! (> max-participants u0) ERR-INVALID-TIME)

        (map-set schedules schedule-id {
            organizer: tx-sender,
            title: title,
            departure-time: departure-time,
            arrival-time: estimated-arrival,
            pickup-location: pickup-location,
            destination: destination,
            max-participants: max-participants,
            current-participants: u1, ;; Organizer is first participant
            status: "active",
            locked: false,
            created-at: block-height
        })

        ;; Add organizer as first participant
        (map-set schedule-participants schedule-id (list {
            participant: tx-sender,
            pickup-time: departure-time,
            pickup-location: pickup-location,
            confirmed: true,
            joined-at: block-height
        }))

        ;; Add to user schedules
        (let ((user-schedule-list (default-to (list) (map-get? user-schedules tx-sender))))
            (map-set user-schedules tx-sender
                (unwrap-panic (as-max-len? (append user-schedule-list schedule-id) u50)))
        )

        (var-set schedule-counter schedule-id)
        (ok schedule-id)
    )
)

;; Join Schedule
(define-public (join-schedule
    (schedule-id uint)
    (preferred-pickup-time uint)
    (pickup-location (string-ascii 100)))
    (let ((schedule-data (unwrap! (map-get? schedules schedule-id) ERR-SCHEDULE-NOT-FOUND))
          (current-participants (default-to (list) (map-get? schedule-participants schedule-id))))
        (asserts! (not (get locked schedule-data)) ERR-SCHEDULE-LOCKED)
        (asserts! (< (get current-participants schedule-data) (get max-participants schedule-data)) ERR-TIME-CONFLICT)
        (asserts! (is-eq (get status schedule-data) "active") ERR-SCHEDULE-LOCKED)
        (asserts! (> preferred-pickup-time block-height) ERR-INVALID-TIME)

        ;; Check for time conflicts
        (asserts! (check-time-availability preferred-pickup-time tx-sender) ERR-TIME-CONFLICT)

        ;; Add participant
        (map-set schedule-participants schedule-id
            (unwrap-panic (as-max-len? (append current-participants {
                participant: tx-sender,
                pickup-time: preferred-pickup-time,
                pickup-location: pickup-location,
                confirmed: false,
                joined-at: block-height
            }) u20)))

        ;; Update schedule
        (map-set schedules schedule-id (merge schedule-data {
            current-participants: (+ (get current-participants schedule-data) u1)
        }))

        ;; Add to user schedules
        (let ((user-schedule-list (default-to (list) (map-get? user-schedules tx-sender))))
            (map-set user-schedules tx-sender
                (unwrap-panic (as-max-len? (append user-schedule-list schedule-id) u50)))
        )

        ;; Notify organizer
        (unwrap-panic (send-notification
            (get organizer schedule-data)
            schedule-id
            "New participant joined your schedule"
            "join"))

        (ok true)
    )
)

;; Confirm Participation
(define-public (confirm-participation (schedule-id uint))
    (let ((schedule-data (unwrap! (map-get? schedules schedule-id) ERR-SCHEDULE-NOT-FOUND))
          (participants (default-to (list) (map-get? schedule-participants schedule-id))))
        (asserts! (not (get locked schedule-data)) ERR-SCHEDULE-LOCKED)

        ;; Update participant confirmation
        (map-set schedule-participants schedule-id
            (map update-participant-confirmation participants))

        (ok true)
    )
)

;; Update Schedule Time
(define-public (update-schedule-time (schedule-id uint) (new-departure-time uint))
    (let ((schedule-data (unwrap! (map-get? schedules schedule-id) ERR-SCHEDULE-NOT-FOUND)))
        (asserts! (is-eq tx-sender (get organizer schedule-data)) ERR-NOT-AUTHORIZED)
        (asserts! (not (get locked schedule-data)) ERR-SCHEDULE-LOCKED)
        (asserts! (> new-departure-time block-height) ERR-INVALID-TIME)

        (map-set schedules schedule-id (merge schedule-data {
            departure-time: new-departure-time,
            arrival-time: (+ new-departure-time u3600)
        }))

        ;; Notify all participants
        (let ((participants (default-to (list) (map-get? schedule-participants schedule-id))))
            (map notify-participant-of-change participants)
        )

        (ok true)
    )
)

;; Lock Schedule
(define-public (lock-schedule (schedule-id uint))
    (let ((schedule-data (unwrap! (map-get? schedules schedule-id) ERR-SCHEDULE-NOT-FOUND)))
        (asserts! (is-eq tx-sender (get organizer schedule-data)) ERR-NOT-AUTHORIZED)
        (asserts! (not (get locked schedule-data)) ERR-SCHEDULE-LOCKED)

        (map-set schedules schedule-id (merge schedule-data {locked: true}))

        ;; Notify all participants
        (let ((participants (default-to (list) (map-get? schedule-participants schedule-id))))
            (map notify-participant-of-lock participants)
        )

        (ok true)
    )
)

;; Complete Schedule
(define-public (complete-schedule (schedule-id uint))
    (let ((schedule-data (unwrap! (map-get? schedules schedule-id) ERR-SCHEDULE-NOT-FOUND)))
        (asserts! (is-eq tx-sender (get organizer schedule-data)) ERR-NOT-AUTHORIZED)

        (map-set schedules schedule-id (merge schedule-data {status: "completed"}))
        (ok true)
    )
)

;; Notification System
(define-public (send-notification
    (recipient principal)
    (schedule-id uint)
    (message (string-ascii 200))
    (notification-type (string-ascii 30)))
    (let ((notification-id (+ (var-get notification-counter) u1)))
        (map-set notifications notification-id {
            recipient: recipient,
            sender: tx-sender,
            schedule-id: schedule-id,
            message: message,
            notification-type: notification-type,
            read: false,
            timestamp: block-height
        })

        ;; Add to user notifications
        (let ((user-notification-list (default-to (list) (map-get? user-notifications recipient))))
            (map-set user-notifications recipient
                (unwrap-panic (as-max-len? (append user-notification-list notification-id) u100)))
        )

        (var-set notification-counter notification-id)
        (ok notification-id)
    )
)

(define-public (mark-notification-read (notification-id uint))
    (let ((notification-data (unwrap! (map-get? notifications notification-id) ERR-SCHEDULE-NOT-FOUND)))
        (asserts! (is-eq tx-sender (get recipient notification-data)) ERR-NOT-AUTHORIZED)

        (map-set notifications notification-id (merge notification-data {read: true}))
        (ok true)
    )
)

;; Helper Functions
(define-private (check-time-availability (time uint) (user principal))
    ;; Simplified availability check - in reality would check against all user schedules
    (> time block-height)
)

(define-private (update-participant-confirmation (participant {participant: principal, pickup-time: uint, pickup-location: (string-ascii 100), confirmed: bool, joined-at: uint}))
    (if (is-eq (get participant participant) tx-sender)
        (merge participant {confirmed: true})
        participant
    )
)

(define-private (notify-participant-of-change (participant {participant: principal, pickup-time: uint, pickup-location: (string-ascii 100), confirmed: bool, joined-at: uint}))
    (unwrap-panic (send-notification
        (get participant participant)
        u0 ;; Would need proper schedule-id in real implementation
        "Schedule time has been updated"
        "update"))
)

(define-private (notify-participant-of-lock (participant {participant: principal, pickup-time: uint, pickup-location: (string-ascii 100), confirmed: bool, joined-at: uint}))
    (unwrap-panic (send-notification
        (get participant participant)
        u0 ;; Would need proper schedule-id in real implementation
        "Schedule has been locked"
        "lock"))
)

;; Read-only Functions
(define-read-only (get-schedule (schedule-id uint))
    (map-get? schedules schedule-id)
)

(define-read-only (get-schedule-participants (schedule-id uint))
    (map-get? schedule-participants schedule-id)
)

(define-read-only (get-user-schedules (user principal))
    (map-get? user-schedules user)
)

(define-read-only (get-user-notifications (user principal))
    (map-get? user-notifications user)
)

(define-read-only (get-notification (notification-id uint))
    (map-get? notifications notification-id)
)

(define-read-only (get-active-schedules-count)
    (var-get schedule-counter)
)

(define-read-only (check-schedule-conflicts (user principal) (start-time uint) (end-time uint))
    ;; Simplified conflict check
    (and (> start-time block-height) (> end-time start-time))
)

(define-read-only (get-schedule-status (schedule-id uint))
    (match (map-get? schedules schedule-id)
        schedule-data {
            status: (get status schedule-data),
            locked: (get locked schedule-data),
            participants: (get current-participants schedule-data),
            max-participants: (get max-participants schedule-data)
        }
        {status: "not-found", locked: false, participants: u0, max-participants: u0}
    )
)
