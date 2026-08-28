INSERT INTO doctors (hospital_id, name, specialty, available) VALUES
('a1b2c3d4-0000-0000-0000-000000000001', 'Dr. Ananya Sharma',    'Cardiology',             TRUE),
('a1b2c3d4-0000-0000-0000-000000000001', 'Dr. Rajeev Menon',     'Neurology',              TRUE),
('a1b2c3d4-0000-0000-0000-000000000001', 'Dr. Priya Iyer',       'Pulmonology',            TRUE),
('a1b2c3d4-0000-0000-0000-000000000001', 'Dr. Vikram Patel',     'Orthopedics',            TRUE),
('a1b2c3d4-0000-0000-0000-000000000001', 'Dr. Sneha Reddy',      'Gastroenterology',       TRUE),
('a1b2c3d4-0000-0000-0000-000000000001', 'Dr. Arjun Nair',       'General Medicine',       TRUE),
('a1b2c3d4-0000-0000-0000-000000000001', 'Dr. Meera Krishnan',   'Dermatology',            TRUE),
('a1b2c3d4-0000-0000-0000-000000000001', 'Dr. Sanjay Gupta',     'Emergency Medicine',     TRUE),
('a1b2c3d4-0000-0000-0000-000000000001', 'Dr. Kavitha Rao',      'ENT',                    TRUE),
('a1b2c3d4-0000-0000-0000-000000000001', 'Dr. Rohan Das',        'Psychiatry',             TRUE),
('a1b2c3d4-0000-0000-0000-000000000001', 'Dr. Lakshmi Venkat',   'Ophthalmology',          TRUE),
('a1b2c3d4-0000-0000-0000-000000000001', 'Dr. Aditya Joshi',     'Urology',                TRUE)
ON CONFLICT DO NOTHING;
