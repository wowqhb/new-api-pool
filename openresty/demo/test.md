# 提交

```bash
curl -X POST http://127.0.0.1/v1/chat/completions \
 -H "Authorization: Bearer sk-6FvF43E12L2kxNTl9nVt3jJvnAF3ltS3ARYzDJLvDvhw75du" \
 -H "Content-Type: application/json" \
 -d '{"model":"deepseek-v4-flash-ga-260731","messages":[{"role":"user","content":"测试一下"}]}'
```

# poll

```bash
curl "http://127.0.0.1/v1/queue/poll?queueId=<返回的queueId>"
```
