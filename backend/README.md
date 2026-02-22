# Backend Configuration

## Firebase Admin SDK

The `firebase-service-account.json` file is used by the backend to send push notifications via Firebase Cloud Messaging (FCM).

### Usage in Kubernetes

```bash
# Create secret from service account
kubectl create secret generic firebase-service-account \
  --from-file=firebase-service-account.json=firebase-service-account.json \
  -n sip-phone
```

### Environment Variable

```yaml
env:
  - name: GOOGLE_APPLICATION_CREDENTIALS
    value: /secrets/firebase-service-account.json
```

### Volume Mount

```yaml
volumeMounts:
  - name: firebase-secret
    mountPath: /secrets
    readOnly: true

volumes:
  - name: firebase-secret
    secret:
      secretName: firebase-service-account
```

## API Endpoints

### Send Push Notification

```bash
POST /api/v1/push/send
Content-Type: application/json

{
  "token": "device-fcm-token",
  "title": "Incoming Call",
  "body": "John Doe is calling",
  "data": {
    "type": "incoming_call",
    "call_id": "uuid",
    "caller_name": "John Doe",
    "caller_number": "+1234567890"
  }
}
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `GOOGLE_APPLICATION_CREDENTIALS` | Path to service account JSON |
| `FIREBASE_PROJECT_ID` | `sip-phone-2d72b` |
| `KAMAILIO_HOST` | SIP proxy host |
| `REDIS_URL` | Redis connection string |
| `DATABASE_URL` | PostgreSQL connection string |
