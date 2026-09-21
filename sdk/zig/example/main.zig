const std = @import("std");
const cri = @import("cri_sdk");
const effects = @import("cri_effects");

var url_buffer: [1024]u8 = undefined;
var effect_buffer: [2048]u8 = undefined;
var effects_buffer: [2200]u8 = undefined;

fn call(request: cri.Request) cri.Response {
    if (!std.mem.eql(u8, request.name, "zig.fetch")) {
        return cri.Response.failure("unknown tool");
    }

    const repo = request.input_string("repo") orelse return cri.Response.failure("missing input: repo");
    const issue = request.input_string("issue") orelse return cri.Response.failure("missing input: issue");
    const url = std.fmt.bufPrint(&url_buffer, "https://api.github.com/repos/{s}/issues/{s}", .{ repo, issue }) catch return cri.Response.failure("request is too long");
    const effect = effects.http.get_with_secret(url, "GITHUB_TOKEN", effect_buffer[0..]);
    effects_buffer[0] = '[';
    @memcpy(effects_buffer[1 .. effect.len + 1], effect);
    effects_buffer[effect.len + 1] = ']';
    return cri.Response.with_effects("null", effects_buffer[0 .. effect.len + 2]);
}

fn resume_extension(request: cri.Request) cri.Response {
    // The resume input is the host result array. Return it unchanged as the tool result.
    return cri.Response.success(request.input);
}

export fn cri_init() void {
    cri.register(.{ .call = call, .resume_fn = resume_extension });
}
