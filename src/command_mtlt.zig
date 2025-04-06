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

const little_end = std.builtin.Endian.little;

// display infos on the kickoff of current thing
fn displayKickoffInfos(kickoff: u25) !void {
    if (kickoff != 0) {
        const kickoff_offset_min = @as(i64, kickoff) - @as(i64, time_helper.curTimestamp());
        const kickoff_offset_step = try time_helper.getStepsFromMinutes(u25, kickoff_offset_min);
        try user_feedback.reportKickoff(kickoff_offset_step, ansi.getDurCol(kickoff_offset_min));
    }
}

// display infos on the time left if there is an estimation
fn displayTimeLeftInfos(cur_thing: dt.Thing) !void {
    if (cur_thing.estimation != 0) {
        const time_left = try time_helper.computeTimeLeft(cur_thing);
        try user_feedback.reportTimeLeftInfos(@intCast(time_left), ansi.getDurCol(time_left));
    }
}

// display infos on the current timer
fn displayCurTimerInfos(start: u25) !void {
    if (start != 0) {
        var buf_dur_id: [10]u8 = undefined;
        const temp_dur: u25 = time_helper.curTimestamp() - start;

        if (temp_dur > std.math.maxInt(u9)) {
            try user_feedback.errTimerDurationTooGreat(temp_dur);
        } else {
            const str_duration = try std.fmt.bufPrint(&buf_dur_id, "{d}", .{@as(u9, @intCast(temp_dur))});
            try user_feedback.reportTimerStarted(str_duration);
        }
    } else {
        try user_feedback.reportNoTimer();
    }
}

/// Display infos on current thing and timer
pub fn cmd() !void {
    var buf_str_id: [4]u8 = undefined;
    const cur_timer = try globals.dfr.getCurrentTimer();

    if (cur_timer.id_thing != 0) {
        const cur_thing = try globals.dfr.getThing(cur_timer.id_thing);
        defer cur_thing.deinit();

        const str_id_thing = base62_helper.b10ToB62(&buf_str_id, cur_thing.id);

        try user_feedback.reportThingIdName(str_id_thing, cur_thing.name);
        try user_feedback.reportStatus(@tagName(cur_thing.status));

        if (cur_thing.status == .open) {
            try displayKickoffInfos(cur_thing.kickoff);
            try displayTimeLeftInfos(cur_thing);
            try displayCurTimerInfos(cur_timer.start);
        }
    } else {
        try user_feedback.reportNoCurrentThing();
    }
}
