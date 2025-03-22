const std = @import("std");

const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const dt = @import("data_types.zig");
const dfr = @import("data_file_reader.zig");
const globals = @import("globals.zig");
const table_printer = @import("table_printer.zig");
const time_helper = @import("time_helper.zig");
const user_feedback = @import("user_feedback.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

/// Stop the current timer
pub fn cmd(args: *ArgumentParser) !void {
    const cur_timer = try globals.dfr.getCurrentTimer();
    var buf_str_id: [4]u8 = undefined;

    try args.*.checkOnlyOneTypeDurationArg();
    try args.*.checkNoStartLessAndMore();

    if (cur_timer.id_thing != 0 and cur_timer.start != 0) {
        const t = try globals.dfw.stopCurrentTimer(.{
            .id = cur_timer.id_last_timer,
            .duration = args.*.duration,
            .duration_off = if (args.*.duration_less == null) args.*.duration_more else args.*.duration_less,
            .add_duration_off = args.*.duration_less == null,
            .start_off = if (args.*.start_less == null) args.*.start_more else args.*.start_less,
            .add_start_off = args.*.start_less == null,
        });

        var buf: [20]u8 = undefined;
        const str_dur = try time_helper.formatDuration(&buf, t.duration);
        const str_id = base62_helper.b10ToB62(&buf_str_id, cur_timer.id_thing);

        // get the name of the thing to stop
        const fpt = try globals.dfr.getFixedPartThing(cur_timer.id_thing);
        const thing_name = try globals.allocator.alloc(u8, fpt.lgt_name);
        defer globals.allocator.free(thing_name);
        _ = try globals.data_file.reader().read(thing_name);

        try user_feedback.stoppedTimer(t.id, str_id, thing_name, str_dur);
    } else {
        try user_feedback.noTimerRunning();
    }
}

/// Print out help for the stop command
pub fn help() !void {
    try std.io.getStdOut().writer().print("TODO help stop\n", .{});
}
