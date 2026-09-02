INSERT INTO clients (name, country_of_birth)
VALUES
  ('Alice Morgan', 'Canada'),
  ('Alex Wilber', 'United States'),
  ('Benjamin Lee', 'United States'),
  ('Chloe Martin', 'France'),
  ('David Nguyen', 'Vietnam'),
  ('Emma Patel', 'India')
ON CONFLICT (name) DO UPDATE
SET country_of_birth = EXCLUDED.country_of_birth;

INSERT INTO client_sensitive_data (
  name,
  email_address,
  social_insurance_number,
  credit_card_information
)
VALUES
  ('Alice Morgan', 'alice.morgan@example.test', '123-456-789', '4111 1111 1111 1111 | 12/29'),
  ('Alex Wilber', 'AlexW@ciscrypt.info', '987-654-321', '5555 2341 5555 4444 | 07/28'),
  ('Benjamin Lee', 'benjamin.lee@example.test', '987-654-321', '5555 5555 5555 4444 | 07/28'),
  ('Chloe Martin', 'chloe.martin@example.test', '246-810-121', '4000 0566 5566 5556 | 03/30'),
  ('David Nguyen', 'david.nguyen@example.test', '135-791-113', '6011 0009 9013 9424 | 10/27'),
  ('Emma Patel', 'emma.patel@example.test', '314-159-265', '3530 1113 3330 0000 | 05/31')
ON CONFLICT (name) DO UPDATE
SET
  email_address = EXCLUDED.email_address,
  social_insurance_number = EXCLUDED.social_insurance_number,
  credit_card_information = EXCLUDED.credit_card_information;
