#include "CV8Bridge.h"
#if defined(XLASER_V8_ENABLED)
#include <libplatform/libplatform.h>
#include <v8.h>
#include <cmath>
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

struct XLaserV8Runtime {
    v8::ArrayBuffer::Allocator *allocator = nullptr;
    v8::Isolate *isolate = nullptr;
    v8::Global<v8::Context> context;
    v8::Global<v8::Function> read;
    v8::Global<v8::Function> make_input;
    std::vector<double> values;
    std::vector<uint16_t> modes;
    std::vector<uint32_t> shapes;
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
        }
        runtime->isolate->Dispose();
    }
    delete runtime->allocator;
    delete runtime;
}

XLaserV8Runtime *xlv8_create(const char *runtime_source, const char *source) {
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
        const char *wrapper = R"JS((function() {
            const output = new Laser3DStream();
            return function(context, inputs) {
                output.reset();
                read(context, inputs, output);
                return output;
            };
        })())JS";
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
            runtime->context.Reset(runtime->isolate, context);
            runtime->make_input.Reset(runtime->isolate, maker.As<v8::Function>());
            runtime->read.Reset(runtime->isolate, result.As<v8::Function>());
            success = true;
        } else save_error(runtime->isolate, caught, "Unable to initialize V8 script");
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
static bool copy_output(v8::Local<v8::Value> value, size_t count, std::vector<T> *output) {
    if constexpr (std::is_same_v<T, double>) { if (!value->IsFloat64Array()) return false; }
    if constexpr (std::is_same_v<T, uint16_t>) { if (!value->IsUint16Array()) return false; }
    if constexpr (std::is_same_v<T, uint32_t>) { if (!value->IsUint32Array()) return false; }
    auto view = value.As<v8::TypedArray>();
    if (view->Length() < count || count > std::numeric_limits<size_t>::max() / sizeof(T)) return false;
    const size_t bytes = count * sizeof(T);
    output->resize(count);
    return !bytes || view->CopyContents(output->data(), bytes) == bytes;
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
    auto js_inputs = v8::Array::New(isolate, static_cast<int>(input_count));
    if (!set_number(isolate, context, context_value, "time", time) ||
        !set_number(isolate, context, context_value, "sampleRate", sample_rate) ||
        !set_number(isolate, context, context_value, "frameLength", frame_length)) {
        save_error(isolate, caught, "Unable to create context"); return 1;
    }
    for (size_t i = 0; i < input_count; ++i) {
        const auto &input = inputs[i];
        if (input.vertex_count > UINT32_MAX || input.shape_count > UINT32_MAX ||
            input.vertex_count > std::numeric_limits<size_t>::max() / (8 * sizeof(double)) ||
            input.shape_count > std::numeric_limits<size_t>::max() / (3 * sizeof(uint32_t)) ||
            (input.vertex_count && (!input.values || !input.modes)) || (input.shape_count && !input.shapes)) {
            error_message = "Invalid input buffer"; return 1;
        }
        auto value_buffer = v8::ArrayBuffer::New(isolate, input.vertex_count * 8 * sizeof(double));
        auto mode_buffer = v8::ArrayBuffer::New(isolate, input.vertex_count * sizeof(uint16_t));
        auto shape_buffer = v8::ArrayBuffer::New(isolate, input.shape_count * 3 * sizeof(uint32_t));
        if (input.vertex_count) {
            std::memcpy(value_buffer->GetBackingStore()->Data(), input.values, input.vertex_count * 8 * sizeof(double));
            std::memcpy(mode_buffer->GetBackingStore()->Data(), input.modes, input.vertex_count * sizeof(uint16_t));
        }
        if (input.shape_count) std::memcpy(shape_buffer->GetBackingStore()->Data(), input.shapes, input.shape_count * 3 * sizeof(uint32_t));
        v8::Local<v8::Value> args[] = {
            v8::Float64Array::New(value_buffer, 0, input.vertex_count * 8),
            v8::Uint16Array::New(mode_buffer, 0, input.vertex_count),
            v8::Uint32Array::New(shape_buffer, 0, input.shape_count * 3),
            v8::Number::New(isolate, static_cast<double>(input.vertex_count)),
            v8::Number::New(isolate, static_cast<double>(input.shape_count))
        };
        v8::Local<v8::Value> value;
        if (!runtime->make_input.Get(isolate)->Call(context, v8::Undefined(isolate), 5, args).ToLocal(&value) ||
            !js_inputs->Set(context, static_cast<uint32_t>(i), value).FromMaybe(false)) {
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
    v8::Local<v8::Value> shape_count_value, vertex_count_value, shapes, values, modes;
    size_t shape_count, vertex_count;
    if (!get_property(isolate, context, object, "shapeCount", &shape_count_value) ||
        !get_property(isolate, context, object, "vertexCount", &vertex_count_value) ||
        !get_count(shape_count_value, &shape_count) || !get_count(vertex_count_value, &vertex_count) ||
        shape_count > std::numeric_limits<size_t>::max() / 3 || vertex_count > std::numeric_limits<size_t>::max() / 8 ||
        !get_property(isolate, context, object, "shapes", &shapes) ||
        !get_property(isolate, context, object, "values", &values) ||
        !get_property(isolate, context, object, "modes", &modes) ||
        !copy_output(shapes, shape_count * 3, &runtime->shapes) ||
        !copy_output(values, vertex_count * 8, &runtime->values) ||
        !copy_output(modes, vertex_count, &runtime->modes)) {
        error_message = "Invalid output"; return 2;
    }
    *output = {runtime->values.data(), runtime->modes.data(), runtime->shapes.data(), vertex_count, shape_count};
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
