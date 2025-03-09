const builtin = @import("builtin");
const std = @import("std");

const command_add = @import("command_add.zig");
const command_add_tag = @import("command_add_tag.zig");
const command_add_timer = @import("command_add_timer.zig");
const command_delete = @import("command_delete.zig");
const command_delete_tag = @import("command_delete_tag.zig");
const command_delete_timer = @import("command_delete_timer.zig");
const command_help = @import("command_help.zig");
const command_mtlt = @import("command_mtlt.zig");
const command_start = @import("command_start.zig");
const command_stop = @import("command_stop.zig");
const command_toggle = @import("command_toggle.zig");
const command_toggle_tag = @import("command_toggle_tag.zig");
const command_update = @import("command_update.zig");
const command_update_tag = @import("command_update_tag.zig");
const command_update_timer = @import("command_update_timer.zig");
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
    help,
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

    // if no command is provided, trigger the associated behavior
    if (args.len < 2) {
        try command_mtlt.cmd();
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
        .@"add-tag" => try command_add_tag.cmd(&arg_parser),
        .@"add-timer" => try command_add_timer.cmd(&arg_parser),
        .@"delete-tag" => try command_delete_tag.cmd(&arg_parser),
        .@"delete-timer" => try command_delete_timer.cmd(&arg_parser),
        .@"toggle-tag" => try command_toggle_tag.cmd(&arg_parser),
        .@"update-tag" => try command_update_tag.cmd(&arg_parser),
        .@"update-timer" => try command_update_timer.cmd(&arg_parser),
        .add => try command_add.cmd(&arg_parser),
        .closed => try report_closed.closedReport(&arg_parser),
        .delete => try command_delete.cmd(&arg_parser),
        .help => try command_help.cmd(&arg_parser),
        .infos => try report_infos.infosReport(&arg_parser),
        .ongoing => try report_ongoing.ongoingReport(&arg_parser),
        .start => try command_start.cmd(&arg_parser),
        .stop => try command_stop.cmd(&arg_parser),
        .tags => try report_tags.tagsReport(&arg_parser),
        .toggle => try command_toggle.cmd(&arg_parser),
        .update => try command_update.cmd(&arg_parser),
        else => try std.io.getStdOut().writer().print("Unknown command: {s}\n", .{args[1]}),
    }
}
