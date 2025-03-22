const std = @import("std");

const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const command_stop = @import("command_stop.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const time_helper = @import("time_helper.zig");
const user_feedback = @import("user_feedback.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;

const little_end = std.builtin.Endian.little;

/// Toggle the status of a thing
pub fn cmd(args: *ArgumentParser) !void {
    var buf_str_id: [4]u8 = undefined;

    // get the current timer contained in the data file
    const cur_timer = try globals.dfr.getCurrentTimer();

    var id_thing: u19 = undefined;

    // determine the id of the thing to toggle
    if (args.*.payload == null) {
        // no argument and no previous current timer
        if (cur_timer.id_thing == 0) {
            try user_feedback.errIdThingMissing();
            return;
        } else {
            id_thing = cur_timer.id_thing;
        }
    } else {
        id_thing = try base62_helper.b62ToB10(args.*.payload.?);
    }

    const str_id = base62_helper.b10ToB62(&buf_str_id, id_thing);

    //  stop a potential current timer running associated to the thing to toggle
    if (globals.dfr.getFixedPartThing(id_thing)) |fpt| {
        if (fpt.status == @intFromEnum(dt.Status.ongoing) and cur_timer.id_thing == id_thing and cur_timer.start != 0) {
            try command_stop.cmd(args);
        }
    } else |err| {
        if (err == DataParsingError.ThingNotFound) {
            try user_feedback.errThingNotFoundNum(id_thing);
            return err;
        } else {
            return err;
        }
    }

    // now that the current timer is closed (if needed), we get the full infos on the thing
    const thing_data = try globals.dfr.getThing(id_thing);
    defer {
        globals.allocator.free(thing_data.name);
        globals.allocator.free(thing_data.tags);
        globals.allocator.free(thing_data.timers);
    }

    // actually toggle the status
    if (globals.dfw.toggleThingStatus(id_thing)) |new_status| {
        const str_new_status: []const u8 = @tagName(new_status);
        try user_feedback.reportThingIdName(str_id, thing_data.name);
        try user_feedback.reportStatus(str_new_status);

        // Display recap on the time spent on this thing
        if (thing_data.timers.len > 0) {
            // get the total amount of time spent on this thing
            var total_time_spent: u64 = 0;
            for (thing_data.timers) |timer| {
                total_time_spent += timer.duration;
            }

            const remaining_time: i64 = @as(i64, @intCast(thing_data.estimation)) - @as(i64, @intCast(total_time_spent));
            var buf_remaining_time: [100]u8 = undefined;
            const str_remaining_time = try time_helper.formatDurationNoSign(&buf_remaining_time, @abs(remaining_time));
            const col_remaining_time = ansi.getDurCol(remaining_time);

            if (thing_data.estimation > 0) {
                try user_feedback.reportTimeLeftInfos(col_remaining_time, str_remaining_time);
            }
        }

        // Display recap on the closure time and target
        if (thing_data.target > 0) {
            const offset_target: i64 = @as(i64, @intCast(thing_data.target)) - @as(i64, @intCast(time_helper.curTimestamp()));
            var buf_target: [100]u8 = undefined;
            const str_target = try time_helper.formatDurationNoSign(&buf_target, @abs(offset_target));
            const col_target = ansi.getDurCol(offset_target);

            try user_feedback.reportTarget(str_target, col_target);
        }
    } else |err| {
        switch (err) {
            DataParsingError.ThingNotFound => try user_feedback.errThingNotFoundStr(str_id),
            else => try user_feedback.errUnexpectedToggleThing(err),
        }
    }
}

/// Print out help for the toggle command
pub fn help() !void {
    try std.io.getStdOut().writer().print("TODO help toggle\n", .{});
}
