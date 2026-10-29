import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const payload = await req.json()
    const { record, old_record, table } = payload

    // 1. Load Service Account from Supabase Secrets
    const serviceAccount = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') || '{}')
    if (!serviceAccount.project_id) {
      return new Response('Firebase Secret missing', { status: 500 })
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    let title = ""
    let body = ""
    let targetToken = ""
    let channelId = "verified_notifications"
    let dataPayload = {}

    // --- HANDLE ACCOUNT VERIFICATION ---
    if (table === 'create_account') {
      if (record.verification_status === old_record?.verification_status) {
        return new Response('No change', { status: 200 })
      }
      targetToken = record.fcm_token
      if (record.verification_status === 'APPROVED') {
        title = "Account Approved! 🎉"
        body = "Congrats! You can now login to Breeder Finder."
      } else {
        return new Response('Status ignored', { status: 200 })
      }
    }
    // --- HANDLE NEW MESSAGES ---
    else if (table === 'messages') {
      const receiverId = record.receiver_id
      const senderId = record.sender_id
      const messageText = record.message_text || "Sent you a message"

      // Fetch receiver's FCM token
      const { data: receiverData } = await supabase
        .from('create_account')
        .select('fcm_token')
        .eq('id', receiverId)
        .single()

      targetToken = receiverData?.fcm_token
      if (!targetToken) {
        console.log(`No FCM token found for receiver: ${receiverId}`)
        return new Response('No receiver token', { status: 200 })
      }

      // Fetch sender's name
      const { data: senderData } = await supabase
        .from('create_account')
        .select('full_name')
        .eq('id', senderId)
        .single()

      const senderName = senderData?.full_name || "Someone"
      title = senderName
      body = messageText
      channelId = "chat_messages"
      dataPayload = {
        type: "chat",
        sender_id: senderId,
        sender_name: senderName,
        message_text: messageText,
        title: senderName,
        body: messageText
      }
    }
    // --- HANDLE ARRIVALS ---
    else if (table === 'arrivals') {
      const hostId = record.host_id
      const visitorId = record.visitor_id
      const status = record.status || 'pending'
      const visitorName = record.visitor_name || "A user"
      const visitorRole = record.visitor_role || "Breeder"
      const hostName = record.host_name || "the host"

      if (status === 'pending') {
        // Send notification to HOST: Arrival Request
        const { data: hostData } = await supabase
          .from('create_account')
          .select('fcm_token')
          .eq('id', hostId)
          .single()

        targetToken = hostData?.fcm_token
        if (!targetToken) {
          console.log(`No FCM token found for host: ${hostId}`)
          return new Response('No host token', { status: 200 })
        }

        title = "Arrival Request"
        body = `${visitorName} wants to arrive at your location. Please accept or decline.`
        channelId = "verified_notifications"
        dataPayload = {
          type: "arrival_request",
          visitor_name: visitorName,
          visitor_role: visitorRole,
        }
      } else if (status === 'accepted') {
        // Send notification to VISITOR: Arrival Accepted
        const { data: visitorData } = await supabase
          .from('create_account')
          .select('fcm_token')
          .eq('id', visitorId)
          .single()

        targetToken = visitorData?.fcm_token
        if (!targetToken) {
          console.log(`No FCM token found for visitor: ${visitorId}`)
          return new Response('No visitor token', { status: 200 })
        }

        title = "Arrival Accepted"
        body = `${hostName} accepted your arrival request! Geofencing is active.`
        channelId = "verified_notifications"
        dataPayload = {
          type: "arrival_accepted",
          host_name: hostName,
        }
      } else if (status === 'arrived') {
        // Send notification to HOST: Visitor Arrived
        const { data: hostData } = await supabase
          .from('create_account')
          .select('fcm_token')
          .eq('id', hostId)
          .single()

        targetToken = hostData?.fcm_token
        if (!targetToken) {
          console.log(`No FCM token found for host: ${hostId}`)
          return new Response('No host token', { status: 200 })
        }

        title = "Visitor Arrived"
        body = `${visitorName} has arrived at your location.`
        channelId = "verified_notifications"
        dataPayload = {
          type: "arrived",
          visitor_name: visitorName,
          visitor_role: visitorRole,
        }
      } else {
        return new Response('Status ignored', { status: 200 })
      }
    }

    if (!targetToken) return new Response('No target token', { status: 200 })

    // 2. Manual JWT Generation for FCM
    const encodeBase64 = (str: string) => btoa(str).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
    const header = encodeBase64(JSON.stringify({ alg: "RS256", typ: "JWT" }));
    const now = Math.floor(Date.now() / 1000);
    const claim = encodeBase64(JSON.stringify({
      iss: serviceAccount.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      exp: now + 3600,
      iat: now,
    }));

    const key = await crypto.subtle.importKey(
      "pkcs8",
      Uint8Array.from(atob(serviceAccount.private_key.replace(/-----(BEGIN|END) PRIVATE KEY-----|\n/g, '')), c => c.charCodeAt(0)),
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"]
    );

    const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claim}`));
    const jwt = `${header}.${claim}.${encodeBase64(String.fromCharCode(...new Uint8Array(signature)))}`;

    const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
    });

    const { access_token } = await tokenRes.json();

    // 3. Send to FCM v1
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${access_token}`,
      },
      body: JSON.stringify({
        message: {
          token: targetToken,
          notification: { title, body },
          data: dataPayload,
          android: {
            priority: "HIGH",
            notification: {
              channel_id: channelId,
              notification_priority: "PRIORITY_MAX",
              sound: "default",
              icon: "launcher_icon",
              click_action: "FLUTTER_NOTIFICATION_CLICK",
            },
          },
          apns: {
            payload: {
              aps: {
                alert: { title, body },
                sound: "default",
                category: channelId,
              },
            },
          },
        }
      })
    })

    const result = await res.json()
    return new Response(JSON.stringify(result), {
      headers: { "Content-Type": "application/json" },
      status: res.status
    })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }
})
