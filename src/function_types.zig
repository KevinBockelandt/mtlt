const std = @import("std");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");

const AddTagToSortToArrayList = fn (dt.Tag, *std.ArrayList(dt.TagToSort)) void;
const WriteTagHtml = fn (dt.Tag, *const std.fs.File.Writer) void;

pub const TagParsingCallbacks = union(enum) {
    AddTagToSortToArrayList: struct {
        func: *const AddTagToSortToArrayList,
        tag_array: *std.ArrayList(dt.TagToSort),
    },
    WriteTagHtml: struct {
        func: *const WriteTagHtml,
        file: *const std.fs.File.Writer,
    },
};

const AddThingToArrayList = fn (dt.Thing, *std.ArrayList(dt.Thing)) void;
const AddThingToSortToArrayList = fn (dt.Thing, *std.ArrayList(dt.ThingToSort)) void;
const CheckThingForTagAssociation = fn (dt.Thing, u16, *u24, *u24) void;
const WriteThingHtml = fn (dt.Thing, *const std.fs.File.Writer) void;

pub const ThingParsingCallbacks = union(enum) {
    AddThingToSortToArrayList: struct {
        func: *const AddThingToSortToArrayList,
        thing_array: *std.ArrayList(dt.ThingToSort),
    },
    AddThingToArrayList: struct {
        func: *const AddThingToArrayList,
        thing_array: *std.ArrayList(dt.Thing),
    },
    CheckThingForTagAssociation: struct {
        func: *const CheckThingForTagAssociation,
        tag_id: u16,
        num_ongoing: *u24,
        num_closed: *u24,
    },
    WriteThingHtml: struct {
        func: *const WriteThingHtml,
        file: *const std.fs.File.Writer,
    },
};
