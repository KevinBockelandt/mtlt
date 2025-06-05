const std = @import("std");

const ansi = @import("ansi_codes.zig");
const command_start = @import("command_start.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const id_helper = @import("id_helper.zig");
const it_helper = @import("integration_tests_helper.zig");
const th = @import("time_helper.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;
const DataOperationError = @import("data_file_writer.zig").DataOperationError;

/// Update a thing
pub fn cmd(args: *ArgumentParser) !void {
    var buf_str_id: [4]u8 = undefined;
    const cur_time = th.curTimestamp();
    const cur_timer = try globals.dfr.getCurrentTimer();

    var id_num: u19 = undefined;

    // determine the id of the thing to toggle
    if (args.*.payload == null) {
        // no argument and no previous current timer
        if (cur_timer.id_thing == 0) {
            try globals.printer.errMissingIdThing();
            return;
        } else {
            id_num = cur_timer.id_thing;
        }
    } else {
        id_num = id_helper.b62ToB10(args.*.payload.?) catch |err| {
            switch (err) {
                id_helper.Base62Error.TooBig => try globals.printer.errIdTooBig(),
                id_helper.Base62Error.ContainsInvalidCharacters => try globals.printer.errIdInvalidCharacters(),
            }
            return;
        };
    }

    // get the kickoff timestamp in minutes and make sure it does not overflow
    var kickoff: ?u25 = undefined;

    if (args.*.kickoff) |k| {
        if (k == 0) {
            kickoff = 0;
        } else if (th.getMinutesFromSteps(u25, k)) |min| {
            if (std.math.add(u25, min, cur_time)) |total_min| {
                kickoff = total_min;
            } else |_| {
                try globals.printer.errKickoffTooBig();
                return;
            }
        } else |err| {
            switch (err) {
                th.TimeError.ReturnVarTypeTooSmall => {
                    try globals.printer.errKickoffTooBig();
                    return;
                },
                else => return err,
            }
        }
    } else {
        kickoff = null;
    }

    // create the array list for the tags to update
    var created_tags = std.ArrayList(dt.Tag).init(globals.allocator);
    defer created_tags.deinit();

    if (globals.dfw.updateThing(.{
        .id = id_num,
        .kickoff = kickoff,
        .estimation = args.*.estimation,
        .name = args.*.name,
        .tags = args.*.tags,
    }, &created_tags)) |_| {} else |err| {
        switch (err) {
            DataParsingError.ThingNotFound => try globals.printer.errThingNotFoundStr(args.*.payload.?),
            DataOperationError.TooManyTags => try globals.printer.errThingTooManyTags(),
            else => try globals.printer.errUnexpectedUpdatingThing(err),
        }
    }

    // get the name of the thing
    const thing_data = try globals.dfr.getFixedPartThing(id_num);
    const thing_name = try globals.allocator.alloc(u8, thing_data.lgt_name);
    defer globals.allocator.free(thing_name);
    _ = try globals.data_file.reader().read(thing_name);

    const str_id = id_helper.b10ToB62(&buf_str_id, id_num);
    try globals.printer.updatedThing(thing_name, str_id);

    for (created_tags.items) |ct| {
        try globals.printer.createdTag(ct.name);
    }

    // if wanted and possible, start the current timer on the updated thing right away
    if (args.*.should_start) {
        if (thing_data.status == @intFromEnum(dt.StatusThing.closed)) {
            try globals.printer.cantStartIfClosed(str_id);
            return;
        }

        try command_start.start_id(id_num, thing_name);
    }
}

/// Print out help for the update command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt update [thing_id] [OPTIONS]{s}
        \\
        \\Update an existing thing.
        \\
        \\If no ID is provided, it deletes the current thing. You can see what
        \\the current thing is by using {s}mtlt{s} without any sub-command.
        \\
        \\All the specified tags will see their association toggled. If it was
        \\already associated to the thing it won't be anymore and if it was not
        \\already associated it will be.
        \\
        \\The kickoff duration represents the number of steps in the future from now.
        \\Except if the value is 0, in which case it removes any existing kickoff on
        \\the thing.
        \\
        \\Options:
        \\  {s}-e{s}, {s}--estimation{s}      How many steps will it take to complete
        \\  {s}-k{s}, {s}--kickoff{s}         When should the thing start
        \\  {s}-n{s}, {s}--name{s}            Name of the thing
        \\  {s}-s{s}, {s}--start{s}           Start a timer on the thing right away
        \\  {s}-t{s}, {s}--tags{s}            Tags to add or remove from this thing
        \\
        \\Examples:
        \\  {s}mtlt update -n "new name" -k 30{s}
        \\      Update the name of the current thing and it's kickoff to 30 steps in
        \\      the future.
        \\
        \\  {s}mtlt update 7 -e 10 -k 0 -s{s}
        \\      Update thing with ID "7" to change it's estimation to 10 steps, remove
        \\      it's kickoff time and start a timer on the thing right away.
        \\
        \\  {s}mtlt update F2 -t soon myCoolTag -s{s}
        \\      Update the tag association for the tags "soon" and "myCoolTag" on
        \\      the thing with ID "F2" and start a timer on that thing right away.
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}

test "update thing - no current thing - no thing id" {
    var args: ArgumentParser = .{ .name = "new name thing" };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getStarterFile(),
        .ex_file = try it_helper.getStarterFile(),
        .ex_stderr = "No ID provided and no current thing to operate on.\n",
        .ex_stdout = "",
    });
}

test "update thing - current thing ok - name ok" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.things.items[2].name = "new name thing";
    var args: ArgumentParser = .{ .name = "new name thing" };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stderr = "",
    });
}

test "update thing - name ok" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.things.items[0].name = "new name thing";
    var args: ArgumentParser = .{ .payload = "3", .name = "new name thing" };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stderr = "",
    });
}

test "update thing - name ok and start timer ok" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.things.items[1].name = "new name thing";
    ex_file.cur_timer.id_thing = 2;
    ex_file.cur_timer.start = cur_time;
    var args: ArgumentParser = .{ .payload = "2", .name = "new name thing", .should_start = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stderr = "",
    });
}

test "update thing - name ok and start timer on closed thing" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.things.items[0].name = "new name thing";
    var args: ArgumentParser = .{ .payload = "3", .name = "new name thing", .should_start = true };

    var buf_update: [128]u8 = undefined;
    var buf_stop1: [128]u8 = undefined;
    var buf_stop2: [256]u8 = undefined;
    var buf_ex_stdout: [512]u8 = undefined;

    const str_update = try std.fmt.bufPrint(&buf_update, "Updated thing {s}3{s} - {s}new name thing{s}\n", .{ ansi.colid, ansi.colres, ansi.colemp, ansi.colres });
    const str_stop1 = try std.fmt.bufPrint(&buf_stop1, "Cannot start a timer on a closed thing\n", .{});
    const str_stop2 = try std.fmt.bufPrint(&buf_stop2, "You can reopen the thing by using the following command: {s}mtlt toggle 3{s}\n", .{ ansi.colemp, ansi.colres });
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "{s}{s}{s}", .{ str_update, str_stop1, str_stop2 });

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stderr = "",
        .ex_stdout = ex_stdout,
    });
}

test "update thing - add non-existing tags" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);

    try ex_file.tags.insert(0, .{ .id = 4, .status = dt.StatusTag.someday, .name = "newtag1" });
    try ex_file.tags.insert(0, .{ .id = 5, .status = dt.StatusTag.someday, .name = "newtag2" });

    var tags_thing_3 = try globals.allocator.alloc(u16, 3);
    tags_thing_3[0] = 4;
    tags_thing_3[1] = 5;
    tags_thing_3[2] = 2;

    ex_file.things.items[0].tags = tags_thing_3[0..];

    var tags = std.ArrayList([]const u8).init(globals.allocator);
    defer tags.deinit();
    try tags.append("newtag1");
    try tags.append("newtag2");
    var args: ArgumentParser = .{ .payload = "3", .tags = tags };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stderr = "",
    });
}

test "update thing - remove and add existing and non-existing tags" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);

    try ex_file.tags.insert(0, .{ .id = 4, .status = dt.StatusTag.someday, .name = "newtag1" });

    var tags_thing_3 = try globals.allocator.alloc(u16, 2);
    tags_thing_3[0] = 3;
    tags_thing_3[1] = 4;

    ex_file.things.items[0].tags = tags_thing_3[0..];

    var tags = std.ArrayList([]const u8).init(globals.allocator);
    defer tags.deinit();
    try tags.append("now");
    try tags.append("soon");
    try tags.append("newtag1");
    var args: ArgumentParser = .{ .payload = "3", .tags = tags };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stderr = "",
    });
}

test "update thing - add max limit of tags" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    const nb_tag_to_add = 62;

    var tags = std.ArrayList([]const u8).init(globals.allocator);
    defer tags.deinit();

    var tags_thing_3 = try globals.allocator.alloc(u16, nb_tag_to_add + 1);

    var buf_tag_name: [10]u8 = undefined;

    for (0..nb_tag_to_add) |i| {
        const tag_name = try std.fmt.bufPrint(&buf_tag_name, "tag{d}", .{i});
        const alloc_tag_name = try globals.allocator.dupe(u8, tag_name);
        try tags.append(alloc_tag_name);

        const id: u16 = @intCast(i + 4);
        try ex_file.tags.insert(0, .{ .id = id, .status = dt.StatusTag.someday, .name = alloc_tag_name });
        tags_thing_3[i] = id;
    }
    defer {
        for (0..nb_tag_to_add) |i| {
            globals.allocator.free(tags.items[i]);
        }
    }

    tags_thing_3[nb_tag_to_add] = 2;
    ex_file.things.items[0].tags = tags_thing_3[0..];

    var args: ArgumentParser = .{ .payload = "3", .tags = tags };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stderr = "",
    });
}

test "update thing - add too many tags" {
    const cur_time = th.curTimestamp();
    const nb_tag_to_add = 63;

    var tags = std.ArrayList([]const u8).init(globals.allocator);
    defer tags.deinit();

    var buf_tag_name: [10]u8 = undefined;

    for (0..nb_tag_to_add) |i| {
        const tag_name = try std.fmt.bufPrint(&buf_tag_name, "tag{d}", .{i});
        const alloc_tag_name = try globals.allocator.dupe(u8, tag_name);
        try tags.append(alloc_tag_name);
    }
    defer {
        for (0..nb_tag_to_add) |i| {
            globals.allocator.free(tags.items[i]);
        }
    }

    var args: ArgumentParser = .{ .payload = "3", .tags = tags };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_stderr = "There are too many tags associated to the thing. The maximum is 63.\n",
    });
}

test "update thing - estimation ok" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.things.items[0].estimation = 40;
    var args: ArgumentParser = .{ .payload = "3", .estimation = 40 };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stderr = "",
    });
}

test "update thing - kickoff at 0 (to remove it)" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.things.items[0].kickoff = 0;
    var args: ArgumentParser = .{ .payload = "3", .kickoff = 0 };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stderr = "",
    });
}

test "update thing - kickoff ok" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.things.items[0].kickoff = cur_time + try th.getMinutesFromSteps(u25, 30);
    var args: ArgumentParser = .{ .payload = "3", .kickoff = 30 };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stderr = "",
    });
}
