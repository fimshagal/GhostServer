const std = @import("std");
const json = std.json;

/// Per-request context passed into action handlers.
pub const Context = struct {
    allocator: std.mem.Allocator,
    random: std.Random,
    io: std.Io,
};

pub const ActionFn = *const fn (ctx: Context, args: []const u8) anyerror!json.Value;

pub const Action = struct {
    name: []const u8,
    run: ActionFn,
};

/// Built-in actions. Add new entries here to extend the language.
pub const builtins = [_]Action{
    .{ .name = "RANDOM_INT_IN_RANGE", .run = randomIntInRange },
    .{ .name = "RANDOM_INT", .run = randomInt },
    .{ .name = "RANDOM_INT_MATRIX", .run = randomIntMatrix },
    .{ .name = "RANDOM_FLOAT_IN_RANGE", .run = randomFloatInRange },
    .{ .name = "RANDOM_FLOAT", .run = randomFloat },
    .{ .name = "RANDOM_FLOAT_MATRIX", .run = randomFloatMatrix },
    .{ .name = "RANDOM_BOOL", .run = randomBool },
    .{ .name = "RANDOM_STRING", .run = randomString },
    .{ .name = "TIMESTAMP_MS", .run = timestampMs },
    .{ .name = "TIMESTAMP_ISO", .run = timestampIso },
    .{ .name = "UUID", .run = uuid },
};

pub const Parsed = struct {
    name: []const u8,
    args: []const u8,
};

/// Detects strings like `!{ACTION_NAME} arg1 arg2`.
/// Returns null if the string is not an action marker.
pub fn parse(s: []const u8) ?Parsed {
    if (!std.mem.startsWith(u8, s, "!{")) return null;
    const rest = s[2..];
    const close = std.mem.indexOfScalar(u8, rest, '}') orelse return null;
    const name = rest[0..close];
    if (name.len == 0) return null;
    const args = std.mem.trim(u8, rest[close + 1 ..], &std.ascii.whitespace);
    return .{ .name = name, .args = args };
}

pub fn lookup(name: []const u8) ?ActionFn {
    for (&builtins) |action| {
        if (std.mem.eql(u8, action.name, name)) return action.run;
    }
    return null;
}

pub fn run(ctx: Context, name: []const u8, args: []const u8) !json.Value {
    const handler = lookup(name) orelse return error.UnknownAction;
    return handler(ctx, args);
}

/// Walk a JSON value and replace action strings with computed values.
pub fn resolveValue(ctx: Context, value: json.Value) !json.Value {
    return switch (value) {
        .string => |s| blk: {
            if (parse(s)) |action| {
                break :blk try run(ctx, action.name, action.args);
            }
            break :blk .{ .string = s };
        },
        .array => |arr| blk: {
            var out = json.Array.init(ctx.allocator);
            errdefer out.deinit();
            try out.ensureTotalCapacity(arr.items.len);
            for (arr.items) |item| {
                try out.append(try resolveValue(ctx, item));
            }
            break :blk .{ .array = out };
        },
        .object => |obj| blk: {
            var out = try json.ObjectMap.init(ctx.allocator, &.{}, &.{});
            errdefer out.deinit(ctx.allocator);
            try out.ensureTotalCapacity(ctx.allocator, obj.count());
            var it = obj.iterator();
            while (it.next()) |entry| {
                const key = try ctx.allocator.dupe(u8, entry.key_ptr.*);
                const resolved = try resolveValue(ctx, entry.value_ptr.*);
                try out.put(ctx.allocator, key, resolved);
            }
            break :blk .{ .object = out };
        },
        .null, .bool, .integer, .float, .number_string => value,
    };
}

fn requireNoArgs(args: []const u8) !void {
    if (std.mem.trim(u8, args, &std.ascii.whitespace).len != 0) return error.InvalidActionArgs;
}

fn randomIntInRange(ctx: Context, args: []const u8) !json.Value {
    var it = std.mem.tokenizeAny(u8, args, &std.ascii.whitespace);
    const min_s = it.next() orelse return error.InvalidActionArgs;
    const max_s = it.next() orelse return error.InvalidActionArgs;
    if (it.next() != null) return error.InvalidActionArgs;

    const min = try std.fmt.parseInt(i64, min_s, 10);
    const max = try std.fmt.parseInt(i64, max_s, 10);
    if (min > max) return error.InvalidActionArgs;

    return .{ .integer = ctx.random.intRangeAtMost(i64, min, max) };
}

fn randomInt(ctx: Context, args: []const u8) !json.Value {
    var it = std.mem.tokenizeAny(u8, args, &std.ascii.whitespace);
    var options: std.ArrayList(i64) = .empty;
    defer options.deinit(ctx.allocator);

    while (it.next()) |token| {
        try options.append(ctx.allocator, try std.fmt.parseInt(i64, token, 10));
    }
    if (options.items.len == 0) return error.InvalidActionArgs;

    const index = ctx.random.uintLessThan(usize, options.items.len);
    return .{ .integer = options.items[index] };
}

fn randomIntMatrix(ctx: Context, args: []const u8) !json.Value {
    var it = std.mem.tokenizeAny(u8, args, &std.ascii.whitespace);
    const outer_s = it.next() orelse return error.InvalidActionArgs;
    const inner_s = it.next() orelse return error.InvalidActionArgs;
    const min_s = it.next() orelse return error.InvalidActionArgs;
    const max_s = it.next() orelse return error.InvalidActionArgs;
    if (it.next() != null) return error.InvalidActionArgs;

    const outer = try std.fmt.parseInt(usize, outer_s, 10);
    const inner = try std.fmt.parseInt(usize, inner_s, 10);
    const min = try std.fmt.parseInt(i64, min_s, 10);
    const max = try std.fmt.parseInt(i64, max_s, 10);
    if (outer == 0 or inner == 0 or min > max) return error.InvalidActionArgs;

    var matrix = json.Array.init(ctx.allocator);
    errdefer matrix.deinit();
    try matrix.ensureTotalCapacity(outer);

    var o: usize = 0;
    while (o < outer) : (o += 1) {
        var row = json.Array.init(ctx.allocator);
        errdefer row.deinit();
        try row.ensureTotalCapacity(inner);
        var i: usize = 0;
        while (i < inner) : (i += 1) {
            try row.append(.{ .integer = ctx.random.intRangeAtMost(i64, min, max) });
        }
        try matrix.append(.{ .array = row });
    }

    return .{ .array = matrix };
}

fn randomFloatInRange(ctx: Context, args: []const u8) !json.Value {
    var it = std.mem.tokenizeAny(u8, args, &std.ascii.whitespace);
    const min_s = it.next() orelse return error.InvalidActionArgs;
    const max_s = it.next() orelse return error.InvalidActionArgs;
    if (it.next() != null) return error.InvalidActionArgs;

    const min = try std.fmt.parseFloat(f64, min_s);
    const max = try std.fmt.parseFloat(f64, max_s);
    if (min > max) return error.InvalidActionArgs;

    const t = ctx.random.float(f64);
    return .{ .float = min + (max - min) * t };
}

fn randomFloat(ctx: Context, args: []const u8) !json.Value {
    var it = std.mem.tokenizeAny(u8, args, &std.ascii.whitespace);
    var options: std.ArrayList(f64) = .empty;
    defer options.deinit(ctx.allocator);

    while (it.next()) |token| {
        try options.append(ctx.allocator, try std.fmt.parseFloat(f64, token));
    }
    if (options.items.len == 0) return error.InvalidActionArgs;

    const index = ctx.random.uintLessThan(usize, options.items.len);
    return .{ .float = options.items[index] };
}

fn randomFloatMatrix(ctx: Context, args: []const u8) !json.Value {
    var it = std.mem.tokenizeAny(u8, args, &std.ascii.whitespace);
    const outer_s = it.next() orelse return error.InvalidActionArgs;
    const inner_s = it.next() orelse return error.InvalidActionArgs;
    const min_s = it.next() orelse return error.InvalidActionArgs;
    const max_s = it.next() orelse return error.InvalidActionArgs;
    if (it.next() != null) return error.InvalidActionArgs;

    const outer = try std.fmt.parseInt(usize, outer_s, 10);
    const inner = try std.fmt.parseInt(usize, inner_s, 10);
    const min = try std.fmt.parseFloat(f64, min_s);
    const max = try std.fmt.parseFloat(f64, max_s);
    if (outer == 0 or inner == 0 or min > max) return error.InvalidActionArgs;

    var matrix = json.Array.init(ctx.allocator);
    errdefer matrix.deinit();
    try matrix.ensureTotalCapacity(outer);

    var o: usize = 0;
    while (o < outer) : (o += 1) {
        var row = json.Array.init(ctx.allocator);
        errdefer row.deinit();
        try row.ensureTotalCapacity(inner);
        var i: usize = 0;
        while (i < inner) : (i += 1) {
            const t = ctx.random.float(f64);
            try row.append(.{ .float = min + (max - min) * t });
        }
        try matrix.append(.{ .array = row });
    }

    return .{ .array = matrix };
}

fn randomBool(ctx: Context, args: []const u8) !json.Value {
    try requireNoArgs(args);
    return .{ .bool = ctx.random.boolean() };
}

fn randomString(ctx: Context, args: []const u8) !json.Value {
    var it = std.mem.tokenizeAny(u8, args, &std.ascii.whitespace);
    var options: std.ArrayList([]const u8) = .empty;
    defer options.deinit(ctx.allocator);

    while (it.next()) |word| {
        try options.append(ctx.allocator, word);
    }
    if (options.items.len == 0) return error.InvalidActionArgs;

    const index = ctx.random.uintLessThan(usize, options.items.len);
    return .{ .string = options.items[index] };
}

fn timestampMs(ctx: Context, args: []const u8) !json.Value {
    try requireNoArgs(args);
    const ts = std.Io.Timestamp.now(ctx.io, .real);
    return .{ .integer = ts.toMilliseconds() };
}

fn timestampIso(ctx: Context, args: []const u8) !json.Value {
    try requireNoArgs(args);
    const ts = std.Io.Timestamp.now(ctx.io, .real);
    const secs_i = ts.toSeconds();
    if (secs_i < 0) return error.InvalidActionArgs;
    const epoch_secs = std.time.epoch.EpochSeconds{ .secs = @intCast(secs_i) };
    const year_day = epoch_secs.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_secs = epoch_secs.getDaySeconds();

    const formatted = try std.fmt.allocPrint(
        ctx.allocator,
        "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z",
        .{
            year_day.year,
            @intFromEnum(month_day.month),
            month_day.day_index + 1,
            day_secs.getHoursIntoDay(),
            day_secs.getMinutesIntoHour(),
            day_secs.getSecondsIntoMinute(),
        },
    );
    return .{ .string = formatted };
}

fn uuid(ctx: Context, args: []const u8) !json.Value {
    try requireNoArgs(args);
    var bytes: [16]u8 = undefined;
    ctx.random.bytes(&bytes);
    // UUID version 4 + RFC 4122 variant bits (looks like a real UUID).
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    const formatted = try std.fmt.allocPrint(
        ctx.allocator,
        "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}",
        .{
            bytes[0],  bytes[1],  bytes[2],  bytes[3],
            bytes[4],  bytes[5],  bytes[6],  bytes[7],
            bytes[8],  bytes[9],  bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15],
        },
    );
    return .{ .string = formatted };
}

test "uuid has expected shape" {
    var prng = std.Random.DefaultPrng.init(123);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const ctx: Context = .{
        .allocator = arena.allocator(),
        .random = prng.random(),
        .io = std.testing.io,
    };

    const value = try uuid(ctx, "");
    try std.testing.expect(value == .string);
    try std.testing.expectEqual(@as(usize, 36), value.string.len);
    try std.testing.expectEqual(@as(u8, '-'), value.string[8]);
    try std.testing.expectEqual(@as(u8, '-'), value.string[13]);
    try std.testing.expectEqual(@as(u8, '4'), value.string[14]);
    try std.testing.expectEqual(@as(u8, '-'), value.string[18]);
    try std.testing.expectEqual(@as(u8, '-'), value.string[23]);
}

test "random string picks from options" {
    var prng = std.Random.DefaultPrng.init(99);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const ctx: Context = .{
        .allocator = arena.allocator(),
        .random = prng.random(),
        .io = std.testing.io,
    };

    var i: usize = 0;
    while (i < 30) : (i += 1) {
        const value = try randomString(ctx, "Alpha Beta Gama");
        try std.testing.expect(value == .string);
        const ok = std.mem.eql(u8, value.string, "Alpha") or
            std.mem.eql(u8, value.string, "Beta") or
            std.mem.eql(u8, value.string, "Gama");
        try std.testing.expect(ok);
    }
}

test "random int and float pick from list" {
    var prng = std.Random.DefaultPrng.init(5);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const ctx: Context = .{
        .allocator = arena.allocator(),
        .random = prng.random(),
        .io = std.testing.io,
    };

    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const iv = try randomInt(ctx, "1 2 3");
        try std.testing.expect(iv == .integer);
        try std.testing.expect(iv.integer == 1 or iv.integer == 2 or iv.integer == 3);

        const fv = try randomFloat(ctx, "0.1 0.2 0.3");
        try std.testing.expect(fv == .float);
        try std.testing.expect(fv.float == 0.1 or fv.float == 0.2 or fv.float == 0.3);
    }
}

test "random int matrix shape" {
    var prng = std.Random.DefaultPrng.init(11);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const ctx: Context = .{
        .allocator = arena.allocator(),
        .random = prng.random(),
        .io = std.testing.io,
    };

    const value = try randomIntMatrix(ctx, "5 3 0 7");
    try std.testing.expect(value == .array);
    try std.testing.expectEqual(@as(usize, 5), value.array.items.len);
    for (value.array.items) |reel| {
        try std.testing.expect(reel == .array);
        try std.testing.expectEqual(@as(usize, 3), reel.array.items.len);
        for (reel.array.items) |cell| {
            try std.testing.expect(cell == .integer);
            try std.testing.expect(cell.integer >= 0 and cell.integer <= 7);
        }
    }
}

test "parse action marker" {
    const a = parse("!{RANDOM_INT_IN_RANGE} 10 120").?;
    try std.testing.expectEqualStrings("RANDOM_INT_IN_RANGE", a.name);
    try std.testing.expectEqualStrings("10 120", a.args);
    try std.testing.expect(parse("hello") == null);
    try std.testing.expect(parse("!{") == null);
}

test "random int stays in range" {
    var prng = std.Random.DefaultPrng.init(42);
    const ctx: Context = .{
        .allocator = std.testing.allocator,
        .random = prng.random(),
        .io = std.testing.io,
    };
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        const value = try randomIntInRange(ctx, "10 120");
        try std.testing.expect(value == .integer);
        try std.testing.expect(value.integer >= 10 and value.integer <= 120);
    }
}

test "timestamp actions produce values" {
    var prng = std.Random.DefaultPrng.init(1);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const ctx: Context = .{
        .allocator = arena.allocator(),
        .random = prng.random(),
        .io = std.testing.io,
    };

    const ms = try timestampMs(ctx, "");
    try std.testing.expect(ms == .integer);
    try std.testing.expect(ms.integer > 0);

    const iso = try timestampIso(ctx, "");
    try std.testing.expect(iso == .string);
    try std.testing.expect(iso.string.len == 20);
}

test "resolve replaces nested actions" {
    var prng = std.Random.DefaultPrng.init(7);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var obj = try json.ObjectMap.init(allocator, &.{}, &.{});
    try obj.put(allocator, "id", .{ .string = "!{RANDOM_INT_IN_RANGE} 1 1" });
    try obj.put(allocator, "ok", .{ .string = "!{RANDOM_BOOL}" });
    try obj.put(allocator, "name", .{ .string = "Alice" });

    const resolved = try resolveValue(.{
        .allocator = allocator,
        .random = prng.random(),
        .io = std.testing.io,
    }, .{ .object = obj });
    try std.testing.expect(resolved == .object);
    try std.testing.expectEqual(@as(i64, 1), resolved.object.get("id").?.integer);
    try std.testing.expect(resolved.object.get("ok").? == .bool);
    try std.testing.expectEqualStrings("Alice", resolved.object.get("name").?.string);
}
