# Go 示例

## 安装

```bash
go get github.com/sashabaranov/go-openai
```

## 基础调用

```go
package main

import (
    "context"
    "fmt"
    "os"

    openai "github.com/sashabaranov/go-openai"
)

func main() {
    cfg := openai.DefaultConfig(os.Getenv("AITR_API_KEY"))
    cfg.BaseURL = os.Getenv("AITR_BASE_URL") + "/v1"
    client := openai.NewClientWithConfig(cfg)

    resp, err := client.CreateChatCompletion(
        context.Background(),
        openai.ChatCompletionRequest{
            Model: "gpt-4o-mini",
            Messages: []openai.ChatCompletionMessage{
                {Role: openai.ChatMessageRoleUser, Content: "Hello"},
            },
        },
    )
    if err != nil {
        panic(err)
    }
    fmt.Println(resp.Choices[0].Message.Content)
}
```

## 流式

```go
stream, err := client.CreateChatCompletionStream(
    context.Background(),
    openai.ChatCompletionRequest{
        Model: "gpt-4o-mini",
        Messages: []openai.ChatCompletionMessage{
            {Role: openai.ChatMessageRoleUser, Content: "讲个长故事"},
        },
        Stream: true,
    },
)
defer stream.Close()

for {
    resp, err := stream.Recv()
    if errors.Is(err, io.EOF) {
        break
    }
    if err != nil {
        panic(err)
    }
    fmt.Print(resp.Choices[0].Delta.Content)
}
```

## 重试

```go
import "github.com/cenkalti/backoff/v4"

operation := func() error {
    _, err := client.CreateChatCompletion(...)
    if err != nil {
        var apiErr *openai.APIError
        if errors.As(err, &apiErr) && (apiErr.HTTPStatusCode == 429 || apiErr.HTTPStatusCode >= 500) {
            return err  // retry
        }
        return backoff.Permanent(err)  // don't retry
    }
    return nil
}

err := backoff.Retry(operation, backoff.WithMaxRetries(backoff.NewExponentialBackOff(), 5))
```
