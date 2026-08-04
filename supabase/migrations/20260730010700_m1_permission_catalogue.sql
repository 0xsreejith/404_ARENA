-- M1 — the P0 permission catalogue.
--
-- The complete set of 33 codes from PERMISSIONS.md §1. A code not listed there
-- does not exist yet. Adding one is an ordinary migration, and it grants
-- nothing until a role references it.
--
-- This is global reference data, not tenant data: it belongs in a migration,
-- unlike roles and role_permissions, which provision_arena creates per arena.
--
-- The post-MVP names in PERMISSIONS.md §4 are deliberately NOT seeded, so they
-- cannot be reintroduced later with a different spelling.

insert into public.permissions (code, description, category) values
  -- Sessions
  ('session.view',       'See the floor and session details',                          'sessions'),
  ('session.start',      'Start a session',                                            'sessions'),
  ('session.pause',      'Pause a running session',                                    'sessions'),
  ('session.resume',     'Resume a paused session',                                    'sessions'),
  ('session.extend',     'Add a package block to a fixed-duration session',            'sessions'),
  ('session.stop',       'Stop a session and open its checkout',                       'sessions'),
  ('session.cancel',     'Cancel a session without billing; also discard a failed offline operation',
                                                                                       'sessions'),
  -- Stations
  ('station.view',        'See stations',                                              'stations'),
  ('station.update',      'Edit station name, zone, type, capacity',                   'stations'),
  ('station.maintenance', 'Mark a station maintenance or inactive',                    'stations'),

  -- Members
  ('member.view',   'Search and view members',    'members'),
  ('member.create', 'Create a member',            'members'),
  ('member.update', 'Edit member details',        'members'),
  ('member.block',  'Block or unblock a member',  'members'),

  -- Products and inventory
  ('product.view',       'See products and prices',                        'products_inventory'),
  ('product.manage',     'Create and edit products',                       'products_inventory'),
  ('inventory.view',     'See current stock and movements',                'products_inventory'),
  ('inventory.sell',     'Add products to an order; open a counter sale',  'products_inventory'),
  ('inventory.adjust',   'Wastage, staff use, breakage, correction',       'products_inventory'),
  ('inventory.receive',  'Restock and opening stock',                      'products_inventory'),

  -- Checkout and money
  ('payment.create', 'Settle an order and record payment',                 'checkout_money'),
  ('payment.view',   'See payments and order history',                     'checkout_money'),
  ('discount.apply', 'Apply an order discount; holding this code is the authorisation',
                                                                           'checkout_money'),
  ('order.void',     'Void an unsettled order',                            'checkout_money'),

  -- Shift
  ('shift.view',  'See the current shift and its summary',   'shift'),
  ('shift.open',  'Open a shift',                            'shift'),
  ('shift.close', 'Close a shift and record counted cash',   'shift'),

  -- Reporting
  ('report.view', 'Shift summaries and the audit log, including session timelines', 'reporting'),

  -- Administration
  ('arena.settings',     'Arena settings, zones, station types, stations, games',   'administration'),
  ('pricing.manage',     'Billing plans, tax rates and their components, tax defaults, receipt numbering settings, tax-inclusive mode',
                                                                                    'administration'),
  ('staff.view',         'See who works here',                                      'administration'),
  ('staff.manage',       'Invite, deactivate, and assign roles to staff',           'administration'),
  ('permissions.manage', 'Edit roles and their permission sets',                    'administration');
