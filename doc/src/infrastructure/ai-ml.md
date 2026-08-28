---
global_sync_id: "v1"
---

# Artificial Intelligence and Machine Learning

To aid AI and ML workflows we offer API based access to various models for chat, embedding, and image recognition. The system is backed by NVIDIA RTX PRO 6000 GPUs.


## Available Models


| Model | Origin | License | Usage | Context Size |
| - | - | - | - | - |
| [gpt-oss:20b](https://huggingface.co/openai/gpt-oss-20b) | OpenAI | Apache License Version 2.0 | llm | 65.536 |
| [gpt-oss:120b](https://huggingface.co/openai/gpt-oss-120b) | OpenAI | Apache License Version 2.0 | llm | 131.072 |
| [rednote-hilab/dots.mocr](https://huggingface.co/rednote-hilab/dots.mocr) | Red Note (hilab)	 | MIT License | Image-Text-to-Text | 32.768 | 
| [Nomic-embed-text:v1.5](https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF) | Nomic | Apache License Version 2.0 | embedding | 8.192 |
| [bge-m3:567m](https://huggingface.co/BAAI/bge-m3)  | Beijing Academy of Artificial Intelligence | MIT License | embedding | 8.192 |
| [embeddinggemma:300m](https://huggingface.co/google/embeddinggemma-300m) | Google | [Gemma Terms of Use](https://ai.google.dev/gemma/terms) | embedding | 2.048 |

## APIs and Access

We provide location-specific OpenAI-compatible API endpoints.
Access to the AI API can be enabled for any resource group via our customer portal https://my.flyingcircus.io/.
Manager permissions are required to do this.

To use the API, an authentication token is required as a bearer token.
We recommend using application specific token.
These tokens can be created in our customer portal by any user with manager permissions in the resource group.

Public endpoints:

- RZOB: https://ai.rzob.fcio.net/openai/v1
- RZHAL: https://ai.whq.fcio.net/openai/v1

Customer-owned hardware is available via custom endpoints.


## Known issues and restrictions

Our AI stack is built faithfully on an open source approach building on top of a wide variety
of open source components including Linux with its GPU drivers, VLLM as the core of the inference engine (which in turn also uses a large number of other projects' libraries) as well as in-house developed tools.

All of those are under active development from a global community of developers. At the same time, the nature of implementing a de-facto standard like the OpenAI API for a wide variety of GPUs, model architectures and an ever growing feature matrix may cause specific compatibility issues and vary over time. 

We make an explicit effort to provide a consistent experience for our customers, which includes providing
a transparent list of compatibility issues that have had visible impact in the past. However, even if you
might be impacted, we encourage you to revisit the items in this list from time to time if they are 
relevant to your use case as they might behave differently in your context and might even have improved
over time but may not have been documented clearly in the upstream projects.

Look-around regular expressions in structured output are not supported
: Using regular expression that leverage look-around/look-ahead/look-behind features
  results in to help guiding structured output may result in errors like this:

  ```
  {
    "error": {
      "message": "Grammar error: regex parse error:\n    ^(?!^[-+.]*$)[+-]?0*[0-9]*\\.?[0-9]*$\n     ^^^\nerror: look-around, including look-ahead and look-behind, is not supported",
      "type": "BadRequestError",
      "param": null,
      "code": 400
    }  
  }
  ```
