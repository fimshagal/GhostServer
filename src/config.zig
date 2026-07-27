const std = @import("std");
const json = std.json;
const actions = @import("actions.zig");

pub const Mode = enum { rest, ws };

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const Route = struct {
    /// HTTP method name (uppercase), or "*" / "ANY" for any method.
    method: []const u8,
    /// Exact path or pattern with `:param` segments, e.g. `/api/users/:id`.
    path: []const u8,
    status: u16,
    delay_ms: u32,
    headers: []const Header,
    /// Template body; action markers are resolved per request. null = empty body.
    body_template: ?json.Value,
    /// True when the original body was a JSON object/array (not a bare string).
    body_is_json: bool,
    /// Default Content-Type applied when the route does not set one.
    content_type: []const u8,
};

pub const Config = struct {
    arena: std.heap.ArenaAllocator,
    mode: Mode,
    host: []const u8,
    port: u16,
    // REST
    cors: bool,
    routes: []const Route,
    // WebSocket
    path: []const u8,
    interval_ms: u32,
    message_template: ?json.Value,
    message_is_json: bool,
};

const RawRoute = struct {
    method: []const u8 = "GET",
    path: []const u8,
    status: u16 = 200,
    delay_ms: u32 = 0,
    headers: ?json.Value = null,
    body: ?json.Value = null,
};

const RawConfig = struct {
    mode: []const u8 = "rest",
    host: []const u8 = "127.0.0.1",
    port: u16 = 8080,
    cors: bool = true,
    routes: []RawRoute = &.{},
    path: []const u8 = "/ws",
    interval_ms: u32 = 1000,
    message: ?json.Value = null,
};

pub fn loadFromFile(
    gpa: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) !Config {
    const bytes = try std.Io.Dir.readFileAlloc(
        .cwd(),
        io,
        path,
        gpa,
        .limited(16 * 1024 * 1024),
    );
    defer gpa.free(bytes);
    return parse(gpa, bytes);
}

pub fn parse(gpa: std.mem.Allocator, bytes: []const u8) !Config {
    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const allocator = arena.allocator();

    const raw = try json.parseFromSliceLeaky(RawConfig, allocator, bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });

    const mode = try parseMode(raw.mode);

    var routes: std.ArrayList(Route) = .empty;
    for (raw.routes) |raw_route| {
        try routes.append(allocator, try buildRoute(allocator, raw_route));
    }

    const message_is_json = if (raw.message) |message| switch (message) {
        .object, .array => true,
        else => false,
    } else true;

    if (mode == .ws and raw.message == null) return error.MissingWsMessage;

    return .{
        .arena = arena,
        .mode = mode,
        .host = raw.host,
        .port = raw.port,
        .cors = raw.cors,
        .routes = try routes.toOwnedSlice(allocator),
        .path = raw.path,
        .interval_ms = raw.interval_ms,
        .message_template = raw.message,
        .message_is_json = message_is_json,
    };
}

pub fn deinit(config: *Config) void {
    config.arena.deinit();
    config.* = undefined;
}

fn parseMode(text: []const u8) !Mode {
    if (std.ascii.eqlIgnoreCase(text, "rest")) return .rest;
    if (std.ascii.eqlIgnoreCase(text, "ws") or std.ascii.eqlIgnoreCase(text, "websocket")) return .ws;
    return error.InvalidMode;
}

fn buildRoute(allocator: std.mem.Allocator, raw: RawRoute) !Route {
    var headers: std.ArrayList(Header) = .empty;
    var has_content_type = false;

    if (raw.headers) |headers_value| {
        if (headers_value != .object) return error.InvalidHeaders;
        var it = headers_value.object.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* != .string) return error.InvalidHeaderValue;
            if (std.ascii.eqlIgnoreCase(entry.key_ptr.*, "content-type")) has_content_type = true;
            try headers.append(allocator, .{
                .name = entry.key_ptr.*,
                .value = entry.value_ptr.*.string,
            });
        }
    }

    const body_is_json = if (raw.body) |body| switch (body) {
        .object, .array => true,
        else => false,
    } else false;

    const default_content_type: []const u8 = if (body_is_json)
        "application/json; charset=utf-8"
    else
        "text/plain; charset=utf-8";

    const content_type = if (has_content_type) "" else default_content_type;

    return .{
        .method = try uppercaseOwned(allocator, raw.method),
        .path = raw.path,
        .status = raw.status,
        .delay_ms = raw.delay_ms,
        .headers = try headers.toOwnedSlice(allocator),
        .body_template = raw.body,
        .body_is_json = body_is_json,
        .content_type = content_type,
    };
}

fn uppercaseOwned(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    const out = try allocator.dupe(u8, text);
    for (out) |*c| c.* = std.ascii.toUpper(c.*);
    return out;
}

/// Resolve `!{ACTION}` markers and render bytes.
pub fn renderTemplate(
    allocator: std.mem.Allocator,
    template: ?json.Value,
    as_json: bool,
    random: std.Random,
    io: std.Io,
    sequences: *actions.SequenceState,
) ![]u8 {
    const value = template orelse return try allocator.dupe(u8, "");
    const ctx: actions.Context = .{
        .allocator = allocator,
        .random = random,
        .io = io,
        .sequences = sequences,
    };
    const resolved = try actions.resolveValue(ctx, value);
    return renderValue(allocator, resolved, as_json);
}

/// Resolve route body template for REST responses.
pub fn renderBody(
    allocator: std.mem.Allocator,
    route: *const Route,
    random: std.Random,
    io: std.Io,
    sequences: *actions.SequenceState,
) ![]u8 {
    return renderTemplate(allocator, route.body_template, route.body_is_json, random, io, sequences);
}

/// Resolve WS message template.
pub fn renderMessage(
    allocator: std.mem.Allocator,
    config: *const Config,
    random: std.Random,
    io: std.Io,
    sequences: *actions.SequenceState,
) ![]u8 {
    return renderTemplate(allocator, config.message_template, config.message_is_json, random, io, sequences);
}

fn renderValue(allocator: std.mem.Allocator, value: json.Value, as_json: bool) ![]u8 {
    if (as_json) {
        return json.Stringify.valueAlloc(allocator, value, .{});
    }

    return switch (value) {
        .string => |s| try allocator.dupe(u8, s),
        .null => try allocator.dupe(u8, ""),
        .bool => |b| try allocator.dupe(u8, if (b) "true" else "false"),
        .integer => |i| try std.fmt.allocPrint(allocator, "{d}", .{i}),
        .float => |f| try std.fmt.allocPrint(allocator, "{d}", .{f}),
        .number_string => |s| try allocator.dupe(u8, s),
        .array, .object => try json.Stringify.valueAlloc(allocator, value, .{}),
    };
}

pub fn pathWithoutQuery(target: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, target, '?')) |idx| return target[0..idx];
    return target;
}

pub fn methodMatches(route_method: []const u8, request_method: []const u8) bool {
    if (std.mem.eql(u8, route_method, "*") or std.mem.eql(u8, route_method, "ANY")) return true;
    return std.ascii.eqlIgnoreCase(route_method, request_method);
}

pub fn pathMatches(pattern: []const u8, path: []const u8) bool {
    var pattern_it = std.mem.splitScalar(u8, pattern, '/');
    var path_it = std.mem.splitScalar(u8, path, '/');

    while (true) {
        const pattern_part = pattern_it.next();
        const path_part = path_it.next();
        if (pattern_part == null and path_part == null) return true;
        if (pattern_part == null or path_part == null) return false;

        if (pattern_part.?.len > 0 and pattern_part.?[0] == ':') continue;
        if (!std.mem.eql(u8, pattern_part.?, path_part.?)) return false;
    }
}

pub fn findRoute(config: *const Config, method: []const u8, path: []const u8) ?*const Route {
    for (config.routes) |*route| {
        if (!methodMatches(route.method, method)) continue;
        if (!pathMatches(route.path, path)) continue;
        return route;
    }
    return null;
}

test "path matching supports params" {
    try std.testing.expect(pathMatches("/api/users/:id", "/api/users/42"));
    try std.testing.expect(!pathMatches("/api/users/:id", "/api/users/42/posts"));
    try std.testing.expect(pathMatches("/health", "/health"));
}

test "parse rest config" {
    const src =
        \\{
        \\  "mode": "rest",
        \\  "port": 9090,
        \\  "routes": [
        \\    {
        \\      "method": "get",
        \\      "path": "/api/ping",
        \\      "body": "pong"
        \\    }
        \\  ]
        \\}
    ;
    var config = try parse(std.testing.allocator, src);
    defer deinit(&config);

    try std.testing.expect(config.mode == .rest);
    try std.testing.expectEqual(@as(u16, 9090), config.port);
    try std.testing.expectEqualStrings("pong", config.routes[0].body_template.?.string);
}

test "parse ws config" {
    const src =
        \\{
        \\  "mode": "ws",
        \\  "port": 8081,
        \\  "path": "/ws",
        \\  "interval_ms": 500,
        \\  "message": { "ts": "!{TIMESTAMP_MS}" }
        \\}
    ;
    var config = try parse(std.testing.allocator, src);
    defer deinit(&config);

    try std.testing.expect(config.mode == .ws);
    try std.testing.expectEqual(@as(u16, 8081), config.port);
    try std.testing.expectEqual(@as(u32, 500), config.interval_ms);
    try std.testing.expect(config.message_is_json);
}

test "renderBody expands actions" {
    const src =
        \\{
        \\  "mode": "rest",
        \\  "routes": [
        \\    {
        \\      "path": "/api/roll",
        \\      "body": { "id": "!{RANDOM_INT_IN_RANGE} 5 5", "flag": "!{RANDOM_BOOL}" }
        \\    }
        \\  ]
        \\}
    ;
    var config = try parse(std.testing.allocator, src);
    defer deinit(&config);

    var prng = std.Random.DefaultPrng.init(1);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var sequences = actions.SequenceState.init(std.testing.allocator);
    defer sequences.deinit();

    const body = try renderBody(arena.allocator(), &config.routes[0], prng.random(), std.testing.io, &sequences);
    var parsed = try json.parseFromSlice(json.Value, std.testing.allocator, body, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i64, 5), parsed.value.object.get("id").?.integer);
    try std.testing.expect(parsed.value.object.get("flag").? == .bool);
}

test "renderBody sequence advances across calls" {
    const src =
        \\{
        \\  "mode": "rest",
        \\  "routes": [
        \\    {
        \\      "path": "/api/seq",
        \\      "body": { "n": "!{SEQUENCE_INT} 1 2 3" }
        \\    }
        \\  ]
        \\}
    ;
    var config = try parse(std.testing.allocator, src);
    defer deinit(&config);

    var prng = std.Random.DefaultPrng.init(1);
    var sequences = actions.SequenceState.init(std.testing.allocator);
    defer sequences.deinit();

    const expected = [_]i64{ 1, 2, 3, 1 };
    for (expected) |want| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const body = try renderBody(arena.allocator(), &config.routes[0], prng.random(), std.testing.io, &sequences);
        var parsed = try json.parseFromSlice(json.Value, std.testing.allocator, body, .{});
        defer parsed.deinit();
        try std.testing.expectEqual(want, parsed.value.object.get("n").?.integer);
    }
}
