const std = @import("std");

const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const dt = @import("data_types.zig");
const dfr = @import("data_file_reader.zig");
const globals = @import("globals.zig");
const table_printer = @import("table_printer.zig");
const time_helper = @import("time_helper.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataOperationError = @import("data_file_writer.zig").DataOperationError;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;

const little_end = std.builtin.Endian.little;

var buf_str_id: [4]u8 = undefined;

pub const CommandError = error{
    NoDuration,
    SeveralDurationArgs,
    StartLessAndMore,
};

/// Display an error received from the parsing of a duration string
fn displayDurationError(dur: []const u8, err: anyerror) !void {
    const w = std.io.getStdOut().writer();

    switch (err) {
        time_helper.TimeError.EmptyDuration => _ = try w.write("Error: the duration is empty\n"),
        time_helper.TimeError.InvalidDurationString => try w.print("Error: the duration string \"{s}\" is invalid\n", .{dur}),
        time_helper.TimeError.DurationTooGreat => try w.print("Error: the duration \"{s}\" is too big\n", .{dur}),
        std.fmt.ParseIntError.Overflow => try w.print("Error: the duration string \"{s}\" contains a number that is too big\n", .{dur}),
        else => {
            try w.print("Unexpected error while parsing the duration {s}\n", .{dur});
            try w.print("{}", .{err});
        },
    }
}

/// Display an info message when the current timer is started
fn displayCurrentTimerStart(cur_timer_id_thing: u19, thing_name: []const u8) !void {
    const str_id = base62_helper.b10ToB62(&buf_str_id, cur_timer_id_thing);
    try std.io.getStdOut().writer().print("Started a timer for: {s}{s}{s} - {s}{s}{s}\n", .{ ansi.colid, str_id, ansi.colres, ansi.colemp, thing_name, ansi.colres });
}

/// Display an info message when the current timer is already running
fn displayCurrentTimerAlreadyRunning(cur_timer_id_thing: u19, thing_name: []const u8) !void {
    const str_id = base62_helper.b10ToB62(&buf_str_id, cur_timer_id_thing);
    try std.io.getStdOut().writer().print("Timer already running for: {s}{s}{s} - {s}{s}{s}\n", .{ ansi.colid, str_id, ansi.colres, ansi.colemp, thing_name, ansi.colres });
}

/// Display an error message when trying to start a timer on a closed thing
fn displayCurrentTimerOnClosedThing(id_thing: u19) !void {
    const str_id = base62_helper.b10ToB62(&buf_str_id, id_thing);
    try std.io.getStdOut().writer().print("Cannot start a timer on a closed thing\n", .{});
    try std.io.getStdOut().writer().print("You can reopen the thing by using the following command: {s}mtlt toggle {s}{s}\n", .{ ansi.colemp, str_id, ansi.colres });
}

/// Display an info message when the specified thing is not found
fn displayThingNotFound(str_thing_id: []const u8) !void {
    try std.io.getStdOut().writer().print("Error: thing with id {s}{s}{s} not found", .{ ansi.colemp, str_thing_id, ansi.colres });
}
///
/// Check that parsed arguments do not contain several types of duration flags
fn checkOnlyOneTypeDurationArg(args: ArgumentParser) !void {
    if ((args.duration != null and args.duration_less != null) or
        (args.duration != null and args.duration_more != null))
    {
        _ = try std.io.getStdOut().write("Error: you cannot give a specific duration and a duration offset at the same time\n");
        return CommandError.SeveralDurationArgs;
    }

    if (args.duration_less != null and args.duration_more != null) {
        _ = try std.io.getStdOut().write("Error: you cannot add and remove duration at the same time\n");
        return CommandError.SeveralDurationArgs;
    }
}

/// Check that parsed arguments do not contain simultaneously duration less and more
fn checkNoDurationLessAndMore(args: ArgumentParser) !void {
    if (args.duration_less != null and args.duration_more != null) {
        _ = try std.io.getStdOut().write("Error: you cannot add and remove duration at the same time\n");
        return CommandError.DurationLessAndMore;
    }
}

/// Check that parsed arguments do not contain simultaneously start offset less and more
fn checkNoStartLessAndMore(args: ArgumentParser) !void {
    if (args.start_less != null and args.start_more != null) {
        _ = try std.io.getStdOut().write("Error: you cannot push the start time backward and forward at the same time\n");
        return CommandError.StartLessAndMore;
    }
}

/// Check there is a duration argument parsed in the command
fn checkDurationPresence(args: ArgumentParser) !u12 {
    if (args.duration) |dur| {
        return dur;
    } else {
        _ = try std.io.getStdOut().write("Error: you need to specify a duration (with the -d flag)\n");
        return CommandError.NoDuration;
    }
}

/// Very basic check to know if a character is a letter or number
/// TODO should be able to handle more than ascii chara
fn isLetterOrNumber(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9');
}

/// Add a new tag to the data file
pub fn addTag(args: ArgumentParser) !void {
    const w = std.io.getStdOut().writer();

    if (args.payload == null) {
        _ = try w.write("Need a name for the tag to add\n");
        return;
    }

    // check for invalid characters in the tag name
    for (args.payload.?) |c| {
        if (!isLetterOrNumber(c)) {
            _ = try w.write("The tag name can only contain ascii letters or numbers");
            return;
        }
    }

    if (globals.dfw.addTagToFile(args.payload.?)) |new_tag_id| {
        _ = new_tag_id;
        try w.print("Added tag {s}{s}{s}\n", .{ ansi.colemp, args.payload.?, ansi.colres });
    } else |err| {
        if (err == DataOperationError.NameTooLong) {
            try w.print("The name {s}\"{s}\"{s} is too long\n", .{ ansi.colemp, args.payload.?, ansi.colres });
        } else if (err == DataOperationError.TagWithThisNameAlreadyExisting) {
            try w.print("A tag with the name {s}{s}{s} already exists\n", .{ ansi.colemp, args.payload.?, ansi.colres });
        } else {
            return err;
        }
    }
}

/// Add a new thing to the data file
pub fn addThing(args: ArgumentParser) !void {
    const w = std.io.getStdOut().writer();

    if (args.payload == null) {
        _ = try w.write("Error: could not parse the name of the thing\n");
        return;
    }

    // format the arguments properly
    const target = if (args.target) |t| t + time_helper.curTimestamp() else 0;
    const estimation = if (args.estimation) |e| e else 0;

    var infos_creation = dt.ThingCreated{};
    infos_creation.created_tags = std.ArrayList([]u8).init(globals.allocator);
    defer infos_creation.created_tags.deinit();

    try globals.dfw.addThingToFile(args.payload.?, target, estimation, args.tags.items, &infos_creation);

    // display infos about the creation of the thing
    const str_id = base62_helper.b10ToB62(&buf_str_id, infos_creation.id);

    try w.print("Created {s}\"{s}\"{s} with ID {s}{s}{s}", .{ ansi.colemp, args.payload.?, ansi.colres, ansi.colid, str_id, ansi.colres });
    if (args.target != null) {
        var str_target: [20]u8 = undefined;
        const slice_str_target = try time_helper.formatDuration(&str_target, args.target.?);
        try w.print(" and a target in {s}{s}{s}\n", .{ ansi.colemp, slice_str_target, ansi.colres });
    } else {
        try w.print("\n", .{});
    }

    for (infos_creation.created_tags.items) |tag| {
        try w.print("Created the tag {s}{s}{s}\n", .{ ansi.colemp, tag, ansi.colres });
    }

    // if wanted, start the current timer on the created thing right away
    if (args.should_start) {
        try start_id(infos_creation.id, args.payload.?);
    }
}

/// Add a new tag to the data file
pub fn addTimer(args: ArgumentParser) !void {
    const w = std.io.getStdOut().writer();
    const cur_time = time_helper.curTimestamp();

    if (args.payload == null) {
        _ = try w.write("Error: could not parse the id of the thing on which to add a timer\n");
        return;
    }
    const id_thing_str = args.payload.?;
    const id_thing_num = try base62_helper.b62ToB10(id_thing_str);

    try checkNoStartLessAndMore(args);

    const duration = try checkDurationPresence(args);

    // Check that there is a start offset value in the command arguments
    if (args.start_less == null) {
        _ = try w.write("Error: you need to specify the time offset between now and the start of the timer (with the -sl flag)\n");
        return;
    }
    const start_less = args.start_less.?;

    // Check that the time offset for start is not too big
    if (cur_time < start_less) {
        try w.print("Error: the time offset between now and the start of the timer is too big. Maximum is: {d}\n", .{cur_time});
        return;
    }

    // compute the absolute value of the start time
    const start_abs = time_helper.curTimestamp() - start_less;

    if (globals.dfw.addTimerToThing(id_thing_num, start_abs, duration)) |id_timer| {
        try w.print("Added timer {s}{s}-{d}{s}\n", .{ ansi.colid, id_thing_str, id_timer, ansi.colres });
    } else |err| {
        try w.print("Error: during the addition of a timer. TODO: {}\n", .{err});
        return;
    }
}

/// Display infos on current thing and timer
pub fn displayCurrent() !void {
    const w = std.io.getStdOut().writer();
    const cur_time = time_helper.curTimestamp();
    const cur_timer = try globals.dfr.getCurrentTimer();

    if (cur_timer.id_thing != 0) {
        const cur_thing = try globals.dfr.getThing(cur_timer.id_thing);
        defer {
            globals.allocator.free(cur_thing.name);
            globals.allocator.free(cur_thing.tags);
            globals.allocator.free(cur_thing.timers);
        }

        var buf_id_thing: [4]u8 = undefined;
        const str_id_thing = base62_helper.b10ToB62(&buf_id_thing, cur_thing.id);

        try w.print("Current thing: {s}{s}{s} - {s}{s}{s}\n", .{ ansi.colid, str_id_thing, ansi.colres, ansi.colemp, cur_thing.name, ansi.colres });

        if (cur_timer.start != 0) {
            var buf_dur_id: [10]u8 = undefined;
            var duration: u9 = 0;
            const temp_dur: u25 = cur_time - cur_timer.start;

            if (temp_dur > std.math.maxInt(u9)) {
                std.debug.print("Error: the current timer has a duration of {d} minutes\n", .{temp_dur});
            } else {
                duration = @intCast(temp_dur);
                try w.print("Timer started {s}{s}{s} ago.\n", .{
                    ansi.coldurntr,
                    try time_helper.formatDurationNoSign(&buf_dur_id, duration),
                    ansi.colres,
                });
            }
        } else {
            try w.print("No current timer.\n", .{});
        }
    } else {
        try w.print("There is no current thing.\n", .{});
        try w.print("See \"mtlt help\" for help.\n", .{});
    }
}

/// Delete a tag from the data file
pub fn deleteTag(args: ArgumentParser) !void {
    const w = std.io.getStdOut().writer();

    if (args.payload == null) {
        _ = try w.write("Need to specify the name(s) of the tag(s) to remove\n");
        return;
    }

    if (globals.dfw.deleteTagFromFile(args.payload.?)) |_| {
        try w.print("The tag {s}{s}{s} was deleted\n", .{ ansi.colemp, args.payload.?, ansi.colres });
    } else |err| {
        if (err == DataParsingError.TagNotFound) {
            try w.print("Error: No tag found with the name {s}{s}{s}\n", .{ ansi.colemp, args.payload.?, ansi.colres });
        } else {
            return err;
        }
    }
}

/// Delete a thing from the data file
pub fn deleteThing(args: ArgumentParser) !void {
    const w = std.io.getStdOut().writer();
    var id_thing_to_delete: u19 = 0;

    // if there is no argument with the command
    if (args.payload == null) {
        const cur_timer = try globals.dfr.getCurrentTimer();

        // and there is a previous thing to delete
        if (cur_timer.id_thing != 0) {
            id_thing_to_delete = cur_timer.id_thing;
        } else {
            _ = try w.write("Need to specify the id of the thing to remove\n");
        }
    } else {
        id_thing_to_delete = try base62_helper.b62ToB10(args.payload.?);
    }

    // check if there is a running timer for this thing. If yes stop it
    const cur_timer = try globals.dfr.getCurrentTimer();
    if (cur_timer.id_thing == id_thing_to_delete) {
        try globals.data_file.seekFromEnd(-dt.lgt_fixed_current_timer);
        const to_write = dt.getIntFromCurrentTimer(.{
            .id_thing = 0,
            .id_last_timer = 0,
            .start = 0,
        });
        try globals.data_file.writer().writeInt(u56, to_write, little_end);
    }

    // get the name of the thing to delete
    if (globals.dfr.getFixedPartThing(id_thing_to_delete)) |fpt| {
        const thing_name = try globals.allocator.alloc(u8, fpt.lgt_name);
        defer globals.allocator.free(thing_name);
        _ = try globals.data_file.reader().read(thing_name);

        // try to delete the thing
        try globals.dfw.deleteThingFromFile(id_thing_to_delete);
        const str_id_thing = base62_helper.b10ToB62(&buf_str_id, id_thing_to_delete);
        try w.print("Deleted thing {s}{s}{s} - {s}{s}{s}\n", .{ ansi.colid, str_id_thing, ansi.colres, ansi.colemp, thing_name, ansi.colres });
    } else |err| {
        switch (err) {
            DataParsingError.ThingNotFound => try displayThingNotFound(args.payload.?),
            else => return err,
        }
    }
}

/// Delete the specified timer of a thing from the data file
pub fn deleteTimer(args: ArgumentParser) !void {
    const w = std.io.getStdOut().writer();

    // if there is no argument with the command
    if (args.payload == null) {
        const cur_timer = try globals.dfr.getCurrentTimer();

        // and there is a previous timer to delete
        if (cur_timer.id_thing != 0 and cur_timer.id_last_timer != 0) {
            if (globals.dfw.deleteTimerFromFile(cur_timer.id_thing, cur_timer.id_last_timer)) |_| {
                var buf_id_timer: [4]u8 = undefined;
                const str_id_timer = try std.fmt.bufPrint(&buf_id_timer, "{d}", .{cur_timer.id_last_timer});
                const str_id_thing = base62_helper.b10ToB62(&buf_str_id, cur_timer.id_thing);
                try w.print("Deleted timer {s}{s}-{s}{s}\n", .{ ansi.colid, str_id_thing, str_id_timer, ansi.colres });
                try globals.dfw.resetIdLastCurrentTimer(cur_timer.id_thing, cur_timer.start);
                return;
            } else |err| {
                try w.print("Error: when trying to delete a timer - {}\n", .{err});
                try globals.dfw.resetIdLastCurrentTimer(cur_timer.id_thing, cur_timer.start);
                return err;
            }
        }

        // if we reach this point, there was no argument with the command but
        // there is no operation that we can perform
        _ = try w.write("There is no immediate last timer to delete and we could not parse a specific timer id\n");
        try w.print("Those should have the format {s}<id thing>-<id timer>{s}. For example: {s}b-2{s}\n", .{ ansi.colid, ansi.colres, ansi.colid, ansi.colres });
        return;
    }

    var arg_it = std.mem.splitSequence(u8, args.payload.?, "-");

    const str_id_thing = arg_it.first();
    const str_id_timer = arg_it.rest();

    const id_thing = base62_helper.b62ToB10(str_id_thing) catch |err| {
        std.debug.print("Error: impossible to parse the ID of the thing: {}\n", .{err});
        return;
    };
    const id_timer = std.fmt.parseInt(u11, str_id_timer, 10) catch |err| {
        std.debug.print("Error: impossible to parse the ID of the thing: {}\n", .{err});
        return;
    };

    // Actually delete and write feedback message
    if (globals.dfw.deleteTimerFromFile(id_thing, id_timer)) |_| {
        try w.print("Deleted timer {s}{s}-{s}{s}\n", .{ ansi.colid, str_id_thing, str_id_timer, ansi.colres });
    } else |err| {
        try w.print("Error: when trying to delete a timer - {}\n", .{err});
        return err;
    }
}

/// Start a timer on a thing
pub fn start(args: ArgumentParser) !void {
    const w = std.io.getStdOut().writer();

    // get the current timer contained in the data file
    const cur_timer = try globals.dfr.getCurrentTimer();

    // if there is no argument
    if (args.payload == null) {
        // and no previous current timer
        if (cur_timer.id_thing == 0) {
            _ = try w.write("Need the ID of a thing to start an associated timer\n");
            return;
        } else {
            // start a timer on the same ID than the previous one
            const cur_fpt = try globals.dfr.getFixedPartThing(cur_timer.id_thing);
            const cur_thing_name = try globals.allocator.alloc(u8, cur_fpt.lgt_name);
            defer globals.allocator.free(cur_thing_name);
            _ = try globals.data_file.reader().readAll(cur_thing_name);
            try start_id(cur_timer.id_thing, cur_thing_name);
        }
    } else {
        const arg_id: u19 = if (args.payload == null) 0 else try base62_helper.b62ToB10(args.payload.?);
        const arg_fpt = try globals.dfr.getFixedPartThing(arg_id);
        const arg_thing_name = try globals.allocator.alloc(u8, arg_fpt.lgt_name);
        defer globals.allocator.free(arg_thing_name);
        _ = try globals.data_file.reader().read(arg_thing_name);
        try start_id(arg_id, arg_thing_name);
    }
}

/// Start a timer on a thing with the specified ID
fn start_id(id: u19, thing_name: []const u8) !void {
    const cur_timer = try globals.dfr.getCurrentTimer();

    // If there is no previous current timer and we have an ID to start on
    if (cur_timer.id_thing == 0 and id != 0) {
        try globals.dfw.startCurrentTimer(id);
        try displayCurrentTimerStart(id, thing_name);
        return;
    }

    // If there is already a cur timer running on another ID
    if (cur_timer.id_thing != 0 and cur_timer.id_thing != id and cur_timer.start != 0) {
        // create an empty default arg parser just to pass to `stop` that requires one
        try stop(ArgumentParser{});
        try globals.dfw.startCurrentTimer(id);
        try displayCurrentTimerStart(id, thing_name);
        return;
    }

    // If there is a stopped previous current timer
    if (cur_timer.id_thing != 0 and cur_timer.id_thing != id and cur_timer.start == 0) {
        try globals.dfw.startCurrentTimer(id);
        try displayCurrentTimerStart(id, thing_name);
        return;
    }

    // If there is already a current timer running with the same ID
    if (cur_timer.id_thing != 0 and cur_timer.id_thing == id and cur_timer.start != 0) {
        try displayCurrentTimerAlreadyRunning(id, thing_name);
        return;
    }

    // If there is a stopped previous current timer with the same ID
    if (cur_timer.id_thing != 0 and cur_timer.id_thing == id and cur_timer.start == 0) {
        try globals.dfw.startCurrentTimer(id);
        try displayCurrentTimerStart(id, thing_name);
        return;
    }
}

/// Stop the current timer
pub fn stop(args: ArgumentParser) !void {
    const w = std.io.getStdOut().writer();
    const cur_timer = try globals.dfr.getCurrentTimer();

    try checkOnlyOneTypeDurationArg(args);
    try checkNoStartLessAndMore(args);

    if (cur_timer.id_thing != 0 and cur_timer.start != 0) {
        const t = try globals.dfw.stopCurrentTimer(.{
            .id = cur_timer.id_last_timer,
            .duration = args.duration,
            .duration_off = if (args.duration_less == null) args.duration_more else args.duration_less,
            .add_duration_off = args.duration_less == null,
            .start_off = if (args.start_less == null) args.start_more else args.start_less,
            .add_start_off = args.start_less == null,
        });

        var buf: [20]u8 = undefined;
        const str_dur = try time_helper.formatDuration(&buf, t.duration);
        const str_id = base62_helper.b10ToB62(&buf_str_id, cur_timer.id_thing);

        // get the name of the thing to stop
        const fpt = try globals.dfr.getFixedPartThing(cur_timer.id_thing);
        const thing_name = try globals.allocator.alloc(u8, fpt.lgt_name);
        defer globals.allocator.free(thing_name);
        _ = try globals.data_file.reader().read(thing_name);

        try w.print("Stopped timer {s}{d}{s} for {s}{s}{s} - {s}{s}{s}. It lasted {s}{s}{s}\n", .{ ansi.colid, t.id, ansi.colres, ansi.colid, str_id, ansi.colres, ansi.colemp, thing_name, ansi.colres, ansi.colemp, str_dur, ansi.colres });
    } else {
        try w.print("No timer currently running\n", .{});
    }
}

/// Toggle the status of a tag
pub fn toggleTagStatus(args: ArgumentParser) !void {
    const w = std.io.getStdOut().writer();

    if (globals.dfw.toggleTagStatus(args.payload.?)) |new_status| {
        try w.print("Status set to {s}{s}{s} for the tag {s}{s}{s}\n", .{ ansi.colemp, @tagName(new_status), ansi.colres, ansi.colemp, args.payload.?, ansi.colres });
    } else |err| {
        if (err == DataParsingError.TagNotFound) {
            try w.print("Error: No tag found for the name {s}{s}{s}\n", .{ ansi.colemp, args.payload.?, ansi.colres });
        } else {
            return err;
        }
    }
}

/// Toggle the status of a thing
pub fn toggleThingStatus(args: ArgumentParser) !void {
    const w = std.io.getStdOut().writer();

    if (args.payload == null) {
        _ = try w.write("Need to specify the id of the thing to toggle\n");
        return;
    }

    const id_thing = try base62_helper.b62ToB10(args.payload.?);

    if (globals.dfr.getFixedPartThing(id_thing)) |fpt| {
        // if there is a current timer running associated to this thing, we stop it
        const cur_timer = try globals.dfr.getCurrentTimer();
        if (fpt.status == @intFromEnum(dt.Status.ongoing) and cur_timer.id_thing == id_thing and cur_timer.start != 0) {
            try stop(args);
        }
    } else |err| {
        if (err == DataParsingError.ThingNotFound) {
            try displayThingNotFound(args.payload.?);
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
        try w.print("{s}{s}{s} - {s}{s}{s} is now {s}{s}{s}\n", .{ ansi.colid, args.payload.?, ansi.colres, ansi.colemp, thing_data.name, ansi.colres, ansi.colemp, str_new_status, ansi.colres });

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
            try displayThingNotFound(args.payload.?);
            return err;
        } else {
            return err;
        }
    }
}

/// Update the name of a tag
pub fn updateTagName(args: ArgumentParser) !void {
    const w = std.io.getStdOut().writer();

    if (args.payload == null) {
        _ = try w.write("You need to specify the current name of the tag to udpate");
        _ = try w.write("The format of the command is \"mtlt udpate-tag <old_name> -n <new_name>\"");
        return;
    }

    if (args.name == null) {
        _ = try w.write("You need to specify the new name for the tag with the \"-n\" or \"--name\" flag");
        _ = try w.write("The format of the command is \"mtlt udpate-tag <old_name> -n <new_name>\"");
        return;
    }

    // finally perform the operation
    if (globals.dfw.updateTagName(args.payload.?, args.name.?)) |_| {
        try w.print("Tag {s}{s}{s} is now nammed {s}{s}{s}\n", .{ ansi.colemp, args.payload.?, ansi.colres, ansi.colemp, args.name.?, ansi.colres });
    } else |err| {
        switch (err) {
            DataParsingError.TagNotFound => try w.print("Error: no tag with name {s}{s}{s} found\n", .{ ansi.colemp, args.payload.?, ansi.colres }),
            DataOperationError.NameTooLong => try w.print("Error: the new name is too long {s}{s}{s}\n", .{ ansi.colemp, args.name.?, ansi.colres }),
            DataOperationError.TagWithThisNameAlreadyExisting => try w.print("Error: a tag with the name {s}{s}{s} already exists\n", .{ ansi.colemp, args.name.?, ansi.colres }),
            else => return err,
        }
    }
}

/// Update a thing
pub fn updateThing(args: ArgumentParser) !void {
    const w = std.io.getStdOut().writer();

    if (args.payload == null) {
        _ = try w.write("Error: could not parse the id of the thing to update\n");
        return;
    }

    const cur_time = time_helper.curTimestamp();

    // format the arguments properly
    const target = if (args.target) |t| if (t == 0) t else t + cur_time else null;
    const id_num = try base62_helper.b62ToB10(args.payload.?);
    const id_str = args.payload.?;

    // create the array list for the tags to update
    var created_tags = std.ArrayList(dt.Tag).init(globals.allocator);
    defer created_tags.deinit();

    if (globals.dfw.updateThing(.{
        .id = id_num,
        .target = target,
        .estimation = args.estimation,
        .name = args.name,
        .tags = args.tags,
    }, &created_tags)) |_| {} else |err| {
        switch (err) {
            DataParsingError.ThingNotFound => try displayThingNotFound(args.payload.?),
            else => std.debug.print("ERROR: {}\n", .{err}),
        }
    }

    // get the name of the thing
    const thing_data = try globals.dfr.getFixedPartThing(id_num);
    const thing_name = try globals.allocator.alloc(u8, thing_data.lgt_name);
    defer globals.allocator.free(thing_name);
    _ = try globals.data_file.reader().read(thing_name);

    try w.print("Updated thing {s}{s}{s} - {s}{s}{s}\n", .{ ansi.colid, id_str, ansi.colres, ansi.colemp, thing_name, ansi.colres });

    for (created_tags.items) |ct| {
        try w.print("Added tag {s}{s}{s}\n", .{ ansi.colemp, ct.name, ansi.colres });
    }

    // if wanted and possible, start the current timer on the updated thing right away
    if (args.should_start) {
        if (thing_data.status == @intFromEnum(dt.Status.closed)) {
            try displayCurrentTimerOnClosedThing(thing_data.id);
            return;
        }

        try start_id(id_num, thing_name);
    }
}

/// Update a timer
pub fn updateTimer(args: ArgumentParser) !void {
    const w = std.io.getStdOut().writer();

    try checkOnlyOneTypeDurationArg(args);
    try checkNoStartLessAndMore(args);

    // if there is no argument with the command
    if (args.payload == null) {
        const cur_timer = try globals.dfr.getCurrentTimer();

        // and there is a previous timer to update
        if (cur_timer.id_thing != 0 and cur_timer.id_last_timer != 0) {
            if (globals.dfw.updateTimer(.{
                .id = cur_timer.id_last_timer,
                .duration = args.duration,
                .duration_off = if (args.duration_less == null) args.duration_more else args.duration_less,
                .add_duration_off = args.duration_less == null,
                .start_off = if (args.start_less == null) args.start_more else args.start_less,
                .add_start_off = args.start_less == null,
            }, cur_timer.id_thing)) |_| {
                var buf_id_timer: [4]u8 = undefined;
                const str_id_timer = try std.fmt.bufPrint(&buf_id_timer, "{d}", .{cur_timer.id_last_timer});
                const str_id_thing = base62_helper.b10ToB62(&buf_str_id, cur_timer.id_thing);
                try w.print("Updated timer {s}{s}-{s}{s}. TODO new start and duration\n", .{ ansi.colid, str_id_thing, str_id_timer, ansi.colres });
                return;
            } else |err| {
                try w.print("Error: when trying to update a timer - {}\n", .{err});
                return err;
            }
        }

        // if we reach this point, there was no argument with the command but
        // there is no operation that we can perform
        _ = try w.write("There is no immediate last timer to update and we could not parse a specific timer id\n");
        try w.print("Those should have the format {s}<id thing>-<id timer>{s}. For example: {s}b-2{s}\n", .{ ansi.colid, ansi.colres, ansi.colid, ansi.colres });
        return;
    }

    var arg_it = std.mem.splitSequence(u8, args.payload.?, "-");

    const str_id_thing = arg_it.first();
    const str_id_timer = arg_it.rest();

    const id_thing = base62_helper.b62ToB10(str_id_thing) catch |err| {
        std.debug.print("Error: impossible to parse the ID of the thing: {}\n", .{err});
        return;
    };
    const id_timer = std.fmt.parseInt(u11, str_id_timer, 10) catch |err| {
        std.debug.print("Error: impossible to parse the ID of the timer: {}\n", .{err});
        return;
    };

    // get the values to pass regarding the duration offset
    var duration_off: ?u12 = null;
    var add_duration_off = false;

    if (args.duration_more != null) {
        duration_off = args.duration_more;
        add_duration_off = true;
    } else if (args.duration_less != null) {
        duration_off = args.duration_less;
        add_duration_off = false;
    }

    // get the values to pass regarding the start offset
    var start_off: ?u25 = null;
    var add_start_off = false;

    if (args.start_more != null) {
        start_off = args.start_more;
        add_start_off = true;
    } else if (args.start_less != null) {
        start_off = args.start_less;
        add_start_off = false;
    }

    if (args.duration == null and duration_off == null and start_off == null) {
        _ = try w.write("Nothing to update on the timer");
        _ = try w.write("You can specify a duration (with -d), a duration offset (with -dm or -dl) or start time offset (with -sm or -sl)");
        _ = try w.write("Ex: '-dm :20' to add 20 minutes to the duration. Or '-sl 1:34' to subtract 1 hour 34 minutes from current start time");
    }

    const update_data = dt.TimerToUpdate{
        .id = id_timer,
        .duration = args.duration,
        .duration_off = duration_off,
        .add_duration_off = add_duration_off,
        .start_off = start_off,
        .add_start_off = add_start_off,
    };

    try globals.dfw.updateTimer(update_data, id_thing);

    // display feedback message
    const fpt = try globals.dfr.getFixedPartThing(id_thing);
    const name_thing = try globals.allocator.alloc(u8, fpt.lgt_name);
    defer globals.allocator.free(name_thing);
    _ = try globals.data_file.readAll(name_thing);

    try w.print("Updated timer {s}{s}{s} of {s}{s}{s} - {s}{s}{s}\n", .{ ansi.colid, str_id_timer, ansi.colres, ansi.colid, str_id_thing, ansi.colres, ansi.colemp, name_thing, ansi.colres });
}
