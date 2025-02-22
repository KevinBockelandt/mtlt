const std = @import("std");
const globals = @import("globals.zig");

fn benchDataFileWriterAddToFile() void {
    std.debug.print("Should benchmark 'data_file_writer.addToFile'\n", .{});
}

fn benchDataFileWriterRemoveFromFile() void {
    std.debug.print("Should benchmark 'data_file_writer.addToFile'\n", .{});
}

fn benchDataFileWriterAddThingToFile() void {
    std.debug.print("Should benchmark 'data_file_writer.addToFile'\n", .{});
}

fn benchDataFileWriterAddTimerToThing() void {
    std.debug.print("Should benchmark 'data_file_writer.addToFile'\n", .{});
}

fn benchDataFileWriterDeleteTagFromFile() void {
    std.debug.print("Should benchmark 'data_file_writer.addToFile'\n", .{});
}

fn benchDataFileWriterGetTagNameFromId() void {
    std.debug.print("Should benchmark 'data_file_writer.addToFile'\n", .{});
}

fn benchDataFileWriterToggleThingStatus() void {
    std.debug.print("Should benchmark 'data_file_writer.addToFile'\n", .{});
}

fn benchDataTypesGetThingFixedPartFromInt() void {
    std.debug.print("Should benchmark 'data_types.getThingFixedPartFromInt'\n", .{});
}

fn benchDataFileReaderGetPosThing() void {
    std.debug.print("Should benchmark 'data_file_reader.getPosThing'\n", .{});
}

fn benchReportOngoingOngoingReport() void {
    std.debug.print("Should benchmark 'report_ongoing.ongoingReport'\n", .{});
}

fn benchBase62B10ToB62() void {
    std.debug.print("Should benchmark 'base62.b10ToB62'\n", .{});
}

fn benchBase62B62ToB10() void {
    std.debug.print("Should benchmark 'base62.b62ToB10'\n", .{});
}

fn wrapperBench(to_test: *const fn () void) void {
    const start_time = std.time.milliTimestamp();

    to_test();

    const end_time = std.time.milliTimestamp();

    std.debug.print("Time spent (ms): {d}\n", .{end_time - start_time});
}

pub fn main() !void {
    wrapperBench(benchBase62B10ToB62);
}
