-- Demo data. Every seeded account uses the password: password123
-- bcrypt hashes are produced by pgcrypto's crypt(); bcryptjs verifies $2a$ fine.

insert into hospitals (id, name, address, city, phone, lat, lng) values
  ('11111111-1111-1111-1111-111111111111',
   'City General Hospital', 'MG Road, Sector 5', 'Bhubaneswar', '+91-674-1000000',
   20.2961, 85.8245),
  ('22222222-2222-2222-2222-222222222222',
   'Sanjeevani Multispeciality', 'Patia Ring Road', 'Bhubaneswar', '+91-674-2000000',
   20.3499, 85.8197);

insert into departments (id, hospital_id, name, specialty) values
  ('aaaa0001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'General Medicine',  'general_medicine'),
  ('aaaa0002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Cardiology',        'cardiology'),
  ('aaaa0003-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'Orthopaedics',      'orthopaedics'),
  ('aaaa0004-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'Dermatology',       'dermatology'),
  ('aaaa0005-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111', 'Emergency',         'emergency'),
  ('bbbb0001-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'General Medicine',  'general_medicine'),
  ('bbbb0002-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'Paediatrics',       'paediatrics'),
  ('bbbb0003-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222', 'Emergency',         'emergency');

-- ---- staff -----------------------------------------------------------------

insert into users (id, email, password_hash, role, full_name) values
  ('d0c70001-0000-0000-0000-000000000001', 'admin@citygeneral.test',
   crypt('password123', gen_salt('bf', 10)), 'admin',  'Ritu Panda'),
  ('d0c70002-0000-0000-0000-000000000002', 'dr.mehta@citygeneral.test',
   crypt('password123', gen_salt('bf', 10)), 'doctor', 'Dr. Anil Mehta'),
  ('d0c70003-0000-0000-0000-000000000003', 'dr.rao@citygeneral.test',
   crypt('password123', gen_salt('bf', 10)), 'doctor', 'Dr. Sneha Rao'),
  ('d0c70004-0000-0000-0000-000000000004', 'dr.khan@citygeneral.test',
   crypt('password123', gen_salt('bf', 10)), 'doctor', 'Dr. Imran Khan');

insert into hospital_admins (user_id, hospital_id) values
  ('d0c70001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111');

insert into doctors (user_id, hospital_id, department_id, specialty, reg_no) values
  ('d0c70002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   'aaaa0001-0000-0000-0000-000000000001', 'general_medicine', 'OD-11021'),
  ('d0c70003-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111',
   'aaaa0002-0000-0000-0000-000000000002', 'cardiology',       'OD-11022'),
  ('d0c70004-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111',
   'aaaa0005-0000-0000-0000-000000000005', 'emergency',        'OD-11023');

-- ---- demo patient ----------------------------------------------------------

insert into users (id, email, password_hash, role, full_name) values
  ('9a7e0001-0000-0000-0000-000000000001', 'patient@demo.test',
   crypt('password123', gen_salt('bf', 10)), 'patient', 'Meera Sahoo');

insert into patients (user_id, dob, gender, blood_type, phone, address, lat, lng,
                      insurance_provider, policy_number, aadhaar_last4, aadhaar_verified,
                      language, profile_complete)
values ('9a7e0001-0000-0000-0000-000000000001', '1994-03-12', 'female', 'O+',
        '+91-9000000001', 'Flat 3B, Jaydev Vihar, Bhubaneswar', 20.2960, 85.8180,
        'Star Health', 'SH-77213345', '4821', true, 'en', true);

insert into patient_conditions (patient_id, kind, label, notes) values
  ('9a7e0001-0000-0000-0000-000000000001', 'disease', 'Type 2 diabetes', 'diagnosed 2021, on metformin'),
  ('9a7e0001-0000-0000-0000-000000000001', 'allergy', 'Penicillin', 'rash'),
  ('9a7e0001-0000-0000-0000-000000000001', 'genetic', 'Thalassemia minor', null);

insert into patient_relatives (patient_id, name, contact, relation) values
  ('9a7e0001-0000-0000-0000-000000000001', 'Ramesh Sahoo', '+91-9000000002', 'parent'),
  ('9a7e0001-0000-0000-0000-000000000001', 'Anita Sahoo',  '+91-9000000003', 'spouse');

insert into patient_preferred_hospitals (patient_id, hospital_id) values
  ('9a7e0001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111');

-- One waiting visit so the doctor queue is not empty on a fresh install.
insert into visits (patient_id, hospital_id, department_id, doctor_user_id,
                    token_no, urgency, status, reason)
values ('9a7e0001-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        'aaaa0001-0000-0000-0000-000000000001',
        'd0c70002-0000-0000-0000-000000000002',
        1, 3, 'waiting', 'Fever and body ache for three days');
