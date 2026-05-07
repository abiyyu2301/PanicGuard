// Copyright 2025 The ODML Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#ifndef THIRD_PARTY_ODML_LITERT_LM_C_ENGINE_H_
#define THIRD_PARTY_ODML_LITERT_LM_C_ENGINE_H_

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define LITERT_LM_C_API_EXPORT __declspec(dllexport)
#else
#define LITERT_LM_C_API_EXPORT __attribute__((visibility("default")))
#endif

// Opaque pointer for the LiteRT LM Engine.
typedef struct LiteRtLmEngine LiteRtLmEngine;

// Opaque pointer for the LiteRT LM Session.
typedef struct LiteRtLmSession LiteRtLmSession;

// Opaque pointer for the LiteRT LM Responses.
typedef struct LiteRtLmResponses LiteRtLmResponses;

// Opaque pointer for the LiteRT LM Engine Settings.
typedef struct LiteRtLmEngineSettings LiteRtLmEngineSettings;

// Opaque pointer for the LiteRT LM Benchmark Info.
typedef struct LiteRtLmBenchmarkInfo LiteRtLmBenchmarkInfo;

// Opaque pointer for the LiteRT LM Conversation.
typedef struct LiteRtLmConversation LiteRtLmConversation;

// Opaque pointer for a JSON response.
typedef struct LiteRtLmJsonResponse LiteRtLmJsonResponse;

// Opaque pointer for a detokenize result.
typedef struct LiteRtLmDetokenizeResult LiteRtLmDetokenizeResult;

// Opaque pointer for a tokenize result.
typedef struct LiteRtLmTokenizeResult LiteRtLmTokenizeResult;

// Represents the type of a TokenUnion.
typedef enum {
  kLiteRtLmTokenUnionTypeString = 0,
  kLiteRtLmTokenUnionTypeIds = 1,
} LiteRtLmTokenUnionType;

// Opaque pointer for LiteRT LM Token Union.
typedef struct LiteRtLmTokenUnion LiteRtLmTokenUnion;

// Opaque pointer for LiteRT LM Token Unions.
typedef struct LiteRtLmTokenUnions LiteRtLmTokenUnions;

// Opaque pointer for LiteRT LM Session Config.
typedef struct LiteRtLmSessionConfig LiteRtLmSessionConfig;

// Opaque pointer for LiteRT LM Conversation Config.
typedef struct LiteRtLmConversationConfig LiteRtLmConversationConfig;

// Represents the type of sampler.
typedef enum {
  kLiteRtLmSamplerTypeUnspecified = 0,
  kLiteRtLmSamplerTypeTopK = 1,
  kLiteRtLmSamplerTypeTopP = 2,
  kLiteRtLmSamplerTypeGreedy = 3,
} LiteRtLmSamplerType;

// Parameters for the sampler.
typedef struct {
  LiteRtLmSamplerType type;
  int32_t top_k;
  float top_p;
  float temperature;
  int32_t seed;
} LiteRtLmSamplerParams;

// Creates a LiteRT LM Session Config.
LITERT_LM_C_API_EXPORT
LiteRtLmSessionConfig* litert_lm_session_config_create();

// Sets the maximum number of output tokens per decode step for this session.
LITERT_LM_C_API_EXPORT
void litert_lm_session_config_set_max_output_tokens(
    LiteRtLmSessionConfig* config, int max_output_tokens);

// Sets whether to apply prompt template for this session.
LITERT_LM_C_API_EXPORT
void litert_lm_session_config_set_apply_prompt_template(
    LiteRtLmSessionConfig* config, bool apply_prompt_template);

// Sets the sampler parameters for this session config.
LITERT_LM_C_API_EXPORT
void litert_lm_session_config_set_sampler_params(
    LiteRtLmSessionConfig* config, const LiteRtLmSamplerParams* sampler_params);

// Destroys a LiteRT LM Session Config.
LITERT_LM_C_API_EXPORT
void litert_lm_session_config_delete(LiteRtLmSessionConfig* config);

// Creates a LiteRT LM Conversation Config.
LITERT_LM_C_API_EXPORT
LiteRtLmConversationConfig* litert_lm_conversation_config_create();

// Sets the session config for this conversation config.
LITERT_LM_C_API_EXPORT
void litert_lm_conversation_config_set_session_config(
    LiteRtLmConversationConfig* config,
    const LiteRtLmSessionConfig* session_config);

// Sets the system message for this conversation config.
LITERT_LM_C_API_EXPORT
void litert_lm_conversation_config_set_system_message(
    LiteRtLmConversationConfig* config, const char* system_message_json);

// Sets the tools for this conversation config.
LITERT_LM_C_API_EXPORT
void litert_lm_conversation_config_set_tools(LiteRtLmConversationConfig* config,
                                             const char* tools_json);

// Sets the initial messages for this conversation config.
LITERT_LM_C_API_EXPORT
void litert_lm_conversation_config_set_messages(
    LiteRtLmConversationConfig* config, const char* messages_json);

// Sets the extra context for the conversation preface.
LITERT_LM_C_API_EXPORT
void litert_lm_conversation_config_set_extra_context(
    LiteRtLmConversationConfig* config, const char* extra_context_json);

// Sets whether to enable constrained decoding for this conversation config.
LITERT_LM_C_API_EXPORT
void litert_lm_conversation_config_set_enable_constrained_decoding(
    LiteRtLmConversationConfig* config, bool enable_constrained_decoding);

// Sets whether to filter channel content from the KV cache.
LITERT_LM_C_API_EXPORT
void litert_lm_conversation_config_set_filter_channel_content_from_kv_cache(
    LiteRtLmConversationConfig* config,
    bool filter_channel_content_from_kv_cache);

// Destroys a LiteRT LM Conversation Config.
LITERT_LM_C_API_EXPORT
void litert_lm_conversation_config_delete(LiteRtLmConversationConfig* config);

// Sets the minimum log level for the LiteRT LM library.
// Log levels are: 0=VERBOSE, 1=DEBUG, 2=INFO, 3=WARNING, 4=ERROR, 5=FATAL, 1000=SILENT.
LITERT_LM_C_API_EXPORT
void litert_lm_set_min_log_level(int level);

// Represents the type of input data.
typedef enum {
  kLiteRtLmInputDataTypeText,
  kLiteRtLmInputDataTypeImage,
  kLiteRtLmInputDataTypeImageEnd,
  kLiteRtLmInputDataTypeAudio,
  kLiteRtLmInputDataTypeAudioEnd,
} LiteRtLmInputDataType;

// Represents a single piece of input data.
typedef struct {
  LiteRtLmInputDataType type;
  const void* data;
  size_t size;
} LiteRtLmInputData;

// Creates LiteRT LM Engine Settings.
LITERT_LM_C_API_EXPORT
LiteRtLmEngineSettings* litert_lm_engine_settings_create(
    const char* model_path, const char* backend_str,
    const char* vision_backend_str, const char* audio_backend_str);

// Destroys LiteRT LM Engine Settings.
LITERT_LM_C_API_EXPORT
void litert_lm_engine_settings_delete(LiteRtLmEngineSettings* settings);

// Sets the maximum number of tokens for the engine.
LITERT_LM_C_API_EXPORT
void litert_lm_engine_settings_set_max_num_tokens(
    LiteRtLmEngineSettings* settings, int max_num_tokens);

// Sets whether the engine should load different sections of the litertlm file in parallel.
LITERT_LM_C_API_EXPORT
void litert_lm_engine_settings_set_parallel_file_section_loading(
    LiteRtLmEngineSettings* settings, bool parallel_file_section_loading);

// Sets the maximum number of images for the engine.
LITERT_LM_C_API_EXPORT
void litert_lm_engine_settings_set_max_num_images(
    LiteRtLmEngineSettings* settings, int max_num_images);

// Sets the cache directory for the engine.
LITERT_LM_C_API_EXPORT
void litert_lm_engine_settings_set_cache_dir(LiteRtLmEngineSettings* settings,
                                             const char* cache_dir);

// Sets the LiteRT dispatch library directory for NPU backend.
LITERT_LM_C_API_EXPORT
void litert_lm_engine_settings_set_litert_dispatch_lib_dir(
    LiteRtLmEngineSettings* settings, const char* lib_dir);

// Sets the activation data type.
LITERT_LM_C_API_EXPORT
void litert_lm_engine_settings_set_activation_data_type(
    LiteRtLmEngineSettings* settings, int activation_data_type_int);

// Sets the prefill chunk size for the engine.
LITERT_LM_C_API_EXPORT
void litert_lm_engine_settings_set_prefill_chunk_size(
    LiteRtLmEngineSettings* settings, int prefill_chunk_size);

// Enables benchmarking for the engine.
LITERT_LM_C_API_EXPORT
void litert_lm_engine_settings_enable_benchmark(
    LiteRtLmEngineSettings* settings);

// Sets the number of prefill tokens for benchmarking.
LITERT_LM_C_API_EXPORT
void litert_lm_engine_settings_set_num_prefill_tokens(
    LiteRtLmEngineSettings* settings, int num_prefill_tokens);

// Sets the number of decode tokens for benchmarking.
LITERT_LM_C_API_EXPORT
void litert_lm_engine_settings_set_num_decode_tokens(
    LiteRtLmEngineSettings* settings, int num_decode_tokens);

// Sets whether to enable speculative decoding.
LITERT_LM_C_API_EXPORT
void litert_lm_engine_settings_set_enable_speculative_decoding(
    LiteRtLmEngineSettings* settings, bool enable_speculative_decoding);

// Creates a LiteRT LM Engine from the given settings.
LITERT_LM_C_API_EXPORT
LiteRtLmEngine* litert_lm_engine_create(const LiteRtLmEngineSettings* settings);

// Destroys a LiteRT LM Engine.
LITERT_LM_C_API_EXPORT
void litert_lm_engine_delete(LiteRtLmEngine* engine);

// Creates a LiteRT LM Session.
LITERT_LM_C_API_EXPORT
LiteRtLmSession* litert_lm_engine_create_session(LiteRtLmEngine* engine,
                                                 LiteRtLmSessionConfig* config);

// Destroys a LiteRT LM Session.
LITERT_LM_C_API_EXPORT
void litert_lm_session_delete(LiteRtLmSession* session);

// Cancels the current processing in the session.
LITERT_LM_C_API_EXPORT
void litert_lm_session_cancel_process(LiteRtLmSession* session);

// Adds the input prompt/query to the model for starting the prefilling process.
LITERT_LM_C_API_EXPORT
int litert_lm_session_run_prefill(LiteRtLmSession* session,
                                  const LiteRtLmInputData* inputs,
                                  size_t num_inputs);

// Starts the decoding process for the model to predict the response.
LITERT_LM_C_API_EXPORT
LiteRtLmResponses* litert_lm_session_run_decode(LiteRtLmSession* session);

// Scores the target text after the prefill process is done.
LITERT_LM_C_API_EXPORT
LiteRtLmResponses* litert_lm_session_run_text_scoring(LiteRtLmSession* session,
                                                      const char** target_text,
                                                      size_t num_targets,
                                                      bool store_token_lengths);

// Generates content from the input prompt.
LITERT_LM_C_API_EXPORT
LiteRtLmResponses* litert_lm_session_generate_content(
    LiteRtLmSession* session, const LiteRtLmInputData* inputs,
    size_t num_inputs);

// Destroys a LiteRT LM Responses object.
LITERT_LM_C_API_EXPORT
void litert_lm_responses_delete(LiteRtLmResponses* responses);

// Returns the number of response candidates.
LITERT_LM_C_API_EXPORT
int litert_lm_responses_get_num_candidates(const LiteRtLmResponses* responses);

// Returns the response text at a given index.
LITERT_LM_C_API_EXPORT
const char* litert_lm_responses_get_response_text_at(
    const LiteRtLmResponses* responses, int index);

// Returns whether the response contains a score at the given index.
LITERT_LM_C_API_EXPORT
bool litert_lm_responses_has_score_at(const LiteRtLmResponses* responses,
                                      int index);

// Returns the score at a given index.
LITERT_LM_C_API_EXPORT
float litert_lm_responses_get_score_at(const LiteRtLmResponses* responses,
                                       int index);

// Returns whether the response contains a token length at the given index.
LITERT_LM_C_API_EXPORT
bool litert_lm_responses_has_token_length_at(const LiteRtLmResponses* responses,
                                             int index);

// Returns the token length at a given index.
LITERT_LM_C_API_EXPORT
int litert_lm_responses_get_token_length_at(const LiteRtLmResponses* responses,
                                            int index);

// Returns whether the response contains token scores at the given index.
LITERT_LM_C_API_EXPORT
bool litert_lm_responses_has_token_scores_at(const LiteRtLmResponses* responses,
                                             int index);

// Returns the number of tokens for which scores are present at a given index.
LITERT_LM_C_API_EXPORT
int litert_lm_responses_get_num_token_scores_at(
    const LiteRtLmResponses* responses, int index);

// Returns the token scores at a given index.
LITERT_LM_C_API_EXPORT
const float* litert_lm_responses_get_token_scores_at(
    const LiteRtLmResponses* responses, int index);

// Retrieves the benchmark information from the session.
LITERT_LM_C_API_EXPORT
LiteRtLmBenchmarkInfo* litert_lm_session_get_benchmark_info(
    LiteRtLmSession* session);

// Destroys a LiteRT LM Benchmark Info object.
LITERT_LM_C_API_EXPORT
void litert_lm_benchmark_info_delete(LiteRtLmBenchmarkInfo* benchmark_info);

// Returns the time to the first token in seconds.
LITERT_LM_C_API_EXPORT
double litert_lm_benchmark_info_get_time_to_first_token(
    const LiteRtLmBenchmarkInfo* benchmark_info);

// Returns the total initialization time in seconds.
LITERT_LM_C_API_EXPORT
double litert_lm_benchmark_info_get_total_init_time_in_second(
    const LiteRtLmBenchmarkInfo* benchmark_info);

// Returns the number of prefill turns.
LITERT_LM_C_API_EXPORT
int litert_lm_benchmark_info_get_num_prefill_turns(
    const LiteRtLmBenchmarkInfo* benchmark_info);

// Returns the number of decode turns.
LITERT_LM_C_API_EXPORT
int litert_lm_benchmark_info_get_num_decode_turns(
    const LiteRtLmBenchmarkInfo* benchmark_info);

// Returns the prefill token count at a given turn index.
LITERT_LM_C_API_EXPORT
int litert_lm_benchmark_info_get_prefill_token_count_at(
    const LiteRtLmBenchmarkInfo* benchmark_info, int index);

// Returns the decode token count at a given turn index.
LITERT_LM_C_API_EXPORT
int litert_lm_benchmark_info_get_decode_token_count_at(
    const LiteRtLmBenchmarkInfo* benchmark_info, int index);

// Returns the prefill tokens per second at a given turn index.
LITERT_LM_C_API_EXPORT
double litert_lm_benchmark_info_get_prefill_tokens_per_sec_at(
    const LiteRtLmBenchmarkInfo* benchmark_info, int index);

// Returns the decode tokens per second at a given turn index.
LITERT_LM_C_API_EXPORT
double litert_lm_benchmark_info_get_decode_tokens_per_sec_at(
    const LiteRtLmBenchmarkInfo* benchmark_info, int index);

// Callback for streaming responses.
typedef void (*LiteRtLmStreamCallback)(void* callback_data, const char* chunk,
                                       bool is_final, const char* error_msg);

// Starts the decoding process — non-blocking with streaming callback.
LITERT_LM_C_API_EXPORT
int litert_lm_session_run_decode_async(LiteRtLmSession* session,
                                       LiteRtLmStreamCallback callback,
                                       void* callback_data);

// Generates content and streams the response via a callback — non-blocking.
LITERT_LM_C_API_EXPORT
int litert_lm_session_generate_content_stream(LiteRtLmSession* session,
                                              const LiteRtLmInputData* inputs,
                                              size_t num_inputs,
                                              LiteRtLmStreamCallback callback,
                                              void* callback_data);

// Creates a LiteRT LM Conversation.
LITERT_LM_C_API_EXPORT
LiteRtLmConversation* litert_lm_conversation_create(
    LiteRtLmEngine* engine, LiteRtLmConversationConfig* config);

// Destroys a LiteRT LM Conversation.
LITERT_LM_C_API_EXPORT
void litert_lm_conversation_delete(LiteRtLmConversation* conversation);

// Sends a message to the conversation and returns the response — blocking.
LITERT_LM_C_API_EXPORT
LiteRtLmJsonResponse* litert_lm_conversation_send_message(
    LiteRtLmConversation* conversation, const char* message_json,
    const char* extra_context);

// Destroys a LiteRT LM Json Response object.
LITERT_LM_C_API_EXPORT
void litert_lm_json_response_delete(LiteRtLmJsonResponse* response);

// Returns the JSON response string from a response object.
LITERT_LM_C_API_EXPORT
const char* litert_lm_json_response_get_string(
    const LiteRtLmJsonResponse* response);

// Sends a message to the conversation and streams the response — non-blocking.
LITERT_LM_C_API_EXPORT
int litert_lm_conversation_send_message_stream(
    LiteRtLmConversation* conversation, const char* message_json,
    const char* extra_context, LiteRtLmStreamCallback callback,
    void* callback_data);

// Renders the message into a string according to the template.
LITERT_LM_C_API_EXPORT
const char* litert_lm_conversation_render_message_to_string(
    LiteRtLmConversation* conversation, const char* message_json);

// Cancels the ongoing inference process.
LITERT_LM_C_API_EXPORT
void litert_lm_conversation_cancel_process(LiteRtLmConversation* conversation);

// Retrieves the benchmark information from the conversation.
LITERT_LM_C_API_EXPORT
LiteRtLmBenchmarkInfo* litert_lm_conversation_get_benchmark_info(
    LiteRtLmConversation* conversation);

// Tokenizes text using the engine's tokenizer.
LITERT_LM_C_API_EXPORT
LiteRtLmTokenizeResult* litert_lm_engine_tokenize(LiteRtLmEngine* engine,
                                                  const char* text);

// Destroys a LiteRT LM Tokenize Result.
LITERT_LM_C_API_EXPORT
void litert_lm_tokenize_result_delete(LiteRtLmTokenizeResult* result);

// Returns the token ids from a tokenize result.
LITERT_LM_C_API_EXPORT
const int* litert_lm_tokenize_result_get_tokens(
    const LiteRtLmTokenizeResult* result);

// Returns the number of token ids from a tokenize result.
LITERT_LM_C_API_EXPORT
size_t litert_lm_tokenize_result_get_num_tokens(
    const LiteRtLmTokenizeResult* result);

// Detokenizes token ids using the engine's tokenizer.
LITERT_LM_C_API_EXPORT
LiteRtLmDetokenizeResult* litert_lm_engine_detokenize(LiteRtLmEngine* engine,
                                                      const int* tokens,
                                                      size_t num_tokens);

// Destroys a LiteRT LM Detokenize Result.
LITERT_LM_C_API_EXPORT
void litert_lm_detokenize_result_delete(LiteRtLmDetokenizeResult* result);

// Returns the string from a detokenize result.
LITERT_LM_C_API_EXPORT
const char* litert_lm_detokenize_result_get_string(
    const LiteRtLmDetokenizeResult* result);

// Destroys a LiteRT LM Token Union.
LITERT_LM_C_API_EXPORT
void litert_lm_token_union_delete(LiteRtLmTokenUnion* token_union);

// Returns the type of the token union.
LITERT_LM_C_API_EXPORT
LiteRtLmTokenUnionType litert_lm_token_union_get_type(
    const LiteRtLmTokenUnion* token_union);

// Returns the string value from a token union.
LITERT_LM_C_API_EXPORT
const char* litert_lm_token_union_get_string(
    const LiteRtLmTokenUnion* token_union);

// Returns the token ids from a token union.
LITERT_LM_C_API_EXPORT
int litert_lm_token_union_get_ids(const LiteRtLmTokenUnion* token_union,
                                  const int** out_tokens,
                                  size_t* out_num_tokens);

// Destroys a LiteRT LM Token Unions object.
LITERT_LM_C_API_EXPORT
void litert_lm_token_unions_delete(LiteRtLmTokenUnions* tokens);

// Returns the number of token unions in the collection.
LITERT_LM_C_API_EXPORT
size_t litert_lm_token_unions_get_num_tokens(const LiteRtLmTokenUnions* tokens);

// Returns the token union at a given index from a collection.
LITERT_LM_C_API_EXPORT
LiteRtLmTokenUnion* litert_lm_token_unions_get_token_at(
    const LiteRtLmTokenUnions* tokens, size_t index);

// Returns the configured start token (BOS), if any.
LITERT_LM_C_API_EXPORT
LiteRtLmTokenUnion* litert_lm_engine_get_start_token(LiteRtLmEngine* engine);

// Returns the configured stop tokens (EOS).
LITERT_LM_C_API_EXPORT
LiteRtLmTokenUnions* litert_lm_engine_get_stop_tokens(LiteRtLmEngine* engine);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // THIRD_PARTY_ODML_LITERT_LM_C_ENGINE_H_
