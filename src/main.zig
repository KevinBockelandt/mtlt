const builtin = @import("builtin");
const std = @import("std");

const argument_parser = @import("argument_parser.zig");
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
const report_info = @import("report_info.zig");
const report_next = @import("report_next.zig");
const report_plan = @import("report_plan.zig");
const report_tags = @import("report_tags.zig");

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
    info,
    next,
    plan,
    start,
    stop,
    tags,
    toggle,
    unknown,
    update,
};

pub fn main() !void {
    try globals.printer.init();
    try globals.initDataFileNames();
    try globals.openDataFiles();

    parseArgs() catch |err| {
        std.debug.print("An unexpected error happened!\n", .{});
        std.debug.print("{}\n", .{err});
    };

    globals.closeDataFiles();
    globals.deinitDataFileNames();
    globals.printer.deinit();
    globals.deinitMemAllocator();
}

fn parseArgs() !void {
    const args = try std.process.argsAlloc(globals.allocator);
    defer std.process.argsFree(globals.allocator, args);

    var arg_parser = argument_parser.ArgumentParser{};

    // if no command is provided, trigger the associated behavior
    if (args.len < 2) {
        try command_mtlt.cmd(&arg_parser);
        return;
    }

    // get the subcommand used (always args[1])
    const cmd = std.meta.stringToEnum(Commands, args[1]) orelse Commands.unknown;

    // if there is something beyond the subcommand, parse it
    arg_parser.init();
    defer arg_parser.deinit();

    if (args.len > 2) {
        arg_parser.parse(args[2..]) catch |err| {
            switch (err) {
                argument_parser.ArgumentParsingError.UnexpectedArgument => return,
                argument_parser.ArgumentParsingError.CannotParseDivisions => return,
                argument_parser.ArgumentParsingError.DivisionsAlreadyParsed => return,
                argument_parser.ArgumentParsingError.CannotParseDuration => return,
                argument_parser.ArgumentParsingError.DurationAlreadyParsed => return,
                argument_parser.ArgumentParsingError.CannotParseDurationLess => return,
                argument_parser.ArgumentParsingError.DurationLessAlreadyParsed => return,
                argument_parser.ArgumentParsingError.CannotParseDurationMore => return,
                argument_parser.ArgumentParsingError.DurationMoreAlreadyParsed => return,
                argument_parser.ArgumentParsingError.CannotParseEndLess => return,
                argument_parser.ArgumentParsingError.EndLessAlreadyParsed => return,
                argument_parser.ArgumentParsingError.CannotParseEstimation => return,
                argument_parser.ArgumentParsingError.EstimationAlreadyParsed => return,
                argument_parser.ArgumentParsingError.CannotParseExcludeTags => return,
                argument_parser.ArgumentParsingError.ExcludeTagsAlreadyParsed => return,
                argument_parser.ArgumentParsingError.CannotParseKickoff => return,
                argument_parser.ArgumentParsingError.KickoffAlreadyParsed => return,
                argument_parser.ArgumentParsingError.CannotParseLimit => return,
                argument_parser.ArgumentParsingError.LimitAlreadyParsed => return,
                argument_parser.ArgumentParsingError.CannotParseName => return,
                argument_parser.ArgumentParsingError.NameAlreadyParsed => return,
                argument_parser.ArgumentParsingError.CannotParsePriority => return,
                argument_parser.ArgumentParsingError.PriorityAlreadyParsed => return,
                argument_parser.ArgumentParsingError.CannotParseStartLess => return,
                argument_parser.ArgumentParsingError.StartLessAlreadyParsed => return,
                argument_parser.ArgumentParsingError.CannotParseStartMore => return,
                argument_parser.ArgumentParsingError.StartMoreAlreadyParsed => return,
                argument_parser.ArgumentParsingError.CannotParseTags => return,
                argument_parser.ArgumentParsingError.TagsAlreadyParsed => return,
                argument_parser.ArgumentParsingError.UnknownFlag => return,
                argument_parser.ArgumentParsingError.SeveralDurationArgs => return,
                argument_parser.ArgumentParsingError.SeveralStartArgs => return,
                else => {
                    return err;
                },
            }
        };
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
        .info => try report_info.infoReport(&arg_parser),
        .next => try report_next.nextReport(&arg_parser),
        .plan => try report_plan.planReport(&arg_parser),
        .start => try command_start.cmd(&arg_parser),
        .stop => try command_stop.cmd(&arg_parser),
        .tags => try report_tags.tagsReport(&arg_parser),
        .toggle => try command_toggle.cmd(&arg_parser),
        .update => try command_update.cmd(&arg_parser),
        else => try globals.printer.errUnknownCommand(args[1]),
    }
}
