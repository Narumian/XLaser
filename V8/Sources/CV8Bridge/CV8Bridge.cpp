#include "CV8Bridge.h"
#include <libplatform/libplatform.h>
#include <v8.h>
#include <memory>
#include <mutex>
#include <string>

struct XLaserV8Runtime {
    v8::ArrayBuffer::Allocator *allocator = nullptr;
    v8::Isolate *isolate = nullptr;
    v8::Global<v8::Context> context;
    v8::Global<v8::Function> read;
    std::string result;
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
    } else {
        error_message = fallback;
    }
}

static bool evaluate(v8::Isolate *isolate, v8::Local<v8::Context> context, const char *source, v8::Local<v8::Value> *result) {
    auto text = v8::String::NewFromUtf8(isolate, source);
    v8::Local<v8::String> code;
    v8::Local<v8::Script> script;
    return text.ToLocal(&code) && v8::Script::Compile(context, code).ToLocal(&script) && script->Run(context).ToLocal(result);
}

void xlv8_destroy(XLaserV8Runtime *runtime) {
    if (!runtime) return;
    if (runtime->isolate) {
        {
            v8::Locker locker(runtime->isolate);
            v8::Isolate::Scope isolate_scope(runtime->isolate);
            runtime->read.Reset();
            runtime->context.Reset();
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
        v8::Local<v8::Value> result;
        const char *wrapper = R"JS((function() {
            const output = new Laser3DStream();
            return function(context, rawInputs) {
                const inputs = rawInputs.map(shapes => {
                    const input = new Laser3DInput();
                    let count = 0;
                    for (const shape of shapes) count += shape.vertices.length;
                    input.prepare(count, shapes.length);
                    let vertex = 0;
                    for (let i = 0; i < shapes.length; i++) {
                        const shape = shapes[i];
                        input.shapes[i * 3] = shape.id;
                        input.shapes[i * 3 + 1] = vertex;
                        input.shapes[i * 3 + 2] = shape.vertices.length;
                        for (const item of shape.vertices) {
                            input.values.set(item.position, vertex * 8);
                            input.values.set(item.rgba, vertex * 8 + 4);
                            input.modes[vertex++] = item.mode;
                        }
                    }
                    return input;
                });
                output.reset();
                read(context, inputs, output);
                if (!Number.isInteger(output.shapeCount) || output.shapeCount < 0 || output.shapeCount > 0xffffffff ||
                    !Number.isInteger(output.vertexCount) || output.vertexCount < 0 || output.vertexCount > 0xffffffff ||
                    !(output.shapes instanceof Uint32Array) || output.shapes.length < output.shapeCount * 3 ||
                    !(output.values instanceof Float64Array) || output.values.length < output.vertexCount * 8 ||
                    !(output.modes instanceof Uint16Array) || output.modes.length < output.vertexCount)
                    return JSON.stringify({});
                return JSON.stringify({
                    shapes: Array.from(output.shapes.subarray(0, output.shapeCount * 3)),
                    values: Array.from(output.values.subarray(0, output.vertexCount * 8)),
                    modes: Array.from(output.modes.subarray(0, output.vertexCount))
                });
            };
        })())JS";
        if (evaluate(runtime->isolate, context, runtime_source, &result) &&
            evaluate(runtime->isolate, context, source, &result) &&
            evaluate(runtime->isolate, context, wrapper, &result) && result->IsFunction()) {
            runtime->context.Reset(runtime->isolate, context);
            runtime->read.Reset(runtime->isolate, result.As<v8::Function>());
            success = true;
        } else {
            save_error(runtime->isolate, caught, "Unable to initialize V8 script");
        }
    }
    if (!success) { xlv8_destroy(runtime.release()); return nullptr; }
    return runtime.release();
}

const char *xlv8_read(XLaserV8Runtime *runtime, const char *context_json, const char *inputs_json) {
    if (!runtime || !context_json || !inputs_json) { error_message = "Invalid arguments"; return nullptr; }
    auto isolate = runtime->isolate;
    v8::Locker locker(isolate);
    v8::Isolate::Scope isolate_scope(isolate);
    v8::HandleScope handles(isolate);
    auto context = runtime->context.Get(isolate);
    v8::Context::Scope context_scope(context);
    v8::TryCatch caught(isolate);
    v8::Local<v8::String> context_text, inputs_text;
    v8::Local<v8::Value> arguments[2], value;
    if (!v8::String::NewFromUtf8(isolate, context_json).ToLocal(&context_text) ||
        !v8::String::NewFromUtf8(isolate, inputs_json).ToLocal(&inputs_text) ||
        !v8::JSON::Parse(context, context_text).ToLocal(&arguments[0]) ||
        !v8::JSON::Parse(context, inputs_text).ToLocal(&arguments[1]) ||
        !runtime->read.Get(isolate)->Call(context, v8::Undefined(isolate), 2, arguments).ToLocal(&value)) {
        save_error(isolate, caught, "V8 execution failed");
        return nullptr;
    }
    v8::String::Utf8Value text(isolate, value);
    if (!*text) { error_message = "Unable to encode output"; return nullptr; }
    runtime->result.assign(*text, text.length());
    return runtime->result.c_str();
}

const char *xlv8_error(void) { return error_message.c_str(); }
