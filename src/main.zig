const std = @import("std");
const config_mod = @import("config.zig");
const server = @import("server.zig");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const gpa = init.gpa;

    const args = try init.minimal.args.toSlice(arena);
    const paths = parseArgs(arena, io, args) catch |err| switch (err) {
        error.HelpRequested => return,
        else => return err,
    };

    var rest_config: ?config_mod.Config = null;
    defer if (rest_config) |*c| config_mod.deinit(c);
    var ws_config: ?config_mod.Config = null;
    defer if (ws_config) |*c| config_mod.deinit(c);

    if (paths.rest) |path| {
        std.log.info("loading REST config: {s}", .{path});
        rest_config = config_mod.loadFromFile(gpa, io, path) catch |err| {
            std.log.err("failed to load REST config '{s}': {s}", .{ path, @errorName(err) });
            return err;
        };
    }

    if (paths.ws) |path| {
        std.log.info("loading WS config: {s}", .{path});
        ws_config = config_mod.loadFromFile(gpa, io, path) catch |err| {
            std.log.err("failed to load WS config '{s}': {s}", .{ path, @errorName(err) });
            return err;
        };
    }

    const rest_ptr: ?*const config_mod.Config = if (rest_config) |*c| c else null;
    const ws_ptr: ?*const config_mod.Config = if (ws_config) |*c| c else null;
    try server.run(io, rest_ptr, ws_ptr);
}

const ConfigPaths = struct {
    rest: ?[]const u8 = null,
    ws: ?[]const u8 = null,
};

fn parseArgs(arena: std.mem.Allocator, io: std.Io, args: []const [:0]const u8) !ConfigPaths {
    var paths: ConfigPaths = .{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--rest")) {
            i += 1;
            if (i >= args.len) {
                std.log.err("--rest requires a path", .{});
                return error.InvalidArgs;
            }
            paths.rest = try arena.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--ws")) {
            i += 1;
            if (i >= args.len) {
                std.log.err("--ws requires a path", .{});
                return error.InvalidArgs;
            }
            paths.ws = try arena.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            return error.HelpRequested;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.log.err("unknown flag: {s}", .{arg});
            printUsage();
            return error.InvalidArgs;
        } else {
            const classified = try classifyConfigPath(arena, io, arg);
            switch (classified.mode) {
                .rest => {
                    if (paths.rest != null) {
                        std.log.err("REST config already specified", .{});
                        return error.InvalidArgs;
                    }
                    paths.rest = classified.path;
                },
                .ws => {
                    if (paths.ws != null) {
                        std.log.err("WS config already specified", .{});
                        return error.InvalidArgs;
                    }
                    paths.ws = classified.path;
                },
            }
        }
    }

    if (paths.rest == null and paths.ws == null) {
        paths = try discoverDefaultConfigs(arena, io);
    }

    if (paths.rest == null and paths.ws == null) {
        printUsage();
        return error.ConfigNotFound;
    }

    return paths;
}

const Classified = struct {
    path: []const u8,
    mode: config_mod.Mode,
};

fn classifyConfigPath(arena: std.mem.Allocator, io: std.Io, path: []const u8) !Classified {
    const owned = try arena.dupe(u8, path);
    const bytes = try std.Io.Dir.readFileAlloc(.cwd(), io, path, arena, .limited(1024 * 1024));
    const leaky = try std.json.parseFromSliceLeaky(struct {
        mode: []const u8 = "rest",
    }, arena, bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });

    const mode: config_mod.Mode = if (std.ascii.eqlIgnoreCase(leaky.mode, "ws") or
        std.ascii.eqlIgnoreCase(leaky.mode, "websocket"))
        .ws
    else
        .rest;

    return .{ .path = owned, .mode = mode };
}

fn discoverDefaultConfigs(arena: std.mem.Allocator, io: std.Io) !ConfigPaths {
    var paths: ConfigPaths = .{};

    const candidates_rest = [_][]const u8{"config-rest.json"};
    const candidates_ws = [_][]const u8{"config-ws.json"};

    // Prefer next to executable, then cwd.
    var exe_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_dir: ?[]const u8 = if (std.process.executableDirPath(io, &exe_buf)) |n| exe_buf[0..n] else |_| null;

    for (candidates_rest) |name| {
        if (try findConfig(arena, io, exe_dir, name)) |found| {
            paths.rest = found;
            break;
        }
    }
    for (candidates_ws) |name| {
        if (try findConfig(arena, io, exe_dir, name)) |found| {
            paths.ws = found;
            break;
        }
    }

    return paths;
}

fn findConfig(arena: std.mem.Allocator, io: std.Io, exe_dir: ?[]const u8, name: []const u8) !?[]const u8 {
    if (exe_dir) |dir| {
        const beside = try std.fs.path.join(arena, &.{ dir, name });
        if (fileExists(io, beside)) return beside;
    }
    if (fileExists(io, name)) return try arena.dupe(u8, name);
    return null;
}

fn fileExists(io: std.Io, path: []const u8) bool {
    std.Io.Dir.access(.cwd(), io, path, .{}) catch return false;
    return true;
}

fn printUsage() void {
    std.log.err(
        \\Usage:
        \\  GhostServer --rest config-rest.json --ws config-ws.json
        \\  GhostServer --rest config-rest.json
        \\  GhostServer --ws config-ws.json
        \\  GhostServer config-rest.json
        \\
        \\If no args are given, looks for config-rest.json / config-ws.json
        \\next to the executable, then in the current directory.
    , .{});
}
