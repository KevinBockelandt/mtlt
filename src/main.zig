const builtin = @import("builtin");
const std = @import("std");

const commands = @import("commands.zig");
const data_types = @import("data_types.zig");
const globals = @import("globals.zig");
const report_closed = @import("report_closed.zig");
const report_infos = @import("report_infos.zig");
const report_ongoing = @import("report_ongoing.zig");
const report_tags = @import("report_tags.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

const Commands = enum {
    @"add-tag",
    @"add-timer",
    @"delete-tag",
    @"delete-timer",
    @"toggle-tag",
    @"update-tag",
    @"update-timer",
    add,
    closed,
    delete,
    infos,
    ongoing,
    start,
    stop,
    tags,
    toggle,
    unknown,
    update,
};

pub fn main() !void {
    try globals.initDataFileNames(null);
    try globals.openDataFiles();

    try parseArgs();

    globals.closeDataFiles();
    globals.deinitDataFileNames();
    globals.deinitMemAllocator();
}

fn parseArgs() !void {
    const args = try std.process.argsAlloc(globals.allocator);
    defer std.process.argsFree(globals.allocator, args);

    if (args.len < 2) {
        _ = try std.io.getStdOut().writer().write("Needs a command. TODO display help\n");
        return;
    }

    // get the subcommand used (always args[1])
    const cmd = std.meta.stringToEnum(Commands, args[1]) orelse Commands.unknown;

    // if there is something beyond the subcommand, parse it
    var arg_parser = ArgumentParser{};
    arg_parser.init();
    defer arg_parser.deinit();

    if (args.len > 2) {
        try arg_parser.parse(args[2..]);
    }

    // handle the command appropriately
    switch (cmd) {
        .@"add-tag" => try commands.addTag(arg_parser),
        .@"add-timer" => try commands.addTimer(arg_parser),
        .@"delete-tag" => try commands.deleteTag(arg_parser),
        .@"delete-timer" => try commands.deleteTimer(arg_parser),
        .@"toggle-tag" => try commands.toggleTagStatus(arg_parser),
        .@"update-tag" => try commands.updateTagName(arg_parser),
        .@"update-timer" => try commands.updateTimer(arg_parser),
        .add => try commands.addThing(arg_parser),
        .closed => try report_closed.closedReport(arg_parser),
        .delete => try commands.deleteThing(arg_parser),
        .infos => try report_infos.infosReport(arg_parser),
        .ongoing => try report_ongoing.ongoingReport(arg_parser),
        .start => try commands.start(arg_parser),
        .stop => try commands.stop(arg_parser),
        .tags => try report_tags.tagsReport(arg_parser),
        .toggle => try commands.toggleThingStatus(arg_parser),
        .update => try commands.updateThing(arg_parser),
        else => try std.io.getStdOut().writer().print("Unknown command: {s}\n", .{args[1]}),
    }
}
