package main

import (
	"encoding/json"
	"fmt"
	"strings"
)

const (
	SUPPLIER_OPENAI = "openai"
	SUPPLIER_ALI    = "ali"
	SUPPLIER_LOCAL  = "local"
)

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

func main() {
	token := 0
	//rawBody := []byte("{\n     \"model\": \"gpt-3.5-turbo11111\",\n     \"messages\": [{\"role\": \"user\", \"content\": \"Say this is a test!\"},\n                 {\"role\": \"user\", \"content\": \"真的假的中共黑帮\"}],\n     \"temperature\": 0.7\n}")
	rawBody := []byte("{\n\t\"model\": \"gpt-3.5-turbo11111\",\n\t\"messages\": [{\n\t\t\t\"role\": \"user\",\n\t\t\t\"content\": [{\n\t\t\t\t\t\"type\": \"text\",\n\t\t\t\t\t\"text\": \"What’s in this image?\"\n\t\t\t\t},\n\t\t\t\t{\n\t\t\t\t\t\"type\": \"text\",\n\t\t\t\t\t\"text\": \"What’s in this image2?\"\n\t\t\t\t}\n\t\t\t]\n\t\t},\n\t\t{\n\t\t\t\"role\": \"user\",\n\t\t\t\"content\": \"真的假的中共黑帮\"\n\t\t}\n\t],\n\t\"temperature\": 0.7\n}")
	switch "local" {
	case SUPPLIER_OPENAI:
		body := &Prompt{}
		json.Unmarshal(rawBody, body)
		if len(body.Messages) == 0 || len(body.Model) == 0 {
			return
		}
		//token = NumTokensFromMessagesByOpenai(body.Messages, body.Model)
	case SUPPLIER_ALI:
		body := &PromptAli{}
		json.Unmarshal(rawBody, body)
		if len(body.Input.Messages) == 0 || len(body.Model) == 0 {
			return
		}
		var build strings.Builder
		//for _, v := range body.Input.Messages {
		//	build.WriteString(v.Content)
		//}
		token = len(strings.TrimSpace(build.String()))
	case SUPPLIER_LOCAL:
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
	default:
		body := &PromptAli{}
		json.Unmarshal(rawBody, body)
		if len(body.Input.Messages) == 0 || len(body.Model) == 0 {
			return
		}
		//var build strings.Builder
		//for _, v := range body.Input.Messages {
		//	build.WriteString(v.Content)
		//}
		//token = len(strings.TrimSpace(build.String()))
	}
	fmt.Printf("%d", token)
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
