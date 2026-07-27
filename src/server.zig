const std = @import("std");
const config_mod = @import("config.zig");
const actions = @import("actions.zig");
const Config = config_mod.Config;
const Route = config_mod.Route;

const net = std.Io.net;
const Io = std.Io;
const http = std.http;

pub fn run(io: Io, rest: ?*const Config, ws: ?*const Config) !void {
    if (rest == null and ws == null) return error.NoConfig;

    if (rest) |rest_config| {
        if (rest_config.mode != .rest) {
            std.log.err("REST config has mode={s}, expected rest", .{@tagName(rest_config.mode)});
            return error.InvalidMode;
        }
    }
    if (ws) |ws_config| {
        if (ws_config.mode != .ws) {
            std.log.err("WS config has mode={s}, expected ws", .{@tagName(ws_config.mode)});
            return error.InvalidMode;
        }
    }

    var sequences = actions.SequenceState.init(std.heap.page_allocator);
    defer sequences.deinit();

    if (rest != null and ws != null) {
        const thread = try std.Thread.spawn(.{}, runRestForever, .{ io, rest.?, &sequences });
        thread.detach();
        try runWs(io, ws.?, &sequences);
        return;
    }

    if (rest) |rest_config| {
        try runRest(io, rest_config, &sequences);
        return;
    }

    try runWs(io, ws.?, &sequences);
}

fn runRestForever(io: Io, config: *const Config, sequences: *actions.SequenceState) void {
    runRest(io, config, sequences) catch |err| {
        std.log.err("REST server stopped: {s}", .{@errorName(err)});
    };
}

fn listen(io: Io, config: *const Config) !net.Server {
    const address = net.IpAddress.parse(config.host, config.port) catch |err| {
        std.log.err("invalid host '{s}': {s} (use 127.0.0.1 or 0.0.0.0)", .{ config.host, @errorName(err) });
        return err;
    };
    return address.listen(io, .{ .reuse_address = true }) catch |err| {
        std.log.err(
            "failed to listen on http://{s}:{d}: {s}",
            .{ config.host, config.port, @errorName(err) },
        );
        if (err == error.AddressInUse) {
            std.log.err("port {d} is already in use — stop the other GhostServer (or change port in config)", .{config.port});
        } else {
            std.log.err("is the host a local address? try 127.0.0.1 or 0.0.0.0", .{});
        }
        return err;
    };
}

pub fn runRest(io: Io, config: *const Config, sequences: *actions.SequenceState) !void {
    var listener = try listen(io, config);
    defer listener.deinit(io);

    std.log.info("REST listening on http://{s}:{d}", .{ config.host, config.port });
    std.log.info("loaded {d} route(s), cors={any}", .{ config.routes.len, config.cors });
    for (config.routes) |route| {
        std.log.info("  {s} {s} -> {d}", .{ route.method, route.path, route.status });
    }

    while (true) {
        const stream = listener.accept(io) catch |err| {
            std.log.err("REST accept failed: {s}", .{@errorName(err)});
            continue;
        };

        const thread = std.Thread.spawn(.{}, handleRestConnection, .{ io, stream, config, sequences }) catch |err| {
            std.log.err("failed to spawn REST connection thread: {s}", .{@errorName(err)});
            stream.close(io);
            continue;
        };
        thread.detach();
    }
}

pub fn runWs(io: Io, config: *const Config, sequences: *actions.SequenceState) !void {
    var listener = try listen(io, config);
    defer listener.deinit(io);

    std.log.info("WS listening on ws://{s}:{d}{s}", .{ config.host, config.port, config.path });
    std.log.info("interval_ms={d}", .{config.interval_ms});

    while (true) {
        const stream = listener.accept(io) catch |err| {
            std.log.err("WS accept failed: {s}", .{@errorName(err)});
            continue;
        };

        const thread = std.Thread.spawn(.{}, handleWsConnection, .{ io, stream, config, sequences }) catch |err| {
            std.log.err("failed to spawn WS connection thread: {s}", .{@errorName(err)});
            stream.close(io);
            continue;
        };
        thread.detach();
    }
}

fn handleRestConnection(io: Io, stream: net.Stream, config: *const Config, sequences: *actions.SequenceState) void {
    defer stream.close(io);

    var recv_buffer: [16 * 1024]u8 = undefined;
    var send_buffer: [16 * 1024]u8 = undefined;
    var stream_reader = stream.reader(io, &recv_buffer);
    var stream_writer = stream.writer(io, &send_buffer);
    var http_server = http.Server.init(&stream_reader.interface, &stream_writer.interface);

    while (http_server.reader.state == .ready) {
        var request = http_server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => {
                std.log.err("failed to read request head: {s}", .{@errorName(err)});
                return;
            },
        };

        serveRestRequest(io, &request, config, sequences) catch |err| {
            std.log.err("failed to serve REST request: {s}", .{@errorName(err)});
            return;
        };
    }
}

fn serveRestRequest(io: Io, request: *http.Server.Request, config: *const Config, sequences: *actions.SequenceState) !void {
    const method_name = @tagName(request.head.method);
    const path = config_mod.pathWithoutQuery(request.head.target);

    std.log.info("REST {s} {s}", .{ method_name, path });

    if (config.cors and request.head.method == .OPTIONS) {
        if (config_mod.findRoute(config, method_name, path)) |route| {
            try respondRoute(io, request, config, route, sequences);
            return;
        }
        try respondCorsPreflight(request);
        return;
    }

    if (config_mod.findRoute(config, method_name, path)) |route| {
        try respondRoute(io, request, config, route, sequences);
        return;
    }

    try respondNotFound(request, config);
}

fn respondRoute(
    io: Io,
    request: *http.Server.Request,
    config: *const Config,
    route: *const Route,
    sequences: *actions.SequenceState,
) !void {
    if (route.delay_ms > 0) {
        try io.sleep(.fromMilliseconds(@intCast(route.delay_ms)), .awake);
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var seed: u64 = undefined;
    io.random(std.mem.asBytes(&seed));
    var prng = std.Random.DefaultPrng.init(seed);

    const body = config_mod.renderBody(allocator, route, prng.random(), io, sequences) catch |err| {
        std.log.err("failed to render body for {s} {s}: {s}", .{ route.method, route.path, @errorName(err) });
        return err;
    };

    var headers: std.ArrayList(http.Header) = .empty;
    try headers.ensureTotalCapacity(allocator, route.headers.len + 8);

    if (route.content_type.len != 0) {
        try headers.append(allocator, .{
            .name = "content-type",
            .value = route.content_type,
        });
    }
    for (route.headers) |header| {
        try headers.append(allocator, .{
            .name = header.name,
            .value = header.value,
        });
    }
    if (config.cors) try appendCorsHeaders(allocator, &headers);

    // keep_alive=false: Zig 0.16 std.http.Server panics on POST/PUT without Content-Length.
    try request.respond(body, .{
        .status = @enumFromInt(route.status),
        .keep_alive = false,
        .extra_headers = headers.items,
    });
}

fn handleWsConnection(io: Io, stream: net.Stream, config: *const Config, sequences: *actions.SequenceState) void {
    defer stream.close(io);

    var recv_buffer: [16 * 1024]u8 = undefined;
    var send_buffer: [16 * 1024]u8 = undefined;
    var stream_reader = stream.reader(io, &recv_buffer);
    var stream_writer = stream.writer(io, &send_buffer);
    var http_server = http.Server.init(&stream_reader.interface, &stream_writer.interface);

    var request = http_server.receiveHead() catch |err| {
        std.log.err("WS failed to read request head: {s}", .{@errorName(err)});
        return;
    };

    const path = config_mod.pathWithoutQuery(request.head.target);
    std.log.info("WS handshake {s} {s}", .{ @tagName(request.head.method), path });

    if (!std.mem.eql(u8, path, config.path)) {
        request.respond("{\"error\":\"not_found\"}", .{
            .status = .not_found,
            .keep_alive = false,
            .extra_headers = &.{
                .{ .name = "content-type", .value = "application/json; charset=utf-8" },
            },
        }) catch {};
        return;
    }

    const key = switch (request.upgradeRequested()) {
        .websocket => |maybe_key| maybe_key orelse {
            std.log.err("WS upgrade missing sec-websocket-key", .{});
            return;
        },
        .none => {
            std.log.err("WS path hit without websocket upgrade", .{});
            request.respond("{\"error\":\"upgrade_required\"}", .{
                .status = .upgrade_required,
                .keep_alive = false,
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "application/json; charset=utf-8" },
                },
            }) catch {};
            return;
        },
        .other => |proto| {
            std.log.err("unsupported upgrade protocol: {s}", .{proto});
            return;
        },
    };

    var ws = request.respondWebSocket(.{ .key = key }) catch |err| {
        std.log.err("WS upgrade failed: {s}", .{@errorName(err)});
        return;
    };
    ws.flush() catch |err| {
        std.log.err("WS flush failed: {s}", .{@errorName(err)});
        return;
    };

    std.log.info("WS client connected on {s}", .{config.path});

    while (true) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();

        var seed: u64 = undefined;
        io.random(std.mem.asBytes(&seed));
        var prng = std.Random.DefaultPrng.init(seed);

        const payload = config_mod.renderMessage(arena.allocator(), config, prng.random(), io, sequences) catch |err| {
            std.log.err("failed to render WS message: {s}", .{@errorName(err)});
            break;
        };

        ws.writeMessage(payload, .text) catch break;

        if (config.interval_ms == 0) continue;
        io.sleep(.fromMilliseconds(@intCast(config.interval_ms)), .awake) catch break;
    }

    std.log.info("WS client disconnected", .{});
}

fn respondCorsPreflight(request: *http.Server.Request) !void {
    var headers: std.ArrayList(http.Header) = .empty;
    defer headers.deinit(std.heap.page_allocator);
    try appendCorsHeaders(std.heap.page_allocator, &headers);
    try headers.append(std.heap.page_allocator, .{
        .name = "access-control-max-age",
        .value = "86400",
    });

    try request.respond("", .{
        .status = .no_content,
        .keep_alive = false,
        .extra_headers = headers.items,
    });
}

fn respondNotFound(request: *http.Server.Request, config: *const Config) !void {
    const body = "{\"error\":\"not_found\"}";
    var headers: std.ArrayList(http.Header) = .empty;
    defer headers.deinit(std.heap.page_allocator);
    try headers.append(std.heap.page_allocator, .{
        .name = "content-type",
        .value = "application/json; charset=utf-8",
    });
    if (config.cors) try appendCorsHeaders(std.heap.page_allocator, &headers);

    try request.respond(body, .{
        .status = .not_found,
        .keep_alive = false,
        .extra_headers = headers.items,
    });
}

fn appendCorsHeaders(allocator: std.mem.Allocator, headers: *std.ArrayList(http.Header)) !void {
    try headers.appendSlice(allocator, &.{
        .{ .name = "access-control-allow-origin", .value = "*" },
        .{ .name = "access-control-allow-methods", .value = "GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD" },
        .{ .name = "access-control-allow-headers", .value = "*" },
    });
}
