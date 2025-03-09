const std = @import("std");

const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const dt = @import("data_types.zig");
const dfr = @import("data_file_reader.zig");
const globals = @import("globals.zig");
const table_printer = @import("table_printer.zig");
const time_helper = @import("time_helper.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

const little_end = std.builtin.Endian.little;

// display infos on the target of current thing
fn displayTargetInfos(target: u25) !void {
    if (target != 0) {
        var buf_str: [128]u8 = undefined;

        const target_offset = @as(i64, target) - @as(i64, time_helper.curTimestamp());
        const str_target_offset = try time_helper.formatDuration(&buf_str, target_offset);
        try std.io.getStdOut().writer().print("{s}target{s} : {s}{s}{s}\n", .{ ansi.colemp, ansi.colres, ansi.getDurCol(target_offset), str_target_offset, ansi.colres });
    }
}

// display infos on the time left if there is an estimation
fn displayTimeLeftInfos(cur_thing: dt.Thing) !void {
    if (cur_thing.estimation != 0) {
        var buf_str: [128]u8 = undefined;

        const time_left = try time_helper.computeTimeLeft(cur_thing);
        const str_time_left = try time_helper.formatDuration(&buf_str, time_left);
        try std.io.getStdOut().writer().print("  {s}left{s} : {s}{s}{s}\n", .{ ansi.colemp, ansi.colres, ansi.getDurCol(time_left), str_time_left, ansi.colres });
    }
}

// display infos on the current timer
fn displayCurTimerInfos(start: u25) !void {
    if (start != 0) {
        var buf_dur_id: [10]u8 = undefined;
        const temp_dur: u25 = time_helper.curTimestamp() - start;

        if (temp_dur > std.math.maxInt(u9)) {
            std.debug.print("Error: the current timer has a duration of {d} minutes\n", .{temp_dur});
        } else {
            const str_duration = try time_helper.formatDurationNoSign(&buf_dur_id, @as(u9, @intCast(temp_dur)));

            try std.io.getStdOut().writer().print(" {s}timer{s} : started {s}{s}{s} ago\n", .{
                ansi.colemp,
                ansi.colres,
                ansi.coldurntr,
                str_duration,
                ansi.colres,
            });
        }
    } else {
        try std.io.getStdOut().writer().print(" {s}timer{s} : no current timer\n", .{ ansi.colemp, ansi.colres });
    }
}

/// Display infos on current thing and timer
pub fn cmd() !void {
    var buf_str_id: [4]u8 = undefined;

    const w = std.io.getStdOut().writer();
    const cur_timer = try globals.dfr.getCurrentTimer();

    if (cur_timer.id_thing != 0) {
        const cur_thing = try globals.dfr.getThing(cur_timer.id_thing);
        defer {
            globals.allocator.free(cur_thing.name);
            globals.allocator.free(cur_thing.tags);
            globals.allocator.free(cur_thing.timers);
        }

        const str_id_thing = base62_helper.b10ToB62(&buf_str_id, cur_thing.id);

        try w.print(" {s}thing{s} : {s}{s}{s} - {s}\n", .{ ansi.colemp, ansi.colres, ansi.colid, str_id_thing, ansi.colres, cur_thing.name });
        try w.print("{s}status{s} : {s}\n", .{ ansi.colemp, ansi.colres, @tagName(cur_thing.status) });

        if (cur_thing.status == .ongoing) {
            try displayTargetInfos(cur_thing.target);
            try displayTimeLeftInfos(cur_thing);
            try displayCurTimerInfos(cur_timer.start);
        }
    } else {
        try w.print("There is no current thing.\n", .{});
        try w.print("See \"mtlt help\" for help.\n", .{});
    }
}
