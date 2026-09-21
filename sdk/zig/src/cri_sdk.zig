pub const abi_version = "cri.extension.v1";

pub const Request = struct {
    kind: []const u8,
    name: []const u8,
    input: []const u8,
    raw: []const u8,
    is_resume: bool,

    pub fn input_string(self: Request, field: []const u8) ?[]const u8 {
        return string_field(self.input, field);
    }

    pub fn input_value(self: Request, field: []const u8) ?[]const u8 {
        return value_field(self.input, field);
    }
};

pub const Response = struct {
    ok: bool = true,
    result_json: []const u8 = "null",
    effects_json: []const u8 = "[]",
    error_message: ?[]const u8 = null,

    pub fn success(result: []const u8) Response {
        return .{ .result_json = result };
    }

    pub fn with_effects(result: []const u8, effects: []const u8) Response {
        return .{ .result_json = result, .effects_json = effects };
    }

    pub fn failure(message: []const u8) Response {
        return .{ .ok = false, .error_message = message };
    }
};

pub const Extension = struct {
    call: *const fn (Request) Response,
    resume_fn: ?*const fn (Request) Response = null,
};

const heap_start: usize = 4096;
const heap_size: usize = 1024 * 1024;
const output_size: usize = 64 * 1024;

var heap: [heap_size]u8 align(16) = undefined;
var output: [output_size]u8 align(16) = undefined;
var heap_offset: usize = heap_start;
var output_length: usize = 0;
var extension: ?Extension = null;

pub fn register(value: Extension) void {
    extension = value;
}

pub fn request_has(request: Request, field: []const u8, value: []const u8) bool {
    var needle_buffer: [128]u8 = undefined;
    const needle = std.fmt.bufPrint(&needle_buffer, "\"{s}\":\"{s}\"", .{ field, value }) catch return false;
    return indexOf(request.raw, needle) != null;
}

pub fn json_string(value: []const u8, buffer: []u8) []const u8 {
    var index: usize = 0;
    if (buffer.len < 2) return buffer[0..0];
    buffer[index] = '"';
    index += 1;
    for (value) |byte| {
        if (index + 2 >= buffer.len) break;
        if (byte == '"' or byte == '\\') {
            buffer[index] = '\\';
            index += 1;
        }
        buffer[index] = byte;
        index += 1;
    }
    buffer[index] = '"';
    return buffer[0 .. index + 1];
}

export fn alloc(size: u32) u32 {
    const requested = @as(usize, size);
    if (requested == 0 or requested > heap.len - heap_offset) return 0;
    const pointer = @intFromPtr(heap[heap_offset..].ptr);
    heap_offset += requested;
    return @truncate(pointer);
}

export fn cri_free(_: u32, _: u32) void {}

export fn cri_call(input_pointer: u32, input_length: u32) u32 {
    return invoke(input_pointer, input_length, false);
}

export fn cri_resume(input_pointer: u32, input_length: u32) u32 {
    return invoke(input_pointer, input_length, true);
}

export fn cri_result_len() u32 {
    return @truncate(output_length);
}

export fn cri_free_result(_: u32, _: u32) void {
    output_length = 0;
}

fn invoke(input_pointer: u32, input_length: u32, is_resume: bool) u32 {
    const pointer: [*]const u8 = @ptrFromInt(input_pointer);
    const raw = pointer[0..input_length];
    const request = Request{
        .kind = if (is_resume) "resume" else (string_field(raw, "kind") orelse ""),
        .name = string_field(raw, "name") orelse "",
        .input = value_field(raw, if (is_resume) "results" else "input") orelse "null",
        .raw = raw,
        .is_resume = is_resume,
    };

    const current = extension orelse return write_response(Response.failure("SDK extension is not registered"));
    const response = if (is_resume and current.resume_fn != null)
        current.resume_fn.?(request)
    else if (is_resume)
        Response.failure("SDK extension does not implement resume")
    else
        current.call(request);
    return write_response(response);
}

fn write_response(response: Response) u32 {
    var index: usize = 0;
    index = append(&output, index, if (response.ok) "{\"ok\":true,\"result\":" else "{\"ok\":false,\"result\":null");
    if (response.ok) {
        index = append(&output, index, response.result_json);
        index = append(&output, index, ",\"effects\":");
        index = append(&output, index, response.effects_json);
    } else {
        index = append(&output, index, ",\"effects\":[],\"error\":\"");
        index = append_escaped(&output, index, response.error_message orelse "unknown error");
        index = append(&output, index, "\"");
    }
    index = append(&output, index, "}");
    output_length = index;
    return @truncate(@intFromPtr(&output[0]));
}

fn append(buffer: []u8, start: usize, value: []const u8) usize {
    if (start >= buffer.len) return start;
    const amount = @min(value.len, buffer.len - start);
    @memcpy(buffer[start .. start + amount], value[0..amount]);
    return start + amount;
}

fn append_escaped(buffer: []u8, start: usize, value: []const u8) usize {
    var index = start;
    for (value) |byte| {
        if (byte == '"' or byte == '\\') index = append(buffer, index, "\\");
        if (index < buffer.len) {
            buffer[index] = byte;
            index += 1;
        }
    }
    return index;
}

fn string_field(json: []const u8, field: []const u8) ?[]const u8 {
    var prefix_buffer: [64]u8 = undefined;
    const prefix = std.fmt.bufPrint(&prefix_buffer, "\"{s}\":\"", .{field}) catch return null;
    const start = indexOf(json, prefix) orelse return null;
    const value_start = start + prefix.len;
    var index = value_start;
    while (index < json.len) : (index += 1) {
        if (json[index] == '"' and (index == value_start or json[index - 1] != '\\')) {
            return json[value_start..index];
        }
    }
    return null;
}

fn value_field(json: []const u8, field: []const u8) ?[]const u8 {
    var prefix_buffer: [64]u8 = undefined;
    const prefix = std.fmt.bufPrint(&prefix_buffer, "\"{s}\":", .{field}) catch return null;
    const start = indexOf(json, prefix) orelse return null;
    var value_start = start + prefix.len;
    while (value_start < json.len and (json[value_start] == ' ' or json[value_start] == '\n' or json[value_start] == '\r' or json[value_start] == '\t')) : (value_start += 1) {}
    if (value_start >= json.len) return null;

    const first = json[value_start];
    if (first == '"') {
        var index = value_start + 1;
        while (index < json.len) : (index += 1) {
            if (json[index] == '"' and json[index - 1] != '\\') return json[value_start .. index + 1];
        }
        return null;
    }

    if (first == '{' or first == '[') {
        var depth: usize = 0;
        var quoted = false;
        var escaped = false;
        var index = value_start;
        while (index < json.len) : (index += 1) {
            const byte = json[index];
            if (quoted) {
                if (escaped) escaped = false else if (byte == '\\') escaped = true else if (byte == '"') quoted = false;
            } else if (byte == '"') {
                quoted = true;
            } else if (byte == '{' or byte == '[') {
                depth += 1;
            } else if (byte == '}' or byte == ']') {
                depth -= 1;
                if (depth == 0) return json[value_start .. index + 1];
            }
        }
        return null;
    }

    var index = value_start;
    while (index < json.len and json[index] != ',' and json[index] != '}') : (index += 1) {}
    return json[value_start..index];
}

fn indexOf(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (needle.len > haystack.len) return null;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (std.mem.eql(u8, haystack[index .. index + needle.len], needle)) return index;
    }
    return null;
}

const std = @import("std");
