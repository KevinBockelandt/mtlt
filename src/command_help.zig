const std = @import("std");

const ansi = @import("ansi_codes.zig");
const dt = @import("data_types.zig");
const dfr = @import("data_file_reader.zig");
const globals = @import("globals.zig");
const string_helper = @import("string_helper.zig");

const help_add = @import("command_add.zig").help;
const help_add_tag = @import("command_add_tag.zig").help;
const help_add_timer = @import("command_add_timer.zig").help;
const help_closed = @import("report_closed.zig").help;
const help_delete = @import("command_delete.zig").help;
const help_delete_tag = @import("command_delete_tag.zig").help;
const help_delete_timer = @import("command_delete_timer.zig").help;
const help_infos = @import("report_infos.zig").help;
const help_start = @import("command_start.zig").help;
const help_stop = @import("command_stop.zig").help;
const help_tags = @import("report_tags.zig").help;
const help_toggle = @import("command_toggle.zig").help;
const help_toggle_tag = @import("command_toggle_tag.zig").help;
const help_update = @import("command_update.zig").help;
const help_update_tag = @import("command_update_tag.zig").help;
const help_update_timer = @import("command_update_timer.zig").help;

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

pub const str_add: [19]u8 = ansi.colid ++ "add".* ++ ansi.colres;
pub const str_add_tag: [23]u8 = ansi.colid ++ "add-tag".* ++ ansi.colres;
pub const str_add_timer: [25]u8 = ansi.colid ++ "add-timer".* ++ ansi.colres;
pub const str_closed: [22]u8 = ansi.colid ++ "closed".* ++ ansi.colres;
pub const str_delete: [22]u8 = ansi.colid ++ "delete".* ++ ansi.colres;
pub const str_delete_tag: [26]u8 = ansi.colid ++ "delete-tag".* ++ ansi.colres;
pub const str_delete_timer: [28]u8 = ansi.colid ++ "delete-timer".* ++ ansi.colres;
pub const str_infos: [21]u8 = ansi.colid ++ "infos".* ++ ansi.colres;
pub const str_help: [20]u8 = ansi.colid ++ "help".* ++ ansi.colres;
pub const str_start: [21]u8 = ansi.colid ++ "start".* ++ ansi.colres;
pub const str_stop: [20]u8 = ansi.colid ++ "stop".* ++ ansi.colres;
pub const str_tags: [20]u8 = ansi.colid ++ "tags".* ++ ansi.colres;
pub const str_toggle: [22]u8 = ansi.colid ++ "toggle".* ++ ansi.colres;
pub const str_toggle_tag: [26]u8 = ansi.colid ++ "toggle-tag".* ++ ansi.colres;
pub const str_update: [22]u8 = ansi.colid ++ "update".* ++ ansi.colres;
pub const str_update_tag: [26]u8 = ansi.colid ++ "update-tag".* ++ ansi.colres;
pub const str_update_timer: [28]u8 = ansi.colid ++ "update-timer".* ++ ansi.colres;

// Display the entry page for help
fn main_help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt [COMMAND] [ARGS]{s}
        \\
        \\Commands:
        \\  {s}             Add a new thing
        \\  {s}         Add a new tag
        \\  {s}       Add a new timer
        \\  {s}          Show the list of closed things
        \\  {s}          Delete a thing
        \\  {s}      Delete a tag
        \\  {s}    Delete a timer
        \\  {s}           Show infos about a thing
        \\  {s}            Show help pages
        \\  {s}           Start a timer on a thing
        \\  {s}            Stop the current timer
        \\  {s}            Show the list of tags
        \\  {s}          Toggle the status of a thing
        \\  {s}      Toggle the status of a tag
        \\  {s}          Update data of a thing
        \\  {s}      Update the name of a tag
        \\  {s}    Update data of a timer
        \\
        \\Use `{s}mtlt help COMMAND{s}` for more information on a specific command and it's
        \\corresponding options.
        \\
        \\See `{s}mtlt help intro{s}` for an explanation of the application and it's main
        \\concepts.
        \\
        \\Running `{s}mtlt{s}` without any command will display infos about the current thing
        \\and timer.
        \\
    , .{
        ansi.colemp,      ansi.colres,
        str_add,          str_add_tag,
        str_add_timer,    str_closed,
        str_delete,       str_delete_tag,
        str_delete_timer, str_infos,
        str_help,         str_start,
        str_stop,         str_tags,
        str_toggle,       str_toggle_tag,
        str_update,       str_update_tag,
        str_update_timer, ansi.colemp,
        ansi.colres,      ansi.colemp,
        ansi.colres,      ansi.colemp,
        ansi.colres,
    });
}

// Display global explanation on the app
fn help_intro() !void {
    try std.io.getStdOut().writer().print(
        \\TODO explanation on the application
        \\
    , .{});
}

/// Display help for the application
pub fn cmd(args: *ArgumentParser) !void {
    // if there is no argument with the command display entry level help
    if (args.*.payload == null) {
        try main_help();
    } else if (std.mem.eql(u8, args.*.payload.?, "add")) {
        try help_add();
    } else if (std.mem.eql(u8, args.*.payload.?, "add-tag")) {
        try help_add_tag();
    } else if (std.mem.eql(u8, args.*.payload.?, "add-timer")) {
        try help_add_timer();
    } else if (std.mem.eql(u8, args.*.payload.?, "closed")) {
        try help_closed();
    } else if (std.mem.eql(u8, args.*.payload.?, "delete")) {
        try help_delete();
    } else if (std.mem.eql(u8, args.*.payload.?, "delete-tag")) {
        try help_delete_tag();
    } else if (std.mem.eql(u8, args.*.payload.?, "delete-timer")) {
        try help_delete_timer();
    } else if (std.mem.eql(u8, args.*.payload.?, "help")) {
        try main_help();
    } else if (std.mem.eql(u8, args.*.payload.?, "infos")) {
        try help_infos();
    } else if (std.mem.eql(u8, args.*.payload.?, "intro")) {
        try help_intro();
    } else if (std.mem.eql(u8, args.*.payload.?, "start")) {
        try help_start();
    } else if (std.mem.eql(u8, args.*.payload.?, "stop")) {
        try help_stop();
    } else if (std.mem.eql(u8, args.*.payload.?, "tags")) {
        try help_tags();
    } else if (std.mem.eql(u8, args.*.payload.?, "toggle")) {
        try help_toggle();
    } else if (std.mem.eql(u8, args.*.payload.?, "toggle-tag")) {
        try help_toggle_tag();
    } else if (std.mem.eql(u8, args.*.payload.?, "update")) {
        try help_update();
    } else if (std.mem.eql(u8, args.*.payload.?, "update-tag")) {
        try help_update_tag();
    } else if (std.mem.eql(u8, args.*.payload.?, "update-timer")) {
        try help_update_timer();
    } else {
        try globals.printer.errUnknownHelpTopic();
    }
}
