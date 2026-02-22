const admin = require('firebase-admin');
const path = require('path');

// Initialize Firebase Admin SDK
const serviceAccount = require(path.join(__dirname, 'firebase-service-account.json'));

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'sip-phone-2d72b',
});

const messaging = admin.messaging();

/**
 * Send push notification for incoming call
 */
async function sendIncomingCallPush({
  token,
  callId,
  callerName,
  callerNumber,
}) {
  const message = {
    token: token,
    notification: {
      title: 'Incoming Call',
      body: `${callerName} is calling`,
    },
    data: {
      type: 'incoming_call',
      call_id: callId,
      caller_name: callerName,
      caller_number: callerNumber,
    },
    android: {
      priority: 'high',
      notification: {
        channelId: 'sip_calls_channel',
        priority: 'high',
        sound: 'default',
      },
    },
  };

  try {
    const response = await messaging.send(message);
    console.log('Push notification sent:', response);
    return response;
  } catch (error) {
    console.error('Error sending push:', error);
    throw error;
  }
}

/**
 * Send call ended notification
 */
async function sendCallEndedPush({ token, callId }) {
  const message = {
    token: token,
    data: {
      type: 'call_ended',
      call_id: callId,
    },
  };

  return messaging.send(message);
}

module.exports = {
  sendIncomingCallPush,
  sendCallEndedPush,
  messaging,
};
