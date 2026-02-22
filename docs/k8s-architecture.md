# Kubernetes Deployment Architecture

## Namespace
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: sip-phone
```

## Component Breakdown

### 1. Kamailio (SIP Proxy/Registrar)

**Purpose:** Handle SIP registration, routing, and proxying

```yaml
# kamailio-deployment.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kamailio
  namespace: sip-phone
spec:
  serviceName: kamailio
  replicas: 2
  selector:
    matchLabels:
      app: kamailio
  template:
    metadata:
      labels:
        app: kamailio
    spec:
      containers:
      - name: kamailio
        image: kamailio/kamailio:5.7
        ports:
        - containerPort: 5060  # SIP UDP
          protocol: UDP
        - containerPort: 5060  # SIP TCP
        - containerPort: 5061  # SIP TLS
        - containerPort: 5062  # SIP WebSocket
        volumeMounts:
        - name: config
          mountPath: /etc/kamailio
        - name: data
          mountPath: /var/lib/kamailio
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
---
apiVersion: v1
kind: Service
metadata:
  name: kamailio
  namespace: sip-phone
spec:
  selector:
    app: kamailio
  ports:
  - name: sip-udp
    port: 5060
    protocol: UDP
  - name: sip-tcp
    port: 5060
  - name: sip-tls
    port: 5061
  - name: sip-ws
    port: 5062
  type: LoadBalancer  # Or NodePort if behind external LB
```

### 2. coturn (STUN/TURN Server)

**Purpose:** NAT traversal for WebRTC media

```yaml
# coturn-deployment.yaml
apiVersion: apps/v1
kind: DaemonSet  # Run on each node or use Deployment
metadata:
  name: coturn
  namespace: sip-phone
spec:
  selector:
    matchLabels:
      app: coturn
  template:
    metadata:
      labels:
        app: coturn
    spec:
      hostNetwork: true  # Required for UDP port ranges
      containers:
      - name: coturn
        image: coturn/coturn:4.6
        ports:
        - containerPort: 3478  # STUN/TURN
        - containerPort: 3479  # STUN/TURN TLS
        - containerPort: 5349  # TURN over TLS
        # UDP relay ports (wide range needed)
        - containerPort: 10000
          protocol: UDP
        env:
        - name: TURN_SECRET
          valueFrom:
            secretKeyRef:
              name: coturn-secret
              key: secret
```

**Alternative:** Deploy coturn on a VPS with public IP (simpler for UDP port ranges)

### 3. Signaling WebSocket Server

**Purpose:** Bridge between mobile app and SIP

```yaml
# signaling-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: signaling
  namespace: sip-phone
spec:
  replicas: 3
  selector:
    matchLabels:
      app: signaling
  template:
    metadata:
      labels:
        app: signaling
    spec:
      containers:
      - name: signaling
        image: your-registry/sip-signaling:latest
        ports:
        - containerPort: 8080
        env:
        - name: REDIS_URL
          value: "redis://redis:6379"
        - name: KAMAILIO_HOST
          value: "kamailio"
        - name: FCM_SERVER_KEY
          valueFrom:
            secretKeyRef:
              name: fcm-secret
              key: server-key
---
apiVersion: v1
kind: Service
metadata:
  name: signaling
  namespace: sip-phone
spec:
  selector:
    app: signaling
  ports:
  - port: 80
    targetPort: 8080
```

### 4. REST API Server

**Purpose:** Device registration, user management, call logs

```yaml
# api-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: sip-phone
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: your-registry/sip-api:latest
        ports:
        - containerPort: 3000
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: url
        - name: REDIS_URL
          value: "redis://redis:6379"
---
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: sip-phone
spec:
  selector:
    app: api
  ports:
  - port: 80
    targetPort: 3000
```

### 5. Ingress

```yaml
# ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sip-phone
  namespace: sip-phone
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/websocket-services: "signaling"
spec:
  tls:
  - hosts:
    - sip-api.nexvision.cc
    - sip-ws.nexvision.cc
    secretName: sip-phone-tls
  rules:
  - host: sip-api.nexvision.cc
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api
            port:
              number: 80
  - host: sip-ws.nexvision.cc
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: signaling
            port:
              number: 80
```

## Network Requirements

| Port | Protocol | Purpose | Source |
|------|----------|---------|--------|
| 5060 | UDP/TCP | SIP signaling | Twilio + Mobile |
| 5061 | TCP | SIP TLS | Twilio + Mobile |
| 5062 | TCP | SIP WebSocket | Mobile |
| 3478 | UDP/TCP | STUN | Mobile |
| 5349 | TCP | TURN TLS | Mobile |
| 10000-20000 | UDP | TURN relay | Mobile |

## Storage

```yaml
# redis.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: sip-phone
spec:
  serviceName: redis
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
        volumeMounts:
        - name: data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 5Gi
---
# postgres.yaml (similar structure)
```

## Secrets Needed

```bash
# Create secrets
kubectl create secret generic coturn-secret \
  --from-literal=secret=your-turn-secret \
  -n sip-phone

kubectl create secret generic fcm-secret \
  --from-literal=server-key=your-fcm-server-key \
  -n sip-phone

kubectl create secret generic db-secret \
  --from-literal=url=postgres://user:pass@postgres:5432/sipphone \
  -n sip-phone
```
