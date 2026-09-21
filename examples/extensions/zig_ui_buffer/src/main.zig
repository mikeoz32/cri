const cri = @import("cri_sdk");
const effects = @import("cri_effects");

var effect_create: [512]u8 = undefined;
var effect_append: [512]u8 = undefined;
var effect_replace: [512]u8 = undefined;
var effect_style: [512]u8 = undefined;
var effect_highlight: [512]u8 = undefined;
var effect_panel_open: [512]u8 = undefined;
var effect_panel_focus: [512]u8 = undefined;
var effect_list: [3584]u8 = undefined;

fn add_effect(cursor: usize, encoded: []const u8) usize {
    @memcpy(effect_list[cursor .. cursor + encoded.len], encoded);
    return cursor + encoded.len;
}

fn call(request: cri.Request) cri.Response {
    _ = request;
    const create = effects.ui.buffer_create("review", "created by a real Zig plugin", &effect_create);
    const append = effects.ui.buffer_append("review", " + appended", &effect_append);
    const replace = effects.ui.buffer_replace("review", "final content", &effect_replace);
    const style = effects.ui.highlight_define("plugin_accent", 45, true, false, &effect_style);
    const highlight = effects.ui.highlight_set("review", 0, 5, "plugin_accent", &effect_highlight);
    const open = effects.ui.panel_open("review", "review", "Plugin Review", "right", false, &effect_panel_open);
    const focus = effects.ui.panel_focus("review", &effect_panel_focus);

    effect_list[0] = '[';
    var cursor: usize = 1;
    cursor = add_effect(cursor, create);
    effect_list[cursor] = ',';
    cursor += 1;
    cursor = add_effect(cursor, append);
    effect_list[cursor] = ',';
    cursor += 1;
    cursor = add_effect(cursor, replace);
    effect_list[cursor] = ',';
    cursor += 1;
    cursor = add_effect(cursor, style);
    effect_list[cursor] = ',';
    cursor += 1;
    cursor = add_effect(cursor, highlight);
    effect_list[cursor] = ',';
    cursor += 1;
    cursor = add_effect(cursor, open);
    effect_list[cursor] = ',';
    cursor += 1;
    cursor = add_effect(cursor, focus);
    effect_list[cursor] = ']';
    cursor += 1;
    return cri.Response.with_effects("null", effect_list[0..cursor]);
}

fn resume_extension(_: cri.Request) cri.Response {
    return cri.Response.success("null");
}

export fn cri_init() void {
    cri.register(.{ .call = call, .resume_fn = resume_extension });
}
