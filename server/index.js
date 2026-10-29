const express = require('express');
const bodyParser = require('body-parser');
const axios = require('axios');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(bodyParser.json());

const PAYMONGO_SECRET = process.env.PAYMONGO_SECRET;
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;
const PORT = process.env.PORT || 8080;

if (!PAYMONGO_SECRET) {
  console.error('ERROR: PAYMONGO_SECRET environment variable is required');
  // do not exit so developer can still inspect code; but warn strongly
}

function authHeader() {
  // axios supports basic auth via the auth option, but construct header for clarity
  const token = Buffer.from(`${PAYMONGO_SECRET}:`).toString('base64');
  return `Basic ${token}`;
}

app.get('/health', (req, res) => res.json({ ok: true }));

// Create a payment link for a given user/subscription
app.post('/create-payment-link', async (req, res) => {
  try {
    const { user_id, amount, currency = 'PHP', description = 'Subscription', interval_days = null, metadata = {} } = req.body;

    if (!user_id || !amount) {
      return res.status(400).json({ error: 'user_id and amount are required' });
    }

    // include subscription details in metadata so webhook can map the payment
    const body = {
      amount: amount,
      currency: currency,
      description: description,
      metadata: { ...metadata, user_id },
    };

    const resp = await axios.post('https://api.paymongo.com/v1/payment_links', body, {
      headers: {
        'Authorization': authHeader(),
        'Content-Type': 'application/json',
      },
    });

    const data = resp.data.data || resp.data;
    const link = {
      id: data.id,
      url: data.url || data.checkout_url || data.attributes?.checkout_url,
      amount: data.amount || body.amount,
      currency: data.currency || body.currency,
    };

    return res.json(link);
  } catch (err) {
    console.error('create-payment-link error', err?.response?.data || err.message);
    return res.status(500).json({ error: err?.response?.data || err.message });
  }
});

// Webhook endpoint for PayMongo
app.post('/webhook', async (req, res) => {
  try {
    const event = req.body;
    console.log('Webhook event received:', JSON.stringify(event).slice(0, 600));

    const type = event?.type || event?.data?.type;

    // Handle link payment paid event
    if (type === 'link.payment.paid' || type === 'link.payment.created' || type === 'payment.paid') {
      // Extract payment and metadata information
      const payment = event.data?.attributes || event.data || {};
      const link = event.data?.attributes?.link || event.data?.attributes?.payment?.link || {};
      const metadata = event.data?.attributes?.metadata || event.data?.attributes?.link?.metadata || event.data?.attributes?.payment?.metadata || {};

      const user_id = metadata?.user_id;
      const amount = payment?.amount || event.data?.attributes?.amount || null;

      if (user_id && SUPABASE_URL && SUPABASE_SERVICE_KEY) {
        try {
          // Insert a new subscription record into Supabase subscriptions table or update existing
          const expiresAt = new Date();
          // Default add 30 days; if metadata provides interval_days, use it
          const intervalDays = parseInt(metadata?.interval_days || '30', 10);
          expiresAt.setDate(expiresAt.getDate() + intervalDays);

          const insertBody = [
            {
              user_id: user_id,
              plan_name: metadata?.plan_name || 'Renewal',
              amount: (amount || 0) / 100.0,
              expires_at: expiresAt.toISOString(),
            },
          ];

          await axios.post(`${SUPABASE_URL}/rest/v1/subscriptions`, insertBody, {
            headers: {
              'apikey': SUPABASE_SERVICE_KEY,
              'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
              'Content-Type': 'application/json',
              'Prefer': 'return=representation',
            },
          });

          console.log('Supabase updated for user', user_id);
        } catch (supErr) {
          console.error('Error updating Supabase from webhook:', supErr?.response?.data || supErr.message);
        }
      } else {
        console.log('Skipping Supabase update: missing user_id or Supabase credentials');
      }
    }

    // Acknowledge quickly
    res.status(200).json({ received: true });
  } catch (err) {
    console.error('Webhook handler error', err.message);
    res.status(500).json({ error: err.message });
  }
});

app.listen(PORT, () => {
  console.log(`Payments server listening on port ${PORT}`);
});
