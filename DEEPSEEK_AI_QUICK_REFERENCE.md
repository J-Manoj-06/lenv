# DeepSeek AI - Quick Reference 🚀

## 🔗 Worker Endpoint
```
https://deepseek-ai.giridharannj.workers.dev
```

## 📍 Endpoints

### 1. Health Check
```bash
GET /health
```

### 2. Chat Completion
```bash
POST /chat
Content-Type: application/json

{
  "model": "deepseek-chat",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant"},
    {"role": "user", "content": "Hello!"}
  ],
  "temperature": 0.7,
  "max_tokens": 1000
}
```

### 3. Test Generation
```bash
POST /generate
Content-Type: application/json

{
  "model": "deepseek-chat",
  "messages": [
    {"role": "system", "content": "You are a test writer"},
    {"role": "user", "content": "Create 5 math questions"}
  ],
  "temperature": 0.7,
  "max_tokens": 4000
}
```

## 🛠️ Common Commands

### Deploy Worker
```bash
cd cloudflare-worker
./deploy-deepseek.sh
```

### Update API Key
```bash
wrangler secret put DEEPSEEK_API_KEY --config cloudflare-worker/wrangler-deepseek.jsonc
```

### View Logs
```bash
wrangler tail --config cloudflare-worker/wrangler-deepseek.jsonc
```

### Test Health
```bash
curl https://deepseek-ai.giridharannj.workers.dev/health
```

### Test Chat
```bash
curl -X POST https://deepseek-ai.giridharannj.workers.dev/chat \
  -H "Content-Type: application/json" \
  -d '{"model":"deepseek-chat","messages":[{"role":"user","content":"Hello"}]}'
```

## 📱 Flutter Files Updated

1. **lib/services/deepseek_service.dart**
   - AI Tutor chat service
   - Now uses worker endpoint

2. **lib/config/ai_test_config.dart**
   - Test generation config
   - Removed direct API mode

3. **lib/config/ai_config.dart**
   - General AI config
   - Worker URL configured

## 🔒 Security

- ✅ API key stored as Wrangler secret
- ✅ Never exposed in client code
- ✅ Encrypted at rest
- ✅ Rotatable without app updates

## 📊 Monitoring

**Cloudflare Dashboard:**
https://dash.cloudflare.com → Workers & Pages → deepseek-ai-worker

## 🆘 Troubleshooting

| Error | Solution |
|-------|----------|
| "AI service not configured" | Set DEEPSEEK_API_KEY secret |
| "Authentication Failed" | Update API key secret |
| "Rate Limit Exceeded" | Wait or upgrade plan |
| "Request Timeout" | Reduce max_tokens |

## 📝 Next Steps

1. ✅ Deploy worker: `./deploy-deepseek.sh`
2. ✅ Test health endpoint
3. ✅ Test chat endpoint  
4. ✅ Revoke old API key
5. ✅ Run Flutter app

---

**Full Documentation:** See `DEEPSEEK_AI_SECURITY_MIGRATION.md`
