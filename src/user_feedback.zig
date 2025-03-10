const std = @import("std");

const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const command_start = @import("command_start.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const time_helper = @import("time_helper.zig");

const w = std.io.getStdOut().writer();

/// When a new tag is created
pub fn createdTag(tag_name: []const u8) !void {
    try w.print("Created the tag {s}{s}{s}\n", .{ ansi.colemp, tag_name, ansi.colres });
}

/// Error with a timer duration that is too great
pub fn errorTimerDurationTooGreat(duration: u25) !void {
    var buf_dur: [24]u8 = undefined;
    const str_dur = time_helper.formatDurationNoSign(&buf_dur, duration);
    try w.print("Error: the current timer has a duration of {s}{s}{s}\n", .{ ansi.colemp, str_dur, ansi.colres });

    const str_max_dur = time_helper.formatDurationNoSign(&buf_dur, std.math.maxInt(u9));
    try w.print("The maximum duration is {s}{s}{s}\n", .{ ansi.colemp, str_max_dur, ansi.colres });
}

/// Error when a thing is not found
pub fn errorThingNotFoundStr(thing_id: []const u8) !void {
    try w.print("Error: thing with id {s}{s}{s} not found\n", .{ ansi.colemp, thing_id, ansi.colres });
}

/// Error when a thing is not found
pub fn errorThingNotFoundNum(thing_id: u19) !void {
    var buf_str_id: [4]u8 = undefined;
    const str_id = base62_helper.b10ToB62(&buf_str_id, thing_id);
    try errorThingNotFoundStr(str_id);
}

/// Error when a tag is not found
pub fn errorTagNotFound(tag_name: []const u8) !void {
    try w.print("Error: tag with the name {s}{s}{s} not found\n", .{ ansi.colemp, tag_name, ansi.colres });
}
