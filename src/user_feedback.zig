const std = @import("std");

const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const command_start = @import("command_start.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const time_helper = @import("time_helper.zig");

const wo = std.io.getStdOut().writer();
const we = std.io.getStdErr().writer();

pub fn createdTag(tag_name: []const u8) !void {
    try wo.print("Created the tag {s}{s}{s}\n", .{ ansi.colemp, tag_name, ansi.colres });
}

pub fn toggledTag(new_status: []const u8, tag_name: []const u8) !void {
    try wo.print("Tag {s}{s}{s} is now {s}{s}{s}\n", .{ ansi.colemp, tag_name, ansi.colres, ansi.colemp, new_status, ansi.colres });
}

pub fn updatedTag(old_name: []const u8, new_name: []const u8) !void {
    try wo.print("Tag {s}{s}{s} is now nammed {s}{s}{s}\n", .{ ansi.colemp, old_name, ansi.colres, ansi.colemp, new_name, ansi.colres });
}

pub fn deletedTag(tag_name: []const u8) !void {
    try wo.print("The tag {s}{s}{s} was deleted\n", .{ ansi.colemp, tag_name, ansi.colres });
}

pub fn createdThing(thing_name: []const u8, str_id: []const u8) !void {
    try wo.print("Created {s}\"{s}\"{s} with ID {s}{s}{s}\n", .{ ansi.colemp, thing_name, ansi.colres, ansi.colid, str_id, ansi.colres });
}

pub fn updatedThing(thing_name: []const u8, str_id: []const u8) !void {
    try wo.print("Updated thing {s}{s}{s} - {s}{s}{s}\n", .{ ansi.colid, str_id, ansi.colres, ansi.colemp, thing_name, ansi.colres });
}

pub fn startedTimer(str_id: []const u8, thing_name: []const u8) !void {
    try wo.print("Started a timer for: {s}{s}{s} - {s}{s}{s}\n", .{ ansi.colid, str_id, ansi.colres, ansi.colemp, thing_name, ansi.colres });
}

pub fn stoppedTimer(id_timer: u11, str_id_thing: []const u8, thing_name: []const u8, duration: u12) !void {
    try wo.print("Stopped timer {s}{d}{s} for {s}{s}{s} - {s}{s}{s}. It lasted {s}{d}{s}\n", .{ ansi.colid, id_timer, ansi.colres, ansi.colid, str_id_thing, ansi.colres, ansi.colemp, thing_name, ansi.colres, ansi.colemp, duration, ansi.colres });
}

pub fn addedTimer(str_id_thing: []const u8, id_timer: u11) !void {
    try wo.print("Added timer {s}{s}-{d}{s}\n", .{ ansi.colid, str_id_thing, id_timer, ansi.colres });
}

pub fn updatedTimer(str_id_thing: []const u8, id_timer: u11) !void {
    try wo.print("Updated timer {s}{s}-{d}{s}\n", .{ ansi.colid, str_id_thing, id_timer, ansi.colres });
}

pub fn deletedTimer(str_id_thing: []const u8, id_timer: u11) !void {
    try wo.print("Deleted timer {s}{s}-{d}{s}\n", .{ ansi.colid, str_id_thing, id_timer, ansi.colres });
}

pub fn timerAlreadyRunning(str_id: []const u8, thing_name: []const u8) !void {
    try wo.print("Timer already running for: {s}{s}{s} - {s}{s}{s}\n", .{ ansi.colid, str_id, ansi.colres, ansi.colemp, thing_name, ansi.colres });
}

pub fn noTimerRunning() !void {
    _ = try wo.write("No timer currently running\n");
}

pub fn deletedThing(str_id: []const u8, thing_name: []const u8) !void {
    try wo.print("Deleted thing {s}{s}{s} - {s}{s}{s}\n", .{ ansi.colid, str_id, ansi.colres, ansi.colemp, thing_name, ansi.colres });
}

pub fn cantStartIfClosed(str_id: []const u8) !void {
    _ = try wo.write("Cannot start a timer on a closed thing\n");
    try wo.print("You can reopen the thing by using the following command: {s}mtlt toggle {s}{s}\n", .{ ansi.colemp, str_id, ansi.colres });
}

pub fn noLastTimerToWorkOn() !void {
    _ = try wo.write("There is no immediate last timer to work on. Please specify an ID.\n");
    try wo.print("It should have the format {s}<id thing>-<id timer>{s}. For example: {s}b-2{s}\n", .{ ansi.colid, ansi.colres, ansi.colid, ansi.colres });
}

pub fn nothingToUpdateTimer() !void {
    _ = try wo.write("Nothing to update on the timer\n");
    _ = try wo.write("See 'mtlt help update-timer' for a list of options\n");
}

pub fn noTagsToList() !void {
    _ = try wo.write("There are no tags to list.\n");
}

pub fn missingEnvVar(env_var: []const u8) !void {
    try wo.print("Please setup the {s} environment variable.\n", .{env_var});
}

// CURRENT THING REPORT

pub fn reportThingIdName(str_id: []const u8, str_name: []const u8) !void {
    try wo.print(" {s}thing{s} : {s}{s}{s} - {s}\n", .{ ansi.colemp, ansi.colres, ansi.colid, str_id, ansi.colres, str_name });
}

pub fn reportStatus(status: []const u8) !void {
    try wo.print("{s}status{s} : {s}\n", .{ ansi.colemp, ansi.colres, status });
}

pub fn reportKickoff(kickoff: u25, col_kickoff: []const u8) !void {
    try wo.print("{s}kickoff{s} : {s}{d}{s}\n", .{ ansi.colemp, ansi.colres, col_kickoff, kickoff, ansi.colres });
}

pub fn reportTimeLeftInfos(step_left: i25, col_time_left: []const u8) !void {
    try wo.print("  {s}left{s} : {s}{d}{s}\n", .{ ansi.colemp, ansi.colres, col_time_left, step_left, ansi.colres });
}

pub fn reportNoTimer() !void {
    try wo.print(" {s}timer{s} : no current timer\n", .{ ansi.colemp, ansi.colres });
}

pub fn reportNoCurrentThing() !void {
    try wo.print("There is no current thing.\n", .{});
    try wo.print("See \"mtlt help\" for help.\n", .{});
}

pub fn reportTimerStarted(str_duration: []const u8) !void {
    try wo.print(" {s}timer{s} : started {s}{s}{s} ago\n", .{ ansi.colemp, ansi.colres, ansi.coldurntr, str_duration, ansi.colres });
}

pub fn reportStarted(offset: u25) !void {
    try wo.print(" {s}started{s} : {s}{d}{s} ago\n", .{ ansi.colemp, ansi.colres, ansi.coldurntr, offset, ansi.colres });
}

pub fn reportDuration(duration: u12) !void {
    try wo.print("{s}duration{s} : {s}{d}{s}\n", .{ ansi.colemp, ansi.colres, ansi.coldurntr, duration, ansi.colres });
}

// ERRORS COMMAND PARSER SPECIFIC

pub fn errMultipleFlagsLong(long: []const u8) !void {
    try we.print("There can be only one \"{s}\" flag.\n", .{long});
}

pub fn errMultipleFlagsShortLong(short: []const u8, long: []const u8) !void {
    try we.print("There can be only one \"{s}\" or \"{s}\" flag.\n", .{ short, long });
}

pub fn errUnexpectedArgument(arg: []const u8) !void {
    try we.print("Unexpected argument: {s}\n", .{arg});
}

pub fn errUnexpectedFlag(flag: []const u8) !void {
    try we.print("Unexpected flag: {s}\n", .{flag});
}

pub fn errDivisionInvalidCharacter() !void {
    _ = try we.write("Division number contains invalid characters\n");
}

pub fn errDivisionTooBig() !void {
    try we.print("Division number too big. Maximum is: {d}\n", .{std.math.maxInt(u8)});
}

pub fn errDurationTooBig(t: type) !void {
    try we.print("Duration number too big. Maximum is: {d}\n", .{std.math.maxInt(t)});
}

pub fn errDurationInvalidCharacter() !void {
    _ = try we.write("Duration number contains invalid characters\n");
}

pub fn errOptionAlreadyParsed(option: []const u8, arg: []const u8) !void {
    try we.print("{s} already parsed. Please remove: \"{s}\"\n", .{ option, arg });
}

pub fn errContradictionAllTagsFlags() !void {
    _ = try wo.write("Warning: you specified the --no-tags flag along the --tags and --excluded-tags flags.\n");
    _ = try wo.write("Since these are contradictory only the --no-tags flag will be taken into account\n");
}

pub fn errContradictionNoTagsTags() !void {
    _ = try wo.write("Warning: you specified the --no-tags flag along the --tags flag.\n");
    _ = try wo.write("Since these are contradictory only the --no-tags flag will be taken into account\n");
}

pub fn errContradictionNoTagsExcludedTags() !void {
    _ = try wo.write("Warning: you specified the --no-tags flag along the --excluded-tags flag.\n");
    _ = try wo.write("Since these are contradictory only the --no-tags flag will be taken into account\n");
}

pub fn errContradictionDurationDurationOffset() !void {
    _ = try we.write("You cannot give a specific duration and a duration offset at the same time\n");
}

pub fn errContradictionAddRemoveDuration() !void {
    _ = try we.write("You cannot add and remove duration at the same time\n");
}

pub fn errContradictionAddRemoveStartTime() !void {
    _ = try we.write("You cannot push the start time backward and forward at the same time\n");
}

pub fn errTimerDurationTooGreat(duration: u25) !void {
    try we.print("The current timer has a duration of {s}{d}{s}\n", .{ ansi.colemp, duration, ansi.colres });
    try we.print("The maximum duration is {s}{d}{s}\n", .{ ansi.colemp, std.math.maxInt(u9), ansi.colres });
}

// ERRORS RELATED TO THINGS

pub fn errThingNotFoundStr(thing_id: []const u8) !void {
    try we.print("Thing with id {s}{s}{s} not found\n", .{ ansi.colemp, thing_id, ansi.colres });
}

pub fn errThingNotFoundNum(thing_id: u19) !void {
    var buf_str_id: [4]u8 = undefined;
    const str_id = base62_helper.b10ToB62(&buf_str_id, thing_id);
    try errThingNotFoundStr(str_id);
}

pub fn errNameThingMissing() !void {
    _ = try we.write("Could not parse the name of the thing.\n");
}

pub fn errIdThingMissing() !void {
    _ = try we.write("Missing the ID of the thing to operate on.\n");
}

// ERRORS RELATED TO TAGS

pub fn errTagNotFoundName(tag_name: []const u8) !void {
    try we.print("Tag with the name {s}{s}{s} not found\n", .{ ansi.colemp, tag_name, ansi.colres });
}

pub fn errTagNotFoundId(tag_id: u16) !void {
    try we.print("Tag with ID {s}{d}{s} not found\n", .{ ansi.colemp, tag_id, ansi.colres });
}

pub fn errMissingTagNameToAdd() !void {
    _ = try we.write("Missing the name of the tag to create\n");
}

pub fn errMissingTagName() !void {
    _ = try we.write("Missing the name of the tag to operate on.\n");
}

pub fn errNameTagInvalidChara() !void {
    _ = try we.write("The tag name can only contain ascii letters, numbers or the '-' or '_' character\n");
}

pub fn errNameTagTooLong(tag_name: []const u8) !void {
    try we.print("The name {s}\"{s}\"{s} is too long\n", .{ ansi.colemp, tag_name, ansi.colres });
}

pub fn errNameTagAlreadyExisting(tag_name: []const u8) !void {
    try we.print("A tag with the name {s}{s}{s} already exists\n", .{ ansi.colemp, tag_name, ansi.colres });
}

pub fn errUpdateTagMissingOldName() !void {
    _ = try we.write("The current name of the tag to udpate is missing\n");
    _ = try we.write("The format of the command is \"mtlt udpate-tag <old_name> -n <new_name>\"\n");
}

pub fn errUpdateTagMissingNewName() !void {
    _ = try we.write("The new name for the tag needs to be specified with the \"-n\" or \"--name\" flag\n");
    _ = try we.write("The format of the command is \"mtlt udpate-tag <old_name> -n <new_name>\"\n");
}

// ERRORS RELATED TO DURATION

pub fn errInvalidDurationString(dur_str: []const u8) !void {
    try we.print("The duration string \"{s}\" is invalid\n", .{dur_str});
}

pub fn errDurationTooGreat(dur_str: []const u8) !void {
    try we.print("The duration \"{s}\" is too great. TODO indicate maximum\n", .{dur_str});
}

pub fn errDurationMissing() !void {
    _ = try we.write("You need to specify a duration (with the -d flag)\n");
}

// ALL OTHER ERRORS

pub fn errUnknownCommand(cmd: []const u8) !void {
    try we.print("Unknown command: {s}\n", .{cmd});
}

pub fn errUnknownHelpTopic() !void {
    _ = try we.write("Unknown help topic\n");
}

pub fn errUnexpectedUpdatingThing(err: anyerror) !void {
    try we.print("Unexpected error while updating a thing.\n", .{});
    try we.print("{}\n", .{err});
}

pub fn errUnexpectedToggleThing(err: anyerror) !void {
    try we.print("Unexpected error while toggling a thing.\n", .{});
    try we.print("{}\n", .{err});
}

pub fn errUnexpectedToggleTag(err: anyerror) !void {
    try we.print("Unexpected error while toggling a tag.\n", .{});
    try we.print("{}\n", .{err});
}

pub fn errUnexpectedTimerAddition(err: anyerror) !void {
    _ = try we.write("Unexpected error during the addition of a timer.\n");
    try we.print("{}\n", .{err});
}

pub fn errUnexpectedTimerDeletion(err: anyerror) !void {
    _ = try we.write("Unexpected error during the deletion of a timer.\n");
    try we.print("{}\n", .{err});
}

pub fn errUnexpectedUpdateTimer(err: anyerror) !void {
    _ = try we.write("Unexpected error during the update of a timer.\n");
    try we.print("{}\n", .{err});
}

pub fn errUnexpectedTimerIdParsing(err: anyerror) !void {
    _ = try we.write("Unexpected error during parsing of the timer ID.\n");
    try we.print("{}\n", .{err});
}

pub fn errUnexpectedAddTagToList(err: anyerror) !void {
    _ = try we.write("Unexpected error while trying to add a tag to a list.\n");
    try we.print("{}\n", .{err});
}

pub fn errUnexpectedAllocateMemory(err: anyerror) !void {
    _ = try we.write("Unexpected error while allocating memory.\n");
    try we.print("{}\n", .{err});
}

pub fn errUnexpectedGetEnvVar(env_var: []const u8, err: anyerror) !void {
    try we.print("Unexpected error while trying to get the {s} environment variable\n", .{env_var});
    try we.print("{}\n", .{err});
}

pub fn errUnexpectedGetTagName(tag_id: u16, err: anyerror) !void {
    try we.print("Unexpected error while trying to get the name of the tag with ID '{d}'\n", .{tag_id});
    try we.print("{}\n", .{err});
}

pub fn errStartOffsetMissing() !void {
    _ = try we.write("You need to specify the time offset between now and the start of the timer (with the -sl flag)\n");
}

pub fn errStartOffsetTooBig(cur_time: u25) !void {
    try we.print("The time offset between now and the start of the timer is too big. Maximum is: {d}\n", .{cur_time});
}

pub fn errInvalidEnvVar(env_var: []const u8) !void {
    try we.print("The {s} environment variable is not valid WTF-8.\n", .{env_var});
}

pub fn errDivisionNumberTooBig() !void {
    try we.print("Division number too big. Maximum is: {d}.\n", .{std.math.maxInt(u8)});
}
