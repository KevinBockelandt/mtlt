const builtin = @import("builtin");
const std = @import("std");

const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");

pub const Printer = struct {
    out_buff: []u8 = undefined,
    err_buff: []u8 = undefined,
    cur_pos_out_buff: usize = 0,
    cur_pos_err_buff: usize = 0,

    pub fn init(self: *Printer) !void {
        if (builtin.is_test) {
            self.out_buff = try globals.allocator.alloc(u8, std.math.maxInt(u16));
            self.err_buff = try globals.allocator.alloc(u8, std.math.maxInt(u16));
            self.cur_pos_out_buff = 0;
            self.cur_pos_err_buff = 0;
        }
    }

    pub fn deinit(self: *Printer) void {
        if (builtin.is_test) {
            globals.allocator.free(self.out_buff);
            globals.allocator.free(self.err_buff);
            self.cur_pos_out_buff = 0;
            self.cur_pos_err_buff = 0;
        }
    }

    pub fn writeOut(self: *Printer, comptime format: []const u8, args: anytype) !void {
        if (builtin.is_test) {
            const res = try std.fmt.bufPrint(self.out_buff[self.cur_pos_out_buff..], format, args);
            self.cur_pos_out_buff += res.len;
        } else {
            try std.io.getStdOut().writer().print(format, args);
        }
    }

    pub fn writeErr(self: *Printer, comptime format: []const u8, args: anytype) !void {
        if (builtin.is_test) {
            const res = try std.fmt.bufPrint(self.err_buff[self.cur_pos_err_buff..], format, args);
            self.cur_pos_err_buff += res.len;
        } else {
            try std.io.getStdErr().writer().print(format, args);
        }
    }

    // FEEDBACK MESSAGES

    pub fn createdTag(self: *Printer, tag_name: []const u8) !void {
        try self.writeOut("Created the tag {s}{s}{s}\n", .{ ansi.colemp, tag_name, ansi.colres });
    }

    pub fn toggledTagClosed(self: *Printer, tag_name: []const u8) !void {
        try self.writeOut("Tag {s}{s}{s} is now {s}closed{s}.\n", .{ ansi.colemp, tag_name, ansi.colres, ansi.colemp, ansi.colres });
    }

    pub fn toggledTagOpenned(self: *Printer, new_priority: []const u8, tag_name: []const u8) !void {
        try self.writeOut("Tag {s}{s}{s} is now {s}open{s} with priority {s}{s}{s}.\n", .{ ansi.colemp, tag_name, ansi.colres, ansi.colemp, ansi.colres, ansi.colemp, new_priority, ansi.colres });
    }

    pub fn updatedTagName(self: *Printer, old_name: []const u8, new_name: []const u8) !void {
        try self.writeOut("Tag {s}{s}{s} is now nammed {s}{s}{s}\n", .{ ansi.colemp, old_name, ansi.colres, ansi.colemp, new_name, ansi.colres });
    }

    pub fn updatedTagPriority(self: *Printer, tag_name: []const u8, priority: dt.StatusTag) !void {
        try self.writeOut("Tag {s}{s}{s} has now the priority: {s}{s}{s}\n", .{ ansi.colemp, tag_name, ansi.colres, ansi.colemp, @tagName(priority), ansi.colres });
    }

    pub fn updatedTagNothing(self: *Printer, old_name: []const u8) !void {
        try self.writeOut("Nothing was updated on the tag {s}{s}{s}.\n", .{ ansi.colemp, old_name, ansi.colres });
    }

    pub fn deletedTag(self: *Printer, tag_name: []const u8) !void {
        try self.writeOut("The tag {s}{s}{s} was deleted\n", .{ ansi.colemp, tag_name, ansi.colres });
    }

    pub fn createdThing(self: *Printer, thing_name: []const u8, str_id: []const u8) !void {
        try self.writeOut("Created {s}\"{s}\"{s} with ID {s}{s}{s}\n", .{ ansi.colemp, thing_name, ansi.colres, ansi.colid, str_id, ansi.colres });
    }

    pub fn updatedThing(self: *Printer, thing_name: []const u8, str_id: []const u8) !void {
        try self.writeOut("Updated thing {s}{s}{s} - {s}{s}{s}\n", .{ ansi.colid, str_id, ansi.colres, ansi.colemp, thing_name, ansi.colres });
    }

    pub fn startedTimer(self: *Printer, str_id: []const u8, thing_name: []const u8) !void {
        try self.writeOut("Started a timer for: {s}{s}{s} - {s}{s}{s}\n", .{ ansi.colid, str_id, ansi.colres, ansi.colemp, thing_name, ansi.colres });
    }

    pub fn stoppedTimer(self: *Printer, id_timer: u11, str_id_thing: []const u8, thing_name: []const u8, duration: u12) !void {
        try self.writeOut("Stopped timer {s}{d}{s} for {s}{s}{s} - {s}{s}{s}. It lasted {s}{d}{s}\n", .{ ansi.colid, id_timer, ansi.colres, ansi.colid, str_id_thing, ansi.colres, ansi.colemp, thing_name, ansi.colres, ansi.colemp, duration, ansi.colres });
    }

    pub fn addedTimer(self: *Printer, str_id_thing: []const u8, id_timer: u11) !void {
        try self.writeOut("Added timer {s}{s}-{d}{s}\n", .{ ansi.colid, str_id_thing, id_timer, ansi.colres });
    }

    pub fn updatedTimer(self: *Printer, str_id_thing: []const u8, id_timer: u11) !void {
        try self.writeOut("Updated timer {s}{s}-{d}{s}\n", .{ ansi.colid, str_id_thing, id_timer, ansi.colres });
    }

    pub fn deletedTimer(self: *Printer, str_id_thing: []const u8, id_timer: u11) !void {
        try self.writeOut("Deleted timer {s}{s}-{d}{s}\n", .{ ansi.colid, str_id_thing, id_timer, ansi.colres });
    }

    pub fn timerAlreadyRunning(self: *Printer, str_id: []const u8, thing_name: []const u8) !void {
        try self.writeOut("Timer already running for: {s}{s}{s} - {s}{s}{s}\n", .{ ansi.colid, str_id, ansi.colres, ansi.colemp, thing_name, ansi.colres });
    }

    pub fn noTimerRunning(self: *Printer) !void {
        try self.writeOut("No timer currently running\n", .{});
    }

    pub fn deletedThing(self: *Printer, str_id: []const u8, thing_name: []const u8) !void {
        try self.writeOut("Deleted thing {s}{s}{s} - {s}{s}{s}\n", .{ ansi.colid, str_id, ansi.colres, ansi.colemp, thing_name, ansi.colres });
    }

    pub fn cantStartIfClosed(self: *Printer, str_id: []const u8) !void {
        try self.writeOut("Cannot start a timer on a closed thing\n", .{});
        try self.writeOut("You can reopen the thing by using the following command: {s}mtlt toggle {s}{s}\n", .{ ansi.colemp, str_id, ansi.colres });
    }

    pub fn noLastTimerToWorkOn(self: *Printer) !void {
        try self.writeOut("There is no immediate last timer to work on. Please specify an ID.\n", .{});
        try self.writeOut("It should have the format {s}<id thing>-<id timer>{s}. For example: {s}b-2{s}\n", .{ ansi.colid, ansi.colres, ansi.colid, ansi.colres });
    }

    pub fn nothingToUpdateTimer(self: *Printer) !void {
        try self.writeOut("Nothing to update on the timer\n", .{});
        try self.writeOut("See 'mtlt help update-timer' for a list of options\n", .{});
    }

    pub fn noTagsToList(self: *Printer) !void {
        try self.writeOut("There are no tags to list.\n", .{});
    }

    pub fn missingEnvVar(self: *Printer, env_var: []const u8) !void {
        try self.writeOut("Please setup the {s} environment variable.\n", .{env_var});
    }

    // CURRENT THING REPORT

    pub fn reportThingIdName(self: *Printer, str_id: []const u8, str_name: []const u8) !void {
        try self.writeOut(" {s}thing{s} : {s}{s}{s} - {s}\n", .{ ansi.colemp, ansi.colres, ansi.colid, str_id, ansi.colres, str_name });
    }

    pub fn reportStatus(self: *Printer, status: []const u8) !void {
        try self.writeOut("{s}status{s} : {s}\n", .{ ansi.colemp, ansi.colres, status });
    }

    pub fn reportKickoff(self: *Printer, kickoff: u25, col_kickoff: []const u8) !void {
        try self.writeOut("{s}kickoff{s} : {s}{d}{s}\n", .{ ansi.colemp, ansi.colres, col_kickoff, kickoff, ansi.colres });
    }

    pub fn reportTimeLeftInfos(self: *Printer, step_left: i25, col_time_left: []const u8) !void {
        try self.writeOut("  {s}left{s} : {s}{d}{s}\n", .{ ansi.colemp, ansi.colres, col_time_left, step_left, ansi.colres });
    }

    pub fn reportNoTimer(self: *Printer) !void {
        try self.writeOut(" {s}timer{s} : no current timer\n", .{ ansi.colemp, ansi.colres });
    }

    pub fn reportNoCurrentThing(self: *Printer) !void {
        try self.writeOut("There is no current thing.\n", .{});
        try self.writeOut("See \"mtlt help\" for help.\n", .{});
    }

    pub fn reportTimerStarted(self: *Printer, str_duration: []const u8) !void {
        try self.writeOut(" {s}timer{s} : started {s}{s}{s} ago\n", .{ ansi.colemp, ansi.colres, ansi.coldurntr, str_duration, ansi.colres });
    }

    pub fn reportStarted(self: *Printer, offset: u25) !void {
        try self.writeOut(" {s}started{s} : {s}{d}{s} ago\n", .{ ansi.colemp, ansi.colres, ansi.coldurntr, offset, ansi.colres });
    }

    pub fn reportDuration(self: *Printer, duration: u12) !void {
        try self.writeOut("{s}duration{s} : {s}{d}{s}\n", .{ ansi.colemp, ansi.colres, ansi.coldurntr, duration, ansi.colres });
    }

    // ERRORS COMMAND PARSER SPECIFIC

    pub fn errMultipleFlagsLong(self: *Printer, long: []const u8) !void {
        try self.writeErr("There can be only one \"{s}\" flag.\n", .{long});
    }

    pub fn errMultipleFlagsShortLong(self: *Printer, short: []const u8, long: []const u8) !void {
        try self.writeErr("There can be only one \"{s}\" or \"{s}\" flag.\n", .{ short, long });
    }

    pub fn errUnexpectedArgument(self: *Printer, arg: []const u8) !void {
        try self.writeErr("Unexpected argument: {s}\n", .{arg});
    }

    pub fn errUnexpectedFlag(self: *Printer, flag: []const u8) !void {
        try self.writeErr("Unexpected flag: {s}\n", .{flag});
    }

    pub fn errDivisionInvalidCharacter(self: *Printer) !void {
        try self.writeErr("Division number contains invalid characters\n", .{});
    }

    pub fn errDivisionTooBig(self: *Printer) !void {
        try self.writeErr("Division number too big. Maximum is: {d}\n", .{std.math.maxInt(u8)});
    }

    pub fn errDurationTooBig(self: *Printer, t: type) !void {
        try self.writeErr("Duration number too big. Maximum is: {d}\n", .{std.math.maxInt(t)});
    }

    pub fn errDurationInvalidCharacter(self: *Printer) !void {
        try self.writeErr("Duration number contains invalid characters\n", .{});
    }

    pub fn errOptionAlreadyParsed(self: *Printer, option: []const u8, arg: []const u8) !void {
        try self.writeErr("{s} already parsed. Please remove: \"{s}\"\n", .{ option, arg });
    }

    pub fn errInvalidPriority(self: *Printer) !void {
        try self.writeErr("The specified priority level does not exist.\n", .{});
        try self.writeErr("Valid values are \"someday\" (default), \"soon\" and \"now\".\n", .{});
    }

    pub fn errContradictionAllTagsFlags(self: *Printer) !void {
        try self.writeOut("Warning: you specified the --no-tags flag along the --tags and --excluded-tags flags.\n", .{});
        try self.writeOut("Since these are contradictory only the --no-tags flag will be taken into account\n", .{});
    }

    pub fn errContradictionNoTagsTags(self: *Printer) !void {
        try self.writeOut("Warning: you specified the --no-tags flag along the --tags flag.\n", .{});
        try self.writeOut("Since these are contradictory only the --no-tags flag will be taken into account\n", .{});
    }

    pub fn errContradictionNoTagsExcludedTags(self: *Printer) !void {
        try self.writeOut("Warning: you specified the --no-tags flag along the --excluded-tags flag.\n", .{});
        try self.writeOut("Since these are contradictory only the --no-tags flag will be taken into account\n", .{});
    }

    pub fn errContradictionDurationDurationOffset(self: *Printer) !void {
        try self.writeErr("You cannot give a specific duration and a duration offset at the same time\n", .{});
    }

    pub fn errContradictionAddRemoveDuration(self: *Printer) !void {
        try self.writeErr("You cannot add and remove duration at the same time\n", .{});
    }

    pub fn errContradictionAddRemoveStartTime(self: *Printer) !void {
        try self.writeErr("You cannot push the start time backward and forward at the same time\n", .{});
    }

    pub fn errTimerDurationTooGreat(self: *Printer, duration: u25) !void {
        try self.writeErr("The current timer has a duration of {s}{d}{s}\n", .{ ansi.colemp, duration, ansi.colres });
        try self.writeErr("The maximum duration is {s}{d}{s}\n", .{ ansi.colemp, std.math.maxInt(u9), ansi.colres });
    }

    // ERRORS RELATED TO THINGS

    pub fn errThingNotFoundStr(self: *Printer, thing_id: []const u8) !void {
        try self.writeErr("Thing with id {s}{s}{s} not found\n", .{ ansi.colemp, thing_id, ansi.colres });
    }

    pub fn errThingNotFoundNum(self: *Printer, thing_id: u19) !void {
        var buf_str_id: [4]u8 = undefined;
        const str_id = base62_helper.b10ToB62(&buf_str_id, thing_id);
        try self.errThingNotFoundStr(str_id);
    }

    pub fn errNameThingMissing(self: *Printer) !void {
        try self.writeErr("Could not parse the name of the thing.\n", .{});
    }

    pub fn errIdThingMissing(self: *Printer) !void {
        try self.writeErr("Missing the ID of the thing to operate on.\n", .{});
    }

    // ERRORS RELATED TO TAGS

    pub fn errTagNotFoundName(self: *Printer, tag_name: []const u8) !void {
        try self.writeErr("Tag with the name {s}{s}{s} not found\n", .{ ansi.colemp, tag_name, ansi.colres });
    }

    pub fn errTagNotFoundId(self: *Printer, tag_id: u16) !void {
        try self.writeErr("Tag with ID {s}{d}{s} not found\n", .{ ansi.colemp, tag_id, ansi.colres });
    }

    pub fn errMissingTagNameToAdd(self: *Printer) !void {
        try self.writeErr("Missing the name of the tag to create\n", .{});
    }

    pub fn errMissingTagName(self: *Printer) !void {
        try self.writeErr("Missing the name of the tag to operate on.\n", .{});
    }

    pub fn errNameTagInvalidChara(self: *Printer) !void {
        try self.writeErr("The tag name can only contain ascii letters, numbers or the '-' or '_' character\n", .{});
    }

    pub fn errNameTagTooLong(self: *Printer, tag_name: []const u8) !void {
        try self.writeErr("The name {s}\"{s}\"{s} is too long\n", .{ ansi.colemp, tag_name, ansi.colres });
    }

    pub fn errNameTagAlreadyExisting(self: *Printer, tag_name: []const u8) !void {
        try self.writeErr("A tag with the name {s}{s}{s} already exists\n", .{ ansi.colemp, tag_name, ansi.colres });
    }

    pub fn errTooManyTags(self: *Printer) !void {
        try self.writeErr("The maximum number of tags in the data file is reached.\n", .{});
        try self.writeErr("Deleting existing tags will not help. If you need more tags, you will need to start a new data file.\n", .{});
    }

    pub fn errUpdateTagMissingOldName(self: *Printer) !void {
        try self.writeErr("The current name of the tag to udpate is missing.\n", .{});
        try self.writeErr("The format of the command can be seen with \"mtlt help update-tag\".\n", .{});
    }

    // ERRORS RELATED TO DURATION

    pub fn errInvalidDurationString(self: *Printer, dur_str: []const u8) !void {
        try self.writeErr("The duration string \"{s}\" is invalid\n", .{dur_str});
    }

    pub fn errDurationTooGreat(self: *Printer, dur_str: []const u8) !void {
        try self.writeErr("The duration \"{s}\" is too great. TODO indicate maximum\n", .{dur_str});
    }

    pub fn errDurationMissing(self: *Printer) !void {
        try self.writeErr("You need to specify a duration (with the -d flag)\n", .{});
    }

    // ALL OTHER ERRORS

    pub fn errUnknownCommand(self: *Printer, cmd: []const u8) !void {
        try self.writeErr("Unknown command: {s}\n", .{cmd});
    }

    pub fn errUnknownHelpTopic(self: *Printer) !void {
        try self.writeErr("Unknown help topic\n", .{});
    }

    pub fn errUnexpectedUpdatingThing(self: *Printer, err: anyerror) !void {
        try self.writeErr("Unexpected error while updating a thing.\n", .{});
        try self.writeErr("{}\n", .{err});
    }

    pub fn errUnexpectedToggleThing(self: *Printer, err: anyerror) !void {
        try self.writeErr("Unexpected error while toggling a thing.\n", .{});
        try self.writeErr("{}\n", .{err});
    }

    pub fn errUnexpectedToggleTag(self: *Printer, err: anyerror) !void {
        try self.writeErr("Unexpected error while toggling a tag.\n", .{});
        try self.writeErr("{}\n", .{err});
    }

    pub fn errUnexpectedTimerAddition(self: *Printer, err: anyerror) !void {
        try self.writeErr("Unexpected error during the addition of a timer.\n", .{});
        try self.writeErr("{}\n", .{err});
    }

    pub fn errUnexpectedTimerDeletion(self: *Printer, err: anyerror) !void {
        try self.writeErr("Unexpected error during the deletion of a timer.\n", .{});
        try self.writeErr("{}\n", .{err});
    }

    pub fn errUnexpectedUpdateTimer(self: *Printer, err: anyerror) !void {
        try self.writeErr("Unexpected error during the update of a timer.\n", .{});
        try self.writeErr("{}\n", .{err});
    }

    pub fn errUnexpectedTimerIdParsing(self: *Printer, err: anyerror) !void {
        try self.writeErr("Unexpected error during parsing of the timer ID.\n", .{});
        try self.writeErr("{}\n", .{err});
    }

    pub fn errUnexpectedAddTagToList(self: *Printer, err: anyerror) !void {
        try self.writeErr("Unexpected error while trying to add a tag to a list.\n", .{});
        try self.writeErr("{}\n", .{err});
    }

    pub fn errUnexpectedAllocateMemory(self: *Printer, err: anyerror) !void {
        try self.writeErr("Unexpected error while allocating memory.\n", .{});
        try self.writeErr("{}\n", .{err});
    }

    pub fn errUnexpectedGetEnvVar(self: *Printer, env_var: []const u8, err: anyerror) !void {
        try self.writeErr("Unexpected error while trying to get the {s} environment variable\n", .{env_var});
        try self.writeErr("{}\n", .{err});
    }

    pub fn errUnexpectedGetTagName(self: *Printer, tag_id: u16, err: anyerror) !void {
        try self.writeErr("Unexpected error while trying to get the name of the tag with ID '{d}'\n", .{tag_id});
        try self.writeErr("{}\n", .{err});
    }

    pub fn errStartOffsetMissing(self: *Printer) !void {
        try self.writeErr("You need to specify the time offset between now and the start of the timer (with the -sl flag)\n", .{});
    }

    pub fn errStartOffsetTooBig(self: *Printer, cur_time: u25) !void {
        try self.writeErr("The time offset between now and the start of the timer is too big. Maximum is: {d}\n", .{cur_time});
    }

    pub fn errInvalidEnvVar(self: *Printer, env_var: []const u8) !void {
        try self.writeErr("The {s} environment variable is not valid WTF-8.\n", .{env_var});
    }

    pub fn errDivisionNumberTooBig(self: *Printer) !void {
        try self.writeErr("Division number too big. Maximum is: {d}.\n", .{std.math.maxInt(u8)});
    }
};
