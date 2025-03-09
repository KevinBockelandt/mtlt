const std = @import("std");

const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const command_stop = @import("command_stop.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const time_helper = @import("time_helper.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;

const little_end = std.builtin.Endian.little;

/// Toggle the status of a thing
pub fn cmd(args: *ArgumentParser) !void {
    const w = std.io.getStdOut().writer();
    var buf_str_id: [4]u8 = undefined;

    // get the current timer contained in the data file
    const cur_timer = try globals.dfr.getCurrentTimer();

    var id_thing: u19 = undefined;

    // determine the id of the thing to toggle
    if (args.*.payload == null) {
        // no argument and no previous current timer
        if (cur_timer.id_thing == 0) {
            _ = try w.write("Need to specify the id of the thing to toggle\n");
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
            try w.print("Error: thing with id {s}{s}{s} not found", .{ ansi.colemp, str_id, ansi.colres });
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
        try w.print("{s}{s}{s} - {s}{s}{s} is now {s}{s}{s}\n", .{ ansi.colid, str_id, ansi.colres, ansi.colemp, thing_data.name, ansi.colres, ansi.colemp, str_new_status, ansi.colres });

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
                if (remaining_time > 0) {
                    try w.print("{s}{s} less{s} than estimation\n", .{ col_remaining_time, str_remaining_time, ansi.colres });
                } else {
                    try w.print("{s}{s} more{s} than estimation\n", .{ col_remaining_time, str_remaining_time, ansi.colres });
                }
            }
        }

        // Display recap on the closure time and target
        if (thing_data.target > 0) {
            const offset_target: i64 = @as(i64, @intCast(thing_data.target)) - @as(i64, @intCast(time_helper.curTimestamp()));
            var buf_target: [100]u8 = undefined;
            const str_target = try time_helper.formatDurationNoSign(&buf_target, @abs(offset_target));
            const col_target = ansi.getDurCol(offset_target);

            if (offset_target > 0) {
                try w.print("{s}{s} less{s} than target\n", .{ col_target, str_target, ansi.colres });
            } else {
                try w.print("{s}{s} more{s} than target\n", .{ col_target, str_target, ansi.colres });
            }
        }
    } else |err| {
        if (err == DataParsingError.ThingNotFound) {
            try w.print("Error: thing with id {s}{s}{s} not found", .{ ansi.colemp, str_id, ansi.colres });
            return err;
        } else {
            return err;
        }
    }
}

/// Print out help for the toggle command
pub fn help() !void {
    try std.io.getStdOut().writer().print("TODO help toggle\n", .{});
}
