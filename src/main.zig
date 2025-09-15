const std = @import("std");
const builtin = @import("builtin");

const usage =
    \\Usage: ruse [--docs] PROG [ARG]...
    \\
    \\Run PROG and display its resource usage when it exits.
    \\
;

const docs =
    \\rc
    \\  Exit code of the process.
    \\wtime
    \\  Wall clock time, i.e. actual time spent executing the process.
    \\utime
    \\  Time spent executing in user mode.
    \\stime
    \\  Time spent executing in kernel mode.
    \\maxrss
    \\  Maximum resident set size used, in kilobytes.
    \\minflt
    \\  Number of page faults which were serviced without requiring any I/O.
    \\majflt
    \\  Number of page faults which were serviced by doing I/O.
    \\inblock
    \\  Number of times the file system had to read from the disk.
    \\oublock
    \\  Number of times the file system had to write to the disk.
    \\nvcsw
    \\  Number of times processes voluntarily invoked a context switch (usually to wait for some service).
    \\nivcsw
    \\  Number of times an involuntary context switch took place (because a time slice expired, or another process of higher priority was scheduled).
    \\
;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const all_args = try std.process.argsAlloc(arena);
    const args = all_args[1..];

    if (args.len == 0) {
        try stdout.writeAll(usage);
        return;
    }

    if (std.mem.eql(u8, args[0], "--docs")) {
        try stdout.writeAll(docs);
        return;
    }

    var child = std.process.Child.init(args, arena);
    child.request_resource_usage_statistics = true;

    var timer = std.time.Timer.start() catch @panic("need timer to work");

    // start time
    const start = timer.read();

    const term = try child.spawnAndWait();

    // stop time
    const end = timer.read();

    const exit_status: u8 = switch (term) {
        .Exited, .Stopped => |code| @intCast(code),
        .Signal => |sig| @intCast(128 + sig),
        else => |code| {
            try stderr.print("error: command terminated unexpectedly with status {}\n", .{code});
            std.process.exit(1);
        },
    };

    const elapsed_time = prettyTime(end - start);

    switch (builtin.os.tag) {
        .linux => {
            const r = child.resource_usage_statistics.rusage.?;

            const usr_time = prettyTime(tvToNs(r.utime));
            const sys_time = prettyTime(tvToNs(r.stime));

            const max_rss: u64 = @intCast(r.maxrss);
            const pretty_max_rss = prettySize(max_rss * 1024);

            try stderr.print("\tcmd        \"", .{});
            for (0.., args) |index, arg| {
                if (index == args.len - 1) {
                    try stderr.print("{s}\"\n", .{arg});
                } else {
                    try stderr.print("{s} ", .{arg});
                }
            }
            try stderr.print("\trc         {d}\n", .{exit_status});
            try stderr.print("\twtime      {d}{s}\n", .{ elapsed_time.value, elapsed_time.unit });
            try stderr.print("\tutime      {d}{s}\n", .{ usr_time.value, usr_time.unit });
            try stderr.print("\tstime      {d}{s}\n", .{ sys_time.value, sys_time.unit });
            try stderr.print("\tmaxrss     {d}{s}\n", .{ pretty_max_rss.value, pretty_max_rss.unit });
            try stderr.print("\tminflt     {d}\n", .{r.minflt});
            try stderr.print("\tmajflt     {d}\n", .{r.majflt});
            try stderr.print("\tinblock    {d}\n", .{r.inblock});
            try stderr.print("\toublock    {d}\n", .{r.oublock});
            try stderr.print("\tnvcsw      {d}\n", .{r.nvcsw});
            try stderr.print("\tnivcsw     {d}\n", .{r.nivcsw});
        },

        else => @panic("os not supported"),
    }
}

fn tvToNs(tv: std.os.linux.timeval) u64 {
    const s: u64 = @intCast(tv.sec);
    const u: u64 = @intCast(tv.usec);
    return s * std.time.ns_per_s + u * std.time.ns_per_us;
}

const PrettyTime = struct {
    value: f64,
    unit: []const u8,
};

fn prettyTime(v: u64) PrettyTime {
    if (v >= std.time.ns_per_s) {
        const vf: f64 = @floatFromInt(v);
        const df: f64 = @floatFromInt(std.time.ns_per_s);
        return .{ .value = vf / df, .unit = "s" };
    }
    if (v >= std.time.ns_per_ms) {
        const vf: f64 = @floatFromInt(v);
        const df: f64 = @floatFromInt(std.time.ns_per_ms);
        return .{ .value = vf / df, .unit = "ms" };
    }
    if (v >= std.time.ns_per_us) {
        const vf: f64 = @floatFromInt(v);
        const df: f64 = @floatFromInt(std.time.ns_per_us);
        return .{ .value = vf / df, .unit = "us" };
    }
    const vf: f64 = @floatFromInt(v);
    return .{ .value = vf, .unit = "ns" };
}

const PrettySize = struct {
    value: f64,
    unit: []const u8,
};

const kb = 1024.0;
const mb = 1024.0 * kb;
const gb = 1024.0 * mb;

fn prettySize(v: u64) PrettySize {
    if (v >= gb) {
        const vf: f64 = @floatFromInt(v);
        return .{ .value = vf / gb, .unit = "gb" };
    }
    if (v >= mb) {
        const vf: f64 = @floatFromInt(v);
        return .{ .value = vf / mb, .unit = "mb" };
    }
    if (v >= kb) {
        const vf: f64 = @floatFromInt(v);
        return .{ .value = vf / kb, .unit = "kb" };
    }
    const vf: f64 = @floatFromInt(v);
    return .{ .value = vf, .unit = "bytes" };
}
