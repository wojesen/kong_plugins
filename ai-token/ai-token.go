/*
	A "ai-token" plugin in Go,
	which reads a request header and sets a response header.
*/

package main

import (
	"encoding/json"
	"fmt"
	"log"
	"strings"

	"github.com/Kong/go-pdk"
	"github.com/Kong/go-pdk/server"
	"github.com/pkoukk/tiktoken-go"
)

func main() {
	server.StartServer(New, Version, Priority)
}

const (
	SUPPLIER_OPENAI = "openai"
	SUPPLIER_ALI    = "ali"
	SUPPLIER_LOCAL  = "local"
)

var Version = "0.2"
var Priority = 903

type Config struct {
	Model    string
	Supplier string
}

func New() interface{} {
	return &Config{}
}

type Message struct {
	Role    string
	Content interface{}
	Name    string
}
type Prompt struct {
	Model       string
	Temperature string
	Messages    []Message
}

type PromptEmbedding struct {
	Model string
	Input string
}

type InputAli struct {
	Messages []Message
}
type PromptAli struct {
	Model       string
	Temperature string
	Input       InputAli
}

func (conf Config) Access(kong *pdk.PDK) {
	rawBody, err := kong.Request.GetRawBody()
	//获取失败，跳过
	if err != nil {
		return
	}
	token := 0
	model := ""
	url := ""
	switch conf.Supplier {
	case SUPPLIER_OPENAI:
		body := &Prompt{}
		json.Unmarshal(rawBody, body)
		if len(body.Messages) == 0 || len(body.Model) == 0 {
			return
		}
		token = NumTokensFromMessagesByOpenai(body.Messages, body.Model)
		model = body.Model
	case SUPPLIER_ALI:
		body := &PromptAli{}
		json.Unmarshal(rawBody, body)
		if len(body.Input.Messages) == 0 || len(body.Model) == 0 {
			return
		}
		var build strings.Builder
		for _, v := range body.Input.Messages {
			build.WriteString(getContent(v))
		}
		token = len(strings.TrimSpace(build.String()))
	default:
		url, err = kong.Request.GetPath()
		if err != nil || url == "" {
			return
		}
		//embeddings和chat报文有区别，所以要分开解析
		if strings.Contains(url, "v1/embeddings") {
			body := &PromptEmbedding{}
			json.Unmarshal(rawBody, body)
			var build strings.Builder
			build.WriteString(body.Input)
			token = len(strings.TrimSpace(build.String()))
			model = body.Model
		} else {
			body := &Prompt{}
			json.Unmarshal(rawBody, body)
			if len(body.Messages) == 0 || len(body.Model) == 0 {
				return
			}
			var build strings.Builder
			for _, v := range body.Messages {
				build.WriteString(getContent(v))
			}
			token = len(strings.TrimSpace(build.String()))
			model = body.Model
		}
	}

	kong.Response.SetHeader("x-token-count", fmt.Sprintf("token num is %d", token))
	kong.Response.SetHeader("x-request-model", model)
	kong.Response.SetHeader("x-request-url", url)
	kong.ServiceRequest.SetHeader("x-request-token-count", fmt.Sprintf("%d", token))
	kong.ServiceRequest.SetHeader("x-request-model", model)
	kong.ServiceRequest.SetHeader("x-request-url", url)
	kong.Nginx.SetCtx("prompt_tokens_go", token)
	//标记当前服务是AI类型的，防止后面对非AI服务进行报文解析，计算token
	kong.Nginx.SetCtx("ai_api_go", true)
}

func NumTokensFromMessagesByOpenai(messages []Message, model string) (numTokens int) {
	tkm, err := tiktoken.EncodingForModel(model)
	if err != nil {
		err = fmt.Errorf("encoding for model: %v", err)
		log.Println(err)
		return
	}

	var tokensPerMessage, tokensPerName int
	switch model {
	case "gpt-3.5-turbo-0613",
		"gpt-3.5-turbo-16k-0613",
		"gpt-4-0314",
		"gpt-4-32k-0314",
		"gpt-4-0613",
		"gpt-4-32k-0613":
		tokensPerMessage = 3
		tokensPerName = 1
	case "gpt-3.5-turbo-0301":
		tokensPerMessage = 4 // every message follows <|start|>{role/name}\n{content}<|end|>\n
		tokensPerName = -1   // if there's a name, the role is omitted
	default:
		if strings.Contains(model, "gpt-3.5-turbo") {
			log.Println("warning: gpt-3.5-turbo may update over time. Returning num tokens assuming gpt-3.5-turbo-0613.")
			return NumTokensFromMessagesByOpenai(messages, "gpt-3.5-turbo-0613")
		} else if strings.Contains(model, "gpt-4") {
			log.Println("warning: gpt-4 may update over time. Returning num tokens assuming gpt-4-0613.")
			return NumTokensFromMessagesByOpenai(messages, "gpt-4-0613")
		} else {
			err = fmt.Errorf("num_tokens_from_messages() is not implemented for model %s. See https://github.com/openai/openai-python/blob/main/chatml.md for information on how messages are converted to tokens.", model)
			log.Println(err)
			return
		}
	}

	for _, message := range messages {
		numTokens += tokensPerMessage
		numTokens += len(tkm.Encode(getContent(message), nil, nil))
		numTokens += len(tkm.Encode(message.Role, nil, nil))
		numTokens += len(tkm.Encode(message.Name, nil, nil))
		if message.Name != "" {
			numTokens += tokensPerName
		}
	}
	numTokens += 3 // every reply is primed with <|start|>assistant<|message|>
	return numTokens
}

func getContent(messages Message) (content string) {
	var build strings.Builder
	switch messages.Content.(type) {
	case string:
		build.WriteString(fmt.Sprintf("%v", messages.Content))
	case []interface{}:
		for _, a := range messages.Content.([]interface{}) {
			switch a.(type) {
			case string:
				build.WriteString(fmt.Sprintf("%v", messages.Content))
			case map[string]interface{}:
				conMap := a.(map[string]interface{})
				con := conMap["text"]
				if con != nil {
					build.WriteString(fmt.Sprintf("%v", con))
				}
			}
		}
	default:
	}
	return build.String()
}
