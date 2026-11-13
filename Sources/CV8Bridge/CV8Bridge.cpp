#include "CV8Bridge.h"
#if defined(XLASER_V8_ENABLED)
#include <libplatform/libplatform.h>
#include <v8.h>
#include <cmath>
#include <cstring>
#include <cstdlib>
#include <limits>
#include <memory>
#include <mutex>
#include <string>

struct XLaserV8Runtime {
    v8::ArrayBuffer::Allocator *allocator = nullptr;
    v8::Isolate *isolate = nullptr;
    v8::Global<v8::Context> context;
    v8::Global<v8::Function> read;
    v8::Global<v8::Function> make_input;
    std::shared_ptr<v8::BackingStore> values;
    std::shared_ptr<v8::BackingStore> modes;
    std::shared_ptr<v8::BackingStore> shapes;
    std::shared_ptr<v8::BackingStore> shape_matrices;
    std::shared_ptr<v8::BackingStore> shape_tints;
};

static thread_local std::string error_message;
static std::once_flag initialized;

static void initialize_v8() {
    std::call_once(initialized, [] {
        v8::V8::InitializeICUDefaultLocation(nullptr);
        v8::V8::InitializeExternalStartupData(nullptr);
        auto platform = v8::platform::NewDefaultPlatform();
        v8::V8::InitializePlatform(platform.release());
        v8::V8::Initialize();
    });
}

static void save_error(v8::Isolate *isolate, v8::TryCatch &caught, const char *fallback) {
    if (caught.HasCaught()) {
        v8::String::Utf8Value text(isolate, caught.Exception());
        error_message = *text ? *text : fallback;
    } else error_message = fallback;
}

static bool evaluate(v8::Isolate *isolate, v8::Local<v8::Context> context, const char *source, v8::Local<v8::Value> *result) {
    v8::Local<v8::String> code;
    v8::Local<v8::Script> script;
    return v8::String::NewFromUtf8(isolate, source).ToLocal(&code) &&
        v8::Script::Compile(context, code).ToLocal(&script) && script->Run(context).ToLocal(result);
}

void xlv8_destroy(XLaserV8Runtime *runtime) {
    if (!runtime) return;
    if (runtime->isolate) {
        {
            v8::Locker locker(runtime->isolate);
            v8::Isolate::Scope isolate_scope(runtime->isolate);
            runtime->read.Reset(); runtime->make_input.Reset(); runtime->context.Reset();
            runtime->values.reset(); runtime->modes.reset(); runtime->shapes.reset();
            runtime->shape_matrices.reset(); runtime->shape_tints.reset();
        }
        runtime->isolate->Dispose();
    }
    delete runtime->allocator;
    delete runtime;
}

static void release_buffer(void *data, size_t, void *) { std::free(data); }

static void allocate_buffer(const v8::FunctionCallbackInfo<v8::Value> &args) {
    auto isolate = args.GetIsolate();
    if (args.Length() != 2 || !args[0]->IsString() || !args[1]->IsNumber()) {
        isolate->ThrowException(v8::Exception::TypeError(v8::String::NewFromUtf8Literal(isolate, "Invalid buffer request")));
        return;
    }
    v8::String::Utf8Value type(isolate, args[0]);
    const double requested = args[1].As<v8::Number>()->Value();
    size_t element_size = 0, maximum = 0;
    if (*type && std::strcmp(*type, "float32") == 0) { element_size = sizeof(float); maximum = v8::Float32Array::kMaxLength; }
    else if (*type && std::strcmp(*type, "uint16") == 0) { element_size = sizeof(uint16_t); maximum = v8::Uint16Array::kMaxLength; }
    else if (*type && std::strcmp(*type, "uint32") == 0) { element_size = sizeof(uint32_t); maximum = v8::Uint32Array::kMaxLength; }
    if (!element_size || !std::isfinite(requested) || requested < 0 || std::floor(requested) != requested || requested > static_cast<double>(maximum)) {
        isolate->ThrowException(v8::Exception::RangeError(v8::String::NewFromUtf8Literal(isolate, "Invalid buffer size")));
        return;
    }
    const size_t count = static_cast<size_t>(requested), bytes = count * element_size;
    void *data = std::calloc(1, bytes ? bytes : 1);
    if (!data) {
        isolate->ThrowException(v8::Exception::RangeError(v8::String::NewFromUtf8Literal(isolate, "Unable to allocate buffer")));
        return;
    }
    auto backing = v8::ArrayBuffer::NewBackingStore(data, bytes, release_buffer, nullptr);
    auto buffer = v8::ArrayBuffer::New(isolate, std::move(backing));
    if (element_size == sizeof(float)) args.GetReturnValue().Set(v8::Float32Array::New(buffer, 0, count));
    else if (element_size == sizeof(uint16_t)) args.GetReturnValue().Set(v8::Uint16Array::New(buffer, 0, count));
    else args.GetReturnValue().Set(v8::Uint32Array::New(buffer, 0, count));
}

XLaserV8Runtime *xlv8_create(const char *runtime_source, const char *source) {
    error_message.clear();
    if (!runtime_source || !source) { error_message = "Missing source"; return nullptr; }
    initialize_v8();
    auto runtime = std::make_unique<XLaserV8Runtime>();
    runtime->allocator = v8::ArrayBuffer::Allocator::NewDefaultAllocator();
    v8::Isolate::CreateParams params;
    params.array_buffer_allocator = runtime->allocator;
    runtime->isolate = v8::Isolate::New(params);
    if (!runtime->isolate) { delete runtime->allocator; error_message = "Unable to create isolate"; return nullptr; }
    bool success = false;
    {
        v8::Locker locker(runtime->isolate);
        v8::Isolate::Scope isolate_scope(runtime->isolate);
        v8::HandleScope handles(runtime->isolate);
        auto context = v8::Context::New(runtime->isolate);
        v8::Context::Scope context_scope(context);
        v8::TryCatch caught(runtime->isolate);
        v8::Local<v8::Value> result, maker;
        const char *wrapper = R"JS((function(allocate) {
            const output = new Laser3DBuffer(allocate);
            return function(context, inputs) {
                output.reset();
                read(context, inputs, output);
                output.finishRead();
                return output;
            };
        }))JS";
        const char *input_maker = R"JS((function(values, modes, shapes, vertices, count) {
            const input = new Laser3DInput();
            input.values = values; input.modes = modes; input.shapes = shapes;
            input.vertexCount = vertices; input.shapeCount = count;
            return input;
        }))JS";
        if (evaluate(runtime->isolate, context, runtime_source, &result) &&
            evaluate(runtime->isolate, context, input_maker, &maker) && maker->IsFunction() &&
            evaluate(runtime->isolate, context, source, &result) &&
            evaluate(runtime->isolate, context, wrapper, &result) && result->IsFunction()) {
            v8::Local<v8::Function> allocate;
            v8::Local<v8::Value> output_reader;
            if (!v8::Function::New(context, allocate_buffer).ToLocal(&allocate)) {
                save_error(runtime->isolate, caught, "Unable to create buffer allocator");
            } else {
                v8::Local<v8::Value> args[] = {allocate};
                if (result.As<v8::Function>()->Call(context, v8::Undefined(runtime->isolate), 1, args).ToLocal(&output_reader) && output_reader->IsFunction()) {
                    result = output_reader;
                    success = true;
                } else save_error(runtime->isolate, caught, "Unable to create output buffer");
            }
        }
        if (success) {
            runtime->context.Reset(runtime->isolate, context);
            runtime->make_input.Reset(runtime->isolate, maker.As<v8::Function>());
            runtime->read.Reset(runtime->isolate, result.As<v8::Function>());
        } else if (error_message.empty()) save_error(runtime->isolate, caught, "Unable to initialize V8 script");
    }
    if (!success) { xlv8_destroy(runtime.release()); return nullptr; }
    return runtime.release();
}

static bool set_number(v8::Isolate *isolate, v8::Local<v8::Context> context, v8::Local<v8::Object> object, const char *name, double value) {
    v8::Local<v8::String> key;
    return v8::String::NewFromUtf8(isolate, name).ToLocal(&key) && object->Set(context, key, v8::Number::New(isolate, value)).FromMaybe(false);
}

static bool get_property(v8::Isolate *isolate, v8::Local<v8::Context> context, v8::Local<v8::Object> object, const char *name, v8::Local<v8::Value> *value) {
    v8::Local<v8::String> key;
    return v8::String::NewFromUtf8(isolate, name).ToLocal(&key) && object->Get(context, key).ToLocal(value);
}

static bool get_count(v8::Local<v8::Value> value, size_t *count) {
    if (!value->IsNumber()) return false;
    const double number = value.As<v8::Number>()->Value();
    if (!std::isfinite(number) || number < 0 || number > UINT32_MAX || std::floor(number) != number) return false;
    *count = static_cast<size_t>(number);
    return true;
}

template <typename T>
static bool output_view(v8::Local<v8::Value> value, size_t count, std::shared_ptr<v8::BackingStore> *owner, const T **result) {
    if constexpr (std::is_same_v<T, float>) { if (!value->IsFloat32Array()) return false; }
    if constexpr (std::is_same_v<T, uint16_t>) { if (!value->IsUint16Array()) return false; }
    if constexpr (std::is_same_v<T, uint32_t>) { if (!value->IsUint32Array()) return false; }
    auto view = value.As<v8::TypedArray>();
    if (view->Length() < count || count > std::numeric_limits<size_t>::max() / sizeof(T)) return false;
    auto buffer = view->Buffer();
    if (buffer->WasDetached()) return false;
    auto store = buffer->GetBackingStore();
    const size_t offset = view->ByteOffset(), bytes = count * sizeof(T);
    if (offset > store->ByteLength() || bytes > store->ByteLength() - offset || (bytes && !store->Data())) return false;
    *result = bytes ? reinterpret_cast<const T *>(static_cast<const char *>(store->Data()) + offset) : nullptr;
    *owner = std::move(store);
    return true;
}

int xlv8_read(XLaserV8Runtime *runtime, double time, double sample_rate, double frame_length,
              const XLaserV8Input *inputs, size_t input_count, XLaserV8Output *output) {
    if (!runtime || !output || (input_count && !inputs) || input_count > INT32_MAX) { error_message = "Invalid input"; return 1; }
    auto isolate = runtime->isolate;
    v8::Locker locker(isolate);
    v8::Isolate::Scope isolate_scope(isolate);
    v8::HandleScope handles(isolate);
    auto context = runtime->context.Get(isolate);
    v8::Context::Scope context_scope(context);
    v8::TryCatch caught(isolate);
    auto context_value = v8::Object::New(isolate);
    auto js_inputs = v8::Object::New(isolate, v8::Null(isolate), nullptr, nullptr, 0);
    if (!set_number(isolate, context, context_value, "time", time) ||
        !set_number(isolate, context, context_value, "sampleRate", sample_rate) ||
        !set_number(isolate, context, context_value, "frameLength", frame_length)) {
        save_error(isolate, caught, "Unable to create context"); return 1;
    }
    for (size_t i = 0; i < input_count; ++i) {
        const auto &input = inputs[i];
        v8::Local<v8::String> name;
        if (!input.name || !v8::String::NewFromUtf8(isolate, input.name).ToLocal(&name)) {
            error_message = "Invalid input name"; return 1;
        }
        if (input.kind == 1) {
            if (!std::isfinite(input.number) || !js_inputs->CreateDataProperty(context, name, v8::Number::New(isolate, input.number)).FromMaybe(false)) {
                error_message = "Invalid numeric input"; return 1;
            }
            continue;
        }
        if (input.kind == 2) {
            v8::Local<v8::String> json;
            v8::Local<v8::Value> value;
            if (!input.json || !v8::String::NewFromUtf8(isolate, input.json).ToLocal(&json) ||
                !v8::JSON::Parse(context, json).ToLocal(&value) ||
                !js_inputs->CreateDataProperty(context, name, value).FromMaybe(false)) {
                save_error(isolate, caught, "Invalid parameter input"); return 1;
            }
            continue;
        }
        if (input.kind >= 3 && input.kind <= 5) {
            const bool image = input.kind == 3;
            const size_t element_size = image ? sizeof(uint8_t) : sizeof(float);
            const size_t maximum = image ? v8::Uint8Array::kMaxLength : v8::Float32Array::kMaxLength;
            if (input.media_count > maximum || input.media_count > std::numeric_limits<size_t>::max() / element_size ||
                (input.media_count && !input.media_data)) { error_message = "Invalid media buffer"; return 1; }
            const size_t bytes = input.media_count * element_size;
            auto buffer = v8::ArrayBuffer::New(isolate, bytes);
            if (bytes) std::memcpy(buffer->GetBackingStore()->Data(), input.media_data, bytes);
            v8::Local<v8::Value> array = image
                ? v8::Local<v8::Value>(v8::Uint8Array::New(buffer, 0, input.media_count))
                : v8::Local<v8::Value>(v8::Float32Array::New(buffer, 0, input.media_count));
            auto media = v8::Object::New(isolate);
            v8::Local<v8::String> key;
            if (!v8::String::NewFromUtf8(isolate, image ? "rgba" : (input.kind == 4 ? "samples" : "bins")).ToLocal(&key) ||
                !media->CreateDataProperty(context, key, array).FromMaybe(false) ||
                (image && (!set_number(isolate, context, media, "width", input.dimension_a) ||
                           !set_number(isolate, context, media, "height", input.dimension_b))) ||
                (!image && (!set_number(isolate, context, media, "sampleRate", input.sample_rate) ||
                            !set_number(isolate, context, media, input.kind == 4 ? "channels" : "fftSize", input.dimension_a))) ||
                !js_inputs->CreateDataProperty(context, name, media).FromMaybe(false)) {
                save_error(isolate, caught, "Unable to create media input"); return 1;
            }
            continue;
        }
        if (input.kind != 0) { error_message = "Invalid input type"; return 1; }
        if (input.vertex_count > UINT32_MAX || input.shape_count > UINT32_MAX ||
            input.vertex_count > std::numeric_limits<size_t>::max() / (8 * sizeof(float)) ||
            input.shape_count > std::numeric_limits<size_t>::max() / (3 * sizeof(uint32_t)) ||
            (input.vertex_count && (!input.values || !input.modes)) || (input.shape_count && !input.shapes)) {
            error_message = "Invalid input buffer"; return 1;
        }
        auto value_buffer = v8::ArrayBuffer::New(isolate, input.vertex_count * 8 * sizeof(float));
        auto mode_buffer = v8::ArrayBuffer::New(isolate, input.vertex_count * sizeof(uint16_t));
        auto shape_buffer = v8::ArrayBuffer::New(isolate, input.shape_count * 3 * sizeof(uint32_t));
        if (input.vertex_count) {
            std::memcpy(value_buffer->GetBackingStore()->Data(), input.values, input.vertex_count * 8 * sizeof(float));
            std::memcpy(mode_buffer->GetBackingStore()->Data(), input.modes, input.vertex_count * sizeof(uint16_t));
        }
        if (input.shape_count) std::memcpy(shape_buffer->GetBackingStore()->Data(), input.shapes, input.shape_count * 3 * sizeof(uint32_t));
        v8::Local<v8::Value> args[] = {
            v8::Float32Array::New(value_buffer, 0, input.vertex_count * 8),
            v8::Uint16Array::New(mode_buffer, 0, input.vertex_count),
            v8::Uint32Array::New(shape_buffer, 0, input.shape_count * 3),
            v8::Number::New(isolate, static_cast<double>(input.vertex_count)),
            v8::Number::New(isolate, static_cast<double>(input.shape_count))
        };
        v8::Local<v8::Value> value;
        if (!runtime->make_input.Get(isolate)->Call(context, v8::Undefined(isolate), 5, args).ToLocal(&value) ||
            !js_inputs->CreateDataProperty(context, name, value).FromMaybe(false)) {
            save_error(isolate, caught, "Unable to create input"); return 1;
        }
    }
    v8::Local<v8::Value> args[] = {context_value, js_inputs};
    v8::Local<v8::Value> result;
    if (!runtime->read.Get(isolate)->Call(context, v8::Undefined(isolate), 2, args).ToLocal(&result)) {
        save_error(isolate, caught, "V8 execution failed"); return 1;
    }
    if (!result->IsObject()) { error_message = "Invalid output"; return 2; }
    auto object = result.As<v8::Object>();
    v8::Local<v8::Value> shape_count_value, vertex_count_value, shapes, values, modes, shape_matrices, shape_tints;
    size_t shape_count, vertex_count;
    const float *output_values = nullptr;
    const uint16_t *output_modes = nullptr;
    const uint32_t *output_shapes = nullptr;
    const float *output_matrices = nullptr;
    const float *output_tints = nullptr;
    if (!get_property(isolate, context, object, "shapeCount", &shape_count_value) ||
        !get_property(isolate, context, object, "vertexCount", &vertex_count_value) ||
        !get_count(shape_count_value, &shape_count) || !get_count(vertex_count_value, &vertex_count) ||
        shape_count > std::numeric_limits<size_t>::max() / 16 || vertex_count > std::numeric_limits<size_t>::max() / 8 ||
        !get_property(isolate, context, object, "shapes", &shapes) ||
        !get_property(isolate, context, object, "values", &values) ||
        !get_property(isolate, context, object, "modes", &modes) ||
        !get_property(isolate, context, object, "shapeMatrices", &shape_matrices) ||
        !get_property(isolate, context, object, "shapeColors", &shape_tints) ||
        !output_view(shapes, shape_count * 3, &runtime->shapes, &output_shapes) ||
        !output_view(values, vertex_count * 8, &runtime->values, &output_values) ||
        !output_view(modes, vertex_count, &runtime->modes, &output_modes) ||
        !output_view(shape_matrices, shape_count * 16, &runtime->shape_matrices, &output_matrices) ||
        !output_view(shape_tints, shape_count * 4, &runtime->shape_tints, &output_tints)) {
        error_message = "Invalid output"; return 2;
    }
    *output = {output_values, output_modes, output_shapes, vertex_count, shape_count, output_matrices, output_tints};
    return 0;
}

int xlv8_available(void) { return 1; }
const char *xlv8_error(void) { return error_message.c_str(); }
#else
int xlv8_available(void) { return 0; }
XLaserV8Runtime *xlv8_create(const char *, const char *) { return nullptr; }
void xlv8_destroy(XLaserV8Runtime *) {}
int xlv8_read(XLaserV8Runtime *, double, double, double, const XLaserV8Input *, size_t, XLaserV8Output *) { return 1; }
const char *xlv8_error(void) { return "V8 library is not configured"; }
#endif
