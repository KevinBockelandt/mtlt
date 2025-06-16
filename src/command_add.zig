const std = @import("std");

const ansi = @import("ansi_codes.zig");
const command_start = @import("command_start.zig");
const dfw = @import("data_file_writer.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const id_helper = @import("id_helper.zig");
const it_helper = @import("integration_tests_helper.zig");
const th = @import("time_helper.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

/// Add a new thing to the data file
pub fn cmd(args: *ArgumentParser) !void {
    var buf_str_id: [4]u8 = undefined;

    // make sure there is a name for the thing
    if (args.*.payload == null) {
        try globals.printer.errNameThingMissing();
        return;
    }

    const name = args.*.payload.?;

    // make sure the name is not too long
    if (name.len > std.math.maxInt(u8)) {
        try globals.printer.errNameTooLong(name);
        return;
    }

    // make sure there are not too many tags
    if (args.*.tags.items.len > std.math.maxInt(u6)) {
        try globals.printer.errThingTooManyTags();
        return;
    }

    // get the kickoff timestamp in minutes and make sure it does not overflow
    var kickoff: u25 = undefined;

    if (args.*.kickoff) |k| {
        if (th.getMinutesFromSteps(u25, k)) |min| {
            const cur_time: u25 = th.curTimestamp();
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
    } else if (args.*.should_start) {
        kickoff = th.curTimestamp();
    } else {
        kickoff = 0;
    }

    // estimation is directly in steps
    const estimation = if (args.*.estimation) |e| e else 0;

    var infos_creation = dt.ThingCreated{};
    infos_creation.created_tags = std.ArrayList([]const u8).init(globals.allocator);
    defer infos_creation.created_tags.deinit();

    // actually execute the command
    globals.dfw.addThingToFile(name, kickoff, estimation, args.*.tags.items, &infos_creation) catch |err| {
        switch (err) {
            dfw.DataOperationError.TooManyThings => try globals.printer.errTooManyThings(),
            else => return err,
        }
    };

    // display infos about the creation of the thing
    const str_id = id_helper.b10ToB62(&buf_str_id, infos_creation.id);
    try globals.printer.createdThing(name, str_id);

    if (args.*.kickoff != null) {
        try globals.printer.reportKickoffPos(args.*.kickoff.?);
    }

    for (infos_creation.created_tags.items) |tag| {
        try globals.printer.createdTag(tag);
    }

    // if wanted, start the current timer on the created thing right away
    if (args.*.should_start) {
        try command_start.start_id(infos_creation.id, name);
    }
}

/// Display help text for this command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt add <thing_name> [OPTIONS]{s}
        \\
        \\Creates a new thing.
        \\
        \\If the start option is specified while no kickoff is given, the kickoff will
        \\be set to 0 automatically.
        \\
        \\Options:
        \\  {s}-e{s}, {s}--estimation{s}         How many steps will it take to complete
        \\  {s}-k{s}, {s}--kickoff{s}            When should the thing start
        \\  {s}-s{s}, {s}--start{s}              Start a timer on the thing right away
        \\  {s}-t{s}, {s}--tags{s}               Tags associated to this thing
        \\
        \\Examples:
        \\  {s}mtlt add "myCoolThing"{s}
        \\      Create a new thing called 'myCoolThing' without additional data.
        \\
        \\  {s}mtlt add "new_thing" -t tag1 tag2 -e 20{s}
        \\      Create a new thing called 'new_thing' with the associated tags 'tag1'
        \\      and 'tag2' and an estimation of 20 steps.
        \\
        \\  {s}mtlt add "# the name can contain anything@@" -k 10 -s{s}
        \\      Create a new thing called '# the name can contain anything@@' with a
        \\      theoric kickoff in 10 steps and start a timer right away on it even
        \\      though it's contradictory with the theoric kickoff.
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
    });
}

test "add thing with only a name" {
    var ex_file = try it_helper.getStarterFile();
    const thing_to_add: dt.Thing = .{
        .id = 1,
        .name = "testthing",
        .tags = &[_]u16{},
        .timers = &[_]dt.Timer{},
        .creation = th.curTimestamp(),
    };
    try ex_file.things.insert(0, thing_to_add);
    var args: ArgumentParser = .{ .payload = "testthing" };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getStarterFile(),
        .ex_file = ex_file,
    });
}

test "add thing with name + tags + kickoff" {
    var ex_file = try it_helper.getStarterFile();
    var expected_tags: [1]u16 = .{1};
    const thing_to_add: dt.Thing = .{
        .id = 1,
        .name = "testthing",
        .tags = expected_tags[0..],
        .timers = &[_]dt.Timer{},
        .creation = th.curTimestamp(),
    };
    try ex_file.things.insert(0, thing_to_add);

    var tags = std.ArrayList([]const u8).init(globals.allocator);
    defer tags.deinit();
    try tags.append("someday");
    var args: ArgumentParser = .{ .payload = "testthing", .tags = tags };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getStarterFile(),
        .ex_file = ex_file,
    });
}

test "add thing with name + tag creation + kickoff + estimation + start" {
    var ex_file = try it_helper.getStarterFile();
    var expected_tags: [1]u16 = .{4};
    const thing_to_add: dt.Thing = .{
        .id = 1,
        .name = "testthing",
        .tags = expected_tags[0..],
        .timers = &[_]dt.Timer{},
        .kickoff = th.curTimestamp() + try th.getMinutesFromSteps(u25, 34),
        .estimation = 5432,
        .creation = th.curTimestamp(),
    };
    try ex_file.things.insert(0, thing_to_add);
    try ex_file.tags.insert(0, .{ .id = 4, .status = dt.StatusTag.someday, .name = "newtag" });
    ex_file.cur_timer = .{
        .id_thing = 1,
        .id_last_timer = 0,
        .start = th.curTimestamp(),
    };

    var tags = std.ArrayList([]const u8).init(globals.allocator);
    defer tags.deinit();
    try tags.append("newtag");
    var args: ArgumentParser = .{
        .payload = "testthing",
        .tags = tags,
        .kickoff = 34,
        .estimation = 5432,
        .should_start = true,
    };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getStarterFile(),
        .ex_file = ex_file,
    });
}

test "add multiple things" {
    var ex_file = try it_helper.getStarterFile();

    var expected_tags_1: [1]u16 = .{3};
    var expected_tags_2: [1]u16 = .{4};
    try ex_file.tags.insert(0, .{ .id = 4, .status = dt.StatusTag.someday, .name = "newtag" });

    const thing_to_add_1: dt.Thing = .{
        .id = 1,
        .name = "test1",
        .tags = expected_tags_1[0..],
        .timers = &[_]dt.Timer{},
        .kickoff = th.curTimestamp() + try th.getMinutesFromSteps(u25, 34),
        .estimation = 5432,
        .creation = th.curTimestamp(),
    };
    try ex_file.things.insert(0, thing_to_add_1);

    const thing_to_add_2: dt.Thing = .{
        .id = 2,
        .name = "test2",
        .tags = expected_tags_2[0..],
        .timers = &[_]dt.Timer{},
        .kickoff = th.curTimestamp() + try th.getMinutesFromSteps(u25, 34),
        .estimation = 5432,
        .creation = th.curTimestamp(),
    };
    try ex_file.things.insert(0, thing_to_add_2);

    var tags1 = std.ArrayList([]const u8).init(globals.allocator);
    defer tags1.deinit();
    try tags1.append("next");

    var tags2 = std.ArrayList([]const u8).init(globals.allocator);
    defer tags2.deinit();
    try tags2.append("newtag");

    try it_helper.setupTest(try it_helper.getStarterFile());

    var args: ArgumentParser = .{
        .payload = "test1",
        .tags = tags1,
        .kickoff = 34,
        .estimation = 5432,
    };
    try cmd(&args);

    args = .{
        .payload = "test2",
        .tags = tags2,
        .kickoff = 34,
        .estimation = 5432,
    };
    try cmd(&args);

    try dfw.writeFullData(ex_file, it_helper.integration_test_file_path);
    try it_helper.compareFiles(ex_file);
}

test "add thing with name + tag creation" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    var expected_tags: [1]u16 = .{4};

    const thing_to_add: dt.Thing = .{
        .id = 4,
        .name = "third thing",
        .tags = expected_tags[0..],
        .timers = &[_]dt.Timer{},
        .kickoff = 0,
        .estimation = 0,
        .creation = cur_time,
    };

    try ex_file.things.insert(0, thing_to_add);
    try ex_file.tags.insert(0, .{ .id = 4, .status = dt.StatusTag.someday, .name = "newTag" });

    var tags = std.ArrayList([]const u8).init(globals.allocator);
    defer tags.deinit();
    try tags.append("newTag");
    var args: ArgumentParser = .{
        .payload = "third thing",
        .tags = tags,
    };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
    });
}

test "add thing with no name" {
    var args: ArgumentParser = .{};

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getStarterFile(),
        .ex_stderr = "Could not parse the name of the thing.\n",
    });
}

test "add thing with name too long" {
    const thing_name = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    var args: ArgumentParser = .{ .payload = thing_name };
    var buf_ex_stderr: [300]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "The name \"{s}\" is too long.\n", .{thing_name});

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getStarterFile(),
        .ex_stderr = ex_stderr,
    });
}

test "add thing with too many tags" {
    var tags = std.ArrayList([]const u8).init(globals.allocator);
    defer tags.deinit();

    var buf_tag_name: [10]u8 = undefined;

    for (0..64) |i| {
        const tag_name = try std.fmt.bufPrint(&buf_tag_name, "tag{d}", .{i});
        try tags.append(try globals.allocator.dupe(u8, tag_name));
    }
    defer {
        for (0..64) |i| {
            globals.allocator.free(tags.items[i]);
        }
    }

    var args: ArgumentParser = .{ .payload = "testthing", .tags = tags };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getStarterFile(),
        .ex_stderr = "There are too many tags associated to the thing. The maximum is 63.\n",
    });
}

test "add thing with maximum number of ids reached on data file" {
    var ac_file = try it_helper.getStarterFile();
    const thing_to_add: dt.Thing = .{
        .id = 524287,
        .name = "testthing",
        .tags = &[_]u16{},
        .timers = &[_]dt.Timer{},
        .creation = th.curTimestamp(),
    };
    try ac_file.things.insert(0, thing_to_add);

    var args: ArgumentParser = .{ .payload = "thingoverflow" };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ac_file,
        .ex_stderr = "The maximum number of things in the data file is reached.\nDeleting existing things will not help. You will need to start a new data file.\n",
    });
}

test "add thing with kickoff overflowing right away" {
    const ac_file = try it_helper.getStarterFile();
    const ex_file = try it_helper.getStarterFile();

    var args: ArgumentParser = .{ .payload = "kickoffoverflow", .kickoff = 30000000 };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stderr = "The kickoff value is too big. Please try with a smaller one.\n",
    });
}

test "add thing with kickoff overflowing with cur timestamp" {
    const ac_file = try it_helper.getStarterFile();
    const ex_file = try it_helper.getStarterFile();

    const cur_time = th.curTimestamp();
    const max_value = std.math.maxInt(u25);
    const min_to_test = (max_value - cur_time);
    const steps_to_test = try th.getStepsFromMinutes(u25, min_to_test) + 10;

    var args: ArgumentParser = .{ .payload = "kickoffoverflow", .kickoff = steps_to_test };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stderr = "The kickoff value is too big. Please try with a smaller one.\n",
    });
}
