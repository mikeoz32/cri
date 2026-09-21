pub const http = struct {
    pub fn get(url: []const u8, output: []u8) []const u8 {
        return request("GET", url, "", null, output);
    }

    pub fn get_with_secret(url: []const u8, secret: []const u8, output: []u8) []const u8 {
        return request("GET", url, "", secret, output);
    }

    pub fn request(method: []const u8, url: []const u8, body: []const u8, secret: ?[]const u8, output: []u8) []const u8 {
        var index: usize = 0;
        index = append(output, index, "{\"type\":\"http.request\",\"method\":\"");
        index = append_escaped(output, index, method);
        index = append(output, index, "\",\"url\":\"");
        index = append_escaped(output, index, url);
        index = append(output, index, "\"");
        if (body.len > 0) {
            index = append(output, index, ",\"body\":");
            index = append(output, index, body);
        }
        if (secret) |secret_name| {
            index = append(output, index, ",\"auth\":{\"secret\":\"");
            index = append_escaped(output, index, secret_name);
            index = append(output, index, "\",\"as\":\"bearer\"}");
        }
        index = append(output, index, "}");
        return output[0..index];
    }
};

pub fn read_file(path: []const u8, output: []u8) []const u8 {
    var index = append(output, 0, "{\"type\":\"file.read\",\"path\":\"");
    index = append_escaped(output, index, path);
    index = append(output, index, "\"}");
    return output[0..index];
}

pub fn propose_edit(path: []const u8, content: []const u8, output: []u8) []const u8 {
    var index = append(output, 0, "{\"type\":\"file.propose_edit\",\"path\":\"");
    index = append_escaped(output, index, path);
    index = append(output, index, "\",\"content\":\"");
    index = append_escaped(output, index, content);
    index = append(output, index, "\"}");
    return output[0..index];
}

pub fn notify(message: []const u8, output: []u8) []const u8 {
    var index = append(output, 0, "{\"type\":\"ui.notification\",\"message\":\"");
    index = append_escaped(output, index, message);
    index = append(output, index, "\"}");
    return output[0..index];
}

pub const ui = struct {
    pub fn buffer_create(id: []const u8, content: []const u8, output: []u8) []const u8 {
        return buffer_mutation("ui.buffer.create", id, content, output);
    }

    pub fn buffer_append(id: []const u8, content: []const u8, output: []u8) []const u8 {
        return buffer_mutation("ui.buffer.append", id, content, output);
    }

    pub fn buffer_replace(id: []const u8, content: []const u8, output: []u8) []const u8 {
        return buffer_mutation("ui.buffer.replace", id, content, output);
    }

    pub fn highlight_define(group: []const u8, foreground: ?usize, bold: bool, underline: bool, output: []u8) []const u8 {
        var index = append(output, 0, "{\"type\":\"ui.highlight.define\",\"group\":\"");
        index = append_escaped(output, index, group);
        if (foreground) |color| {
            index = append(output, index, "\",\"foreground\":");
            index = append_number(output, index, color);
        } else {
            index = append(output, index, "\",\"foreground\":null");
        }
        index = append(output, index, ",\"bold\":");
        index = append(output, index, if (bold) "true" else "false");
        index = append(output, index, ",\"underline\":");
        index = append(output, index, if (underline) "true" else "false");
        index = append(output, index, "}");
        return output[0..index];
    }

    pub fn highlight_set(id: []const u8, start: usize, finish: usize, group: []const u8, output: []u8) []const u8 {
        var index = append(output, 0, "{\"type\":\"ui.highlight.set\",\"id\":\"");
        index = append_escaped(output, index, id);
        index = append(output, index, "\",\"start\":");
        index = append_number(output, index, start);
        index = append(output, index, ",\"finish\":");
        index = append_number(output, index, finish);
        index = append(output, index, ",\"group\":\"");
        index = append_escaped(output, index, group);
        index = append(output, index, "\"}");
        return output[0..index];
    }

    pub fn panel_open(id: []const u8, buffer_id: []const u8, title: []const u8, position: []const u8, focus: bool, output: []u8) []const u8 {
        var index = append(output, 0, "{\"type\":\"ui.panel.open\",\"id\":\"");
        index = append_escaped(output, index, id);
        index = append(output, index, "\",\"buffer_id\":\"");
        index = append_escaped(output, index, buffer_id);
        index = append(output, index, "\",\"title\":\"");
        index = append_escaped(output, index, title);
        index = append(output, index, "\",\"position\":\"");
        index = append_escaped(output, index, position);
        index = append(output, index, "\",\"focus\":");
        index = append(output, index, if (focus) "true" else "false");
        index = append(output, index, "}");
        return output[0..index];
    }

    pub fn panel_focus(id: []const u8, output: []u8) []const u8 {
        var index = append(output, 0, "{\"type\":\"ui.panel.focus\",\"id\":\"");
        index = append_escaped(output, index, id);
        index = append(output, index, "\"}");
        return output[0..index];
    }
};

fn buffer_mutation(kind: []const u8, id: []const u8, content: []const u8, output: []u8) []const u8 {
    var index = append(output, 0, "{\"type\":\"");
    index = append(output, index, kind);
    index = append(output, index, "\",\"id\":\"");
    index = append_escaped(output, index, id);
    index = append(output, index, "\",\"content\":\"");
    index = append_escaped(output, index, content);
    index = append(output, index, "\"}");
    return output[0..index];
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

fn append_number(buffer: []u8, start: usize, value: usize) usize {
    var digits: [20]u8 = undefined;
    var count: usize = 0;
    var number = value;
    while (true) {
        digits[count] = @as(u8, @intCast(number % 10)) + '0';
        count += 1;
        number /= 10;
        if (number == 0) break;
    }

    var index = start;
    while (count > 0) {
        count -= 1;
        if (index < buffer.len) {
            buffer[index] = digits[count];
            index += 1;
        }
    }
    return index;
}
