BreederFinder Payments Server

This is a minimal Node/Express server to create PayMongo Payment Links and handle webhooks for subscription renewals using GCash (via PayMongo).

Setup
1. Create a .env file in this folder with the following keys:

   PAYMONGO_SECRET=sk_test_...   # Your PayMongo secret key
   SUPABASE_URL=https://your-supabase-url
   SUPABASE_SERVICE_KEY=your-service-role-key
   PORT=8080

2. Install dependencies:
   cd server && npm install

3. Start server:
   npm start

Endpoints
- POST /create-payment-link
  Body: { user_id, amount, currency, description, interval_days (optional), metadata }
  Returns: { id, url }

- POST /webhook
  Receives PayMongo webhook events. On link.payment.paid it will insert/update subscription in Supabase using the service role key.

Notes
- This is a minimal example. Add signature verification for webhooks and more robust error handling before production.
