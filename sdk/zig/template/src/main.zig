const cri = @import("cri_sdk");

fn call(request: cri.Request) cri.Response {
    _ = request;
    return cri.Response.success("{\"message\":\"hello from a Zig cri extension\"}");
}

fn resume_extension(request: cri.Request) cri.Response {
    return cri.Response.success(request.input);
}

export fn cri_init() void {
    cri.register(.{ .call = call, .resume_fn = resume_extension });
}
