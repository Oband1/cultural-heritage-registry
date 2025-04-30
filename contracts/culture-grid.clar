;; culture-grid
;; A smart contract for managing the registration and ownership of cultural heritage assets

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ENTRY-ALREADY-EXISTS (err u101))
(define-constant ERR-ENTRY-NOT-FOUND (err u102))
(define-constant ERR-NOT-OWNER (err u103))
(define-constant ERR-INVALID-PERMISSION (err u104))
(define-constant ERR-INVALID-REPRESENTATIVE (err u105))
(define-constant ERR-VERIFICATION-REQUIRED (err u106))
(define-constant ERR-COMMUNITY-NOT-REGISTERED (err u107))

;; Data maps and variables

;; Tracks registered cultural communities and their authorized representatives
(define-map communities
  { community-id: (string-ascii 50) }
  { 
    name: (string-utf8 100), 
    description: (string-utf8 500),
    region: (string-ascii 100),
    creation-time: uint,
    admin: principal
  }
)

;; Maps representatives to their communities
(define-map community-representatives
  { representative: principal, community-id: (string-ascii 50) }
  { is-authorized: bool, verification-status: bool }
)

;; Stores cultural heritage entries
(define-map cultural-entries
  { entry-id: (string-ascii 50) }
  {
    title: (string-utf8 100),
    description: (string-utf8 1000),
    community-id: (string-ascii 50),
    geographic-origin: (string-utf8 100),
    creation-date: (optional (string-ascii 30)),
    significance: (string-utf8 1000),
    media-links: (list 10 (string-utf8 256)),
    created-at: uint,
    updated-at: uint,
    owner: principal,
    creator: principal
  }
)

;; Tracks permissions for cultural entries
(define-map entry-permissions
  { entry-id: (string-ascii 50) }
  {
    is-public: bool,
    allowed-uses: (list 10 (string-ascii 30)),
    restricted-uses: (list 10 (string-ascii 30)),
    requires-attribution: bool
  }
)

;; Maps entries to categories and tags for discovery
(define-map entry-categories
  { entry-id: (string-ascii 50) }
  {
    primary-category: (string-ascii 50),
    secondary-categories: (list 5 (string-ascii 50)),
    tags: (list 20 (string-ascii 30))
  }
)

;; Tracks collaborators for an entry
(define-map entry-collaborators
  { entry-id: (string-ascii 50), collaborator: principal }
  { role: (string-ascii 30), permissions: (list 5 (string-ascii 30)) }
)

;; Counter for total entries
(define-data-var total-entries uint u0)

;; Private functions

;; Check if the principal is an authorized representative for a community
(define-private (is-authorized-representative (community-id (string-ascii 50)) (representative principal))
  (match (map-get? community-representatives { representative: representative, community-id: community-id })
    rep (and (get is-authorized rep) (get verification-status rep))
    false
  )
)

;; Check if principal is the owner of an entry
(define-private (is-entry-owner (entry-id (string-ascii 50)) (user principal))
  (match (map-get? cultural-entries { entry-id: entry-id })
    entry (is-eq (get owner entry) user)
    false
  )
)

;; Check if principal is a community admin
(define-private (is-community-admin (community-id (string-ascii 50)) (user principal))
  (match (map-get? communities { community-id: community-id })
    community (is-eq (get admin community) user)
    false
  )
)

;; Check if community exists
(define-private (is-community-registered (community-id (string-ascii 50)))
  (is-some (map-get? communities { community-id: community-id }))
)

;; Read-only functions

;; Get community details
(define-read-only (get-community (community-id (string-ascii 50)))
  (map-get? communities { community-id: community-id })
)

;; Get representative status
(define-read-only (get-representative-status (representative principal) (community-id (string-ascii 50)))
  (map-get? community-representatives { representative: representative, community-id: community-id })
)

;; Get cultural entry details
(define-read-only (get-cultural-entry (entry-id (string-ascii 50)))
  (map-get? cultural-entries { entry-id: entry-id })
)

;; Get entry permissions
(define-read-only (get-entry-permissions (entry-id (string-ascii 50)))
  (map-get? entry-permissions { entry-id: entry-id })
)

;; Get entry categories and tags
(define-read-only (get-entry-categories (entry-id (string-ascii 50)))
  (map-get? entry-categories { entry-id: entry-id })
)

;; Get entry collaborator details
(define-read-only (get-entry-collaborator (entry-id (string-ascii 50)) (collaborator principal))
  (map-get? entry-collaborators { entry-id: entry-id, collaborator: collaborator })
)

;; Get total entries count
(define-read-only (get-total-entries)
  (var-get total-entries)
)

;; Public functions

;; Register a new community
(define-public (register-community (community-id (string-ascii 50)) (name (string-utf8 100)) (description (string-utf8 500)) (region (string-ascii 100)))
  (let ((admin tx-sender))
    (asserts! (not (is-community-registered community-id)) ERR-ENTRY-ALREADY-EXISTS)
    
    ;; Store community data
    (map-set communities 
      { community-id: community-id }
      { 
        name: name, 
        description: description,
        region: region,
        creation-time: block-height,
        admin: admin
      }
    )
    
    ;; Register admin as verified representative
    (map-set community-representatives
      { representative: admin, community-id: community-id }
      { is-authorized: true, verification-status: true }
    )
    
    (ok true)
  )
)

;; Add a representative to community
(define-public (add-community-representative (community-id (string-ascii 50)) (representative principal) (verified bool))
  (begin
    (asserts! (is-community-registered community-id) ERR-COMMUNITY-NOT-REGISTERED)
    (asserts! (is-community-admin community-id tx-sender) ERR-NOT-AUTHORIZED)
    
    (map-set community-representatives
      { representative: representative, community-id: community-id }
      { is-authorized: true, verification-status: verified }
    )
    
    (ok true)
  )
)

;; Remove representative from community
(define-public (remove-community-representative (community-id (string-ascii 50)) (representative principal))
  (begin
    (asserts! (is-community-registered community-id) ERR-COMMUNITY-NOT-REGISTERED)
    (asserts! (is-community-admin community-id tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-eq representative tx-sender)) ERR-NOT-AUTHORIZED) ;; Can't remove yourself
    
    (map-delete community-representatives { representative: representative, community-id: community-id })
    
    (ok true)
  )
)

;; Register new cultural heritage entry
(define-public (register-cultural-entry
  (entry-id (string-ascii 50))
  (title (string-utf8 100))
  (description (string-utf8 1000))
  (community-id (string-ascii 50))
  (geographic-origin (string-utf8 100))
  (creation-date (optional (string-ascii 30)))
  (significance (string-utf8 1000))
  (media-links (list 10 (string-utf8 256)))
  (is-public bool)
  (allowed-uses (list 10 (string-ascii 30)))
  (restricted-uses (list 10 (string-ascii 30)))
  (requires-attribution bool)
  (primary-category (string-ascii 50))
  (secondary-categories (list 5 (string-ascii 50)))
  (tags (list 20 (string-ascii 30))))
  
  (let ((creator tx-sender) (current-time block-height))
    ;; Validate input - creator must be an authorized representative
    (asserts! (is-community-registered community-id) ERR-COMMUNITY-NOT-REGISTERED)
    (asserts! (is-authorized-representative community-id creator) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-some (map-get? cultural-entries { entry-id: entry-id }))) ERR-ENTRY-ALREADY-EXISTS)
    
    ;; Store the cultural entry
    (map-set cultural-entries
      { entry-id: entry-id }
      {
        title: title,
        description: description,
        community-id: community-id,
        geographic-origin: geographic-origin,
        creation-date: creation-date,
        significance: significance,
        media-links: media-links,
        created-at: current-time,
        updated-at: current-time,
        owner: creator,
        creator: creator
      }
    )
    
    ;; Set permissions
    (map-set entry-permissions
      { entry-id: entry-id }
      {
        is-public: is-public,
        allowed-uses: allowed-uses,
        restricted-uses: restricted-uses,
        requires-attribution: requires-attribution
      }
    )
    
    ;; Set categories
    (map-set entry-categories
      { entry-id: entry-id }
      {
        primary-category: primary-category,
        secondary-categories: secondary-categories,
        tags: tags
      }
    )
    
    ;; Increment total entries counter
    (var-set total-entries (+ (var-get total-entries) u1))
    
    (ok true)
  )
)

;; Update an existing cultural entry
(define-public (update-cultural-entry
  (entry-id (string-ascii 50))
  (title (string-utf8 100))
  (description (string-utf8 1000))
  (geographic-origin (string-utf8 100))
  (creation-date (optional (string-ascii 30)))
  (significance (string-utf8 1000))
  (media-links (list 10 (string-utf8 256))))
  
  (let ((editor tx-sender) (current-time block-height))
    ;; Ensure entry exists
    (match (map-get? cultural-entries { entry-id: entry-id })
      entry
      (begin
        ;; Validate editor is either the owner or a collaborator
        (asserts! (or 
                    (is-entry-owner entry-id editor)
                    (is-some (map-get? entry-collaborators { entry-id: entry-id, collaborator: editor }))
                  ) 
                  ERR-NOT-AUTHORIZED)
        
        ;; Update the entry
        (map-set cultural-entries
          { entry-id: entry-id }
          {
            title: title,
            description: description,
            community-id: (get community-id entry),
            geographic-origin: geographic-origin,
            creation-date: creation-date,
            significance: significance,
            media-links: media-links,
            created-at: (get created-at entry),
            updated-at: current-time,
            owner: (get owner entry),
            creator: (get creator entry)
          }
        )
        
        (ok true)
      )
      ERR-ENTRY-NOT-FOUND
    )
  )
)

;; Update entry permissions
(define-public (update-entry-permissions
  (entry-id (string-ascii 50))
  (is-public bool)
  (allowed-uses (list 10 (string-ascii 30)))
  (restricted-uses (list 10 (string-ascii 30)))
  (requires-attribution bool))
  
  (begin
    ;; Validate owner
    (asserts! (is-entry-owner entry-id tx-sender) ERR-NOT-OWNER)
    
    ;; Update permissions
    (map-set entry-permissions
      { entry-id: entry-id }
      {
        is-public: is-public,
        allowed-uses: allowed-uses,
        restricted-uses: restricted-uses,
        requires-attribution: requires-attribution
      }
    )
    
    (ok true)
  )
)

;; Add a collaborator to an entry
(define-public (add-entry-collaborator
  (entry-id (string-ascii 50))
  (collaborator principal)
  (role (string-ascii 30))
  (permissions (list 5 (string-ascii 30))))
  
  (begin
    ;; Ensure entry exists and sender is the owner
    (asserts! (is-some (map-get? cultural-entries { entry-id: entry-id })) ERR-ENTRY-NOT-FOUND)
    (asserts! (is-entry-owner entry-id tx-sender) ERR-NOT-OWNER)
    
    ;; Add collaborator
    (map-set entry-collaborators
      { entry-id: entry-id, collaborator: collaborator }
      { role: role, permissions: permissions }
    )
    
    (ok true)
  )
)

;; Remove a collaborator from an entry
(define-public (remove-entry-collaborator
  (entry-id (string-ascii 50))
  (collaborator principal))
  
  (begin
    ;; Ensure entry exists and sender is the owner
    (asserts! (is-some (map-get? cultural-entries { entry-id: entry-id })) ERR-ENTRY-NOT-FOUND)
    (asserts! (is-entry-owner entry-id tx-sender) ERR-NOT-OWNER)
    
    ;; Remove collaborator
    (map-delete entry-collaborators { entry-id: entry-id, collaborator: collaborator })
    
    (ok true)
  )
)

;; Transfer entry ownership
(define-public (transfer-entry-ownership
  (entry-id (string-ascii 50))
  (new-owner principal))
  
  (let ((current-time block-height))
    ;; Ensure entry exists and sender is the owner
    (match (map-get? cultural-entries { entry-id: entry-id })
      entry
      (begin
        (asserts! (is-eq (get owner entry) tx-sender) ERR-NOT-OWNER)
        
        ;; Update owner
        (map-set cultural-entries
          { entry-id: entry-id }
          {
            title: (get title entry),
            description: (get description entry),
            community-id: (get community-id entry),
            geographic-origin: (get geographic-origin entry),
            creation-date: (get creation-date entry),
            significance: (get significance entry),
            media-links: (get media-links entry),
            created-at: (get created-at entry),
            updated-at: current-time,
            owner: new-owner,
            creator: (get creator entry)
          }
        )
        
        (ok true)
      )
      ERR-ENTRY-NOT-FOUND
    )
  )
)

;; Update entry categories and tags
(define-public (update-entry-categories
  (entry-id (string-ascii 50))
  (primary-category (string-ascii 50))
  (secondary-categories (list 5 (string-ascii 50)))
  (tags (list 20 (string-ascii 30))))
  
  (begin
    ;; Ensure entry exists and sender has permission
    (asserts! (is-some (map-get? cultural-entries { entry-id: entry-id })) ERR-ENTRY-NOT-FOUND)
    (asserts! (or 
                (is-entry-owner entry-id tx-sender)
                (is-some (map-get? entry-collaborators { entry-id: entry-id, collaborator: tx-sender }))
              ) 
              ERR-NOT-AUTHORIZED)
    
    ;; Update categories
    (map-set entry-categories
      { entry-id: entry-id }
      {
        primary-category: primary-category,
        secondary-categories: secondary-categories,
        tags: tags
      }
    )
    
    (ok true)
  )
)