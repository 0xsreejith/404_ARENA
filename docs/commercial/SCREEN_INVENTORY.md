# Arena OS — Screen Inventory (Figma-level)

**Naming:** `S-{SURFACE}-{MODULE}-{NN}`  
**Parity:** Staff screens must match Lobby HTML; Owner Web match W* frames.

Wireframe fidelity: layout regions, key components, states, empty/error/loading — sufficient to build Figma frames 1:1.

---

## A. Staff Flutter (`S-STF-*`)

### Auth
| ID | Screen | States |
|---|---|---|
| S-STF-AUTH-01 | PIN unlock | empty, error, success |
| S-STF-AUTH-02 | Email login | validation, auth error |
| S-STF-AUTH-03 | MFA challenge | |
| S-STF-AUTH-04 | QR login | |

### Shell
| ID | Screen |
|---|---|
| S-STF-SHELL-01 | Floor mode shell (sidebar+header) |
| S-STF-SHELL-02 | Manage/BOH mode shell |
| S-STF-SHELL-03 | Branch selector |
| S-STF-SHELL-04 | Connectivity banners |

### Floor
| ID | Screen |
|---|---|
| S-STF-FLR-01 | Live floor grid |
| S-STF-FLR-02 | Live floor map |
| S-STF-FLR-03 | Start session dialog |
| S-STF-FLR-04 | Active session dialog |
| S-STF-FLR-05 | Bill / checkout dialog |
| S-STF-FLR-06 | Time-up alert |
| S-STF-FLR-07 | Parked alert bubbles |
| S-STF-FLR-08 | Unbilled queue |

### Members / CRM
| ID | Screen |
|---|---|
| S-STF-MEM-01 | Members table |
| S-STF-MEM-02 | Member profile |
| S-STF-MEM-03 | Add/edit member |
| S-STF-MEM-04 | Timeline |

### Inventory
| ID | Screen |
|---|---|
| S-STF-INV-01 | Stock actions |
| S-STF-INV-02 | Product table |
| S-STF-INV-03 | Adjust / receive |
| S-STF-INV-04 | Barcode scan |

### Shift / more
| ID | Screen |
|---|---|
| S-STF-SHF-01 | Shift dashboard |
| S-STF-SHF-02 | Close shift |
| S-STF-RPT-01 | Manager reports |
| S-STF-SET-01 | Settings subset |
| S-STF-SYN-01 | Sync Issues |
| S-STF-MNT-01 | Maintenance list |
| S-STF-BKG-01 | Bookings day board |

---

## B. Customer Flutter (`S-CUS-*`)

S-CUS-AUTH-01 Register · 02 OTP · 03 Biometric  
S-CUS-HOME-01 Home availability  
S-CUS-BKG-01 Book · 02 Confirm · 03 My bookings  
S-CUS-WAL-01 Wallet · 02 Top-up  
S-CUS-MEM-01 Memberships  
S-CUS-REW-01 Rewards  
S-CUS-INV-01 Invoices  
S-CUS-SUP-01 Support  
S-CUS-PRF-01 Profile  

---

## C. Owner Web (`S-OWN-*`)

Mirror WEBNAV: one primary list/detail per module.

| ID | Module |
|---|---|
| S-OWN-DSH-01 | Dashboard KPIs |
| S-OWN-FLR-01 | Live floor |
| S-OWN-STN-01..03 | Stations list, editor, bulk |
| S-OWN-LAY-01 | Floor layout drag-drop |
| S-OWN-SES-01 | Session history |
| S-OWN-CHK-01 | Checkout queue |
| S-OWN-BKG-01 | Booking calendar |
| S-OWN-MEM-01..04 | Members CRM |
| S-OWN-MBR-01 | Membership plans |
| S-OWN-LOY-01 | Loyalty |
| S-OWN-WLT-01 | Wallet admin |
| S-OWN-GAM-01 | Games library |
| S-OWN-INV-01..05 | Inventory, PO, suppliers, transfers |
| S-OWN-PRC-01 | Pricing & packages |
| S-OWN-TAX-01 | Tax rates |
| S-OWN-EXP-01 | Expenses |
| S-OWN-STF-01 | Staff & roles matrix |
| S-OWN-RPT-01..12 | Each report |
| S-OWN-ANL-01 | Analytics |
| S-OWN-TRN-01 | Tournaments |
| S-OWN-EVT-01 | Events |
| S-OWN-MKT-01 | Campaigns |
| S-OWN-INT-01 | Integrations |
| S-OWN-AUD-01 | Audit log |
| S-OWN-SET-01 | Settings hub |
| S-OWN-BRN-01 | Branding |
| S-OWN-BRC-01 | Branches |
| S-OWN-DEV-01 | Devices |
| S-OWN-NTF-01 | Notification templates |

---

## D. Super Admin (`S-ADM-*`)

S-ADM-TEN-01 Tenants · S-ADM-SUB-01 Subscriptions · S-ADM-PLN-01 Plans · S-ADM-INV-01 Invoices · S-ADM-FLG-01 Flags · S-ADM-DOM-01 Domains · S-ADM-USG-01 Usage · S-ADM-SUP-01 Support · S-ADM-IMP-01 Impersonation · S-ADM-HLT-01 Health  

---

## E. Website (`S-WEB-*`)

Home · Features · Pricing · Industries · Demo · Legal  

---

## F. Portal (`S-POR-*`)

Parity with Customer app routes for desktop.

---

## Wireframe checklist (every screen)

- [ ] Header / nav  
- [ ] Primary action  
- [ ] Empty state  
- [ ] Loading  
- [ ] Error  
- [ ] Permission denied  
- [ ] Offline (staff)  
- [ ] Responsive breakpoints (phone/tablet/desktop as applicable)
